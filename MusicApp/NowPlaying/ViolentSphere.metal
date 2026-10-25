#include <metal_stdlib>
using namespace metal;

/// The Violent Sphere visualizer (ViolentSphereView.swift draws with these).
/// Each point of the mesh is its direction times how far it reaches; the
/// ball is turned, set in perspective and colored by height on screen, the
/// palette running from `stops[0]` at the top to `stops[4]` at the bottom.
/// Spike tips are bright and the core is dark, so the spikes stand out.
///
/// The same vertex function draws the faces (dark, so they hide the wires
/// behind the ball) and the wires (pushed out a hair so they win over their
/// own faces). `look` is (brightness, push outward, unused, unused).

struct SphereVertex {
    float4 position [[position]];
    float4 color;
};

/// Turning, then scale and perspective: `frame` is (x scale, y scale,
/// camera distance, unused) and `center` the ball's middle in clip space.
vertex SphereVertex violentSphereVertex(
    uint id [[vertex_id]],
    const device packed_float3 *directions [[buffer(0)]],
    const device float *radii [[buffer(1)]],
    constant float4x4 &turn [[buffer(2)]],
    constant float4 *stops [[buffer(3)]],
    constant float4 &frame [[buffer(4)]],
    constant float4 &center [[buffer(5)]],
    constant float4 &look [[buffer(6)]]
) {
    float radius = radii[id];
    float3 point = (turn * float4(float3(directions[id]) * radius * look.y, 1)).xyz;

    // 0 at the top of the ball's reach, 1 at the bottom (y is up).
    float height = clamp(0.5 - point.y / 3.7, 0.0, 1.0);
    float scaled = height * 4;
    int low = min(int(scaled), 3);
    float4 color = mix(stops[low], stops[low + 1], scaled - float(low));
    float tip = clamp((radius - 1.0) / 0.7, 0.0, 1.0);
    color.rgb *= (0.3 + 0.7 * tip) * look.x;

    // Nearer points (larger z) are drawn bigger, and win the depth test.
    float w = (frame.z - point.z) / frame.z;
    SphereVertex out;
    out.position = float4(
        point.x * frame.x + center.x * w,
        point.y * frame.y + center.y * w,
        (2.5 - point.z) / 5 * w,
        w
    );
    out.color = float4(color.rgb, 1);
    return out;
}

fragment float4 violentSphereFragment(SphereVertex in [[stage_in]]) {
    return in.color;
}
