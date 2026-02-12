//  GooeyDistortion.metal
//  Fluid Content Switcher — Metal Shading Language
//
//  A .layerEffect shader that applies SDF-based deformation with
//  gooey smooth-minimum merging, liquid stretch displacement, and
//  ripple physics driven by SwiftUI uniforms.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ──────────────────────────────────────────────
// MARK: - SDF Primitives & Utilities
// ──────────────────────────────────────────────

/// Polynomial smooth minimum — the heart of the "gooey" merge.
/// `k` controls the blending radius between two distance fields.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// SDF for a rounded rectangle centered at the origin.
/// `b` = half-extents, `r` = corner radius.
float sdRoundedRect(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/// SDF for a circle at the origin with radius `r`.
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

/// Attempt a soft-body SDF: the card shape merges organically with
/// a "touch blob" via smooth-minimum, so the geometry looks like it
/// bulges toward the user's finger.
float gooeyField(
    float2 pos,
    float2 cardCenter,
    float2 cardHalfSize,
    float  cornerRadius,
    float2 touchPoint,
    float  blobRadius,
    float  mergeRadius
) {
    float cardDist  = sdRoundedRect(pos - cardCenter, cardHalfSize, cornerRadius);
    float touchDist = sdCircle(pos - touchPoint, blobRadius);
    return smin(cardDist, touchDist, mergeRadius);
}


// ──────────────────────────────────────────────
// MARK: - Main Layer Effect Shader
// ──────────────────────────────────────────────

/// Applies gooey fluid distortion to a SwiftUI layer.
///
/// Uniforms (passed from SwiftUI via Shader arguments):
///   size        — viewport dimensions
///   touchPoint  — current drag position (in layer coords)
///   velocity    — instantaneous drag velocity
///   time        — continuous elapsed seconds (from TimelineView)
///   angularity  — [0…1] corner curvature; 0 = sharp, 1 = pill
///   amplitude   — [0…1] stretch intensity (height)
///   viscosity   — [0…1] pixel drag / damping factor
///   isDragging  — 1.0 while finger is down, 0.0 on release
///
[[ stitchable ]] half4 gooeyDistortion(
    float2         position,
    SwiftUI::Layer layer,
    float2         size,
    float2         touchPoint,
    float2         velocity,
    float          time,
    float          angularity,
    float          amplitude,
    float          viscosity,
    float          isDragging
) {
    // ── Derived constants ──────────────────────
    float2 center       = size * 0.5;
    float  maxDim       = max(size.x, size.y);
    float  influenceRad = maxDim * 0.45;          // reach of the touch field

    // ── 1. Radial influence from touch ─────────
    float dist      = length(position - touchPoint);
    float normDist  = dist / influenceRad;

    // Smooth falloff shaped by viscosity — high viscosity = wider, stickier pull
    float falloff   = 1.0 - smoothstep(0.0, 1.0, normDist);
    float shaped    = pow(falloff, mix(1.5, 0.6, viscosity));  // viscosity widens the curve
    float influence = shaped * isDragging;

    // ── 2. SDF gooey field for edge warping ────
    float2 cardHalf    = size * 0.46;
    float  cornerR     = mix(8.0, cardHalf.y, angularity);     // angularity drives corners
    float  blobR       = mix(20.0, 60.0, amplitude) * isDragging;
    float  mergeK      = mix(15.0, 100.0, viscosity);          // viscosity drives merge softness
    float  field       = gooeyField(position, center, cardHalf, cornerR,
                                    touchPoint, blobR, mergeK);

    // Soft SDF-based edge warp — pushes pixels outward near merged region
    float edgeFactor   = 1.0 - smoothstep(-10.0, 10.0, field);
    float2 edgeNormal  = normalize(position - touchPoint + 0.001);
    float2 edgeDisp    = edgeNormal * edgeFactor * amplitude * 18.0 * isDragging;

    // ── 3. Primary displacement (liquid stretch toward touch) ─
    float2 toTouch     = touchPoint - position;
    float2 pullDir     = normalize(toTouch + 0.001);
    float  stretchMag  = influence * amplitude * 75.0;
    float2 stretch     = pullDir * stretchMag;

    // ── 4. Velocity trailing (viscous pixel drag) ──
    //    Pixels behind the leading edge lag proportionally to viscosity.
    float2 velTrail    = velocity * influence * viscosity * 0.12;

    // ── 5. Ripple / wobble overlay ─────────────
    //    Two overlapping sine waves for organic motion.
    float ripple1 = sin(dist * 0.04 - time * 4.0) * cos(dist * 0.025 + time * 1.7);
    float ripple2 = sin(dist * 0.07 + time * 2.3);
    float ripple  = (ripple1 * 0.6 + ripple2 * 0.4) * influence * amplitude * 12.0;
    float2 rippleDisp = pullDir * ripple;

    // ── 6. Ambient idle undulation (even when not dragging) ──
    float idle = sin(position.y * 0.015 + time * 1.2) *
                 cos(position.x * 0.012 + time * 0.9) * 1.5;
    float2 idleDisp = float2(idle, idle * 0.7);

    // ── 7. Compose total displacement ──────────
    float2 totalDisp = stretch + velTrail + rippleDisp + edgeDisp + idleDisp;

    // Damping: viscosity reduces the final displacement's snappiness
    // (high viscosity = movement feels heavier, more syrupy)
    totalDisp *= mix(1.0, 0.55, viscosity * 0.4);

    // ── 8. Sample the layer at the displaced coordinate ──
    float2 samplePos = position - totalDisp;
    half4  color     = layer.sample(samplePos);

    return color;
}


// ──────────────────────────────────────────────
// MARK: - Bonus: Gooey Transition Mask
// ──────────────────────────────────────────────

/// A color-effect shader that outputs a gooey alpha mask.
/// Useful for clipping / masking card shapes with organic edges.
[[ stitchable ]] half4 gooeyMask(
    float2         position,
    half4          currentColor,
    float2         size,
    float2         touchPoint,
    float          angularity,
    float          viscosity,
    float          isDragging
) {
    float2 center    = size * 0.5;
    float2 halfSize  = size * 0.46;
    float  cornerR   = mix(8.0, halfSize.y, angularity);
    float  blobR     = 40.0 * isDragging;
    float  mergeK    = mix(15.0, 90.0, viscosity);

    float field = gooeyField(position, center, halfSize, cornerR,
                             touchPoint, blobR, mergeK);

    float alpha = 1.0 - smoothstep(-1.5, 1.5, field);
    return currentColor * half(alpha);
}
