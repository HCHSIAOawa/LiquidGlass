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
    float4 atmosphereParams;  // x: solarWarmth (-1..1), y: globalRimBoost, z: fusionK (pt), w: islandHalfHeightPt
    float4 islandParams;      // x: islandCenterX, y: islandCenterY, z: islandHalfWidthPt, w: islandPullStretchPt
};

struct GlassElementUniform {
    float4 centerAndHalfSize; // xy: centerPt, zw: halfSizePt
    float4 shapeAndTransform; // x: cornerRadiusPt, y: stretchAngleRad, z: stretchFactor, w: rimBoost
    float4 styleParams;       // x: opacity, y: refractionScale, z: frostBoost, w: shadowElevation
    float4 tintOverride;      // xyz: accentRGB, w: accentStrength (-1.0f = Dual-Droplet Fusion leader)
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

// MARK: - Procedural Wallpaper Generators (Zero Offscreen Blur)

static inline float3 wallpaperAurora(float2 uv, float aspect, float t) {
    float2 p = float2((uv.x - 0.5f) * aspect, uv.y - 0.5f);

    float3 base = mix(
        float3(0.025f, 0.042f, 0.105f),
        float3(0.055f, 0.085f, 0.185f),
        clamp(uv.y * 1.1f, 0.0f, 1.0f)
    );

    float2 c1 = float2(sin(t * 0.65f) * 0.24f - 0.14f, cos(t * 0.48f) * 0.20f - 0.22f);
    float2 c2 = float2(cos(t * 0.56f) * 0.26f + 0.16f, sin(t * 0.42f) * 0.22f - 0.03f);
    float2 c3 = float2(sin(t * 0.50f + 1.6f) * 0.22f - 0.02f, cos(t * 0.60f) * 0.19f + 0.24f);
    float2 c4 = float2(cos(t * 0.38f + 2.4f) * 0.20f + 0.10f, sin(t * 0.52f + 0.9f) * 0.24f + 0.16f);

    float g1 = exp(-dot(p - c1, p - c1) * 7.2f);
    float g2 = exp(-dot(p - c2, p - c2) * 6.4f);
    float g3 = exp(-dot(p - c3, p - c3) * 7.8f);
    float g4 = exp(-dot(p - c4, p - c4) * 9.0f);

    float ribbon = sin(p.x * 5.2f + sin(p.y * 4.0f + t * 0.8f) * 1.6f + t * 0.55f) * 0.5f + 0.5f;
    ribbon = pow(max(0.0f, ribbon), 2.2f) * exp(-abs(p.y + 0.06f) * 3.2f);

    float3 col = base;
    col += float3(1.00f, 0.20f, 0.42f) * (g1 * 0.82f);
    col += float3(0.38f, 0.34f, 0.96f) * (g2 * 0.84f);
    col += float3(0.00f, 0.84f, 0.78f) * (g3 * 0.76f);
    col += float3(0.45f, 0.95f, 0.58f) * (g4 * 0.38f + ribbon * 0.26f);

    return clamp(col, 0.0f, 1.0f);
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
    if (abs(ringDist) > 48.0f || dist < 1.0f) {
        return samplePt;
    }
    float envelope = exp(-(ringDist * ringDist) * 0.0028f) * strength;
    float wave = sin(ringDist * 0.22f) * envelope * 22.0f;
    return samplePt + (delta / dist) * wave;
}

static inline float3 sampleSceneBackground(
    float2 rawSamplePt,
    float frostAmount,
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
        bg = wallpaperAurora(uv, aspect, time);
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
            ? mix(float3(1.0f), float3(1.12f, 0.94f, 0.78f), warmth)
            : mix(float3(1.0f), float3(0.78f, 0.88f, 1.14f), -warmth);
        bg *= tint;
    }

    return bg * scene.lightingParams.w;
}

// MARK: - Ultra-Fast 120Hz Hardware-Mipmap + 3-Tap Chromatic Frost Sampler

