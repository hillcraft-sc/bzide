#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The Plasma visualizer, after the classic demoscene effect: sine waves (two
/// straight, one diagonal, one radial around a wandering center, and a fine
/// shimmer) add up to swirling interference bands, which cycle through a
/// four-color palette twice.
///
/// The music drives it without flashing: `flow` (a clock that runs faster in
/// busy passages and lurches on beats, never jumping) moves the pattern;
/// `beat` (a pulse on each drum hit) zooms it in slightly and ripples it;
/// `bass` swells the radial rings, `mid` the diagonal bands, `treble` the
/// shimmer and the colors.
///
/// `position` is the pixel, `size` the view's size; `beat`, `bass`, `mid`,
/// `treble` are 0...1; `c0`…`c3` the palette.
[[ stitchable ]] half4 plasma(
    float2 position, half4 color,
    float2 size, float flow,
    float beat, float bass, float mid, float treble,
    half4 c0, half4 c1, half4 c2, half4 c3
) {
    // Centered, so the shorter side spans -0.5...0.5.
    float2 uv = (position - size * 0.5) / min(size.x, size.y);
    // Each beat zooms in a touch and sends a ripple through the field.
    uv *= 1.0 - 0.12 * beat;
    float ripple = 0.03 * bass + 0.07 * beat;
    uv += ripple * float2(sin(uv.y * 9.0 + flow * 2.0), cos(uv.x * 9.0 + flow * 1.7));

    float2 p = uv * 11.0;
    float value = sin(p.x + flow);
    value += sin((p.y + flow) * 0.6);
    value += (0.7 + 0.9 * mid) * sin((p.x + p.y + flow) * 0.5);
    float2 center = float2(sin(flow * 0.31) * 3.0, cos(flow * 0.23) * 3.0);
    value += (0.7 + 1.0 * bass) * sin(length(p + center) * (1.0 + 0.3 * beat) + flow * 1.3);
    // Fine shimmer from the treble.
    value += 0.8 * treble * sin(p.x * 2.3 - p.y * 1.9 + flow * 3.1);

    // Around the palette loop twice; the treble slides the colors along.
    float along = fract(value * 0.25 + treble * 0.35);
    float stop = along * 4.0;
    int index = int(floor(stop));
    float blend = smoothstep(0.0, 1.0, stop - floor(stop));
    half4 from = index == 0 ? c0 : index == 1 ? c1 : index == 2 ? c2 : c3;
    half4 to = index == 0 ? c1 : index == 1 ? c2 : index == 2 ? c3 : c0;
    half3 rgb = mix(from.rgb, to.rgb, half(blend));

    // A soft fade at the edges, and at most a slight lift on beats: no strobing.
    float vignette = mix(0.55, 1.0, smoothstep(0.95, 0.25, length(uv)));
    float lift = 0.9 + 0.1 * beat;
    return half4(rgb * half(vignette * lift), 1.0);
}
