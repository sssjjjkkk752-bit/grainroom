"""Compare the shipped C ABI to a pinned Python spektrafilm reference.
Run with a Python 3.13 environment containing the reference requirements.
PYTHONPATH=/path/to/spektrafilm/src python Tests/parity.py --library /path/to/libgrainroom_spectral.dylib
"""
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import ctypes as C
import json
import time
from pathlib import Path
import numpy as np
from spektrafilm import init_params, simulate

parser = argparse.ArgumentParser()
parser.add_argument('--library', required=True)
parser.add_argument('--report', default='parity-report.json')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
lib = C.CDLL(str(Path(args.library).resolve()))
ptr = C.POINTER(C.c_float)
lib.gr_spectral_create.argtypes = [C.c_char_p]*4 + [C.POINTER(C.c_void_p), C.c_char_p, C.c_size_t]
lib.gr_spectral_create.restype = C.c_int32
lib.gr_spectral_render.argtypes = [C.c_void_p, ptr, ptr, C.c_uint32, C.c_uint32, C.c_size_t, C.c_char_p, C.c_size_t]
lib.gr_spectral_render.restype = C.c_int32
lib.gr_spectral_destroy.argtypes = [C.c_void_p]
lib.gr_spectral_destroy.restype = None

def native(image, film, paper, params):
    image = np.asarray(image, dtype=np.float32)
    rgba = np.ones((*image.shape[:2], 4), dtype=np.float32)
    rgba[:,:,:3] = image
    output = np.empty_like(rgba)
    handle = C.c_void_p()
    error = C.create_string_buffer(2048)
    rc = lib.gr_spectral_create(str(root/'Grainroom/SpectralData').encode(), film.encode(), paper.encode(), json.dumps(params).encode(), C.byref(handle), error, len(error))
    if rc: raise RuntimeError(error.value.decode())
    try:
        rc = lib.gr_spectral_render(handle, rgba.ctypes.data_as(ptr), output.ctypes.data_as(ptr), image.shape[1], image.shape[0], rgba.size, error, len(error))
        if rc: raise RuntimeError(error.value.decode())
        return output[:,:,:3].copy()
    finally:
        lib.gr_spectral_destroy(handle)

# Tests include dark tones, midgray, saturated colours and bright highlights.
x = np.linspace(0.001, 1, 16, dtype=np.float32)
image = np.stack(np.meshgrid(x, x), axis=-1)
image = np.concatenate([image, (0.02+0.75*image[:,:,:1])], axis=-1).astype(np.float32)
results=[]
cases=[
    ('kodak_portra_400', 'kodak_portra_endura', 'bare', 0, 0),
    ('fujifilm_pro_400h', 'fujifilm_crystal_archive_typeii', 'bare', 0, 0),
    ('kodak_vision3_500t', 'kodak_2383', 'bare', 0.7, 6),
    ('kodak_portra_400', 'kodak_portra_endura', 'spatial_dir', 0, 0),
    ('kodak_vision3_500t', 'kodak_2383', 'spatial_dir', 0, 0),
]
for file in sorted((root/'Grainroom/SpectralData/profiles').glob('*.json')):
    info=json.loads(file.read_text())['info']
    if info['stage']=='filming' and info.get('channel_model')!='bw':
        cases.append((file.stem, info.get('target_print') or 'kodak_portra_endura', 'scan_slide' if info['type']=='positive' else 'bare', 0, 0))
for film, paper, mode, ev, yshift in cases:
    start=time.monotonic()
    p=init_params(film, paper)
    p.camera.auto_exposure=False
    p.camera.exposure_compensation_ev=ev
    p.io.input_color_space='sRGB'
    p.io.input_cctf_decoding=False
    p.io.output_color_space='sRGB'
    p.io.output_cctf_encoding=True
    p.io.scan_film=mode=='scan_slide'
    p.settings.use_enlarger_lut=False
    p.settings.use_scanner_lut=False
    p.film_render.grain.active=False
    p.print_render.glare.active=False
    p.film_render.glare.active=False
    p.enlarger.y_filter_shift=yshift
    p.scanner.unsharp_mask=(0,0)
    p.film_render.dir_couplers.active=mode!='bare'
    p.film_render.halation.active=mode!='bare'
    params={
        'camera': {'auto_exposure': False, 'exposure_compensation_ev': ev},
        'io': {'input_color_space':'sRGB','input_cctf_decoding':False,'output_color_space':'sRGB','output_cctf_encoding':True,'scan_film':mode=='scan_slide'},
        'enlarger': {'y_filter_shift': yshift},
        'film_render': {'grain':{'active':False},'dir_couplers':{'active':mode!='bare'},'halation':{'active':mode!='bare'},'glare':{'active':False}},
        'print_render': {'glare':{'active':False}},
        'scanner': {'unsharp_mask':[0,0]},
        'settings': {'use_enlarger_lut':False,'use_scanner_lut':False},
    }
    reference=np.clip(simulate(image.astype(np.float64),p),0,1)
    actual=native(image,film,paper,params)
    diff=np.abs(reference-actual)
    # Limit includes the f32 ABI and 8-bit display quantisation budget, without
    # pretending stochastic grain should be pixel-identical across engines.
    result={'film':film,'paper':paper,'mode':mode,'max_abs':float(diff.max()),'mean_abs':float(diff.mean()),'seconds':round(time.monotonic()-start,2)}
    result['passed']=result['max_abs']<=1e-4 and result['mean_abs']<=1e-5
    results.append(result)
    print(json.dumps(result),flush=True)
report={'python_reference_commit':'3bb2c2d2801ff68b92019cf1dbcbb133d60832bc','rust_commit':'9dd59b0380194b93686aaa230a8bb9680aa270a4','input':'16x16 linear-sRGB float32 colour grid','results':results}
Path(args.report).write_text(json.dumps(report,indent=2))
if not all(r['passed'] for r in results): raise SystemExit('Parity tolerance exceeded')
