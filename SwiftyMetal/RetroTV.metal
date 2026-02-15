//  RetroTV.metal
//  Retro Black & White Pixelated TV — Metal Shading Language
//
//  A .layerEffect shader that applies pixelation, grayscale conversion,
//  animated static noise, CRT scanlines, and a vignette to produce a
//  vintage television look.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;


// ──────────────────────────────────────────────
// MARK: - Retro TV Effect (layerEffect)
// ──────────────────────────────────────────────

/// Transforms any SwiftUI layer into a retro B&W pixelated CRT TV.
///
/// Uniforms (passed from SwiftUI):
///   size      — view dimensions (width, height)
///   time      — continuous elapsed seconds (drives noise animation)
///   pixelSize — grid cell size for pixelation (higher = blockier)
///
[[ stitchable ]] half4 retroTV(
    float2         position,
    SwiftUI::Layer layer,
    float2         size,
    float          time,
    float          pixelSize
) {
    // ── 1. Pixelation ─────────────────────────────
    // Snap position to the center of the nearest grid cell
    float ps = max(pixelSize, 1.0);
    float2 gridPos = floor(position / ps) * ps + ps * 0.5;
    half4 color = layer.sample(gridPos);

    // ── 2. Grayscale (BT.601 luminance weights) ───
    half luma = dot(color.rgb, half3(0.299h, 0.587h, 0.114h));

    // ── 3. Static noise ───────────────────────────
    // Hash-based pseudo-random per pixelated cell, animated over time
    float2 cell = floor(position / ps);
    float seed = dot(cell, float2(12.9898, 78.233)) + time * 6.283;
    float noise = fract(sin(seed) * 43758.5453);
    half noiseMix = half(noise) * 0.12h;

    // ── 4. CRT scanlines ─────────────────────────
    // Horizontal dark bands simulating a CRT raster
    float scanFreq = 3.14159265 * 2.0 / 3.0;
    float scan = sin(position.y * scanFreq) * 0.5 + 0.5;
    half scanDim = half(mix(0.78, 1.0, scan));

    // ── 5. Vignette (CRT edge darkening) ──────────
    float2 uv = position / size;
    float2 vc = uv - 0.5;
    float vignette = 1.0 - dot(vc, vc) * 1.4;
    vignette = clamp(vignette, 0.0, 1.0);

    // ── 6. Phosphor glow tint ─────────────────────
    // Slight warm tint mimicking old CRT phosphor
    half3 phosphor = half3(1.0h, 0.95h, 0.85h);

    // ── 7. Compose ────────────────────────────────
    half finalLuma = (luma + noiseMix) * scanDim * half(vignette);
    half3 finalColor = half3(finalLuma) * phosphor;

    return half4(finalColor, color.a);
}
