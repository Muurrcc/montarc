// Montarc's look: a touch of sharpening, the bloom, a hue-keeping highlight shoulder (so bright
// colours roll off instead of clipping), contrast, saturation and a light vignette.
override tonemap: u32 = 1u;
override exposure: f32 = 1.0;
override saturation: f32 = 1.08;
override contrast: f32 = 1.05;
override bloom: f32 = 0.5;
override sharpen: f32 = 0.3;
override vignette: bool = true;
override dimension_grade: bool = true;
override heat_haze: f32 = 1.0;
override god_rays: f32 = 0.0;

fn soft_shoulder(c: vec3<f32>) -> vec3<f32> {
    let m = max(max(c.r, c.g), max(c.b, 0.0001));
    let knee = 0.75;
    var f = m;
    if m > knee {
        f = knee + (1.0 - knee) * (1.0 - exp(-(m - knee) / (1.0 - knee)));
    }
    return c * (f / m);
}

fn scene(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb;
}

// Sunbeams: light from the sky streaming past whatever stands between you and the sun. Marches
// from this pixel toward the sun on screen and counts how much of the way is open sky.
fn sun_rays(uv: vec2<f32>) -> vec3<f32> {
    let sun = frame.sun_direction;
    if frame.dimension != 0 || sun.y < 0.02 || frame.eye_in != 0u {
        return vec3<f32>(0.0);
    }
    let clip = frame.projection * (frame.view * vec4<f32>(sun, 0.0) + vec4<f32>(0.0, 0.0, 0.0, 1.0));
    if clip.w <= 0.0 {
        return vec3<f32>(0.0);
    }
    let ndc = clip.xy / clip.w;
    let suv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    let aspect = frame.resolution.x / frame.resolution.y;
    let near = length((uv - suv) * vec2<f32>(aspect, 1.0));
    let falloff = 1.0 - smoothstep(0.0, 1.2, near);
    if falloff <= 0.0 {
        return vec3<f32>(0.0);
    }
    let jitter = ign(uv * frame.resolution);
    var open = 0.0;
    for (var i = 0; i < 12; i++) {
        let f = (f32(i) + jitter) / 12.0;
        let p = mix(uv, suv, f * 0.8);
        if all(p > vec2<f32>(0.0)) && all(p < vec2<f32>(1.0)) {
            open += select(0.0, 1.0, depth_at(p) == 0.0);
        }
    }
    let k = pow(open / 12.0, 1.5) * falloff * smoothstep(0.02, 0.3, sun.y);
    return direct_color() * (k * (1.0 - frame.rain) * 0.35);
}

fn post(input: PostInput) -> vec4<f32> {
    var uv = input.uv;
    // Nether: the air shimmers, a little more the farther away it is.
    if dimension_grade && frame.dimension == -1 && heat_haze > 0.0 {
        let far = 1.0 - smoothstep(0.0, 0.08, input.depth);
        let amp = heat_haze * 0.0011 * (0.35 + 0.65 * far);
        let t = frame.time;
        uv += vec2<f32>(sin(uv.y * 38.0 + t * 1.7) + sin(uv.y * 91.0 - t * 2.3) * 0.5, cos(uv.x * 33.0 + t * 1.3) * 0.4) * amp;
        uv = clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
    }
    let s = textureSampleLevel(scene_color, linear_sampler, uv, 0.0);
    var c = s.rgb;

    if sharpen > 0.0 {
        let px = 1.0 / frame.resolution;
        let blur = (scene(uv + vec2<f32>(px.x, 0.0)) + scene(uv - vec2<f32>(px.x, 0.0))
            + scene(uv + vec2<f32>(0.0, px.y)) + scene(uv - vec2<f32>(0.0, px.y))) * 0.25;
        c = max(c + (c - blur) * sharpen, vec3<f32>(0.0));
    }

    if bloom > 0.0 {
        var boost = 1.0;
        if dimension_grade && frame.dimension != 0 {
            boost = select(1.35, 1.6, frame.dimension == -1);
        }
        c += textureSampleLevel(bloom_c, linear_sampler, uv, 0.0).rgb * (bloom * 1.6 * boost);
    }

    if god_rays > 0.0 {
        c += sun_rays(uv) * god_rays;
    }

    // Underwater the picture goes blue-green; in lava, red.
    c = mix(c, c * vec3<f32>(0.62, 0.9, 1.05) + vec3<f32>(0.0, 0.012, 0.028), frame.in_water);
    c = mix(c, c * vec3<f32>(1.2, 0.8, 0.7), frame.in_lava);

    c *= exposure;
    if tonemap == 1u {
        c = soft_shoulder(c);
    } else if tonemap == 2u {
        c = aces(c * 0.9) * 1.04;
    }
    c = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));

    c = clamp((c - vec3<f32>(0.5)) * contrast + vec3<f32>(0.5), vec3<f32>(0.0), vec3<f32>(1.0));
    c = saturate_color(c, saturation);

    var edge = 0.28;
    if dimension_grade && frame.dimension == -1 {
        // Nether: warm, punchy, embers in the shadows.
        c = c * vec3<f32>(1.1, 0.95, 0.88) + vec3<f32>(0.018, 0.004, 0.0);
        c = clamp((c - vec3<f32>(0.5)) * 1.1 + vec3<f32>(0.5), vec3<f32>(0.0), vec3<f32>(1.0));
        c = saturate_color(c, 1.1);
        edge = 0.4;
    } else if dimension_grade && frame.dimension != 0 {
        // End: cold and violet, with deep blacks.
        let l = luminance(c);
        c = mix(c, vec3<f32>(l) * vec3<f32>(0.85, 0.72, 1.25), 0.3);
        c = c * vec3<f32>(0.94, 0.9, 1.1) + vec3<f32>(0.004, 0.0, 0.016) * (1.0 - l);
        c = saturate_color(c, 1.05);
        edge = 0.5;
    }

    if vignette {
        let aspect = frame.resolution.x / frame.resolution.y;
        let d = length((uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.55, 1.1, d) * edge;
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), s.a);
}
