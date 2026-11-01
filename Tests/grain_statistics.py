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

image=np.full((192,192,3),.18,dtype=np.float32)
film='kodak_portra_400';paper='kodak_portra_endura'
p=init_params(film,paper); p.camera.auto_exposure=False;p.io.input_color_space='sRGB';p.io.input_cctf_decoding=False
p.settings.use_enlarger_lut=False;p.settings.use_scanner_lut=False;p.print_render.glare.active=False
p.scanner.unsharp_mask=(0,0)
params={'camera':{'auto_exposure':False},'io':{'input_color_space':'sRGB','input_cctf_decoding':False,'output_color_space':'sRGB','output_cctf_encoding':True},'print_render':{'glare':{'active':False}},'scanner':{'unsharp_mask':[0,0]}}
ref=np.clip(simulate(image.astype(np.float64),p),0,1);out=native(image,film,paper,params)
print('Reference mean/std:',ref.mean(axis=(0,1)),ref.std(axis=(0,1)),flush=True)
print('Native mean/std:',out.mean(axis=(0,1)),out.std(axis=(0,1)),flush=True)
print('Max abs',np.max(abs(ref-out)),'mean abs',np.mean(abs(ref-out)),flush=True)
assert np.max(abs(ref.mean(axis=(0,1))-out.mean(axis=(0,1))))<.002
assert np.all((out.std(axis=(0,1))/ref.std(axis=(0,1))>.8)&(out.std(axis=(0,1))/ref.std(axis=(0,1))<1.2))

report={"input":"192x192 uniform linear-sRGB 0.18", "film":film, "paper":paper,
        "reference_mean":ref.mean(axis=(0,1)).tolist(),"reference_std":ref.std(axis=(0,1)).tolist(),
        "native_mean":out.mean(axis=(0,1)).tolist(),"native_std":out.std(axis=(0,1)).tolist(),
        "mean_abs_difference":float(np.mean(abs(ref-out))),"passed":True}
Path(args.report).write_text(json.dumps(report,indent=2))
