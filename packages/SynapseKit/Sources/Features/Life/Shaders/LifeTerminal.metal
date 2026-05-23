#include <metal_stdlib>
using namespace metal;

// Mirrors `DesignSystem.ShaderUniforms`. If you change the field layout
// here, change it there too — Swift writes the buffer with the SIMD
// alignment the host-side struct implies.
struct LifeShaderUniforms {
    float  time;
    float2 resolution;
    float  bloomRadius;
    float  scanlineIntensity;
    float4 phosphorBright;
    float4 phosphorDim;
    float4 terminalInk;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen triangle. Caller draws 3 vertices with no buffer; the
// vertex id selects the corner.
vertex VertexOut life_vertex(uint vid [[vertex_id]]) {
    // Generates a triangle covering the [-1, 3] range in both axes so
    // the clipped result fills the full [-1, 1] viewport without a quad.
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    // uv in [0, 1] across the visible quad.
    out.uv = (positions[vid] + 1.0) * 0.5;
    return out;
}

// Cheap, single-pass amber phosphor fragment.
//
// The glyph mask is provided as a texture by the host; the shader does
// not synthesize text. For pure-render tests with no text texture we
// still want a meaningful output, so the host can pass a 1x1 white
// texture and the shader will paint a uniform phosphor plate.
fragment float4 life_fragment(
    VertexOut in [[stage_in]],
    constant LifeShaderUniforms& u [[buffer(0)]],
    texture2d<float, access::sample> glyphTex [[texture(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;

    // Sample glyph mask. Single tap as the baseline.
    float mask = glyphTex.sample(s, uv).r;

    // Cheap bloom: four fixed-offset samples around the current pixel,
    // gated by bloomRadius. When the radius is 0 (Reduce Motion / Reduce
    // Transparency), the offsets collapse to the center sample and the
    // mix below becomes a no-op.
    float2 px = float2(u.bloomRadius) / max(u.resolution, float2(1.0));
    float bloom =
        glyphTex.sample(s, uv + float2( px.x, 0.0)).r +
        glyphTex.sample(s, uv + float2(-px.x, 0.0)).r +
        glyphTex.sample(s, uv + float2(0.0,  px.y)).r +
        glyphTex.sample(s, uv + float2(0.0, -px.y)).r;
    bloom *= 0.25;
    float combined = clamp(mask + bloom * 0.5, 0.0, 1.0);

    // Phosphor decay: sub-second amber pulse. `time` is frozen by the
    // host when Reduce Motion is on, so this term becomes a constant.
    float decay = 0.92 + 0.08 * sin(u.time * 2.4);
    float3 phosphor = mix(u.terminalInk.rgb, u.phosphorBright.rgb, combined * decay);

    // Scanlines. Sub-pixel sine over y; intensity gated by Increase Contrast.
    float scanline = 0.5 + 0.5 * sin(uv.y * u.resolution.y * 3.14159265);
    float scanlineFactor = mix(1.0, scanline, u.scanlineIntensity);
    phosphor *= scanlineFactor;

    // Dim halo where the mask is low but a neighbour is high — keeps
    // wrapped continuation glyphs feeling connected to their head line.
    phosphor = mix(phosphor, u.phosphorDim.rgb, max(0.0, bloom - mask) * 0.35);

    return float4(phosphor, 1.0);
}
