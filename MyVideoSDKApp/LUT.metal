#include <metal_stdlib>
using namespace metal;

struct LUTParams {
    uint  width;
    uint  height;
    uint  yStride;
    uint  uStride;
    uint  vStride;
    uint  lutSize;      // e.g. 33 for a 33x33x33 LUT
    float intensity;    // 0.0 = no effect, 1.0 = full LUT
};

/*
 BT.601 YUV ↔ RGB conversions (full-range 0-255)

 These match the standard used by most consumer video and webcams.
 */
static float3 yuv_to_rgb(float y, float u, float v) {
    float Y = y;
    float U = u - 128.0f;
    float V = v - 128.0f;

    float r = Y + 1.402f * V;
    float g = Y - 0.344136f * U - 0.714136f * V;
    float b = Y + 1.772f * U;

    return float3(
        clamp(r, 0.0f, 255.0f),
        clamp(g, 0.0f, 255.0f),
        clamp(b, 0.0f, 255.0f)
    );
}

static float3 rgb_to_yuv(float r, float g, float b) {
    float Y =  0.299f * r + 0.587f * g + 0.114f * b;
    float U = -0.168736f * r - 0.331264f * g + 0.5f * b + 128.0f;
    float V =  0.5f * r - 0.418688f * g - 0.081312f * b + 128.0f;

    return float3(
        clamp(Y, 0.0f, 255.0f),
        clamp(U, 0.0f, 255.0f),
        clamp(V, 0.0f, 255.0f)
    );
}

/*
 3D LUT application kernel for YUV 4:2:0 video frames.

 Takes the Y, U, V planes plus a 3D LUT texture and applies
 color grading via trilinear-interpolated LUT lookup.

 The LUT texture is a standard 3D texture indexed by (R, G, B)
 in normalized [0,1] coordinates, loaded from a .cube file.
 */
kernel void apply_lut_yuv(
    device uint8_t       *yPlane  [[buffer(0)]],
    device uint8_t       *uPlane  [[buffer(1)]],
    device uint8_t       *vPlane  [[buffer(2)]],
    constant LUTParams   &params  [[buffer(3)]],
    texture3d<float, access::sample> lutTexture [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint x = gid.x;
    uint y = gid.y;

    // Read Y for this pixel, U/V for the 2x2 block it belongs to
    uint yIndex = y * params.yStride + x;
    float Y = (float)yPlane[yIndex];

    uint uvX = x / 2u;
    uint uvY = y / 2u;
    uint uIndex = uvY * params.uStride + uvX;
    uint vIndex = uvY * params.vStride + uvX;
    float U = (float)uPlane[uIndex];
    float V = (float)vPlane[vIndex];

    // YUV → RGB
    float3 rgb = yuv_to_rgb(Y, U, V);

    // Normalize to [0,1] for LUT sampling
    float3 coords = rgb / 255.0f;

    // Hardware trilinear-interpolated 3D LUT lookup
    constexpr sampler lutSampler(coord::normalized,
                                 address::clamp_to_edge,
                                 filter::linear);
    float4 lutColor = lutTexture.sample(lutSampler, coords);

    // Denormalize LUT output back to [0,255]
    float3 graded = lutColor.rgb * 255.0f;

    // Blend between original and graded based on intensity
    float3 blended = mix(rgb, graded, params.intensity);

    // RGB → YUV
    float3 newYUV = rgb_to_yuv(blended.r, blended.g, blended.b);

    // Always write Y (full resolution)
    yPlane[yIndex] = (uint8_t)clamp(newYUV.x, 0.0f, 255.0f);

    // Write U/V only once per 2x2 block (4:2:0 subsampling)
    if ((x % 2u == 0u) && (y % 2u == 0u)) {
        uPlane[uIndex] = (uint8_t)clamp(newYUV.y, 0.0f, 255.0f);
        vPlane[vIndex] = (uint8_t)clamp(newYUV.z, 0.0f, 255.0f);
    }
}
