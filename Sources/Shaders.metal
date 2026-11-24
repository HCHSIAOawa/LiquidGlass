#include <metal_stdlib>
using namespace metal;

// MARK: - 16-Byte Aligned Uniform Structs (Matches PlaygroundModels.swift 1:1)

struct SceneUniforms {
    float4 viewportAndTime;   // x: widthPt, y: heightPt, z: timeSec, w: wallpaperMode (0..4)
    float4 opticalParams;     // x: refraction, y: bezel, z: dispersion, w: frost
    float4 lightingParams;    // x: lightDirX, y: lightDirY, z: tintMode (0..2), w: brightness
    float4 spotlightParams;   // x: originX, y: originY, z: dirX, w: strength (0..1)
    float4 layerFlags;        // x: elementCount, y: hasCustomPhoto, z: photoAspect, w: textOverlayMix
};

struct GlassElementUniform {
    float4 centerAndHalfSize; // xy: centerPt, zw: halfSizePt
    float4 shapeAndTransform; // x: cornerRadiusPt, y: stretchAngleRad, z: stretchFactor, w: rimBoost
    float4 styleParams;       // x: opacity, y: refractionScale, z: frostBoost, w: shadowElevation
    float4 tintOverride;      // xyz: accentRGB, w: accentStrength
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Full-Screen Triangle Vertex Shader (Zero Vertex Buffer Overhead)

vertex VertexOut liquidGlassVertex(uint vid [[vertex_id]]) {
    VertexOut out;
    float2 uv = float2(float((vid << 1u) & 2u), float(vid & 2u));
    out.position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    out.uv = uv;
    return out;
}

// MARK: - Fast Procedural Noise & Hash

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

// MARK: - Procedural Wallpaper Generators (Zero Offscreen Blur Cost)

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

    // Cosine chromatic palette + crisp architectural sub-bands
    float3 pal = 0.54f + 0.44f * cos(6.2831853f * (coord * 0.22f + float3(0.00f, 0.33f, 0.67f)));
    float band = fract(coord);
    float crispEdge = smoothstep(0.0f, 0.06f, band) * smoothstep(1.0f, 0.94f, band);
    float3 deepAccent = pal * (0.72f + 0.32f * crispEdge);

    // Subtle dark vignette for glass contrast
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

    // Concentric optical rings that bend dramatically through convex glass
    float ringPhase = r * 26.0f - t * 0.85f;
    float rings = sin(ringPhase);
    float sharpRing = smoothstep(0.55f, 0.96f, rings);
    float sunCore = exp(-r * 4.4f);

    float3 ringColor = mix(float3(1.0f, 0.76f, 0.34f), float3(1.0f, 0.95f, 0.80f), sunCore);
    float3 col = grad + ringColor * (sharpRing * 0.34f * exp(-r * 1.6f) + sunCore * 0.55f);

    // Horizon reflection bars in lower third
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

    // Analytical anti-aliased grid lines (softens naturally with frostBlur)
    float aa = 0.85f + frostBlur * 1.8f;

    float2 minorDist = abs(fract(posPt / 24.0f + 0.5f) - 0.5f) * 24.0f;
    float minorLine = 1.0f - smoothstep(0.45f, 0.45f + aa, min(minorDist.x, minorDist.y));

    float2 majorDist = abs(fract(posPt / 120.0f + 0.5f) - 0.5f) * 120.0f;
    float majorLine = 1.0f - smoothstep(0.85f, 0.85f + aa, min(majorDist.x, majorDist.y));

    // Subtle colored optical calibration crosshairs near center
    float2 centerDist = abs(posPt - viewport * float2(0.5f, 0.44f));
    float axisLineX = 1.0f - smoothstep(0.7f, 0.7f + aa, centerDist.x);
    float axisLineY = 1.0f - smoothstep(0.7f, 0.7f + aa, centerDist.y);

    float3 col = paper;
    col = mix(col, float3(0.76f, 0.80f, 0.87f), minorLine * 0.55f);
    col = mix(col, float3(0.42f, 0.52f, 0.72f), majorLine * 0.65f);
    col = mix(col, float3(0.92f, 0.28f, 0.42f), axisLineX * 0.35f);
    col = mix(col, float3(0.14f, 0.58f, 0.88f), axisLineY * 0.35f);
    return col;
}

// MARK: - Composite Background + UV-Scrolled Typography Texture + Custom Photo

