#include <metal_stdlib>
using namespace metal;

// MARK: - 16-Byte Aligned Uniform Structs (Matches PlaygroundModels.swift 1:1)

struct SceneUniforms {
    float4 viewportAndTime;   // x: widthPt, y: heightPt, z: timeSec, w: wallpaperMode (0..4)
    float4 opticalParams;     // x: refraction, y: bezel, z: dispersion, w: frost
    float4 lightingParams;    // x: lightDirX, y: lightDirY, z: tintMode (0..2), w: brightness
    float4 spotlightParams;   // x: originX, y: originY, z: dirX, w: strength (0..1)
    float4 layerFlags;        // x: elementCount, y: hasCustomPhoto, z: photoAspect, w: textOverlayMix
    float4 rippleParams;      // x: rippleCenterX, y: rippleCenterY, z: rippleRadiusPt, w: rippleStrength
    float4 atmosphereParams;  // x: atmosphereWarmth (-1..1), y: globalRimBoost, z: fusionK (pt), w: islandHalfHeightPt
    float4 islandParams;      // x: islandCenterX, y: islandCenterY, z: islandHalfWidthPt, w: islandPullStretchPt
};

struct GlassElementUniform {
    float4 centerAndHalfSize; // xy: centerPt, zw: halfSizePt
    float4 shapeAndTransform; // x: cornerRadiusPt, y: stretchAngleRad, z: stretchFactor, w: rimBoost
    float4 styleParams;       // x: opacity, y: refractionScale, z: frostBoost, w: shadowElevation
    float4 tintOverride;      // xyz: accentRGB, w: accentStrength (-1.0f = Dual-Droplet Fusion leader, -2.0f = Island-magnetic)
};

