#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// ──────────────────────────────────────────────────────────────
// CONSTANTS & TYPES
// ──────────────────────────────────────────────────────────────

constant uint MAX_DROPS = 32;
constant uint FIELD_W   = 128;
constant uint FIELD_H   = 128;
constant float THRESHOLD = 0.55;
constant float DROP_BASE_RADIUS = 0.12;

struct Drop {
    float2 pos;
    float  radius;
    float  phase;
    float  vy;
    uint   alive;
    float  _pad[2];
};

struct Uniforms {
    float2  resolution;
    float2  gridResolution;
    float   time;
    float   threshold;
    uint    dropCount;
    float   blurRadius;
    float   colorMatrix[16];
    float   highlightIntensity;
    float   shadowIntensity;
    float   bodyOpacity;
    float   rimPower;
    float   rimIntensity;
    // Void params
    float   voidProgress;
    float   voidScale;
    // Disk params
    float   diskRotation;
    float   diskOpacity;
    // Ripple params
    float   rippleProgress;
    float2  rippleCenter;
    float   rippleMaxRadius;
    // Checkmark params
    float   checkProgress;
    float2  checkCenter;
    float   checkSize;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ──────────────────────────────────────────────────────────────
// COMPUTE SHADER: Metaball Field Solver
// ──────────────────────────────────────────────────────────────

kernel void metaball_field_solve(
    device const Drop* drops [[buffer(0)]],
    device float* field [[buffer(1)]],
    constant Uniforms& u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.gridResolution.x || gid.y >= u.gridResolution.y) return;

    float2 uv = float2(gid) / u.gridResolution;
    float sum = 0.0;

    for (uint i = 0; i < u.dropCount; ++i) {
        Drop d = drops[i];
        if (!d.alive) continue;

        float2 diff = uv - d.pos;
        float dist2 = dot(diff, diff);
        float r2 = d.radius * d.radius;
        sum += r2 / (r2 + dist2 * 4.0);
    }

    field[gid.y * FIELD_W + gid.x] = sum;
}

// ──────────────────────────────────────────────────────────────
// COMPUTE SHADER: Gaussian Blur (separable)
// ──────────────────────────────────────────────────────────────

kernel void gaussian_blur_h(
    device const float* inField [[buffer(0)]],
    device float* outField [[buffer(1)]],
    constant Uniforms& u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.gridResolution.x || gid.y >= u.gridResolution.y) return;

    int radius = max(1, int(u.blurRadius));
    float sum = 0.0;
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; ++i) {
        int x = clamp(int(gid.x) + i, 0, int(u.gridResolution.x) - 1);
        float w = exp(-float(i * i) / (2.0 * u.blurRadius * u.blurRadius));
        sum += inField[gid.y * FIELD_W + x] * w;
        weightSum += w;
    }
    outField[gid.y * FIELD_W + gid.x] = sum / weightSum;
}

kernel void gaussian_blur_v(
    device const float* inField [[buffer(0)]],
    device float* outField [[buffer(1)]],
    constant Uniforms& u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.gridResolution.x || gid.y >= u.gridResolution.y) return;

    int radius = max(1, int(u.blurRadius));
    float sum = 0.0;
    float weightSum = 0.0;

    for (int i = -radius; i <= radius; ++i) {
        int y = clamp(int(gid.y) + i, 0, int(u.gridResolution.y) - 1);
        float w = exp(-float(i * i) / (2.0 * u.blurRadius * u.blurRadius));
        sum += inField[y * FIELD_W + gid.x] * w;
        weightSum += w;
    }
    outField[gid.y * FIELD_W + gid.x] = sum / weightSum;
}

// ──────────────────────────────────────────────────────────────
// COMPUTE SHADER: Gradient + Normals
// ──────────────────────────────────────────────────────────────

kernel void compute_normals(
    device const float* field [[buffer(0)]],
    device float2* normals [[buffer(1)]],
    constant Uniforms& u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= u.gridResolution.x || gid.y >= u.gridResolution.y) return;

    uint idx = gid.y * FIELD_W + gid.x;

    float L = (gid.x > 0)     ? field[idx - 1] : field[idx];
    float R = (gid.x + 1 < FIELD_W) ? field[idx + 1] : field[idx];
    float B = (gid.y > 0)     ? field[idx - FIELD_W] : field[idx];
    float T = (gid.y + 1 < FIELD_H) ? field[idx + FIELD_W] : field[idx];

    float2 grad = float2(R - L, T - B) * 0.5;
    float len = length(grad);
    normals[idx] = len > 1e-4 ? normalize(grad) : float2(0.0, 1.0);
}

