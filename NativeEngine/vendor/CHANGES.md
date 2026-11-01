# Grainroom integration changes

Base: turbasvin/spektrafilm-rs commit 9dd59b0380194b93686aaa230a8bb9680aa270a4.
Reference: andreavolpato/spektrafilm commit 3bb2c2d2801ff68b92019cf1dbcbb133d60832bc.

- Retain the core, model, math, GPU-abstraction and shader sources; omit the desktop GUI/CLI crates.
- Disable the wgpu default feature for the mobile CPU library. All spectral stages use the CPU f64 backend. No baked RGB LUT replaces the physical pipeline.
- Select Accelerate BLAS for all Apple targets, including iOS and iOS Simulator.
- Add the missing Incandescent (T) reference and Kinoton 75P viewing spectra, generated with the reference Python implementation. The upstream Rust selectors silently used daylight for these identifiers, causing incorrect tungsten/cinema output.
- Mirror the Python stock-specific halation presets and Velvia/Provia DIR factors.
- Implement the Python three-emulsion grain mode, including layer density interpolation, particle size by emulsion, dye cloud blur and microstructure. The upstream Rust CPU path ignored sublayers_active and always used its simple grain model.
- Use a local fixed seed for optional microstructure to make previews stable; stochastic output is not claimed to be pixel-identical to Python.
- Add a C ABI with validated buffers, bounded pixels, caught Rust panics and serialized Accelerate calls.

Profile JSON, Hanatos spectral reconstruction assets, filter assets and neutral-print calibration database are copied unchanged from the pinned Rust repository. Their original spektrafilm attribution/metadata is retained. See SpectralData/SPEKTRAFILM_LICENSE.txt. Added code is GPL-3.0-only.

- Disable viewing glare in direct film scans, matching the Python reference (the upstream Rust path applied film_render.glare there).

## Grainroom 0.3

- Add an explicit tile-geometry C ABI. Reuse calibrated spectral data while
  setting film_format_mm so a tile retains the full frame's physical pixel pitch.
- Add a deterministic per-tile seed offset to both grain paths, avoiding a repeated
  identical noise field in every tile. This preserves the original seed=0 tests.
- Add the grainroom_custom_bw wrapper: adjust the measured Double-X log spectral
  sensitivity with weighted 450/540/620nm response bands and development gamma.
  The original data files remain unchanged; this is an experimental derived model.
- The Swift export layer writes bounded overlapping tiles to a mapped raster.
  Finite overlap approximates infinite IIR tails; stochastic pixels differ from
  a one-shot whole-frame computation. RAW export copies original file bytes.
