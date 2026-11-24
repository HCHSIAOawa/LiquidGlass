#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

float sdRoundBox(float2 p, float2 b, float r) {
    float rr = min(r, min(b.x, b.y));
    float2 q = abs(p) - b + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
}

float3 sampleFrosted(SwiftUI::Layer layer, float2 pos, float frost) {
    if (frost <= 0.1) {
        return layer.sample(pos).rgb;
    }
    float r = frost * 2.2;
    float3 sum = layer.sample(pos).rgb * 0.28;
    sum += layer.sample(pos + float2( r,  0.0)).rgb * 0.18;
    sum += layer.sample(pos + float2(-r,  0.0)).rgb * 0.18;
    sum += layer.sample(pos + float2( 0.0,  r)).rgb * 0.18;
    sum += layer.sample(pos + float2( 0.0, -r)).rgb * 0.18;
    return sum;
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

    // 鏡頭外部：僅繪製柔和投影
    if (sd > 1.5) {
        float shadowDist = sdRoundBox(rel - float2(0.0, 10.0), halfSize, radius);
        if (shadowDist > 0.0 && shadowDist < 42.0) {
            float shadow = exp(-shadowDist * 0.09) * 0.36;
            return half4(base.rgb * half(1.0 - shadow), base.a);
        }
        return base;
    }

    // 計算法線方向與邊緣倒角深度
    float eps = 1.0;
    float2 grad = float2(
        sdRoundBox(rel + float2(eps, 0.0), halfSize, radius) - sdRoundBox(rel - float2(eps, 0.0), halfSize, radius),
        sdRoundBox(rel + float2(0.0, eps), halfSize, radius) - sdRoundBox(rel - float2(0.0, eps), halfSize, radius)
    );
    float gLen = length(grad);
    float2 n = gLen > 1e-4 ? grad / gLen : float2(0.0, -1.0);

    float dist = max(0.0, -sd);
    float bz = max(2.0, min(bezel, min(halfSize.x, halfSize.y)));
    float t = clamp(dist / bz, 0.0, 1.0);
    float edgeCurve = (1.0 - t) * (1.0 - t);

    // 結合邊緣折射與中央微放大效果
    float2 disp = -n * edgeCurve * 0.72 - (rel / max(halfSize, float2(1.0))) * 0.28;
    float2 offset = disp * refraction;

    // RGB 三通道微幅錯位產生彩虹色散
    float3 refracted;
    refracted.r = sampleFrosted(layer, position + offset, frost).r;
    refracted.g = sampleFrosted(layer, position + offset * (1.0 - dispersion), frost).g;
    refracted.b = sampleFrosted(layer, position + offset * (1.0 - 2.0 * dispersion), frost).b;

    // 提升玻璃內部色彩飽和度
    float luma = dot(refracted, float3(0.2126, 0.7152, 0.0722));
    refracted = clamp(mix(float3(luma), refracted, 1.45), 0.0, 1.0);

    // 菲涅耳邊緣高光（隨手指位置動態變化）
    float2 toLight = lightPos - center;
    float2 lDir = length(toLight) > 1.0 ? normalize(toLight) : normalize(float2(-0.6, -0.8));
    float rimAlign = abs(dot(n, lDir));
    float rim = smoothstep(2.4, 0.0, dist) * (0.28 + 0.72 * pow(rimAlign, 2.0));
    float innerGlow = smoothstep(16.0, 0.0, dist) * (0.12 + 0.22 * max(0.0, dot(-n, lDir)));

    float3 glassCol = clamp(refracted + float3(1.0) * (rim * 0.85 + innerGlow), 0.0, 1.0);
    float mask = smoothstep(1.2, -0.8, sd);
    float3 outCol = mix(float3(base.rgb), glassCol, mask);

    return half4(half3(outCol), base.a);
}