// ──────────────────────────────────────────────────────────────
// VERTEX SHADER: Full-screen quad
// ──────────────────────────────────────────────────────────────

vertex VertexOut metaball_vertex(
    uint vid [[vertex_id]],
    constant Uniforms& u [[buffer(0)]]
) {
    VertexOut out;
    float2 pos[4] = {
        float2(-1, -1), float2( 1, -1),
        float2(-1,  1), float2( 1,  1)
    };
    float2 uv[4] = {
        float2(0, 1), float2(1, 1),
        float2(0, 0), float2(1, 0)
    };
    out.position = float4(pos[vid], 0, 1);
    out.uv = uv[vid];
    return out;
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Dropf Filter Recreation (1:1 from SVG)
// ──────────────────────────────────────────────────────────────

fragment float4 metaball_fragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> fieldTex [[texture(0)]],
    constant float2* normals [[buffer(1)]],
    sampler fieldSampler [[sampler(0)]],
    constant Uniforms& u [[buffer(0)]]
) {
    float2 uv = in.uv;
    float field = fieldTex.sample(fieldSampler, uv).r;

    // ─── DEBUG: visualize raw field as grayscale ───
    // Uncomment to see field values (0=black, 1=white)
    return float4(field, field, field, 1.0);
    // ────────────────────────────────────────────────

    // Read normals from buffer (fieldWidth x fieldHeight grid)
    int2 gridCoord = int2(uv * u.gridResolution);
    gridCoord = clamp(gridCoord, int2(0), int2(u.gridResolution - 1));
    int index = gridCoord.y * int(u.gridResolution.x) + gridCoord.x;
    float2 N = normals[index];

    // Body alpha - smoothstep like feColorMatrix slope=.42 equivalent
    float bodyAlpha = smoothstep(u.threshold - 0.03, u.threshold + 0.03, field) * u.bodyOpacity;

    // Highlight offset (+3, +4) - feOffset dx="3" dy="4"
    float2 offsetHi = float2( 3.0,  4.0) / u.resolution;
    // Shadow offset (-3, -4) - feOffset dx="-3" dy="-4"
    float2 offsetLo = float2(-3.0, -4.0) / u.resolution;

    float fieldHi = fieldTex.sample(fieldSampler, uv + offsetHi).r;
    float fieldLo = fieldTex.sample(fieldSampler, uv + offsetLo).r;

    float hiAlpha = smoothstep(u.threshold - 0.03, u.threshold + 0.03, fieldHi);
    float loAlpha = smoothstep(u.threshold - 0.03, u.threshold + 0.03, fieldLo);

    // feComposite operator="out" - highlight = body - hiAlpha (clamped)
    float highlight = max(0.0, bodyAlpha - hiAlpha) * 0.85 * u.highlightIntensity;
    // Shadow = loAlpha - bodyAlpha (clamped)
    float shadow    = max(0.0, loAlpha - bodyAlpha) * 0.85 * u.shadowIntensity;

    // Rim lighting from normals
    float nl = dot(N, normalize(float2(1.0, 1.0)));
    float rim = pow(max(0.0, nl), u.rimPower) * u.rimIntensity * bodyAlpha;

    // Color gradient from concept: #30d158 -> lighter green
    float t = smoothstep(u.threshold - 0.06, u.threshold + 0.2, field);
    float3 color = mix(
        float3(48.0, 209.0, 88.0) / 255.0,   // #30d158
        float3(235.0, 255.0, 240.0) / 255.0, // light mint
        t
    );

    float3 finalColor = color * bodyAlpha;
    finalColor += float3(highlight);                    // highlight (white)
    finalColor -= float3(shadow * 0.5, shadow * 0.0, shadow * 0.6); // shadow (tinted dark green)
    finalColor += float3(rim);                          // rim

    float finalAlpha = bodyAlpha + highlight;

    return float4(finalColor, saturate(finalAlpha));
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Void / Black Hole (concept #void)
// ──────────────────────────────────────────────────────────────

fragment float4 void_fragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]]
) {
    float2 uv = in.uv * 2.0 - 1.0;
    float dist = length(uv);
    float angle = atan2(uv.y, uv.x) + u.time * 0.5;

    // Conic gradient bands (6 sectors like concept)
    float bands = sin(angle * 6.0 + u.time * 2.0) * 0.5 + 0.5;
    // Rotating rings
    float ring = sin(dist * 80.0 - u.time * 5.0) * 0.5 + 0.5;

    // Radial mask: smoothstep(44%, 49%) * (1 - smoothstep(60%, 67%))
    float mask = smoothstep(0.44, 0.49, dist) * (1.0 - smoothstep(0.60, 0.67, dist));
    // Blur mask at edges
    float blurMask = smoothstep(0.0, 0.02, abs(dist - 0.465)) * (1.0 - smoothstep(0.0, 0.02, abs(dist - 0.635)));

    float3 color1 = float3(0.08, 0.35, 0.22);  // dark green
    float3 color2 = float3(0.35, 0.78, 0.90);  // cyan
    float3 color3 = float3(0.19, 0.63, 0.35);  // medium green

    float3 col = mix(color1, color2, bands);
    col = mix(col, color3, ring);

    float alpha = mask * 0.8 * blurMask;

    // Center void - black hole
    float centerVoid = smoothstep(0.0, 0.55, dist);
    col = mix(float3(0.0, 0.0, 0.0), col, centerVoid);
    alpha *= centerVoid;

    // Scale by voidProgress
    alpha *= u.voidProgress;

    return float4(col, alpha);
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Rotating Disk (concept #disk)
// conic-gradient + radial mask + blur + rotation
// ──────────────────────────────────────────────────────────────

fragment float4 disk_fragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]]
) {
    float2 uv = in.uv * 2.0 - 1.0;
    float dist = length(uv);
    float angle = atan2(uv.y, uv.x) + u.diskRotation;

    // Conic gradient: transparent -> green(12%) -> transparent(30%) -> cyan(55%) -> transparent(75%) -> green(90%) -> transparent
    float conic = 0.0;
    float a = angle / 6.28318; // normalize to 0-1
    if (a < 0.12) conic = smoothstep(0.0, 0.12, a);                    // 0-12%: fade in green
    else if (a < 0.30) conic = 1.0 - smoothstep(0.12, 0.30, a);        // 12-30%: fade out
    else if (a < 0.55) conic = smoothstep(0.30, 0.55, a) * 0.65;       // 30-55%: fade in cyan
    else if (a < 0.75) conic = (1.0 - smoothstep(0.55, 0.75, a)) * 0.65; // 55-75%: fade out
    else if (a < 0.90) conic = smoothstep(0.75, 0.90, a) * 0.5;        // 75-90%: fade in green
    else conic = 1.0 - smoothstep(0.90, 1.0, a);                        // 90-100%: fade out

    // Radial mask: transparent 44% -> black 49% -> black 60% -> transparent 67%
    float radialMask = smoothstep(0.44, 0.49, dist) * (1.0 - smoothstep(0.60, 0.67, dist));

    // Blur approximation (filter:blur(3px))
    float blurMask = smoothstep(0.0, 0.03, abs(dist - 0.465)) * (1.0 - smoothstep(0.0, 0.03, abs(dist - 0.635)));

    float3 col = float3(0.19, 0.63, 0.35); // #30d158 green
    col = mix(float3(0.35, 0.78, 0.90), col, conic); // mix with cyan

    float alpha = conic * radialMask * blurMask * u.diskOpacity * 0.8;

    return float4(col, alpha);
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Progress Ring (concept .pr .c)
// ──────────────────────────────────────────────────────────────

fragment float4 progress_ring_fragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant float& progress [[buffer(1)]],
    constant float3& color [[buffer(2)]]
) {
    float2 uv = in.uv * 2.0 - 1.0;
    float dist = length(uv);
    float angle = atan2(uv.y, uv.x) + 1.5708; // start at top

    float ringWidth = 0.18;
    float ringMask = smoothstep(0.5 - ringWidth, 0.5, dist) * (1.0 - smoothstep(0.5, 0.5 + ringWidth, dist));

    float progAngle = progress * 6.28318;
    float angleMask = step(angle, progAngle);

    float3 c1 = color * 0.65;
    float3 c2 = color;

    float3 col = mix(c1, c2, angleMask) * ringMask;
    float alpha = ringMask * angleMask;

    // Glow on leading edge
    float glow = exp(-abs(dist - 0.5) * 80.0) * angleMask * 0.45;
    col += float3(glow) * color;

    return float4(col, alpha);
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Ripple (concept .rpl)
// scale 0.8 -> 3.2, fade out
// ──────────────────────────────────────────────────────────────

fragment float4 ripple_fragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant float2& center [[buffer(1)]],
    constant float& progress [[buffer(2)]],
    constant float& maxRadius [[buffer(3)]]
) {
    float2 uv = in.uv;
    float2 centerUV = center;
    float dist = distance(uv, centerUV) / maxRadius;

    // Ring expanding from 0.8 to 3.2 scale
    float ringStart = 0.08;
    float ringEnd = 0.32;
    float currentRadius = mix(ringStart, ringEnd, progress);

    float ringWidth = 0.02;
    float ringMask = smoothstep(currentRadius - ringWidth, currentRadius, dist) *
                     (1.0 - smoothstep(currentRadius, currentRadius + ringWidth, dist));

    float alpha = ringMask * (1.0 - progress) * 0.9; // fade out
    float3 color = float3(0.49, 1.0, 0.63); // #7dffa0

    return float4(color, alpha);
}

