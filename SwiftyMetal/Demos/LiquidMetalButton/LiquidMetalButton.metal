//  LiquidMetalButton.metal
//  Liquid Metal Pill Button — Metal Shading Language
//
//  Cool-toned prismatic spectrum border that shifts with device tilt.
//  No red — uses silver, cyan, blue, violet, gold palette.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;


// ──────────────────────────────────────────────
// MARK: - Prismatic Border (colorEffect)
// ──────────────────────────────────────────────

/// Cool chrome spectrum mapped around the pill perimeter.
/// Tilt shifts the color bands and specular hotspot position.
///
/// Uniforms:
///   size  — view dimensions
///   time  — elapsed seconds
///   tiltX — device roll  (−1 to +1)
///   tiltY — device pitch (−1 to +1)
///
[[ stitchable ]] half4 liquidMetalBorder(
    float2 position,
    half4  color,
    float2 size,
    float  time,
    float  tiltX,
    float  tiltY
) {
    if (color.a < 0.01h) return color;

    // Center-relative, aspect-corrected
    float2 center = size * 0.5;
    float2 delta = position - center;
    float aspect = size.x / max(size.y, 1.0);
    float2 circ = float2(delta.x / aspect, delta.y);

    // Perimeter parameter (0 to 1)
    float angle = atan2(circ.y, circ.x);
    float t = (angle / 3.14159265) * 0.5 + 0.5;

    // Tilt shifts the spectrum around the border
    float shifted = fract(t + tiltX * 0.4 + tiltY * 0.3 + time * 0.05);

    // ── Curated cool-chrome palette (no red) ──
    // 5-stop gradient: silver → cyan → blue → violet → gold → silver
    half3 silver = half3(0.85h, 0.87h, 0.90h);
    half3 cyan   = half3(0.2h,  0.85h, 1.0h);
    half3 blue   = half3(0.25h, 0.4h,  1.0h);
    half3 violet = half3(0.6h,  0.3h,  0.9h);
    half3 gold   = half3(0.9h,  0.75h, 0.3h);

    // Map shifted (0–1) through the 5 stops
    half3 col;
    if (shifted < 0.2) {
        col = mix(silver, cyan,   half(shifted / 0.2));
    } else if (shifted < 0.4) {
        col = mix(cyan,   blue,   half((shifted - 0.2) / 0.2));
    } else if (shifted < 0.6) {
        col = mix(blue,   violet, half((shifted - 0.4) / 0.2));
    } else if (shifted < 0.8) {
        col = mix(violet, gold,   half((shifted - 0.6) / 0.2));
    } else {
        col = mix(gold,   silver, half((shifted - 0.8) / 0.2));
    }

    // ── Specular hotspot that follows tilt ──
    float lightAngle = tiltX * 2.5 + tiltY * 1.5;
    float lightT = fract((lightAngle / 3.14159265) * 0.5 + 0.5);
    float dist = abs(t - lightT);
    dist = min(dist, 1.0 - dist);

    float specular = exp(-dist * dist * 80.0);  // sharp white flash
    col = mix(col, half3(1.0h), half(specular * 0.7));

    return half4(col * color.a, color.a);
}