struct HourglassUniforms {
    float4 centerAndSize;       // x: centerX, y: centerY, z: halfWidth, w: halfHeight
    float4 morphAndFill;        // x: visibility (0..1), y: flipAngleRad, z: upperFill (0..1), w: lowerFill (0..1)
    float4 dropletParams;       // x: pinchPhase (0..1), y: dropLocalY (pt), z: dropRadius (pt), w: filamentThickness (pt)
    float4 impactAndAtmosphere; // x: impactWavePhase (0..1), y: impactStrength (0..1), z: causticBloom (0..1), w: modeBlend (0=Focus, 1=Rest)
    float4 dialRingParams;      // x: dialVisibility (0..1), y: dialRadiusPt, z: progressAngleRad, w: dialDragGlow (0..1)
    float4 dialLensParams;      // x: knobCenterX, y: knobCenterY, z: knobRadiusPt, w: knobTangentAngleRad
    float4 gravityAndZen;       // x: gravityTiltX, y: gravityTiltY, z: zenBreathGlow, w: knobStretch
    float4 neckAndStream;       // x: streamActive, y: dropStretch, z: satelliteLocalY, w: satelliteRadius
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut liquidGlassVertex(uint vid [[vertex_id]]) {
    VertexOut out;
    float2 uv = float2(float((vid << 1u) & 2u), float(vid & 2u));
    out.position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    out.uv = uv;
    return out;
}

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float sminPoly(float a, float b, float k) {
    float kk = max(k, 0.001f);
    float h = clamp(0.5f + 0.5f * (b - a) / kk, 0.0f, 1.0f);
    return mix(b, a, h) - kk * h * (1.0f - h);
}

static inline float smaxPoly(float a, float b, float k) {
    return -sminPoly(-a, -b, k);
}

// MARK: - Procedural Wallpaper Generators (With Focus Aurora vs. Break Dawn Atmospheric Blend)

static inline float3 wallpaperAurora(float2 uv, float aspect, float t, float modeBlend) {
    float2 p = float2((uv.x - 0.5f) * aspect, uv.y - 0.5f);

    float3 focusBase = mix(
        float3(0.020f, 0.038f, 0.098f),
        float3(0.048f, 0.088f, 0.195f),
        clamp(uv.y * 1.1f, 0.0f, 1.0f)
    );
    float3 breakBase = mix(
        float3(0.032f, 0.068f, 0.064f),
        float3(0.110f, 0.092f, 0.058f),
        clamp(uv.y * 1.1f, 0.0f, 1.0f)
    );
    float3 base = mix(focusBase, breakBase, modeBlend);

    float2 c1 = float2(sin(t * 0.62f) * 0.24f - 0.14f, cos(t * 0.46f) * 0.20f - 0.22f);
    float2 c2 = float2(cos(t * 0.54f) * 0.26f + 0.16f, sin(t * 0.40f) * 0.22f - 0.03f);
    float2 c3 = float2(sin(t * 0.48f + 1.6f) * 0.22f - 0.02f, cos(t * 0.58f) * 0.19f + 0.24f);
    float2 c4 = float2(cos(t * 0.36f + 2.4f) * 0.20f + 0.10f, sin(t * 0.50f + 0.9f) * 0.24f + 0.16f);

    float g1 = exp(-dot(p - c1, p - c1) * 7.0f);
    float g2 = exp(-dot(p - c2, p - c2) * 6.2f);
    float g3 = exp(-dot(p - c3, p - c3) * 7.6f);
    float g4 = exp(-dot(p - c4, p - c4) * 8.8f);

    float ribbon = sin(p.x * 5.2f + sin(p.y * 4.0f + t * 0.78f) * 1.6f + t * 0.52f) * 0.5f + 0.5f;
    ribbon = pow(max(0.0f, ribbon), 2.2f) * exp(-abs(p.y + 0.05f) * 3.1f);

    float3 colFocus = base
        + float3(0.16f, 0.58f, 1.00f) * (g1 * 0.78f)
        + float3(0.38f, 0.34f, 0.96f) * (g2 * 0.84f)
        + float3(0.05f, 0.84f, 0.88f) * (g3 * 0.78f)
        + float3(0.45f, 0.92f, 1.00f) * (g4 * 0.36f + ribbon * 0.28f);

    float3 colBreak = base
        + float3(0.98f, 0.68f, 0.22f) * (g1 * 0.72f)
        + float3(0.12f, 0.78f, 0.52f) * (g2 * 0.82f)
        + float3(0.24f, 0.88f, 0.64f) * (g3 * 0.74f)
        + float3(1.00f, 0.84f, 0.42f) * (g4 * 0.42f + ribbon * 0.30f);

    return clamp(mix(colFocus, colBreak, modeBlend), 0.0f, 1.0f);
}

static inline float3 wallpaperRainbowStripes(float2 uv, float aspect, float t) {
    float2 p = float2((uv.x - 0.5f) * aspect, uv.y - 0.5f);
    float wave = sin(p.y * 4.5f + t * 0.55f) * 0.065f;
    float coord = (p.x * 0.86f + p.y * 0.50f + wave) * 5.6f - t * 0.28f;

    float3 pal = 0.54f + 0.44f * cos(6.2831853f * (coord * 0.22f + float3(0.00f, 0.33f, 0.67f)));
    float band = fract(coord);
    float crispEdge = smoothstep(0.0f, 0.06f, band) * smoothstep(1.0f, 0.94f, band);
    float3 deepAccent = pal * (0.72f + 0.32f * crispEdge);

    float vig = 1.0f - 0.24f * dot(p, p);
    return clamp(deepAccent * vig, 0.0f, 1.0f);
}

static inline float3 wallpaperSunsetRings(float2 uv, float aspect, float t) {
    float2 sunCenter = float2(0.0f, -0.06f);
    float2 p = float2((uv.x - 0.5f) * aspect, uv.y - 0.5f) - sunCenter;
    float r = length(p);

    float3 skyTop = float3(0.11f, 0.07f, 0.24f);
    float3 skyMid = float3(0.76f, 0.22f, 0.40f);
    float3 skyBot = float3(1.00f, 0.58f, 0.20f);
    float3 grad = uv.y < 0.52f
        ? mix(skyTop, skyMid, clamp(uv.y / 0.52f, 0.0f, 1.0f))
        : mix(skyMid, skyBot, clamp((uv.y - 0.52f) / 0.48f, 0.0f, 1.0f));

    float ringPhase = r * 26.0f - t * 0.85f;
    float rings = sin(ringPhase);
    float sharpRing = smoothstep(0.55f, 0.96f, rings);
    float sunCore = exp(-r * 4.4f);

    float3 ringColor = mix(float3(1.0f, 0.76f, 0.34f), float3(1.0f, 0.95f, 0.80f), sunCore);
    float3 col = grad + ringColor * (sharpRing * 0.34f * exp(-r * 1.6f) + sunCore * 0.55f);

    if (p.y > 0.14f) {
        float waterStripe = sin((p.y - 0.14f) * 95.0f + sin(p.x * 18.0f + t * 1.4f) * 1.8f);
        float reflectMask = exp(-abs(p.x) * 3.6f) * smoothstep(0.14f, 0.24f, p.y);
        col += float3(1.0f, 0.72f, 0.35f) * max(0.0f, waterStripe) * reflectMask * 0.28f;
    }

    return clamp(col, 0.0f, 1.0f);
}

static inline float3 wallpaperMinimalGrid(float2 posPt, float2 viewport, float frostBlur) {
    float2 uv = posPt / max(viewport, float2(1.0f));
    float3 paper = mix(
        float3(0.945f, 0.952f, 0.968f),
        float3(0.885f, 0.902f, 0.935f),
        clamp(uv.y * 0.85f + uv.x * 0.15f, 0.0f, 1.0f)
    );

    float aa = 0.85f + frostBlur * 1.8f;

    float2 minorDist = abs(fract(posPt / 24.0f + 0.5f) - 0.5f) * 24.0f;
    float minorLine = 1.0f - smoothstep(0.45f, 0.45f + aa, min(minorDist.x, minorDist.y));

    float2 majorDist = abs(fract(posPt / 120.0f + 0.5f) - 0.5f) * 120.0f;
    float majorLine = 1.0f - smoothstep(0.85f, 0.85f + aa, min(majorDist.x, majorDist.y));

    float2 centerDist = abs(posPt - viewport * float2(0.5f, 0.48f));
    float axisLineX = 1.0f - smoothstep(0.7f, 0.7f + aa, centerDist.x);
    float axisLineY = 1.0f - smoothstep(0.7f, 0.7f + aa, centerDist.y);

    float3 col = paper;
    col = mix(col, float3(0.76f, 0.80f, 0.87f), minorLine * 0.55f);
    col = mix(col, float3(0.42f, 0.52f, 0.72f), majorLine * 0.65f);
    col = mix(col, float3(0.92f, 0.28f, 0.42f), axisLineX * 0.35f);
    col = mix(col, float3(0.14f, 0.58f, 0.88f), axisLineY * 0.35f);
    return col;
}

static inline float2 applyShockwaveRipple(float2 samplePt, constant SceneUniforms &scene) {
    float strength = scene.rippleParams.w;
    if (strength <= 0.002f) {
        return samplePt;
    }
    float2 delta = samplePt - scene.rippleParams.xy;
    float dist = length(delta);
    float ringDist = dist - scene.rippleParams.z;
    if (abs(ringDist) > 52.0f || dist < 1.0f) {
        return samplePt;
    }
    float envelope = exp(-(ringDist * ringDist) * 0.0026f) * strength;
    float wave = sin(ringDist * 0.22f) * envelope * 24.0f;
    return samplePt + (delta / dist) * wave;
}

static inline float3 sampleSceneBackground(
    float2 rawSamplePt,
    float frostAmount,
    float modeBlend,
    constant SceneUniforms &scene,
    texture2d<float, access::sample> textTex,
    texture2d<float, access::sample> photoTex
) {
    constexpr sampler repeatSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    constexpr sampler clampSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

    float2 samplePt = applyShockwaveRipple(rawSamplePt, scene);
    float2 viewport = max(scene.viewportAndTime.xy, float2(1.0f));
    float time = scene.viewportAndTime.z;
    int mode = int(scene.viewportAndTime.w + 0.5f);
    float aspect = viewport.x / viewport.y;
    float2 uv = samplePt / viewport;
    float mipLod = clamp(frostAmount * 1.25f, 0.0f, 5.0f);

    float3 bg;
    if (mode == 4 && scene.layerFlags.y > 0.5f) {
        float photoAspect = max(scene.layerFlags.z, 0.05f);
        float2 photoUV = uv - 0.5f;
        if (aspect > photoAspect) {
            photoUV.y *= photoAspect / aspect;
        } else {
            photoUV.x *= aspect / photoAspect;
        }
        photoUV += 0.5f;
        bg = photoTex.sample(clampSampler, photoUV, level(mipLod)).rgb;
    } else if (mode == 1) {
        bg = wallpaperRainbowStripes(uv, aspect, time);
    } else if (mode == 2) {
        bg = wallpaperSunsetRings(uv, aspect, time);
    } else if (mode == 3) {
        bg = wallpaperMinimalGrid(samplePt, viewport, frostAmount);
    } else {
        bg = wallpaperAurora(uv, aspect, time, modeBlend);
    }

    float textMix = scene.layerFlags.w;
    if (textMix > 0.01f) {
        float2 centered = samplePt - viewport * 0.5f;
        float2 rotated = float2(
            centered.x * 0.990268f - centered.y * (-0.139173f),
            centered.x * (-0.139173f) + centered.y * 0.990268f
        );
        float2 tileUV = rotated / float2(820.0f, 520.0f) + 0.5f;
        int rowIdx = int(floor(tileUV.y * 8.0f));
        float dir = ((rowIdx & 1) == 0) ? -1.0f : 1.0f;
        tileUV.x += time * 0.036f * dir;

        float4 txt = textTex.sample(repeatSampler, tileUV, level(mipLod));
        if (mode == 3) {
            float3 inkColor = ((rowIdx & 1) == 0)
                ? float3(0.09f, 0.12f, 0.20f)
                : float3(0.08f, 0.44f, 0.68f);
            bg = mix(bg, inkColor, txt.a * 0.86f * textMix);
        } else {
            bg = bg * (1.0f - txt.a * textMix) + txt.rgb * textMix;
        }
    }

    float warmth = scene.atmosphereParams.x;
    if (abs(warmth) > 0.01f) {
        float3 tint = warmth > 0.0f
            ? mix(float3(1.0f), float3(1.12f, 0.96f, 0.80f), warmth)
            : mix(float3(1.0f), float3(0.80f, 0.90f, 1.14f), -warmth);
        bg *= tint;
    }

    return bg * scene.lightingParams.w;
}

static inline float3 sampleFrostedRefraction(
    float2 posR,
    float2 posG,
    float2 posB,
    float frost,
    float modeBlend,
    float2 pixelSeed,
    constant SceneUniforms &scene,
    texture2d<float, access::sample> textTex,
    texture2d<float, access::sample> photoTex
) {
    if (frost <= 0.05f) {
        float r = sampleSceneBackground(posR, 0.0f, modeBlend, scene, textTex, photoTex).r;
        float g = sampleSceneBackground(posG, 0.0f, modeBlend, scene, textTex, photoTex).g;
        float b = sampleSceneBackground(posB, 0.0f, modeBlend, scene, textTex, photoTex).b;
        return float3(r, g, b);
    }

    float radius = frost * 2.4f;
    float angle = (hash12(pixelSeed) - 0.5f) * 0.40f + 0.52f;
    float2 d1 = float2(cos(angle), sin(angle)) * radius;
    float2 d2 = float2(-d1.y, d1.x);

    float r = 0.5f * (
        sampleSceneBackground(posR + d1, frost, modeBlend, scene, textTex, photoTex).r +
        sampleSceneBackground(posR - d1, frost, modeBlend, scene, textTex, photoTex).r
    );
    float g = sampleSceneBackground(posG + d2 * 0.5f, frost, modeBlend, scene, textTex, photoTex).g;
    float b = 0.5f * (
        sampleSceneBackground(posB - d2, frost, modeBlend, scene, textTex, photoTex).b +
        sampleSceneBackground(posB + d2, frost, modeBlend, scene, textTex, photoTex).b
    );
    return float3(r, g, b);
}

// MARK: - Core Analytic SDF Primitives

static inline float2 applyLiquidDeform(float2 rel, float2 uDir, float stretch) {
    float2 vDir = float2(-uDir.y, uDir.x);
    float invStretch = 1.0f / max(stretch, 0.45f);
    float projU = dot(rel, uDir) * invStretch;
    float projV = dot(rel, vDir) * stretch;
    return uDir * projU + vDir * projV;
}

static inline float sdRoundBox(float2 p, float2 b, float r) {
    float rr = min(r, min(b.x, b.y));
    float2 q = abs(p) - b + rr;
    return min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f)) - rr;
}