static inline float3 sampleFrostedRefraction(
    float2 posR,
    float2 posG,
    float2 posB,
    float frost,
    float2 pixelSeed,
    constant SceneUniforms &scene,
    texture2d<float, access::sample> textTex,
    texture2d<float, access::sample> photoTex
) {
    if (frost <= 0.05f) {
        float r = sampleSceneBackground(posR, 0.0f, scene, textTex, photoTex).r;
        float g = sampleSceneBackground(posG, 0.0f, scene, textTex, photoTex).g;
        float b = sampleSceneBackground(posB, 0.0f, scene, textTex, photoTex).b;
        return float3(r, g, b);
    }

    // 4-tap compact rotated diamond + hardware trilinear mipmap LOD keeps GPU pass < 1.3ms
    float radius = frost * 2.4f;
    float angle = (hash12(pixelSeed) - 0.5f) * 0.40f + 0.52f;
    float2 d1 = float2(cos(angle), sin(angle)) * radius;
    float2 d2 = float2(-d1.y, d1.x);

    float r = 0.5f * (
        sampleSceneBackground(posR + d1, frost, scene, textTex, photoTex).r +
        sampleSceneBackground(posR - d1, frost, scene, textTex, photoTex).r
    );
    float g = sampleSceneBackground(posG + d2 * 0.5f, frost, scene, textTex, photoTex).g;
    float b = 0.5f * (
        sampleSceneBackground(posB - d2, frost, scene, textTex, photoTex).b +
        sampleSceneBackground(posB + d2, frost, scene, textTex, photoTex).b
    );
    return float3(r, g, b);
}

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

    // 1. Viscous pure-black ferrofluid drop when user pulls downward from the cutout
    if (pullStretch > 1.0f) {
        float2 budCenter = islandCenter + float2(0.0f, pullStretch * 0.82f);
        float budR = max(11.0f, 18.0f - pullStretch * 0.08f);
        float sdBud = sdRoundBox(posPt - budCenter, float2(budR, budR * 1.15f), budR);
        float kPull = 22.0f;
        float h = clamp(0.5f + 0.5f * (sdBud - sdIsland) / kPull, 0.0f, 1.0f);
        sdIsland = mix(sdBud, sdIsland, h) - kPull * h * (1.0f - h);
    }

    // 2. Pure-black magnetic liquid tentacle reaching out when glass droplet approaches cutout
    if (heroActive) {
        float topDist = (heroCenter.y - heroHalfSize.y) - (islandCenter.y + halfH);
        float horizDist = abs(heroCenter.x - islandCenter.x);
        if (topDist < 96.0f && horizDist < (halfW + heroHalfSize.x + 42.0f)) {
            float proximity = clamp(1.0f - max(0.0f, topDist) / 96.0f, 0.0f, 1.0f);
            float2 tentacleTarget = mix(
                islandCenter + float2(clamp(heroCenter.x - islandCenter.x, -halfW * 0.6f, halfW * 0.6f), halfH * 0.5f),
                heroCenter,
                0.38f * proximity
            );
            float tentacleR = 13.0f * proximity;
            if (tentacleR > 1.5f) {
                float sdTentacle = length(posPt - tentacleTarget) - tentacleR;
                float kTent = 28.0f * proximity + 2.0f;
                float hT = clamp(0.5f + 0.5f * (sdTentacle - sdIsland) / kTent, 0.0f, 1.0f);
                sdIsland = mix(sdTentacle, sdIsland, hT) - kTent * hT * (1.0f - hT);
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
    texture2d<float, access::sample> textTex [[texture(0)]],
    texture2d<float, access::sample> photoTex [[texture(1)]]
) {
    float2 viewport = max(scene.viewportAndTime.xy, float2(1.0f));
    float2 posPt = in.uv * viewport;

    float3 color = sampleSceneBackground(posPt, 0.0f, scene, textTex, photoTex);

    if (scene.rippleParams.w > 0.005f) {
        float rDist = abs(length(posPt - scene.rippleParams.xy) - scene.rippleParams.z);
        if (rDist < 24.0f) {
            float ringGlow = exp(-rDist * 0.16f) * scene.rippleParams.w * 0.35f;
            color += float3(0.82f, 0.96f, 1.0f) * ringGlow;
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

    int elemCount = clamp(int(scene.layerFlags.x + 0.5f), 0, 12);

    // Track Hero Droplet bounds for top OLED black-hole tentacle interaction
    float2 heroCenter = float2(0.0f, 9999.0f);
    float2 heroHalfSize = float2(0.0f);
    bool heroActive = false;

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
        float2 dispVec = (-n * meniscus * 0.78f - domeNorm * 0.24f) * refStrength;

        // Amplified 3-Channel Prismatic Chromatic Dispersion (Crisp Rainbow Separation in 0.05..0.28)
        float dispMultiplier = globalDispersion * (2.35f + 3.10f * meniscus);
        float2 tangentN = float2(-n.y, n.x);
        float2 prismAxis = dispVec + (-n * 18.0f + tangentN * 8.5f) * meniscus * refScale;
        float2 posR = posPt + dispVec + prismAxis * dispMultiplier;
        float2 posG = posPt + dispVec;
        float2 posB = posPt + dispVec - prismAxis * dispMultiplier;

        float totalFrost = clamp(globalFrost + frostBoost, 0.0f, 4.5f);
        float3 refracted = sampleFrostedRefraction(
            posR, posG, posB, totalFrost, in.position.xy, scene, textTex, photoTex
        );

        float luma = dot(refracted, float3(0.2126f, 0.7152f, 0.0722f));
        float satFactor = (tintMode == 0 || frostBoost < -1.0f) ? 1.44f : 1.26f;
        refracted = clamp(mix(float3(luma), refracted, satFactor), 0.0f, 1.15f);

        if (frostBoost < -1.5f) {
            refracted = mix(refracted, float3(0.96f, 0.99f, 1.0f), 0.05f);
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

        // Angular Prismatic Rainbow Fringe along Fresnel Specular Bevel!
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

    // Top OLED Pure Black (#000000) Hardware Dynamic Island Cutout & Metaball Black-Hole Fusion!
    // Zero colored border: completely invisible against iPhone 18 Pro OLED hardware pill at rest,
    // and stretches pure #000000 liquid ferrofluid tentacles when swallowing/spitting droplets!
    if (posPt.y < 145.0f) {
        float islandSD = evaluatePureBlackIslandSDF(posPt, scene, heroCenter, heroHalfSize, heroActive);
        if (islandSD < 0.85f) {
            float blackMask = smoothstep(0.85f, -0.65f, islandSD);
            color = mix(color, float3(0.0f, 0.0f, 0.0f), blackMask);
        }
    }

    return float4(clamp(color, 0.0f, 1.0f), 1.0f);
}
