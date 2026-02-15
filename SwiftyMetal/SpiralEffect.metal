//  SpiralEffect.metal
//  3D Cylindrical Spiral — Metal Shading Language
//
//  A .layerEffect shader that applies depth-of-field blur,
//  perspective compression, and opacity modulation for items
//  positioned on a virtual 3D cylinder.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;


// ──────────────────────────────────────────────
// MARK: - Spiral Depth Effect (layerEffect)
// ──────────────────────────────────────────────

/// Applies depth-based Gaussian blur and subtle perspective warp.
///
/// Uniforms (passed from SwiftUI):
///   size            — cell dimensions (width, height)
///   normalizedDepth — 0.0 = far back, 1.0 = front of cylinder
///   maxBlurRadius   — maximum blur radius in pixels for back items
///
[[ stitchable ]] half4 spiralDepthEffect(
    float2         position,
    SwiftUI::Layer layer,
    float2         size,
    float          normalizedDepth,
    float          maxBlurRadius
) {
    // Depth factor: 0 = front (no effect), 1 = far back (max effect)
    float depth = 1.0 - normalizedDepth;
    float blur  = depth * maxBlurRadius;

    // ── Perspective compression ────────────────
    // Items further away appear slightly narrower horizontally,
    // simulating the curvature of the cylinder surface.
    float2 center    = size * 0.5;
    float2 fromCenter = position - center;
    float compression = 1.0 - depth * 0.07;
    float2 basePos    = float2(center.x + fromCenter.x * compression, position.y);

    // ── Fast path — no blur for foreground cells ──
    if (blur < 0.5) {
        return layer.sample(basePos);
    }

    // ── Gaussian blur with circular kernel ─────
    half4 color      = half4(0.0h);
    float totalWeight = 0.0;

    int r = clamp(int(ceil(blur)), 1, 5);
    float sigma       = max(blur * 0.5, 0.5);
    float invSigma2   = 1.0 / (2.0 * sigma * sigma);

    for (int dx = -r; dx <= r; dx++) {
        for (int dy = -r; dy <= r; dy++) {
            float d2 = float(dx * dx + dy * dy);

            // Circular kernel — skip corner samples for efficiency
            if (d2 > float((r + 1) * (r + 1))) continue;

            float weight   = exp(-d2 * invSigma2);
            float2 sample  = basePos + float2(float(dx), float(dy));
            color         += layer.sample(sample) * half(weight);
            totalWeight   += weight;
        }
    }

    return color / half(totalWeight);
}


// ──────────────────────────────────────────────
// MARK: - Spiral Perspective Warp (distortionEffect)
// ──────────────────────────────────────────────

/// A distortionEffect variant that warps cell geometry
/// to simulate cylindrical curvature. Items on the side
/// of the cylinder have their far edges foreshortened.
///
[[ stitchable ]] float2 spiralPerspectiveWarp(
    float2 position,
    float2 size,
    float  angle,
    float  perspectiveStrength
) {
    float2 center    = size * 0.5;
    float2 fromCenter = position - center;

    // Foreshorten based on angle from center of cylinder
    float sinA = sin(angle);
    float cosA = cos(angle);

    // Horizontal compression scales with how far the cell is turned
    float xScale = 1.0 - abs(sinA) * perspectiveStrength * 0.15;

    // Vertical skew — top/bottom edges tilt toward vanishing point
    float ySkew = fromCenter.x * sinA * perspectiveStrength * 0.002;

    float2 warped = float2(
        center.x + fromCenter.x * xScale,
        position.y + ySkew * fromCenter.y
    );

    return warped;
}