static inline float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4f), 0.0f, 1.0f);
    return length(pa - ba * h);
}

static inline float sdRoundConeY(float2 p, float r1, float r2, float h) {
    float2 q = float2(abs(p.x), p.y);
    float b = (r1 - r2) / h;
    float a = sqrt(max(1.0f - b * b, 1e-4f));
    float k = dot(q, float2(-b, a));
    if (k < 0.0f) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0f, h)) - r2;
    return dot(q, float2(a, b)) - r1;
}

static inline float3 sdAndNormalDeformedBox(
    float2 rel,
    float2 halfSize,
    float radius,
    float2 uDir,
    float stretch
) {
    float2 p = applyLiquidDeform(rel, uDir, stretch);
    float rr = min(radius, min(halfSize.x, halfSize.y));
    float2 inner = max(halfSize - rr, float2(0.0f));
    float2 absP = abs(p);
    float2 q = absP - inner;
    float2 w = max(q, 0.0f);
    float lenW = length(w);
    float sd = min(max(q.x, q.y), 0.0f) + lenW - rr;

    float2 signs = float2(p.x >= 0.0f ? 1.0f : -1.0f, p.y >= 0.0f ? 1.0f : -1.0f);
    float2 localN;
    if (lenW > 1e-3f) {
        localN = signs * (w / lenW);
    } else {
        float2 edgeProx = exp(q * 0.18f);
        float2 rawN = signs * edgeProx;
        float rawLen = length(rawN);
        localN = rawLen > 1e-4f ? (rawN / rawLen) : float2(0.0f, -1.0f);
    }

    float2 worldGrad = applyLiquidDeform(localN, uDir, stretch);
    float gLen = length(worldGrad);
    float2 n = gLen > 1e-4f ? (worldGrad / gLen) : float2(0.0f, -1.0f);
    return float3(sd, n.x, n.y);
}

static inline float evaluateSpotlight(float2 posPt, constant SceneUniforms &scene) {
    float strength = scene.spotlightParams.w;
    if (strength <= 0.002f) {
        return 0.0f;
    }
    float2 origin = scene.spotlightParams.xy;
    float2 delta = posPt - origin;
    float dist = length(delta);
    float2 beamDir = normalize(float2(scene.spotlightParams.z, 0.88f));
    float2 dir = dist > 1.0f ? (delta / dist) : beamDir;
    float cone = max(0.0f, dot(dir, beamDir));
    float beam = pow(cone, 7.0f) * exp(-dist * 0.0016f);
    float halo = exp(-dist * 0.012f) * 0.55f;
    return (beam + halo) * strength;
}

// MARK: - Dual-Chamber Liquid Glass Hourglass Analytic SDF + Droplet Pinch-Off + Caustics

/// Symmetric sculptural dual-bulb glass shell SDF in hourglass-local coordinates `p`.
static inline float sdHourglassOuterShell(float2 p) {
    float2 symP = float2(abs(p.x), abs(p.y));

    // Tapered optical bulb from waist (0, 8) r=9.5 up to shoulder (0, 82) r=59.0
    float sdCone = sdRoundConeY(float2(symP.x, symP.y - 8.0f), 9.5f, 59.0f, 74.0f);
    // Wide cylindrical glass reservoir chamber
    float sdReservoir = sdRoundBox(symP - float2(0.0f, 94.0f), float2(59.0f, 22.0f), 20.0f);
    float sdBulb = sminPoly(sdCone, sdReservoir, 10.0f);

    // Hyperbolic waist neck collar
    float sdWaist = sdRoundBox(symP, float2(11.5f, 13.0f), 5.5f);
    float sdBody = sminPoly(sdBulb, sdWaist, 11.0f);

    // Sculpted bevelled glass end-caps at y = ±118pt
    float sdEndCap = sdRoundBox(symP - float2(0.0f, 117.5f), float2(64.5f, 5.2f), 5.2f);
    return sminPoly(sdBody, sdEndCap, 5.5f);
}

/// Inner hollow fluid cavity SDF (8.2pt crystal glass wall + open capillary orifice channel at waist).
static inline float sdHourglassInnerCavity(float2 p) {
    float sdShell = sdHourglassOuterShell(p);
    // Keep end-caps solid crystal glass beyond |y| = 110pt
    float capClip = abs(p.y) - 110.0f;
    float chamberRaw = max(sdShell + 8.2f, capClip);
    // Open capillary orifice tube (half-width 4.8pt) connecting upper & lower chambers
    float neckTube = max(abs(p.x) - 4.8f, abs(p.y) - 18.0f);
    return sminPoly(chamberRaw, neckTube, 3.5f);
}

static inline float evaluateCausticWeb(float2 p, float time, float impactPhase, float impactStrength) {
    float2 cp = p * 0.068f + float2(time * 0.42f, -time * 0.34f);
    cp += float2(
        sin(cp.y * 3.1f + impactPhase * 6.28318f),
        cos(cp.x * 2.8f - impactPhase * 6.28318f)
    ) * (0.42f + impactStrength * 0.58f);
    float c1 = abs(sin(cp.x * 3.9f + sin(cp.y * 2.9f)));
    float c2 = abs(cos(cp.y * 4.2f + cos(cp.x * 3.4f)));
    return pow(clamp(1.0f - min(c1, c2), 0.0f, 1.0f), 3.4f);
}

