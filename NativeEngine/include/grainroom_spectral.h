// SPDX-License-Identifier: GPL-3.0-only
#ifndef GRAINROOM_SPECTRAL_H
#define GRAINROOM_SPECTRAL_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Return 0 on success, 1 on error, 2 on panic. Errors are UTF-8, NUL terminated.
// create -> render zero or more times -> destroy exactly once.
// Calls are serialized internally for Accelerate BLAS. Never destroy a handle
// concurrently with another call that uses that same handle.
int32_t gr_spectral_create(const char *data_dir, const char *film,
    const char *paper, const char *params_json, void **handle,
    char *error, size_t error_capacity);
// Input: tightly packed top-down linear sRGB float RGBA, straight alpha.
// Alpha is composited over black. Output: encoded sRGB float RGBA, alpha=1.
// Nonoverlapping buffers, each has width*height*4 floats. Full spectral path.
int32_t gr_spectral_render(void *handle, const float *input, float *output,
    uint32_t width, uint32_t height, size_t float_count,
    char *error, size_t error_capacity);
// Full-resolution export renders bounded tiles with overlap. Call this before
// each render to keep the physical pixel size tied to the full image, not tile.
// The full pipeline calibration is retained; random grain uses the tile seed.
int32_t gr_spectral_tile_geometry(void *handle, uint32_t tile_long_edge,
    uint32_t full_long_edge, uint64_t seed, char *error, size_t error_capacity);
void gr_spectral_destroy(void *handle);
const char *gr_spectral_version(void);
#ifdef __cplusplus
}
#endif
#endif
