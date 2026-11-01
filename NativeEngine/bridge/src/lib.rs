// SPDX-License-Identifier: GPL-3.0-only
//! Grainroom's C ABI for the unabridged spektrafilm-rs CPU spectral pipeline.
//! No RGB-LUT fallback is permitted. Vendor changes are documented separately.
use std::ffi::{CStr, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::Mutex;

use spektrafilm_core::{params::RuntimeParams, pipeline::Pipeline, profile::load_profile_by_name};
use spektrafilm_gpu::cpu_backend::CpuBackend;
use spektrafilm_math::image::ImageBuf;

static SERIAL: Mutex<()> = Mutex::new(());
const MAX_PIXELS: usize = 2048 * 2048;
struct Engine { pipeline: Pipeline, base_params: RuntimeParams, pool: rayon::ThreadPool }

unsafe fn string<'a>(p: *const c_char) -> Result<&'a str, String> {
    if p.is_null() { return Err("Null string argument".into()); }
    unsafe { CStr::from_ptr(p) }.to_str().map_err(|_| "Invalid UTF-8".into())
}
fn stock_name(name: &str) -> bool {
    !name.is_empty() && name.len() < 100 && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}
unsafe fn write_error(dst: *mut c_char, cap: usize, msg: &str) {
    if !dst.is_null() && cap > 0 {
        let n = msg.len().min(cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(msg.as_ptr(), dst.cast::<u8>(), n);
            *dst.add(n) = 0;
        }
    }
}
unsafe fn boundary(error: *mut c_char, cap: usize, operation: impl FnOnce() -> Result<(), String>) -> i32 {
    unsafe { write_error(error, cap, ""); }
    // Lock outside catch so a trapped panic does not poison the shared lock.
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => { unsafe { write_error(error, cap, &message); } 1 }
        Err(payload) => {
            let message = payload.downcast_ref::<String>().map(String::as_str)
                .or_else(|| payload.downcast_ref::<&str>().copied()).unwrap_or("Spectral engine panicked");
            unsafe { write_error(error, cap, message); }
            2
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gr_spectral_create(
    data_dir: *const c_char, film: *const c_char, paper: *const c_char,
    params_json: *const c_char, handle: *mut *mut c_void,
    error: *mut c_char, error_capacity: usize,
) -> i32 {
    if !handle.is_null() { unsafe { *handle = std::ptr::null_mut(); } }
    unsafe { boundary(error, error_capacity, || {
        if handle.is_null() { return Err("Null handle destination".into()); }
        let path = Path::new(string(data_dir)?);
        let film = string(film)?;
        let paper = string(paper)?;
        if !stock_name(film) || !stock_name(paper) { return Err("Invalid stock name".into()); }
        let mut params: RuntimeParams = serde_json::from_str(string(params_json)?).map_err(|e| format!("Parameters: {e}"))?;
        if params.io.input_color_space != "sRGB" || params.io.input_cctf_decoding
            || params.io.output_color_space != "sRGB" || !params.io.output_cctf_encoding
            || params.io.crop || params.io.upscale_factor != 1.0 {
            return Err("ABI requires linear sRGB input, encoded sRGB output, no crop or upscale".into());
        }
        // Refuse an incomplete data bundle instead of using default neutral filters.
        if !path.join("filters/neutral_print_filters.json").is_file() { return Err("Missing neutral print filter database".into()); }
        let mut film = load_profile_by_name(path, film).map_err(|e| format!("Film: {e}"))?;
        let paper = load_profile_by_name(path, paper).map_err(|e| format!("Paper: {e}"))?;
        // A custom B&W emulsion modifies measured spectral sensitivity, not a
        // post-render RGB desaturation. The base profile and data remain intact.
        let object: serde_json::Value = serde_json::from_str(string(params_json)?).map_err(|e| e.to_string())?;
        if let Some(bw) = object.get("grainroom_custom_bw") {
            if !film.is_bw() { return Err("Custom emulsion requires a monochrome base stock".into()); }
            let read = |key: &str, default: f64, min: f64, max: f64| -> Result<f64,String> {
                let v = bw.get(key).and_then(|x| x.as_f64()).unwrap_or(default);
                if !v.is_finite() || v < min || v > max { return Err(format!("Invalid emulsion parameter {key}")); }
                Ok(v)
            };
            let r=read("red",1.0,0.0,2.0)?;
            let g=read("green",1.0,0.0,2.0)?;
            let b=read("blue",1.0,0.0,2.0)?;
            for (i,row) in film.data.log_sensitivity.iter_mut().enumerate() {
                let wl=380.0 + i as f64 * 5.0;
                let band=|center: f64| (-0.5*((wl-center)/45.0).powi(2)).exp();
                let response=(r*band(620.0)+g*band(540.0)+b*band(450.0)).max(1e-5);
                for v in row { *v += response.log10(); }
            }
            params.film_render.density_curve_gamma *= read("contrast",1.0,0.4,2.0)? as f32;
        }
        let pool = rayon::ThreadPoolBuilder::new().num_threads(2).build().map_err(|e| e.to_string())?;
        let pipeline = pool.install(|| Pipeline::new_with_spectral(film, paper, params, path))?;
        let base_params = pipeline.params.clone();
        let engine = Box::new(Engine { pipeline, base_params, pool });
        *handle = Box::into_raw(engine).cast();
        Ok(())
    }) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gr_spectral_render(
    handle: *mut c_void, input: *const f32, output: *mut f32,
    width: u32, height: u32, float_count: usize,
    error: *mut c_char, error_capacity: usize,
) -> i32 {
    unsafe { boundary(error, error_capacity, || {
        if handle.is_null() || input.is_null() || output.is_null() { return Err("Null render argument".into()); }
        let pixels = (width as usize).checked_mul(height as usize).ok_or("Dimension overflow")?;
        let count = pixels.checked_mul(4).ok_or("Dimension overflow")?;
        if pixels == 0 || pixels > MAX_PIXELS || count != float_count { return Err("Invalid dimensions or pixel budget exceeded (maximum 2048 x 2048 pixels)".into()); }
        let bytes = count * std::mem::size_of::<f32>();
        let a = input as usize; let b = output as usize;
        if a % 4 != 0 || b % 4 != 0 || a.abs_diff(b) < bytes { return Err("Misaligned or overlapping buffers".into()); }
        let source = std::slice::from_raw_parts(input, count);
        if !source.iter().all(|v| v.is_finite()) { return Err("Input contains non-finite values".into()); }
        let mut rgb = Vec::with_capacity(pixels * 3);
        for rgba in source.chunks_exact(4) {
            let alpha = rgba[3].clamp(0.0, 1.0) as f64;
            for &v in &rgba[..3] { rgb.push(v.max(0.0) as f64 * alpha); }
        }
        let engine = &*handle.cast::<Engine>();
        let result = engine.pool.install(|| engine.pipeline.process(ImageBuf::from_data(width, height, rgb), &CpuBackend));
        if result.width != width || result.height != height || result.data.len() != pixels * 3
            || !result.data.iter().all(|v| v.is_finite()) { return Err("Spectral output is invalid".into()); }
        let destination = std::slice::from_raw_parts_mut(output, count);
        for (src, dst) in result.data.chunks_exact(3).zip(destination.chunks_exact_mut(4)) {
            for c in 0..3 { dst[c] = src[c].clamp(0.0, 1.0) as f32; }
            dst[3] = 1.0;
        }
        Ok(())
    }) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gr_spectral_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        let _lock = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe { drop(Box::from_raw(handle.cast::<Engine>())); }));
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn gr_spectral_version() -> *const c_char {
    c"spektrafilm-rs 9dd59b0 / Grainroom ABI 1 / CPU f64".as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_null_and_bad_dimensions_without_unwinding() {
        let mut error = [0 as c_char; 256];
        let code = unsafe { gr_spectral_render(std::ptr::null_mut(), std::ptr::null(), std::ptr::null_mut(), 0, 0, 0, error.as_mut_ptr(), error.len()) };
        assert_eq!(code, 1);
        assert!(unsafe { CStr::from_ptr(error.as_ptr()) }.to_str().unwrap().contains("Null"));
    }
    #[test]
    fn rejects_path_traversal_stock_names() {
        assert!(!stock_name("../bad"));
        assert!(!stock_name(""));
        assert!(stock_name("kodak_portra_400"));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gr_spectral_tile_geometry(
    handle: *mut c_void, tile_long_edge: u32, full_long_edge: u32, seed: u64,
    error: *mut c_char, capacity: usize,
) -> i32 {
    unsafe { boundary(error,capacity,|| {
        if handle.is_null() || tile_long_edge == 0 || full_long_edge < tile_long_edge || full_long_edge > 100000 {
            return Err("Invalid tile geometry".into());
        }
        let engine=&mut *handle.cast::<Engine>();
        let mut params=engine.base_params.clone();
        params.camera.film_format_mm *= tile_long_edge as f32 / full_long_edge as f32;
        params.film_render.grain.seed_offset=seed;
        engine.pipeline=engine.pipeline.clone().with_params(params);
        Ok(())
    }) }
}
