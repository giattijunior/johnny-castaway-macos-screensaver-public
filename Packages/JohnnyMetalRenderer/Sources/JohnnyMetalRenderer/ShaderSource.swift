// ShaderSource.swift
//
// Metal shader source compiled at runtime via MTLDevice.makeLibrary(source:options:).
// Compiling from source avoids the need for a pre-built .metallib in the
// SwiftPM package, while giving both the debug app and the .saver access to
// the same shaders.
//
// Pipeline overview:
//   Vertex: fullscreen quad covering NDC [-1, 1]. Passes NDC coordinates to fragment.
//   Fragment: Checks if coordinates are within the game rect.
//             If inside, samples the R8Uint framebuffer + RGBA palette LUT.
//             If outside, draws a premium deep ocean/sky vertical gradient.

internal let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 ndc;
};

struct Uniforms {
    float4 gameRect;
    int crtEnabled;
    float timeSinceStart;
};

vertex VertexOut vertexShader(
    uint vertexID [[vertex_id]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    // Quad coordinates (triangle strip):
    //   0 = top-left,  1 = top-right
    //   2 = bottom-left, 3 = bottom-right
    float u = float(vertexID & 1u);
    float v = float((vertexID >> 1u) & 1u);

    // Fullscreen NDC (-1 to 1)
    float ndcX = u * 2.0 - 1.0;
    float ndcY = 1.0 - v * 2.0;

    VertexOut out;
    out.position = float4(ndcX, ndcY, 0.0, 1.0);
    out.ndc = float2(ndcX, ndcY);
    return out;
}

fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<uint, access::read> framebuffer [[texture(0)]],
    texture2d<float, access::read> palette    [[texture(1)]]
) {
    float2 ndc = in.ndc;

    // Apply radial distortion (barrel effect) if CRT is enabled
    if (uniforms.crtEnabled != 0) {
        float distortion = 0.035; // Adjusts screen bulging curvature
        float r2 = ndc.x * ndc.x + ndc.y * ndc.y;
        ndc = ndc * (1.0 + r2 * distortion);

        // Clip to black at the warped screen edges (simulates bezel curved boundary)
        if (abs(ndc.x) > 1.005 || abs(ndc.y) > 1.005) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    // Check if the fragment falls inside the game rectangle
    // gameRect format: (left, top, right, bottom)
    // y NDC: bottom is lower than top
    if (ndc.x >= uniforms.gameRect.x && ndc.x <= uniforms.gameRect.z &&
        ndc.y >= uniforms.gameRect.w && ndc.y <= uniforms.gameRect.y) {
        
        // Map NDC back to local game UV [0, 1]
        float u = (ndc.x - uniforms.gameRect.x) / (uniforms.gameRect.z - uniforms.gameRect.x);
        float v = (uniforms.gameRect.y - ndc.y) / (uniforms.gameRect.y - uniforms.gameRect.w);
        
        uint2 px = min(uint2(float2(u, v) * float2(640.0, 480.0)), uint2(639, 479));
        uint idx = framebuffer.read(px).r;

        if (idx >= 16u) {
            color = float4(0.0, 0.0, 0.0, 1.0);
        } else {
            color = palette.read(uint2(idx, 0u));
        }
    } else {
        // Render a premium deep ocean/night sky vertical gradient in the bars
        float t = ndc.y * 0.5 + 0.5; // Map [-1, 1] to [0, 1]
        
        // Deep indigo-navy gradient colors
        float3 colorBottom = float3(0.012, 0.031, 0.078); // rgb(3, 8, 20)
        float3 colorTop    = float3(0.059, 0.125, 0.263); // rgb(15, 32, 67)
        
        float3 bgColor = mix(colorBottom, colorTop, t);
        color = float4(bgColor, 1.0);
    }

    // Apply scanlines and retro phosphor effects if CRT is enabled
    if (uniforms.crtEnabled != 0) {
        // Scanlines based on vertical screen position
        float scanline = sin(in.position.y * 1.35) * 0.07 + 0.93;
        
        // Sub-pixel mask (aperture grille phosphor emulation)
        float mask = sin(in.position.x * 2.0) * 0.03 + 0.97;
        
        color.rgb *= scanline * mask;

        // Subtle vignette (darker edges)
        float2 uv = ndc * 0.5;
        float vignette = 1.0 - (uv.x * uv.x + uv.y * uv.y) * 0.15;
        color.rgb *= vignette;
    }

    // Apply 1-second startup fade-in from black
    float fade = clamp(uniforms.timeSinceStart, 0.0, 1.0);
    color.rgb *= fade;

    return color;
}
"""
