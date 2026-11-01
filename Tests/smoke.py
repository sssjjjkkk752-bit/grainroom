# SPDX-License-Identifier: GPL-3.0-only
"""CPU C ABI tests; needs Python 3 + numpy, without the Python reference.
Usage: python Tests/smoke.py /path/to/libgrainroom_spectral.dylib report.json
"""
import ctypes as C
import json
import sys
import time
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1]
lib=C.CDLL(str(Path(sys.argv[1]).resolve()))
ptr=C.POINTER(C.c_float)
lib.gr_spectral_create.argtypes=[C.c_char_p]*4+[C.POINTER(C.c_void_p),C.c_char_p,C.c_size_t]
lib.gr_spectral_render.argtypes=[C.c_void_p,ptr,ptr,C.c_uint32,C.c_uint32,C.c_size_t,C.c_char_p,C.c_size_t]
lib.gr_spectral_destroy.argtypes=[C.c_void_p]
error=C.create_string_buffer(2048)
params={'camera':{'auto_exposure':False},'io':{'input_color_space':'sRGB','input_cctf_decoding':False,'output_color_space':'sRGB','output_cctf_encoding':True}}
source=np.ones((32,32,4),dtype=np.float32)
source[:,:,:3]=np.linspace(.005,1,32)[None,:,None]
out=np.empty_like(source)
results=[]
for file in sorted((root/'Grainroom/SpectralData/profiles').glob('*.json')):
 info=json.loads(file.read_text())['info']
 if info['stage']!='filming':continue
 config=json.loads(json.dumps(params));config['io']['scan_film']=info['type']=='positive'
 paper=info.get('target_print') or ('kodak_2302' if info.get('channel_model')=='bw' else 'kodak_portra_endura')
 handle=C.c_void_p(); start=time.monotonic()
 rc=lib.gr_spectral_create(str(root/'Grainroom/SpectralData').encode(),file.stem.encode(),paper.encode(),json.dumps(config).encode(),C.byref(handle),error,len(error))
 assert rc==0,(file.stem,error.value)
 try:
  rc=lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),out.ctypes.data_as(ptr),32,32,source.size,error,len(error))
  assert rc==0,(file.stem,error.value)
  assert np.all(np.isfinite(out)) and np.all((out>=0)&(out<=1))
  assert np.all(out[:,:,3]==1)
  # Must reject invalid ABI inputs before reading/writing buffers.
  assert lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),out.ctypes.data_as(ptr),32,32,1,error,len(error))==1
  assert lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),source.ctypes.data_as(ptr),32,32,source.size,error,len(error))==1
  assert lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),out.ctypes.data_as(ptr),0,32,0,error,len(error))==1
  source[0,0,0]=np.nan
  assert lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),out.ctypes.data_as(ptr),32,32,source.size,error,len(error))==1
  source[0,0,0]=.005
 finally:lib.gr_spectral_destroy(handle)
 results.append({'film':file.stem,'paper':paper,'scan_film':config['io']['scan_film'],'passed':True,'seconds':round(time.monotonic()-start,3)})
 print(file.stem,'OK',flush=True)
# All print profiles must be loadable and renderable through the same full chain.
for file in sorted((root/'Grainroom/SpectralData/profiles').glob('*.json')):
 info=json.loads(file.read_text())['info']
 if info['stage']!='printing':continue
 film='kodak_doublex' if info.get('channel_model')=='bw' else 'kodak_portra_400'
 handle=C.c_void_p()
 rc=lib.gr_spectral_create(str(root/'Grainroom/SpectralData').encode(),film.encode(),file.stem.encode(),json.dumps(params).encode(),C.byref(handle),error,len(error))
 assert rc==0,(file.stem,error.value)
 try:
  assert lib.gr_spectral_render(handle,source.ctypes.data_as(ptr),out.ctypes.data_as(ptr),32,32,source.size,error,len(error))==0,(file.stem,error.value)
  assert np.isfinite(out).all()
 finally:lib.gr_spectral_destroy(handle)
 results.append({'print':file.stem,'passed':True})
handle=C.c_void_p(123)
assert lib.gr_spectral_create(b'/missing',b'../bad',b'paper',b'{}',C.byref(handle),error,len(error))==1
assert handle.value is None
Path(sys.argv[2]).write_text(json.dumps({'results':results,'passed':True},indent=2))
print('All',len(results),'profile cases and ABI validation checks passed',flush=True)