static inline float3 renderLiquidHourglassAndDial(
    float2 posPt,
    float3 baseColor,
    float2 pixelSeed,
    float2 lightDir,
    constant SceneUniforms &scene,
    constant HourglassUniforms &hg,
    texture2d<float, access::sample> textTex,
    texture2d<float, access::sample> photoTex
) {
    float vis = hg.morphAndFill.x;
    if (vis <= 0.004f) {
        return baseColor;
    }

    float3 color = baseColor;
    float2 hgCenter = hg.centerAndSize.xy;
    float time = scene.viewportAndTime.z;
    float modeBlend = clamp(hg.impactAndAtmosphere.w, 0.0f, 1.0f);
    float zenGlow = hg.gravityAndZen.z;

    float2 relWorld = posPt - hgCenter;
    float distCenter = length(relWorld);

    // 1. Zen Meditative Breathing Aura + Ambient Mode Glow around Hourglass
    if (distCenter < 245.0f) {
        float breath = 0.72f + 0.28f * sin(time * 1.35f);
        float auraFalloff = exp(-(distCenter * distCenter) * 0.000048f);
        float3 focusAura = float3(0.14f, 0.62f, 0.98f);
        float3 breakAura = float3(0.22f, 0.86f, 0.60f);
        float3 auraTint = mix(focusAura, breakAura, modeBlend);
        color += auraTint * auraFalloff * (0.07f + 0.16f * zenGlow * breath) * vis;
    }

    // 2. Tactile Radial Optical Time Dial Track (Ring + Minute Ticks + Progress Arc)
    float dialVis = hg.dialRingParams.x * vis;
    float dialRadius = hg.dialRingParams.y;
    float progAngle = hg.dialRingParams.z;
    float dialDragGlow = hg.dialRingParams.w;

    if (dialVis > 0.005f && abs(distCenter - dialRadius) < 22.0f) {
        float ringSD = abs(distCenter - dialRadius) - (1.8f + 0.7f * dialDragGlow);
        if (ringSD < 8.0f) {
            // Angle clockwise from 12 o'clock (0 .. 2*pi)
            float rawAng = atan2(relWorld.x, -relWorld.y);
            float cwAngle = rawAng < 0.0f ? (rawAng + 6.2831853f) : rawAng;

            // 55 minute intervals (5..60 min mapped around full 360° circle)
            float tickCoord = (cwAngle / 6.2831853f) * 55.0f;
            float nearestTick = abs(fract(tickCoord + 0.5f) - 0.5f);
            float fiveMinCoord = (cwAngle / 6.2831853f) * 11.0f;
            float majorTick = abs(fract(fiveMinCoord + 0.5f) - 0.5f);

            float minorTickMask = smoothstep(0.13f, 0.02f, nearestTick) * smoothstep(7.5f, 3.2f, abs(distCenter - (dialRadius + 6.0f)));
            float majorTickMask = smoothstep(0.06f, 0.01f, majorTick) * smoothstep(9.5f, 2.5f, abs(distCenter - (dialRadius + 6.8f)));

            float trackMask = smoothstep(1.3f, -0.5f, ringSD);
            float inProgressArc = smoothstep(progAngle + 0.025f, progAngle - 0.025f, cwAngle);

            float3 activeArcCol = mix(
                float3(0.22f, 0.78f, 1.0f),
                float3(0.32f, 0.92f, 0.64f),
                modeBlend
            );
            float3 ringCol = mix(float3(0.75f, 0.85f, 0.98f) * 0.34f, activeArcCol, inProgressArc);

            color = mix(color, ringCol + float3(0.22f) * dialDragGlow, trackMask * (0.62f + 0.32f * inProgressArc) * dialVis);
            color += activeArcCol * (minorTickMask * 0.28f + majorTickMask * 0.58f) * dialVis;
        }
    }

    // 3. Transform into Hourglass Local Frame (Supports Physical 180° Smooth Flip Rotation + Scale!)
    float invScale = 1.0f / max(0.35f, 0.94f + 0.06f * vis + 0.05f * zenGlow);
    float flipAngle = hg.morphAndFill.y;
    float ca = cos(flipAngle);
    float sa = sin(flipAngle);
    float2 scaledRel = relWorld * invScale;
    float2 p = float2(
        ca * scaledRel.x + sa * scaledRel.y,
        -sa * scaledRel.x + ca * scaledRel.y
    );

    // Projected Floor Caustic Apron beneath Lower Glass Chamber
    float causticBloom = hg.impactAndAtmosphere.z;
    float impactPhase = hg.impactAndAtmosphere.x;
    float impactStrength = hg.impactAndAtmosphere.y;
    float lowerFill = hg.morphAndFill.w;

    if (abs(p.x) < 88.0f && p.y > 86.0f && p.y < 158.0f && lowerFill > 0.01f) {
        float2 apronDelta = float2(p.x * 0.82f, (p.y - 124.0f) * 1.45f);
        float apronFalloff = exp(-dot(apronDelta, apronDelta) * 0.00052f);
        if (apronFalloff > 0.01f) {
            float cWebR = evaluateCausticWeb(p + float2(2.2f, 0.0f), time, impactPhase, impactStrength);
            float cWebG = evaluateCausticWeb(p, time, impactPhase, impactStrength);
            float cWebB = evaluateCausticWeb(p - float2(2.2f, 0.0f), time, impactPhase, impactStrength);
            float3 focusCaustic = float3(cWebR * 0.48f, cWebG * 0.88f, cWebB * 1.15f);
            float3 breakCaustic = float3(cWebR * 1.10f, cWebG * 0.92f, cWebB * 0.48f);
            float3 floorCaustic = mix(focusCaustic, breakCaustic, modeBlend);
            float intensity = (0.24f + 0.56f * causticBloom) * min(1.0f, lowerFill * 3.5f) * apronFalloff * vis;
            color += floorCaustic * intensity;
        }
    }

    // Bounding-box early out for Hourglass Glass & Fluid SDF
    if (abs(p.x) < 92.0f && abs(p.y) < 146.0f) {
        float sdShell = sdHourglassOuterShell(p);

        // Soft volumetric glass shadow + caustic rim under hourglass
        if (sdShell > -1.0f && sdShell < 34.0f) {
            float2 shadowP = p - (-lightDir * 9.0f + float2(0.0f, 11.0f));
            float shadowSD = sdHourglassOuterShell(shadowP);
            if (shadowSD < 30.0f) {
                float drop = exp(-max(0.0f, shadowSD) * 0.095f) * 0.28f * vis;
                color *= (1.0f - clamp(drop, 0.0f, 0.42f));
            }
        }

        if (sdShell < 1.25f) {
            // Finite-difference exact normal of sculpted hourglass glass shell
            const float eps = 0.65f;
            float gx = sdHourglassOuterShell(p + float2(eps, 0.0f)) - sdHourglassOuterShell(p - float2(eps, 0.0f));
            float gy = sdHourglassOuterShell(p + float2(0.0f, eps)) - sdHourglassOuterShell(p - float2(0.0f, eps));
            float2 localN = normalize(float2(gx, gy) + float2(1e-5f));
            // Rotate normal back to screen space for physically accurate lighting & refraction
            float2 worldN = float2(ca * localN.x - sa * localN.y, sa * localN.x + ca * localN.y);

            float shellDist = max(0.0f, -sdShell);
            float globalRef = scene.opticalParams.x;
            float globalDisp = max(0.06f, scene.opticalParams.z);
            float globalFrost = scene.opticalParams.w;

            // Evaluate Inner Cavity & Dual-Chamber Liquid + Pinch-Off Droplet Cascade SDF!
            float sdCavity = sdHourglassInnerCavity(p);
            float tiltX = clamp(hg.gravityAndZen.x, -0.75f, 0.75f);
            float upperFill = hg.morphAndFill.z;
            float streamActive = hg.neckAndStream.x;

            float sdLiquid = 1e4f;

            // A. Upper Chamber Remaining Liquid (p.y < -1.0)
            if (upperFill > 0.002f && p.y < 4.0f) {
                float hFracU = pow(clamp(upperFill, 0.0f, 1.0f), 0.65f);
                float upperSurfY = -4.0f - hFracU * 104.0f;
                float sloshU = p.x * tiltX * 0.46f;
                float vortexDimple = streamActive * 3.8f * exp(-abs(p.x) * 0.14f);
                float wallClimb = -2.4f * exp(-max(0.0f, -sdCavity) * 0.22f);
                float planeTop = (upperSurfY + sloshU + vortexDimple + wallClimb) - p.y;
                float planeNeck = p.y - (-1.2f);
                float sdUpperPool = smaxPoly(sdCavity, max(planeTop, planeNeck), 3.0f);
                sdLiquid = min(sdLiquid, sdUpperPool);
            }

            // B. Lower Chamber Accumulated Liquid + Droplet Impact Ripples (p.y > 1.0)
            if (lowerFill > 0.002f && p.y > -4.0f) {
                float hFracL = pow(clamp(lowerFill, 0.0f, 1.0f), 0.82f);
                float lowerSurfY = 110.0f - hFracL * 96.0f;
                float sloshL = p.x * tiltX * 0.46f;
                float rippleWave = sin(abs(p.x) * 0.28f - impactPhase * 16.0f)
                    * exp(-abs(p.x) * 0.024f)
                    * impactStrength * 4.4f;
                float crownDip = -cos(impactPhase * 9.0f) * exp(-abs(p.x) * 0.15f) * impactStrength * 4.8f;
                float wallClimbL = -2.2f * exp(-max(0.0f, -sdCavity) * 0.22f);
                float planeLower = (lowerSurfY + sloshL + rippleWave + crownDip + wallClimbL) - p.y;
                float sdLowerPool = smaxPoly(sdCavity, planeLower, 3.2f);
                sdLiquid = min(sdLiquid, sdLowerPool);
            }

            // C. Neck Pendant Meniscus + Capillary Filament Pinch-Off + Free-Falling Teardrop + Satellite Bead!
            float dropR = hg.dropletParams.z;
            if (dropR > 0.2f) {
                float pinchPhase = hg.dropletParams.x;
                float dropY = hg.dropletParams.y;
                float filamentW = hg.dropletParams.w;
                float dropStretch = clamp(hg.neckAndStream.y, 1.0f, 1.55f);
                float dropDriftX = tiltX * max(0.0f, dropY - 6.0f) * 0.22f;

                // Neck upper meniscus bulge right at orifice (0, -2pt)
                float sdMeniscus = length((p - float2(0.0f, -2.0f)) * float2(1.0f, 1.15f)) - 4.8f;
                sdLiquid = sminPoly(sdLiquid, max(sdMeniscus, sdCavity), 5.0f);

                // Elongated falling liquid teardrop
                float2 dRel = p - float2(dropDriftX, dropY);
                // Subtle teardrop taper (narrower top tail, rounder bottom belly)
                float taperX = 1.0f - clamp(dRel.y / max(dropR * 2.0f, 1.0f), -0.35f, 0.25f) * 0.28f;
                float sdDrop = length(float2(dRel.x / max(0.55f, taperX), dRel.y / dropStretch)) - dropR;

                if (filamentW > 0.15f && pinchPhase < 0.44f) {
                    // Surface-tension liquid thread before pinch-off!
                    float sdThread = sdSegment(p, float2(0.0f, -2.0f), float2(dropDriftX, dropY)) - filamentW;
                    float connectedDrop = sminPoly(sdThread, sdDrop, 5.5f);
                    sdLiquid = sminPoly(sdLiquid, max(connectedDrop, sdCavity), 6.5f);
                } else {
                    // Detached teardrop falling & merging smoothly into lower pool via smin on impact!
                    sdLiquid = sminPoly(sdLiquid, max(sdDrop, sdCavity), 9.5f);
                }

                // Plateau-Rayleigh capillary satellite micro-droplet trailing after snap!
                float satR = hg.neckAndStream.w;
                if (satR > 0.25f) {
                    float satY = hg.neckAndStream.z;
                    float sdSat = length(p - float2(dropDriftX * 0.55f, satY)) - satR;
                    sdLiquid = sminPoly(sdLiquid, max(sdSat, sdCavity), 3.5f);
                }
            } else if (streamActive > 0.05f && upperFill > 0.005f) {
                // Subtle poised meniscus bead at neck
                float sdBead = length(p - float2(0.0f, -1.5f)) - 4.2f * streamActive;
                sdLiquid = sminPoly(sdLiquid, max(sdBead, sdCavity), 4.5f);
            }

            // Glass Bevel Meniscus + High-Refraction Displacement
            float bz = clamp(scene.opticalParams.y * 0.72f, 8.0f, 34.0f);
            float tShell = clamp(shellDist / bz, 0.0f, 1.0f);
            float shellMeniscus = pow(1.0f - tShell, 2.2f);

            float liquidMask = smoothstep(0.85f, -0.85f, sdLiquid);
            float liquidDepth = clamp(-sdLiquid / 28.0f, 0.0f, 1.0f);

            // Compute fluid interior normal when inside liquid for rich internal meniscus refraction
            float2 fluidWorldN = float2(0.0f);
            if (sdLiquid < 3.0f) {
                float2 dLiq = float2(p.x / 52.0f, (p.y > 0.0f ? (p.y - 75.0f) : (p.y + 65.0f)) / 52.0f);
                fluidWorldN = float2(ca * dLiq.x - sa * dLiq.y, sa * dLiq.x + ca * dLiq.y);
            }

            float2 dispVec = (-worldN * shellMeniscus * 0.88f - fluidWorldN * liquidMask * 0.46f) * (globalRef * 1.12f);

            // Amplified RGB Chromatic Dispersion across Glass Bevel & Liquid Meniscus
            float dispMult = globalDisp * (2.65f + 3.45f * shellMeniscus + 1.40f * liquidMask);
            float2 tangentN = float2(-worldN.y, worldN.x);
            float2 prismAxis = dispVec + (-worldN * 20.0f + tangentN * 9.5f) * (shellMeniscus + 0.35f * liquidMask);
            float2 posR = posPt + dispVec + prismAxis * dispMult;
            float2 posG = posPt + dispVec;
            float2 posB = posPt + dispVec - prismAxis * dispMult;

            float shellFrost = clamp(globalFrost * 0.45f, 0.0f, 1.8f) * (1.0f - 0.55f * liquidMask);
            float3 refracted = sampleFrostedRefraction(
                posR, posG, posB, shellFrost, modeBlend, pixelSeed, scene, textTex, photoTex
            );

            // Boost chromatic purity inside optical crystal
            float luma = dot(refracted, float3(0.2126f, 0.7152f, 0.0722f));
            refracted = clamp(mix(float3(luma), refracted, 1.46f), 0.0f, 1.18f);

            // Volumetric Liquid Absorption & Internal Caustic Shimmer
            if (liquidMask > 0.005f) {
                // Focus Palette: Deep Aurora Sapphire -> Luminous Sky Prism (#38BDF8)
                float3 focusDeep = float3(0.05f, 0.28f, 0.68f);
                float3 focusBright = float3(0.24f, 0.82f, 1.00f);
                // Break Palette: Emerald Forest -> Warm Dawn Gold
                float3 breakDeep = float3(0.06f, 0.48f, 0.38f);
                float3 breakBright = float3(0.98f, 0.78f, 0.30f);

                float3 liqDeep = mix(focusDeep, breakDeep, modeBlend);
                float3 liqBright = mix(focusBright, breakBright, modeBlend);

                float vertGrad = clamp((p.y + 110.0f) / 220.0f, 0.0f, 1.0f);
                float3 bodyTint = mix(liqBright, liqDeep, 0.35f + 0.45f * liquidDepth * vertGrad);

                float3 fluidCol = mix(refracted, bodyTint, 0.44f + 0.28f * liquidDepth);

                // Luminous liquid free-surface meniscus highlight
                float liqRim = smoothstep(4.2f, 0.0f, -sdLiquid);
                fluidCol += mix(liqBright, float3(1.0f), 0.55f) * liqRim * 0.46f;

                // Underwater Caustics inside Lower Chamber
                if (p.y > 4.0f) {
                    float innerCaustic = evaluateCausticWeb(p * 1.15f, time * 1.2f, impactPhase, impactStrength);
                    float bottomWeight = smoothstep(20.0f, 108.0f, p.y);
                    float3 cCol = mix(float3(0.52f, 0.94f, 1.0f), float3(1.0f, 0.90f, 0.52f), modeBlend);
                    fluidCol += cCol * innerCaustic * (0.26f + 0.58f * causticBloom) * bottomWeight;
                }

                refracted = mix(refracted, fluidCol, liquidMask);
            }

            // Dual-Layer Fresnel Specular Rim + Inner Wall Reflection + Prismatic Rainbow Edge!
            float primaryLight = max(0.0f, dot(worldN, lightDir));
            float secondaryBounce = max(0.0f, dot(worldN, -lightDir));
            float rimDir = 0.28f + 0.92f * pow(primaryLight, 2.2f) + 0.42f * pow(secondaryBounce, 3.6f);

            float globalRim = max(0.9f, scene.atmosphereParams.y);
            // Layer 1: Razor-crisp Outer Grazing Fresnel Highlight
            float outerFresnel = smoothstep(2.4f, 0.0f, shellDist) * rimDir * 1.28f * globalRim;
            // Layer 2: Inner Glass Wall Thickness Fresnel Ring (at ~8.2pt wall depth!)
            float innerWallBand = exp(-pow(shellDist - 7.8f, 2.0f) * 0.22f) * (0.32f + 0.52f * rimDir) * globalRim;
            // Broad bevel sheen
            float bevelSheen = smoothstep(bz * 0.72f, 0.0f, shellDist) * (0.08f + 0.20f * max(0.0f, dot(-worldN, lightDir)));

            float prismStrength = clamp(globalDisp * 4.6f, 0.0f, 1.0f);
            float specPhase = atan2(worldN.y, worldN.x) * 2.0f - atan2(lightDir.y, lightDir.x);
            float3 prismSpectrum = 0.52f + 0.48f * cos(specPhase + float3(0.0f, 2.0944f, 4.1888f));
            float3 fresnelTint = mix(float3(0.96f, 0.99f, 1.0f), prismSpectrum * 1.22f, prismStrength * 0.75f);

            // Vertical sculptural specular streak along curved bulb
            float bulbStreak = exp(-pow((p.x + 28.0f) / 9.5f, 2.0f)) * smoothstep(14.0f, 45.0f, abs(p.y)) * smoothstep(112.0f, 82.0f, abs(p.y)) * 0.22f;

            float3 hgGlassCol = refracted
                + fresnelTint * (outerFresnel * 0.88f + innerWallBand * 0.65f + bevelSheen)
                + prismSpectrum * (shellMeniscus * prismStrength * 0.30f)
                + float3(0.96f, 0.99f, 1.0f) * bulbStreak;

            float shellMask = smoothstep(0.95f, -0.75f, sdShell) * vis;
            color = mix(color, clamp(hgGlassCol, 0.0f, 1.0f), shellMask);
        }
    }

    // 4. Radial Time Dial Optical Magnifier Water-Droplet Knob (Convex Lens with Tangential Jelly Stretch)
    if (dialVis > 0.005f) {
        float2 knobCenter = hg.dialLensParams.xy;
        float knobR = max(8.0f, hg.dialLensParams.z);
        float knobAngle = hg.dialLensParams.w;
        float knobStretch = clamp(hg.gravityAndZen.w, 0.80f, 1.45f);
        float2 relKnob = posPt - knobCenter;

        if (abs(relKnob.x) < knobR * 1.8f + 16.0f && abs(relKnob.y) < knobR * 1.8f + 16.0f) {
            float2 uKnob = float2(cos(knobAngle), sin(knobAngle));
            float3 sdnK = sdAndNormalDeformedBox(relKnob, float2(knobR, knobR), knobR, uKnob, knobStretch);
            float sdK = sdnK.x;
            if (sdK < 14.0f) {
                if (sdK > -0.5f) {
                    float kShadow = exp(-max(0.0f, sdK) * 0.24f) * (0.20f + 0.16f * dialDragGlow) * dialVis;
                    color *= (1.0f - kShadow);
                }
                if (sdK < 1.1f) {
                    float2 nK = sdnK.yz;
                    float distK = max(0.0f, -sdK);
                    float tK = clamp(distK / max(4.0f, knobR * 0.88f), 0.0f, 1.0f);
                    float menK = pow(1.0f - tK, 2.0f);
                    float2 domeK = relKnob / knobR;

                    // True Convex Magnifier Displacement + Chromatic Dispersion!
                    float magPower = (22.0f + 26.0f * dialDragGlow);
                    float2 dispK = (-domeK * 0.62f - nK * menK * 0.55f) * magPower;
                    float dispChrom = max(0.08f, scene.opticalParams.z) * (2.6f + 2.8f * menK);
                    float3 knobRef = sampleFrostedRefraction(
                        posPt + dispK * (1.0f + dispChrom * 0.35f),
                        posPt + dispK,
                        posPt + dispK * (1.0f - dispChrom * 0.35f),
                        0.0f,
                        modeBlend,
                        pixelSeed,
                        scene,
                        textTex,
                        photoTex
                    );

                    float rimK = smoothstep(2.2f, 0.0f, distK) * (0.45f + 0.85f * max(0.0f, dot(nK, lightDir)));
                    float specK = atan2(nK.y, nK.x) * 2.0f;
                    float3 prismK = 0.54f + 0.46f * cos(specK + float3(0.0f, 2.094f, 4.188f));
                    float3 accentK = mix(float3(0.22f, 0.74f, 0.98f), float3(0.28f, 0.90f, 0.62f), modeBlend);

                    float3 knobGlass = mix(knobRef, accentK, 0.14f * (1.0f - dialDragGlow))
                        + mix(float3(1.0f), prismK * 1.2f, 0.58f) * rimK * (0.95f + 0.35f * dialDragGlow);

                    float kMask = smoothstep(0.90f, -0.70f, sdK) * dialVis;
                    color = mix(color, clamp(knobGlass, 0.0f, 1.0f), kMask);
                }
            }
        }
    }

    return color;
}

