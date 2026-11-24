#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float sdRoundBox(float2 p, float2 b, float r) {
    float rr = min(r, min(b.x, b.y));
    float2 q = abs(p) - b + rr;
    return min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f)) - rr;
}

[[ stitchable ]] half4 liquidGlass(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float2 center,
    float2 halfSize,
    float radius,
    float refraction,
    float bezel,
    float dispersion,
    float frost,
    float2 lightPos
) {
    half4 base = layer.sample(position);
    float2 rel = position - center;
    float sd = sdRoundBox(rel, halfSize, radius);

    if (sd > 1.5f) {
        float shadowDist = sdRoundBox(rel - float2(0.0f, 10.0f), halfSize, radius);
        if (shadowDist > 0.0f && shadowDist < 42.0f) {
            float shadow = exp(-shadowDist * 0.09f) * 0.36f;
            return half4(base.rgb * half(1.0f - shadow), base.a);
        }
        return base;
    }

    float eps = 1.0f;
    float2 grad = float2(
        sdRoundBox(rel + float2(eps, 0.0f), halfSize, radius) - sdRoundBox(rel - float2(eps, 0.0f), halfSize, radius),
        sdRoundBox(rel + float2(0.0f, eps), halfSize, radius) - sdRoundBox(rel - float2(0.0f, eps), halfSize, radius)
    );
    float gLen = length(grad);
    float2 n = gLen > 1e-4f ? grad / gLen : float2(0.0f, -1.0f);

    float dist = max(0.0f, -sd);
    float bz = max(2.0f, min(bezel, min(halfSize.x, halfSize.y)));
    float t = clamp(dist / bz, 0.0f, 1.0f);
    float edgeCurve = (1.0f - t) * (1.0f - t);

    float2 disp = -n * edgeCurve * 0.72f - (rel / max(halfSize, float2(1.0f))) * 0.28f;
    float2 offset = disp * refraction;

    float2 posR = position + offset;
    float2 posG = position + offset * (1.0f - dispersion);
    float2 posB = position + offset * (1.0f - 2.0f * dispersion);

    float3 refracted;
    if (frost <= 0.1f) {
        refracted.r = float(layer.sample(posR).r);
        refracted.g = float(layer.sample(posG).g);
        refracted.b = float(layer.sample(posB).b);
    } else {
        float r = frost * 2.2f;
        float2 o1 = float2( r,  0.0f);
        float2 o2 = float2(-r,  0.0f);
        float2 o3 = float2( 0.0f,  r);
        float2 o4 = float2( 0.0f, -r);

        refracted.r = float(layer.sample(posR).r) * 0.28f
                    + float(layer.sample(posR + o1).r) * 0.18f
                    + float(layer.sample(posR + o2).r) * 0.18f
                    + float(layer.sample(posR + o3).r) * 0.18f
                    + float(layer.sample(posR + o4).r) * 0.18f;

        refracted.g = float(layer.sample(posG).g) * 0.28f
                    + float(layer.sample(posG + o1).g) * 0.18f
                    + float(layer.sample(posG + o2).g) * 0.18f
                    + float(layer.sample(posG + o3).g) * 0.18f
                    + float(layer.sample(posG + o4).g) * 0.18f;

        refracted.b = float(layer.sample(posB).b) * 0.28f
                    + float(layer.sample(posB + o1).b) * 0.18f
                    + float(layer.sample(posB + o2).b) * 0.18f
                    + float(layer.sample(posB + o3).b) * 0.18f
                    + float(layer.sample(posB + o4).b) * 0.18f;
    }

    float luma = dot(refracted, float3(0.2126f, 0.7152f, 0.0722f));
    refracted = clamp(mix(float3(luma), refracted, 1.45f), 0.0f, 1.0f);

    float2 toLight = lightPos - center;
    float2 lDir = length(toLight) > 1.0f ? normalize(toLight) : normalize(float2(-0.6f, -0.8f));
    float rimAlign = abs(dot(n, lDir));
    float rim = smoothstep(2.4f, 0.0f, dist) * (0.28f + 0.72f * pow(rimAlign, 2.0f));
    float innerGlow = smoothstep(16.0f, 0.0f, dist) * (0.12f + 0.22f * max(0.0f, dot(-n, lDir)));

    float3 glassCol = clamp(refracted + float3(1.0f) * (rim * 0.85f + innerGlow), 0.0f, 1.0f);
    float mask = smoothstep(1.2f, -0.8f, sd);
    float3 outCol = mix(float3(base.rgb), glassCol, mask);

    return half4(half3(outCol), base.a);
}
