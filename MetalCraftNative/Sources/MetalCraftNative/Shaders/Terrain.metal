#include <metal_stdlib>
using namespace metal;

// Terrain pass for the experimental Metal backend.
//
// Vertex layout mirrors the vanilla block-vertex format handed over from the
// Java side (position, color, UV, light UV, normal). The camera matrices are
// pushed per frame; light-map and block-atlas textures are bound from shared
// IOSurfaces so no texture data is duplicated between GL and Metal.

struct TerrainVertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
    float2 uv       [[attribute(2)]];
    float2 lightUV  [[attribute(3)]];
};

struct TerrainVertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float2 lightUV;
};

struct FrameUniforms {
    float4x4 viewProjection;
    float4   fogColor;
    float2   fogRange;      // start, end
};

vertex TerrainVertexOut terrain_vertex(
    const device float*        vertexData [[buffer(0)]],
    constant FrameUniforms&    uniforms   [[buffer(1)]],
    uint                       vid        [[vertex_id]]
) {
    // Packed stride: 3 pos + 4 color + 2 uv + 2 light = 11 floats
    const uint stride = 11;
    const device float* v = vertexData + vid * stride;

    TerrainVertexOut out;
    float3 position = float3(v[0], v[1], v[2]);
    out.position = uniforms.viewProjection * float4(position, 1.0);
    out.color    = float4(v[3], v[4], v[5], v[6]);
    out.uv       = float2(v[7], v[8]);
    out.lightUV  = float2(v[9], v[10]);
    return out;
}

fragment float4 terrain_fragment(
    TerrainVertexOut  in       [[stage_in]],
    texture2d<float>  atlas    [[texture(0)]],
    texture2d<float>  lightMap [[texture(1)]],
    sampler           nearest  [[sampler(0)]]
) {
    float4 base  = atlas.sample(nearest, in.uv);
    if (base.a < 0.1) {
        discard_fragment();
    }
    float4 light = lightMap.sample(nearest, in.lightUV);
    return base * in.color * light;
}