// MARK: - iPhone 18 Pro OLED Pure Black (#000000) Hardware Cutout & Metaball Tentacle SDF

static inline float evaluatePureBlackIslandSDF(
    float2 posPt,
    constant SceneUniforms &scene,
    float2 heroCenter,
    float2 heroHalfSize,
    bool heroActive
) {
    float2 islandCenter = scene.islandParams.xy;
    float halfW = max(24.0f, scene.islandParams.z);        // Default 44pt -> 88pt wide
    float halfH = max(10.0f, scene.atmosphereParams.w);    // Default 16pt -> 32pt tall
    float pullStretch = scene.islandParams.w;

    float sdIsland = sdRoundBox(posPt - islandCenter, float2(halfW, halfH), halfH);

    // 1. Viscous pure-black ferrofluid drop when user pulls downward from the cutout (Zen toggle / Spit)
    if (pullStretch > 1.0f) {
        float2 budCenter = islandCenter + float2(0.0f, pullStretch * 0.82f);
        float budR = max(11.0f, 18.0f - pullStretch * 0.08f);
        float sdBud = sdRoundBox(posPt - budCenter, float2(budR, budR * 1.15f), budR);
        sdIsland = sminPoly(sdBud, sdIsland, 22.0f);
    }

    // 2. Pure-black magnetic liquid tentacle reaching out when droplet approaches cutout (Focus or LensLab)
    if (heroActive) {
        float topDist = (heroCenter.y - heroHalfSize.y) - (islandCenter.y + halfH);
        float horizDist = abs(heroCenter.x - islandCenter.x);
        if (topDist < 98.0f && horizDist < (halfW + heroHalfSize.x + 44.0f)) {
            float proximity = clamp(1.0f - max(0.0f, topDist) / 98.0f, 0.0f, 1.0f);
            float2 tentacleTarget = mix(
                islandCenter + float2(clamp(heroCenter.x - islandCenter.x, -halfW * 0.6f, halfW * 0.6f), halfH * 0.5f),
                heroCenter,
                0.40f * proximity
            );
            float tentacleR = 13.5f * proximity;
            if (tentacleR > 1.5f) {
                float sdTentacle = length(posPt - tentacleTarget) - tentacleR;
                sdIsland = sminPoly(sdTentacle, sdIsland, 28.0f * proximity + 2.0f);
            }
        }
    }

    return sdIsland;
}

