#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The Chrome visualizer: a blob of liquid metal reflecting the album cover.
///
/// The outline comes from `radii` (`ChromeBlob` in the core package): how far
/// the blob reaches at each angle, as a multiple of `radius`. Inside, the blob
/// is treated as a dome; its slope gives a surface direction at each pixel,
/// and that direction picks which part of `cover` is reflected there, like a
/// polished ball. Beats send rings across the surface (`beat`, moving with
/// `time`). `drops` are the splashed droplets (`ChromeSplash`), three floats
/// each: position and size in radii; they melt into the blob as they near it. The edges catch a colored light (`rim0`…`rim3`, around the
/// blob), and a highlight sits at the top left, where the light comes from.

/// The outline's reach at screen angle `angle`, curving smoothly through the
/// points (Catmull-Rom), so the surface shows no ridges between them.
static float reach(float angle, device const float *radii, int count) {
    float at = fract(angle / (2.0 * M_PI_F)) * float(count);
    int i1 = int(floor(at)) % count;
    int i0 = (i1 + count - 1) % count;
    int i2 = (i1 + 1) % count;
    int i3 = (i1 + 2) % count;
    float t = at - floor(at);
    float p0 = radii[i0], p1 = radii[i1], p2 = radii[i2], p3 = radii[i3];
    return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
}

/// Blends two distances so shapes that come close melt together with a
/// neck between them instead of just touching (a smooth minimum).
static float smoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// The blob and its droplets at `p` (relative to the middle, in pixels):
/// `x` is the distance to the surface (negative inside), `y` how high the
/// metal stands there, 1 at the blob's middle. Each piece is a dome; where
/// they melt together, the neck's height comes from how deep inside it is.
/// Beat rings ripple the blob's surface.
static float2 shape(
    float2 p, float radius, device const float *radii, int count,
    device const float *drops, int dropFloats, float time, float beat
) {
    float distanceFromMiddle = length(p);
    float edge = radius * reach(atan2(p.y, p.x), radii, count);
    float along = distanceFromMiddle / edge;
    float surface = distanceFromMiddle - edge;
    float height = along < 1.0 ? sqrt(1.0 - along * along) + 0.04 * beat * sin(along * 22.0 - time * 9.0) * (1.0 - along) : 0.0;

    for (int i = 0; i + 2 < dropFloats; i += 3) {
        float size = drops[i + 2] * radius;
        if (size <= 0.0) { continue; }
        float2 offset = p - float2(drops[i], drops[i + 1]) * radius;
        float fromDrop = length(offset);
        surface = smoothUnion(surface, fromDrop - size, radius * 0.3);
        float q = fromDrop / size;
        // A droplet is a low bead: its height in proportion to its size.
        float bead = q < 1.0 ? sqrt(1.0 - q * q) * (size / radius) * 1.8 : 0.0;
        height = max(height, bead);
    }
    float neck = clamp(-surface / (radius * 0.2), 0.0, 1.0) * 0.2;
    return float2(surface, max(height, neck));
}

[[ stitchable ]] half4 chrome(
    float2 position, half4 color,
    float2 size, float radius,
    device const float *radii, int count,
    device const float *drops, int dropFloats,
    float time, float beat,
    half4 rim0, half4 rim1, half4 rim2, half4 rim3,
    texture2d<half> cover
) {
    float2 p = position - size * 0.5;
    float2 here = shape(p, radius, radii, count, drops, dropFloats, time, beat);
    // Outside, past a pixel of soft edge.
    if (here.x > 1.0) { return half4(0.0); }

    // The surface's slope from neighboring heights gives its direction.
    float hx = shape(p + float2(1.0, 0.0), radius, radii, count, drops, dropFloats, time, beat).y;
    float hy = shape(p + float2(0.0, 1.0), radius, radii, count, drops, dropFloats, time, beat).y;
    float steepness = radius * 0.6;
    float3 normal = normalize(float3(-(hx - here.y) * steepness, -(hy - here.y) * steepness, 1.0));

    // Looking straight down at it, what's reflected is off toward the slope.
    float3 reflected = reflect(float3(0.0, 0.0, -1.0), normal);
    float2 uv = clamp(0.5 + reflected.xy * 0.5, 0.0, 1.0);
    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
    half3 mirror = cover.sample(linearSampler, uv).rgb;

    // Steel: the reflection, toned toward gray-blue, darker facing away.
    half3 steel = mix(half3(0.18, 0.2, 0.23), half3(0.85, 0.87, 0.9), half(0.5 + 0.5 * -reflected.y));
    half3 metal = mix(steel, mirror, 0.7h);

    // Colored light catching the edges, its color going around the blob.
    float rimAmount = pow(1.0 - normal.z, 2.5);
    float turn = fract(atan2(p.y, p.x) / (2.0 * M_PI_F) + 0.25);
    float stop = turn * 4.0;
    int index = int(floor(stop)) % 4;
    half4 from = index == 0 ? rim0 : index == 1 ? rim1 : index == 2 ? rim2 : rim3;
    half4 to = index == 0 ? rim1 : index == 1 ? rim2 : index == 2 ? rim3 : rim0;
    half3 rim = mix(from.rgb, to.rgb, half(smoothstep(0.0, 1.0, fract(stop))));
    metal = mix(metal, rim, half(rimAmount * 0.75));

    // The highlight, from a light at the top left.
    float3 light = normalize(float3(-0.45, -0.6, 0.65));
    float shine = pow(max(dot(reflect(-light, normal), float3(0.0, 0.0, 1.0)), 0.0), 40.0);
    metal += half3(shine * 0.9);

    float coverage = 1.0 - smoothstep(-1.0, 1.0, here.x);
    return half4(metal * half(coverage), half(coverage));
}