static inline float3 sampleSceneBackground(
    float2 samplePt,
    float frostAmount,
    constant SceneUniforms &scene,
    texture2d<float, access::sample> textTex,
    texture2d<float, access::sample> photoTex
) {
    constexpr sampler repeatSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    constexpr sampler clampSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

    float2 viewport = max(scene.viewportAndTime.xy, float2(1.0f));
    float time = scene.viewportAndTime.z;
    int mode = int(scene.viewportAndTime.w + 0.5f);
    float aspect = viewport.x / viewport.y;
    float2 uv = samplePt / viewport;
    float mipLod = clamp(frostAmount * 1.15f, 0.0f, 5.0f);

    float3 bg;
    if (mode == 4 && scene.layerFlags.y > 0.5f) {
        // Aspect-fill custom photo UV mapping
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

    // Pre-rendered static typography texture with per-row alternating UV scroll at -8 degrees
    float textMix = scene.layerFlags.w;
    if (textMix > 0.01f) {
        float2 centered = samplePt - viewport * 0.5f;
        // -8 deg rotation: cos(-8°) = 0.990268f, sin(-8°) = -0.139173f
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
            // Dark editorial ink typography on bright minimal grid paper (txt is premultiplied RGBA)
            float3 inkColor = ((rowIdx & 1) == 0)
                ? float3(0.09f, 0.12f, 0.20f)
                : float3(0.08f, 0.44f, 0.68f);
            bg = mix(bg, inkColor, txt.a * 0.86f * textMix);
        } else {
            // Premultiplied-alpha composite prevents mipmap fringe halos
            bg = bg * (1.0f - txt.a * textMix) + txt.rgb * textMix;
        }
    }

    return bg * scene.lightingParams.w;
}

// MARK: - Frosted + Chromatically Dispersed Background Sampler

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
    if (frost <= 0.06f) {
        float r = sampleSceneBackground(posR, 0.0f, scene, textTex, photoTex).r;
        float g = sampleSceneBackground(posG, 0.0f, scene, textTex, photoTex).g;
        float b = sampleSceneBackground(posB, 0.0f, scene, textTex, photoTex).b;
        return float3(r, g, b);
    }

    // Hardware trilinear mipmaps handle high-frequency blur; a rotated 4-tap Poisson kernel
    // blurs procedural backgrounds smoothly with 6 total taps instead of 15.
    float radius = frost * 2.6f;
    float jitterAngle = (hash12(pixelSeed) - 0.5f) * 0.35f + 0.48f;
    float cs = cos(jitterAngle);
    float sn = sin(jitterAngle);
    float2 d1 = float2(cs, sn) * radius;
    float2 d2 = float2(-sn, cs) * radius;

    float r = 0.5f * (
        sampleSceneBackground(posR + d1, frost, scene, textTex, photoTex).r +
        sampleSceneBackground(posR - d1, frost, scene, textTex, photoTex).r
    );
    float g = 0.5f * (
        sampleSceneBackground(posG + d2, frost, scene, textTex, photoTex).g +
        sampleSceneBackground(posG - d2, frost, scene, textTex, photoTex).g
    );
    float b = 0.5f * (
        sampleSceneBackground(posB - d1 * 0.7f + d2 * 0.7f, frost, scene, textTex, photoTex).b +
        sampleSceneBackground(posB + d1 * 0.7f - d2 * 0.7f, frost, scene, textTex, photoTex).b
    );
    return float3(r, g, b);
}