// MARK: - Single-Pass 120fps Fragment Shader

fragment float4 liquidGlassFragment(
    VertexOut in [[stage_in]],
    constant SceneUniforms &scene [[buffer(0)]],
    constant GlassElementUniform *elements [[buffer(1)]],
    constant HourglassUniforms &hourglass [[buffer(2)]],
    texture2d<float, access::sample> textTex [[texture(0)]],
    texture2d<float, access::sample> photoTex [[texture(1)]]
) {
    float2 viewport = max(scene.viewportAndTime.xy, float2(1.0f));
    float2 posPt = in.uv * viewport;
    float modeBlend = clamp(hourglass.impactAndAtmosphere.w, 0.0f, 1.0f);

    float3 color = sampleSceneBackground(posPt, 0.0f, modeBlend, scene, textTex, photoTex);

    if (scene.rippleParams.w > 0.005f) {
        float rDist = abs(length(posPt - scene.rippleParams.xy) - scene.rippleParams.z);
        if (rDist < 26.0f) {
            float ringGlow = exp(-rDist * 0.15f) * scene.rippleParams.w * 0.36f;
            color += mix(float3(0.80f, 0.95f, 1.0f), float3(0.98f, 0.90f, 0.68f), modeBlend) * ringGlow;
        }
    }

    float spotVal = evaluateSpotlight(posPt, scene);
    if (spotVal > 0.001f) {
        color += float3(0.94f, 0.97f, 1.0f) * (spotVal * 0.48f);
    }

    float globalRefraction = scene.opticalParams.x;
    float globalBezel = scene.opticalParams.y;
    float globalDispersion = scene.opticalParams.z;
    float globalFrost = scene.opticalParams.w;

    float2 rawLightDir = scene.lightingParams.xy;
    float lLen = length(rawLightDir);
    float2 lightDir = lLen > 1e-3f ? (rawLightDir / lLen) : float2(-0.58f, -0.81f);
    int tintMode = int(scene.lightingParams.z + 0.5f);
    int wallpaperMode = int(scene.viewportAndTime.w + 0.5f);
    float globalRimScale = max(0.8f, scene.atmosphereParams.y);
    float fusionK = max(4.0f, scene.atmosphereParams.z);

    // 1. Flagship Dual-Chamber Liquid Glass Hourglass & Tactile Radial Optical Dial
    if (hourglass.morphAndFill.x > 0.004f) {
        color = renderLiquidHourglassAndDial(
            posPt, color, in.position.xy, lightDir, scene, hourglass, textTex, photoTex
        );
    }

    int elemCount = clamp(int(scene.layerFlags.x + 0.5f), 0, 16);

    // Track Island-magnetic droplet bounds (works in both LensLab and Focus tabs!)
    float2 heroCenter = float2(0.0f, 9999.0f);
    float2 heroHalfSize = float2(0.0f);
    bool heroActive = false;

    if (hourglass.morphAndFill.x > 0.25f && hourglass.dialRingParams.x > 0.25f) {
        // Allow dial droplet dragged near top cutout in Focus mode to attract pure-black tentacle!
        float2 kc = hourglass.dialLensParams.xy;
        if (kc.y < 155.0f) {
            heroCenter = kc;
            heroHalfSize = float2(hourglass.dialLensParams.z);
            heroActive = true;
        }
    }

    // 2. Liquid Droplets, Floating Cards, Two-Part Dock Plates & Convex Sliding Magnifier Lens
    for (int i = 0; i < elemCount; ++i) {
        GlassElementUniform elem = elements[i];
        float elemOpacity = elem.styleParams.x;
        if (elemOpacity <= 0.004f) {
            continue;
        }

        if (elem.tintOverride.w < -0.5f) {
            heroCenter = elem.centerAndHalfSize.xy;
            heroHalfSize = elem.centerAndHalfSize.zw;
            heroActive = true;
        }

        bool isMetaballLeader = (elem.tintOverride.w < -0.5f && elem.tintOverride.w > -1.5f) && ((i + 1) < elemCount);

        float sd;
        float2 n;
        float2 domeNorm;
        float minDim;
        float elevation;
        float refScale;
        float frostBoost;
        float rimBoost;
        float3 accentRGB = elem.tintOverride.xyz;
        float accentStrength = max(0.0f, elem.tintOverride.w);

        if (isMetaballLeader) {
            GlassElementUniform elemB = elements[i + 1];
            i += 1;

            float2 cA = elem.centerAndHalfSize.xy;
            float2 hsA = max(elem.centerAndHalfSize.zw, float2(4.0f));
            float2 relA = posPt - cA;
            float strA = clamp(elem.shapeAndTransform.z, 0.65f, 1.48f);
            float extA = max(hsA.x, hsA.y) * max(strA, 1.0f / strA) + 64.0f;

            float2 cB = elemB.centerAndHalfSize.xy;
            float2 hsB = max(elemB.centerAndHalfSize.zw, float2(4.0f));
            float2 relB = posPt - cB;
            float strB = clamp(elemB.shapeAndTransform.z, 0.65f, 1.48f);
            float extB = max(hsB.x, hsB.y) * max(strB, 1.0f / strB) + 64.0f;

            bool inA = (abs(relA.x) <= extA && abs(relA.y) <= extA);
            bool inB = (abs(relB.x) <= extB && abs(relB.y) <= extB);
            if (!inA && !inB) {
                continue;
            }

            float2 uA = float2(cos(elem.shapeAndTransform.y), sin(elem.shapeAndTransform.y));
            float2 uB = float2(cos(elemB.shapeAndTransform.y), sin(elemB.shapeAndTransform.y));

            float3 sdnA = sdAndNormalDeformedBox(relA, hsA, elem.shapeAndTransform.x, uA, strA);
            float3 sdnB = sdAndNormalDeformedBox(relB, hsB, elemB.shapeAndTransform.x, uB, strB);

            float k = fusionK * clamp(elemB.styleParams.x, 0.0f, 1.0f);
            float h = clamp(0.5f + 0.5f * (sdnB.x - sdnA.x) / max(k, 0.01f), 0.0f, 1.0f);
            sd = mix(sdnB.x, sdnA.x, h) - k * h * (1.0f - h);
            float2 blendedN = mix(sdnB.yz, sdnA.yz, h);

            float nLen = length(blendedN);
            n = nLen > 1e-4f ? (blendedN / nLen) : float2(0.0f, -1.0f);

            domeNorm = mix(relB / hsB, relA / hsA, h);
            minDim = mix(min(hsB.x, hsB.y), min(hsA.x, hsA.y), h);
            elevation = mix(elemB.styleParams.w, elem.styleParams.w, h);
            refScale = mix(elemB.styleParams.y, elem.styleParams.y, h);
            frostBoost = mix(elemB.styleParams.z, elem.styleParams.z, h);
            rimBoost = mix(elemB.shapeAndTransform.w, elem.shapeAndTransform.w, h);

            if (sd > -0.5f && sd < 38.0f) {
                float ambient = exp(-max(0.0f, sd) * 0.20f) * 0.24f;
                color *= (1.0f - clamp(ambient * elemOpacity, 0.0f, 0.42f));
            }
        } else {
            float2 center = elem.centerAndHalfSize.xy;
            float2 halfSize = max(elem.centerAndHalfSize.zw, float2(4.0f));
            float2 rel = posPt - center;

            float stretch = clamp(elem.shapeAndTransform.z, 0.60f, 1.55f);
            float maxScale = max(stretch, 1.0f / stretch);
            float maxExtent = max(halfSize.x, halfSize.y) * maxScale + 46.0f;

            if (abs(rel.x) > maxExtent || abs(rel.y) > maxExtent) {
                continue;
            }

            float radius = elem.shapeAndTransform.x;
            float angle = elem.shapeAndTransform.y;
            float2 uDir = float2(cos(angle), sin(angle));
            elevation = elem.styleParams.w;

            float3 sdn = sdAndNormalDeformedBox(rel, halfSize, radius, uDir, stretch);
            sd = sdn.x;
            n = sdn.yz;
            domeNorm = rel / max(halfSize, float2(1.0f));
            minDim = min(halfSize.x, halfSize.y);
            refScale = elem.styleParams.y;
            frostBoost = elem.styleParams.z;
            rimBoost = elem.shapeAndTransform.w;

            if (sd > -0.5f && elevation > 0.01f) {
                float2 shadowOffset = -lightDir * (8.0f * elevation) + float2(0.0f, 9.0f * elevation);
                float2 relShadow = applyLiquidDeform(rel - shadowOffset, uDir, stretch);
                float shadowSD = sdRoundBox(relShadow, halfSize, radius);

                if (shadowSD > -4.0f && shadowSD < 40.0f) {
                    float ambient = exp(-max(0.0f, sd) * 0.24f) * 0.16f;
                    float drop = exp(-max(0.0f, shadowSD) * (0.085f / max(elevation, 0.5f))) * 0.30f;
                    float totalShadow = clamp((ambient + drop) * elemOpacity * elevation, 0.0f, 0.50f);
                    color *= (1.0f - totalShadow);

                    if (tintMode == 0 && shadowSD > -2.0f && shadowSD < 14.0f) {
                        float caustic = exp(-abs(shadowSD - 3.5f) * 0.28f) * 0.09f * elemOpacity;
                        color += float3(0.85f, 0.95f, 1.0f) * caustic;
                    }
                }
            }
        }

        if (sd > 1.25f) {
            continue;
        }

        float dist = max(0.0f, -sd);

        float bz = clamp(globalBezel, 4.0f, max(5.0f, minDim * 0.92f));
        float t = clamp(dist / bz, 0.0f, 1.0f);
        float meniscus = pow(1.0f - t, 2.25f);

        float refStrength = globalRefraction * refScale;
        // Convex lens dome magnification boost when frostBoost < -2.0 (Dock sliding magnifier droplet!)
        float domeMag = (frostBoost < -2.0f) ? 0.52f : 0.24f;
        float2 dispVec = (-n * meniscus * 0.78f - domeNorm * domeMag) * refStrength;

        // Amplified 3-Channel Prismatic Chromatic Dispersion
        float dispMultiplier = globalDispersion * (2.35f + 3.10f * meniscus);
        float2 tangentN = float2(-n.y, n.x);
        float2 prismAxis = dispVec + (-n * 18.0f + tangentN * 8.5f) * meniscus * refScale;
        float2 posR = posPt + dispVec + prismAxis * dispMultiplier;
        float2 posG = posPt + dispVec;
        float2 posB = posPt + dispVec - prismAxis * dispMultiplier;

        float totalFrost = clamp(globalFrost + frostBoost, 0.0f, 4.5f);
        float3 refracted = sampleFrostedRefraction(
            posR, posG, posB, totalFrost, modeBlend, in.position.xy, scene, textTex, photoTex
        );

        float luma = dot(refracted, float3(0.2126f, 0.7152f, 0.0722f));
        float satFactor = (tintMode == 0 || frostBoost < -1.0f) ? 1.44f : 1.26f;
        refracted = clamp(mix(float3(luma), refracted, satFactor), 0.0f, 1.15f);

        if (frostBoost < -1.5f) {
            refracted = mix(refracted, float3(0.96f, 0.99f, 1.0f), 0.04f);
        } else if (tintMode == 1) {
            float lightMix = (wallpaperMode == 3) ? 0.40f : 0.28f;
            refracted = mix(refracted, float3(0.95f, 0.97f, 1.0f), lightMix);
        } else if (tintMode == 2) {
            refracted = mix(refracted * 0.56f, float3(0.05f, 0.07f, 0.12f), 0.44f);
        } else {
            refracted = mix(refracted, float3(0.96f, 0.98f, 1.0f), 0.04f);
        }

        if (accentStrength > 0.005f) {
            float accentFalloff = smoothstep(minDim * 1.2f, 0.0f, dist) * 0.65f + 0.35f;
            refracted = mix(refracted, accentRGB, accentStrength * accentFalloff);
        }

        float primaryLight = max(0.0f, dot(n, lightDir));
        float secondaryBounce = max(0.0f, dot(n, -lightDir));
        float rimDirectional = 0.24f
            + 0.88f * pow(primaryLight, 2.4f)
            + 0.36f * pow(secondaryBounce, 4.0f);

        float effectiveRim = (rimBoost + spotVal * 0.55f) * globalRimScale;
        float outerRim = smoothstep(2.3f, 0.0f, dist) * rimDirectional * effectiveRim;
        float innerSheen = smoothstep(bz * 0.65f, 0.0f, dist)
            * (0.08f + 0.18f * max(0.0f, dot(-n, lightDir)))
            * effectiveRim;

        float prismStrength = clamp(globalDispersion * 4.4f, 0.0f, 1.0f);
        float specPhase = atan2(n.y, n.x) * 2.0f - atan2(lightDir.y, lightDir.x);
        float3 prismSpectrum = 0.52f + 0.48f * cos(specPhase + float3(0.0f, 2.0944f, 4.1888f));
        float bevelBand = smoothstep(bz * 0.52f, 0.0f, dist) * (0.35f + 0.65f * rimDirectional);
        float3 chromaticRimTint = mix(float3(0.96f, 0.99f, 1.0f), prismSpectrum * 1.18f, prismStrength * 0.72f);

        float sheenCoord = dot(domeNorm, lightDir);
        float surfaceLuster = exp(-pow(sheenCoord - 0.35f, 2.0f) * 4.5f) * 0.055f * effectiveRim;
        float grain = (hash12(in.position.xy + float2(float(i) * 19.3f, 7.1f)) - 0.5f) * 0.012f;

        float3 glassCol = refracted
            + chromaticRimTint * (outerRim * 0.84f + innerSheen)
            + prismSpectrum * (bevelBand * prismStrength * 0.28f * refScale)
            + float3(1.0f) * surfaceLuster
            + grain;

        if (wallpaperMode == 3 && tintMode != 2) {
            float hairline = smoothstep(1.4f, 0.0f, abs(sd + 0.6f)) * 0.18f;
            glassCol = mix(glassCol, float3(0.22f, 0.30f, 0.45f), hairline);
        }

        float edgeMask = smoothstep(0.95f, -0.75f, sd) * elemOpacity;
        color = mix(color, clamp(glassCol, 0.0f, 1.0f), edgeMask);
    }

    // 3. Top OLED Pure Black (#000000) Hardware Dynamic Island Cutout & Metaball Black-Hole Fusion!
    if (posPt.y < 148.0f) {
        float islandSD = evaluatePureBlackIslandSDF(posPt, scene, heroCenter, heroHalfSize, heroActive);
        if (islandSD < 0.85f) {
            float blackMask = smoothstep(0.85f, -0.65f, islandSD);
            color = mix(color, float3(0.0f, 0.0f, 0.0f), blackMask);
        }
    }

    return float4(clamp(color, 0.0f, 1.0f), 1.0f);
}
