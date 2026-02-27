#include <metal_stdlib>
using namespace metal;

struct YUVParams {
    uint  width;
    uint  height;
    uint  yStride;
    uint  uStride;
    uint  vStride;
    float mixFactor;
    float uRed;
    float vRed;
};

// Compute kernel that tints U/V towards red for 4:2:0 YUV
kernel void tint_red_yuv(
    device uint8_t *yPlane [[buffer(0)]],
    device uint8_t *uPlane [[buffer(1)]],
    device uint8_t *vPlane [[buffer(2)]],
    constant YUVParams &params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint x = gid.x;
    uint y = gid.y;

    // Y is left unchanged
    uint yIndex = y * params.yStride + x;
    (void)yPlane[yIndex];

    // For 4:2:0 chroma, update one U/V sample per 2x2 block
    if ((x % 2u == 0u) && (y % 2u == 0u)) {
        uint uvX = x / 2u;
        uint uvY = y / 2u;

        uint uIndex = uvY * params.uStride + uvX;
        uint vIndex = uvY * params.vStride + uvX;

        float u = (float)uPlane[uIndex];
        float v = (float)vPlane[vIndex];

        float uNew = mix(u, params.uRed, params.mixFactor);
        float vNew = mix(v, params.vRed, params.mixFactor);

        uPlane[uIndex] = (uint8_t)clamp(uNew, 0.0f, 255.0f);
        vPlane[vIndex] = (uint8_t)clamp(vNew, 0.0f, 255.0f);
    }
}