// MARK: - Incompressible Liquid Squash & Stretch SDF + Analytical Normal

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

    // Smooth crease-free outward normal in local space, then transformed by symmetric M
    float2 signs = float2(p.x >= 0.0f ? 1.0f : -1.0f, p.y >= 0.0f ? 1.0f : -1.0f);
    float2 localN;
    if (lenW > 1e-3f) {
        localN = signs * (w / lenW);
    } else {
        // Smooth meniscus gradient inside flat core without 45-degree creases
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

// MARK: - Volumetric Spotlight Cone (Mini Control Center Flashlight)

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

// MARK: - Single-Pass Multi-Element Liquid Glass Fragment Shader (120fps Target)

fragment float4 liquidGlassFragment(
    VertexOut in [[stage_in]],
    constant SceneUniforms &scene [[buffer(0)]],
    constant GlassElementUniform *elements [[buffer(1)]],
    texture2d<float, access::sample> textTex [[texture(0)]],
    texture2d<float, access::sample> photoTex [[texture(1)]]
) {
    float2 viewport = max(scene.viewportAndTime.xy, float2(1.0f));
    float2 posPt = in.uv * viewport;

    // 1. Base procedural/photo wallpaper + UV-scrolled typography
    float3 color = sampleSceneBackground(posPt, 0.0f, scene, textTex, photoTex);

    // 2. Optional Mini Control Center volumetric spotlight beam
    float spotVal = evaluateSpotlight(posPt, scene);
    if (spotVal > 0.001f) {
        color += float3(0.94f, 0.97f, 1.0f) * (spotVal * 0.48f);
    }

    // Global optical & lighting parameters
    float globalRefraction = scene.opticalParams.x;
    float globalBezel = scene.opticalParams.y;
    float globalDispersion = scene.opticalParams.z;
    float globalFrost = scene.opticalParams.w;

    float2 rawLightDir = scene.lightingParams.xy;
    float lLen = length(rawLightDir);
    float2 lightDir = lLen > 1e-3f ? (rawLightDir / lLen) : float2(-0.58f, -0.81f);
    int tintMode = int(scene.lightingParams.z + 0.5f);
    int wallpaperMode = int(scene.viewportAndTime.w + 0.5f);

    int elemCount = clamp(int(scene.layerFlags.x + 0.5f), 0, 8);

    // 3. Single-pass multi-glass evaluation (back-to-front order)
    for (int i = 0; i < elemCount; ++i) {
        GlassElementUniform elem = elements[i];
        float elemOpacity = elem.styleParams.x;
        if (elemOpacity <= 0.004f) {
            continue;
        }

        float2 center = elem.centerAndHalfSize.xy;
        float2 halfSize = max(elem.centerAndHalfSize.zw, float2(4.0f));
        float2 rel = posPt - center;

        float stretch = clamp(elem.shapeAndTransform.z, 0.65f, 1.45f);
        float maxScale = max(stretch, 1.0f / stretch);
        float maxExtent = max(halfSize.x, halfSize.y) * maxScale + 48.0f;

        // Ultra-fast AABB early-out skips 80%+ of screen pixels in 2 comparisons
        if (abs(rel.x) > maxExtent || abs(rel.y) > maxExtent) {
            continue;
        }

        float radius = elem.shapeAndTransform.x;
        float angle = elem.shapeAndTransform.y;
        float2 uDir = float2(cos(angle), sin(angle));
        float elevation = elem.styleParams.w;

        float3 sdn = sdAndNormalDeformedBox(rel, halfSize, radius, uDir, stretch);
        float sd = sdn.x;

        // Soft dual-layer drop shadow + clear-glass caustic glow outside silhouette
        if (sd > -0.5f && elevation > 0.01f) {
            float2 shadowOffset = -lightDir * (8.0f * elevation) + float2(0.0f, 9.0f * elevation);
            float2 relShadow = applyLiquidDeform(rel - shadowOffset, uDir, stretch);
            float shadowSD = sdRoundBox(relShadow, halfSize, radius);

            if (shadowSD > -4.0f && shadowSD < 42.0f) {
                float ambient = exp(-max(0.0f, sd) * 0.24f) * 0.16f;
                float drop = exp(-max(0.0f, shadowSD) * (0.085f / max(elevation, 0.5f))) * 0.30f;
                float totalShadow = clamp((ambient + drop) * elemOpacity * elevation, 0.0f, 0.52f);
                color *= (1.0f - totalShadow);

                // Subtle focused caustic brightening inside shadow for Clear glass
                if (tintMode == 0 && shadowSD > -2.0f && shadowSD < 14.0f) {
                    float caustic = exp(-abs(shadowSD - 3.5f) * 0.28f) * 0.09f * elemOpacity;
                    color += float3(0.85f, 0.95f, 1.0f) * caustic;
                }
            }
        }

        if (sd > 1.25f) {
            continue;
        }

        float2 n = sdn.yz;
        float dist = max(0.0f, -sd);

        // Dual-zone meniscus bevel + gentle spherical dome magnification
        float minDim = min(halfSize.x, halfSize.y);
        float bz = clamp(globalBezel, 4.0f, max(5.0f, minDim * 0.92f));
        float t = clamp(dist / bz, 0.0f, 1.0f);
        float meniscus = pow(1.0f - t, 2.35f);
        float2 domeNorm = rel / max(halfSize, float2(1.0f));

        float refStrength = globalRefraction * elem.styleParams.y;
        float2 dispVec = (-n * meniscus * 0.78f - domeNorm * 0.22f) * refStrength;

        // Symmetric RGB chromatic dispersion around Green channel
        float disp = globalDispersion * (0.45f + 0.85f * meniscus);
        float2 posR = posPt + dispVec * (1.0f + disp);
        float2 posG = posPt + dispVec;
        float2 posB = posPt + dispVec * (1.0f - disp);

        float totalFrost = clamp(globalFrost + elem.styleParams.z, 0.0f, 4.5f);
        float3 refracted = sampleFrostedRefraction(
            posR, posG, posB, totalFrost, in.position.xy, scene, textTex, photoTex
        );

        // Boost internal optical chroma vibrancy
        float luma = dot(refracted, float3(0.2126f, 0.7152f, 0.0722f));
        float satFactor = (tintMode == 0) ? 1.40f : 1.24f;
        refracted = clamp(mix(float3(luma), refracted, satFactor), 0.0f, 1.2f);

        // Material tint modes: 0 = Clear, 1 = Light, 2 = Dark
        if (tintMode == 1) {
            float lightMix = (wallpaperMode == 3) ? 0.42f : 0.30f;
            refracted = mix(refracted, float3(0.95f, 0.97f, 1.0f), lightMix);
        } else if (tintMode == 2) {
            refracted = mix(refracted * 0.56f, float3(0.05f, 0.07f, 0.12f), 0.44f);
        } else {
            refracted = mix(refracted, float3(0.96f, 0.98f, 1.0f), 0.05f);
        }

        // Per-card subtle dynamic accent tint (e.g., playing album aura or flashlight glow)
        if (elem.tintOverride.w > 0.005f) {
            float accentFalloff = smoothstep(minDim * 1.2f, 0.0f, dist) * 0.65f + 0.35f;
            refracted = mix(refracted, elem.tintOverride.xyz, elem.tintOverride.w * accentFalloff);
        }

        // Dual-layer gyro Fresnel specular rim + internal bevel sheen
        float primaryLight = max(0.0f, dot(n, lightDir));
        float secondaryBounce = max(0.0f, dot(n, -lightDir));
        float rimDirectional = 0.24f
            + 0.88f * pow(primaryLight, 2.4f)
            + 0.34f * pow(secondaryBounce, 4.0f);

        float rimBoost = elem.shapeAndTransform.w + spotVal * 0.55f;
        float outerRim = smoothstep(2.1f, 0.0f, dist) * rimDirectional * rimBoost;
        float innerSheen = smoothstep(bz * 0.65f, 0.0f, dist)
            * (0.08f + 0.18f * max(0.0f, dot(-n, lightDir)))
            * rimBoost;

        // Subtle diagonal gyroscopic surface luster across glass face
        float sheenCoord = dot(domeNorm, lightDir);
        float surfaceLuster = exp(-pow(sheenCoord - 0.35f, 2.0f) * 4.5f) * 0.055f * rimBoost;

        // Micro-grain quartz glass texture (eliminates banding & adds physical feel)
        float grain = (hash12(in.position.xy + float2(float(i) * 19.3f, 7.1f)) - 0.5f) * 0.014f;

        float3 rimColor = (tintMode == 1 && wallpaperMode == 3)
            ? float3(1.0f, 1.0f, 1.0f) * 0.95f
            : float3(0.96f, 0.99f, 1.0f);

        float3 glassCol = refracted
            + rimColor * (outerRim * 0.82f + innerSheen + surfaceLuster)
            + grain;

        // Crisp dark hairline contour on bright drafting paper so clear/light glass pops
        if (wallpaperMode == 3 && tintMode != 2) {
            float hairline = smoothstep(1.4f, 0.0f, abs(sd + 0.6f)) * 0.16f;
            glassCol = mix(glassCol, float3(0.22f, 0.30f, 0.45f), hairline);
        }

        float edgeMask = smoothstep(0.95f, -0.75f, sd) * elemOpacity;
        color = mix(color, clamp(glassCol, 0.0f, 1.0f), edgeMask);
    }

    return float4(clamp(color, 0.0f, 1.0f), 1.0f);
}