// ──────────────────────────────────────────────────────────────
// FRAGMENT SHADER: Checkmark (concept .ck)
// stroke-dashoffset animation
// ──────────────────────────────────────────────────────────────

fragment float4 checkmark_fragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant float2& center [[buffer(1)]],
    constant float& progress [[buffer(2)]],
    constant float& size [[buffer(3)]]
) {
    float2 uv = in.uv;
    float2 c = center;
    float s = size;

    // Checkmark path: M5 12.5 l4.5 4.5 L19 7.5
    // In normalized coords: (0.21, 0.52) -> (0.4, 0.71) -> (0.79, 0.31)
    // Draw as two line segments with stroke

    float2 p1 = float2(0.21, 0.52);
    float2 p2 = float2(0.40, 0.71);
    float2 p3 = float2(0.79, 0.31);

    float2 localUV = (uv - c) / s + 0.5;

    float strokeWidth = 0.032;
    float totalLength = distance(p1, p2) + distance(p2, p3);
    float drawLength = progress * totalLength;

    float alpha = 0.0;
    float3 color = float3(0.49, 1.0, 0.63); // #7dffa0

    // First segment
    if (drawLength > 0) {
        float seg1Len = distance(p1, p2);
        float drawn1 = min(drawLength, seg1Len);
        if (drawn1 > 0) {
            float t = drawn1 / seg1Len;
            float2 endPt = mix(p1, p2, t);
            // Distance from line segment p1->endPt
            float2 v = endPt - p1;
            float2 w = localUV - p1;
            float proj = dot(w, v) / dot(v, v);
            if (proj >= 0.0 && proj <= 1.0) {
                float2 closest = p1 + v * proj;
                float d = distance(localUV, closest);
                if (d < strokeWidth) {
                    alpha = 1.0 - smoothstep(0.0, strokeWidth, d);
                }
            }
        }
    }

    // Second segment
    if (drawLength > distance(p1, p2)) {
        float seg2Len = distance(p2, p3);
        float drawn2 = min(drawLength - distance(p1, p2), seg2Len);
        if (drawn2 > 0) {
            float t = drawn2 / seg2Len;
            float2 endPt = mix(p2, p3, t);
            float2 v = endPt - p2;
            float2 w = localUV - p2;
            float proj = dot(w, v) / dot(v, v);
            if (proj >= 0.0 && proj <= 1.0) {
                float2 closest = p2 + v * proj;
                float d = distance(localUV, closest);
                if (d < strokeWidth) {
                    alpha = max(alpha, 1.0 - smoothstep(0.0, strokeWidth, d));
                }
            }
        }
    }

    return float4(color, alpha);
}