# SPDX-License-Identifier: GPL-3.0-only
"""Run with Python spektrafilm on PYTHONPATH. Bake missing T/K75P spectra.
Derived from spektrafilm/model/illuminants.py by Andrea Volpato and the
colour-science light-source dataset. No modification to film profiles.
"""
from pathlib import Path
from spektrafilm.model.illuminants import standard_illuminant
root=Path(__file__).resolve().parents[1]/'NativeEngine/vendor/crates/spektrafilm-core/src'
text='// SPDX-License-Identifier: GPL-3.0-only\n// Generated from Python spektrafilm standard_illuminant; see Scripts/export-reference-illuminants.py.\n'
for name in ['T','K75P']:
    values=standard_illuminant(name)
    text+=f'pub const {name}_F64: [f64; 81] = ['+','.join(repr(float(x)) for x in values)+'];\n'
    text+=f'pub const {name}_F32: [f32; 81] = ['+','.join(f'{float(x):.9e}f32' for x in values)+'];\n'
(root/'reference_illuminants.rs').write_text(text)
