// Montarc terrain: sun and sky light with soft shadows, warm coloured block light, a living
// water surface and a fog that melts into the sky. Vertex wind lives in vertex.wgsl (same module).
override shadows: bool = true;
override shadow_samples: u32 = 1u;
override shadow_softness: f32 = 1.6;
override shadow_bias: f32 = 1.0;
override sun_strength: f32 = 1.0;
override ambient_strength: f32 = 1.0;
override block_light_strength: f32 = 1.0;
override colored_lights: bool = true;
override material_vibrance: f32 = 1.12;
override fog_amount: f32 = 1.0;
override wet_ground: bool = true;
override reflections: bool = true;
override water_waves: f32 = 1.0;
override water_clarity: f32 = 1.0;
override foam: bool = true;

// Vanilla's directional face shade, baked into the vertex colour: undone here because the pack
// lights faces itself.
fn face_shade(n: vec3<f32>) -> f32 {
    let s = n * n;
    let down = select(1.0, 0.5, n.y < 0.0);
    return clamp(s.y * down + s.z * 0.8 + s.x * 0.6, 0.5, 1.0);
}

struct ShadowResult {
    vis: f32,
    tint: vec3<f32>,
}

// How much of the light reaches `position`, and the colour water or glass gives it on the way.
fn sample_shadow(position: vec3<f32>, n: vec3<f32>, l: vec3<f32>, pixel: vec2<f32>) -> ShadowResult {
    var r: ShadowResult;
    r.vis = 1.0;
    r.tint = vec3<f32>(1.0);
    if frame.has_shadow == 0u {
        return r;
    }
    let dist = length(position.xz);
    // A shadow texel covers more ground the farther it is from the camera.
    let scale = 1.0 + 2.5 * dist / max(frame.shadow_distance, 1.0);
    let texel = frame.shadow_center_texel * scale * shadow_bias;
    let ndl = clamp(dot(n, l), 0.0, 1.0);
    let slope = sqrt(1.0 - ndl * ndl) / max(ndl, 0.2);
    let offset = n * (texel * 1.3) + l * (texel * (0.7 + min(slope, 3.0) * 0.9));
    let sp = shadow_position(position + offset);

    let radius = shadow_softness / max(frame.shadow_resolution, 1.0);
    let rot = ign(pixel) * 6.2831853;
    let count = select(select(14u, 8u, shadow_samples == 1u), 4u, shadow_samples == 0u);
    var sum = 0.0;
    for (var i = 0u; i < count; i++) {
        let fi = f32(i);
        let rr = sqrt((fi + 0.5) / f32(count));
        let a = fi * 2.3999632 + rot;
        let o = vec2<f32>(cos(a), sin(a)) * (rr * radius);
        sum += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy + o, sp.z);
    }
    r.vis = sum / f32(count);

    // Light that passes through water or stained glass takes its colour.
    if r.vis > 0.02 {
        let lit_t = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, sp.xy, sp.z);
        if lit_t < 0.5 {
            let dims = vec2<f32>(textureDimensions(shadow_color));
            let uv = clamp(sp.xy, vec2<f32>(0.0), vec2<f32>(0.999));
            let c = textureLoad(shadow_color, vec2<i32>(uv * dims), 0);
            let k = select(c.a, 0.85, c.a > 0.99);
            r.tint = mix(vec3<f32>(1.0), c.rgb, k) * select(1.0, 0.92, c.a > 0.99);
        }
    }
    return r;
}

// All the light a surface with normal `n` receives (before its colour is applied).
// `wrap` lets light bend round foliage; `use_shadow` turns the shadow map on for this surface.
fn surface_light(input: MaterialInput, n: vec3<f32>, wrap: f32, use_shadow: bool) -> vec3<f32> {
    let sky_l = clamp(input.light.y, 0.0, 1.0);
    let block_l = clamp(input.light.x, 0.0, 1.0);
    let day = day_amount();
    let pixel = input.screen * frame.resolution;
    var total = vec3<f32>(0.0);

    // Sky light: brighter on faces that look up.
    let hemi = mix(0.62, 1.0, n.y * 0.5 + 0.5);
    total += ambient_color() * (hemi * pow(sky_l, 1.7) * ambient_strength);

    // Sun by day, moon by night.
    let l = frame.light_direction;
    let fade = smoothstep(0.0, 0.16, l.y);
    let diff = clamp((dot(n, l) + wrap) / (1.0 + wrap), 0.0, 1.0);
    let access = smoothstep(0.55, 0.95, sky_l);
    if diff > 0.0 && fade > 0.0 && access > 0.0 {
        var vis = 1.0;
        var tint = vec3<f32>(1.0);
        if shadows && use_shadow {
            let s = sample_shadow(input.position, n, l, pixel);
            let edge = smoothstep(0.8, 1.0, length(input.position.xz) / max(frame.shadow_distance, 1.0));
            vis = mix(s.vis, 1.0, edge);
            tint = mix(s.tint, vec3<f32>(1.0), edge);
        }
        total += direct_color() * tint * (diff * vis * access * fade * sun_strength);
    }

    // Block light: torch-warm unless the source has a colour of its own.
    var bcol = vec3<f32>(1.0, 0.64, 0.34);
    if colored_lights {
        let bl = block_light_color(input.position);
        let m = max(max(bl.r, bl.g), max(bl.b, 0.001));
        bcol = mix(bcol, bl.rgb / m, clamp(bl.a, 0.0, 1.0) * step(0.01, m));
        total += input.colored_light * 1.2;
    }
    let wash = 1.0 - 0.8 * day * sky_l;
    total += bcol * (pow(block_l, 2.4) * 1.5 * wash * block_light_strength);

    // A little light everywhere so caves are dark, not black.
    total += vec3<f32>(0.022, 0.024, 0.036) * (1.0 + frame.brightness * 1.5);
    total += vec3<f32>(frame.night_vision * 0.55);
    return total * (1.0 - frame.darkness * 0.6);
}

// The Nether's biome colour: vanilla's fog colour (crimson, warped teal, soul-sand blue, basalt
// grey...) stretched to full brightness, so each biome keeps its own mood.
fn nether_tone() -> vec3<f32> {
    let f = frame.fog_color;
    return f / max(max(f.r, max(f.g, f.b)), 0.06);
}

// Light for the Nether and the End, which have no sun: a coloured ambient with a soft top-down
// shape, strong coloured block light, and in the End a violet rim on edges.
fn dimension_light(input: MaterialInput, n: vec3<f32>) -> vec3<f32> {
    let block_l = clamp(input.light.x, 0.0, 1.0);
    let up = n.y * 0.5 + 0.5;
    let vanilla = clamp(luminance(input.lightmap), 0.0, 1.0);
    var total = vec3<f32>(0.0);

    if frame.dimension == -1 {
        // Hot, close, orange-red: the biome colour leans on a lava glow from below.
        let tone = mix(vec3<f32>(1.0, 0.42, 0.2), nether_tone(), 0.55);
        let from_below = mix(0.75, 1.0, 1.0 - up) ;
        total += tone * (0.34 * from_below * (0.55 + 0.45 * vanilla));
        let glow = mix(vec3<f32>(1.0, 0.5, 0.18), tone, 0.3);
        total += glow * (pow(block_l, 2.0) * 2.2 * block_light_strength);
    } else {
        // The End: cold violet air, pale lilac light on the main island.
        let sky_l = clamp(input.light.y, 0.0, 1.0);
        let tone = vec3<f32>(0.46, 0.34, 0.9);
        total += tone * (0.3 * mix(0.7, 1.0, up) * (0.6 + 0.4 * max(vanilla, sky_l)));
        total += vec3<f32>(0.82, 0.62, 1.0) * (pow(block_l, 2.2) * 1.7 * block_light_strength);
        let view = normalize(input.position);
        let rim = pow(1.0 - clamp(abs(dot(n, -view)), 0.0, 1.0), 3.0);
        total += vec3<f32>(0.5, 0.2, 0.95) * (rim * 0.22);
    }

    if colored_lights {
        total += input.colored_light * 1.2;
    }
    total += vec3<f32>(frame.night_vision * 0.55);
    return total * (1.0 - frame.darkness * 0.6);
}

// Fog toward the sky's own colour, so the world fades into the horizon without a seam.
fn fog_blend(color: vec3<f32>, position: vec3<f32>) -> vec3<f32> {
    let dist = length(position);
    let dir = position / max(dist, 0.0001);
    let eye_sky = clamp(frame.eye_light_smooth.y, 0.0, 1.0);
    var f = 0.0;
    var fc = frame.fog_color;

    if frame.eye_in == 1u {
        f = 1.0 - exp(-dist * 0.1);
        fc = vec3<f32>(0.03, 0.2, 0.33) * (0.18 + 0.82 * eye_sky);
    } else if frame.eye_in == 2u {
        f = 1.0 - exp(-dist * 0.7);
        fc = vec3<f32>(0.6, 0.15, 0.02);
    } else if frame.eye_in == 3u {
        f = 1.0 - exp(-dist * 1.2);
        fc = vec3<f32>(0.78, 0.88, 0.95) * (0.3 + 0.7 * eye_sky);
    } else if frame.dimension == -1 {
        // Thick, glowing heat haze in the biome's colour.
        let reach = max(frame.fog_end, 24.0) * 0.85 / max(fog_amount, 0.05);
        f = 1.0 - exp(-pow(dist / reach, 2.2));
        fc = nether_tone() * mix(vec3<f32>(0.5, 0.2, 0.12), vec3<f32>(0.42), 0.4) * vec3<f32>(1.0, 0.8, 0.7);
    } else if frame.dimension != 0 {
        // The End: a violet mist that swallows the void.
        let reach = max(frame.fog_end, 48.0) / max(fog_amount, 0.05);
        f = 1.0 - exp(-pow(dist / reach, 2.4));
        fc = mix(frame.fog_color, vec3<f32>(0.08, 0.035, 0.16), 0.65);
    } else {
        let reach = frame.render_distance * mix(0.7, 0.42, frame.wetness) / max(fog_amount, 0.05);
        f = 1.0 - exp(-pow(dist / max(reach, 1.0), 3.4));
        // A faint blue depth haze, so far hills read as far.
        let haze = 1.0 - exp(-dist * 0.0018 * fog_amount);
        f = 1.0 - (1.0 - f) * (1.0 - haze * 0.45);
        fc = sky_gradient(normalize(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.3, dir.z)));
        fc *= mix(0.12, 1.0, smoothstep(0.0, 0.55, eye_sky));
    }

    let blind = max(frame.blindness, frame.darkness * 0.7);
    f = mix(f, 1.0, blind * smoothstep(1.0, 8.0, dist));
    fc = mix(fc, vec3<f32>(0.0), blind);
    return mix(color, fc, clamp(f, 0.0, 1.0));
}

fn water_height(p: vec2<f32>, t: f32) -> f32 {
    let q = p * 0.55 + vec2<f32>(t * 0.12, t * 0.07);
    return fbm3(q) + fbm3(q * 1.9 - vec2<f32>(t * 0.2, t * 0.05)) * 0.5;
}

// How far the world behind this point is, in blocks from the camera (96 for open sky).
fn distance_behind(screen: vec2<f32>) -> f32 {
    let size = frame.resolution;
    let px = vec2<i32>(clamp(screen * size, vec2<f32>(0.0), size - vec2<f32>(1.0)));
    let d = textureLoad(opaque_depth, px, 0);
    if d <= 0.0 {
        return 96.0;
    }
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, d, 1.0);
    let v = frame.projection_inverse * clip;
    return length(v.xyz / v.w);
}

fn water_surface(input: MaterialInput, tint: vec3<f32>) -> vec4<f32> {
    let n = input.normal;
    let view = normalize(input.position);
    let w = input.position + frame.camera_position;
    let t = frame.time;
    let dist = length(input.position);

    // Ripples on the top face, fading with distance.
    var wn = n;
    if input.face == 1u && water_waves > 0.0 {
        let e = 0.1;
        let h0 = water_height(w.xz, t);
        let hx = water_height(w.xz + vec2<f32>(e, 0.0), t);
        let hz = water_height(w.xz + vec2<f32>(0.0, e), t);
        let amp = 0.2 * water_waves / (1.0 + dist * 0.025);
        wn = normalize(vec3<f32>(-(hx - h0) / e * amp, 1.0, -(hz - h0) / e * amp));
    }

    let thick = max(distance_behind(input.screen) - dist, 0.0);
    let absorb = 1.0 - exp(-thick * 0.22 / max(water_clarity, 0.1));
    let shallow = vec3<f32>(0.10, 0.62, 0.70);
    let deep = vec3<f32>(0.015, 0.13, 0.30);
    var body = mix(shallow, deep, absorb);
    // Keep a hint of the biome's water colour (swamps stay murky and green).
    body = mix(body, body * (tint / max(luminance(tint), 0.25)), 0.4);
    let lit = surface_light(input, vec3<f32>(0.0, 1.0, 0.0), 0.35, true);
    body *= clamp(lit, vec3<f32>(0.0), vec3<f32>(1.6)) * 0.95;

    var alpha = mix(0.34, 0.94, absorb);
    var rgb = body;

    if frame.eye_in == 0u {
        let cosv = clamp(dot(-view, wn), 0.0, 1.0);
        let fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
        let r = reflect(view, wn);
        var refl = sky_gradient(vec3<f32>(r.x, abs(r.y), r.z));
        if reflections && frame.has_reflection == 1u {
            let suv = clamp(input.screen + wn.xz * 0.12, vec2<f32>(0.002), vec2<f32>(0.998));
            let mir = textureSampleLevel(reflection, reflection_sampler, suv, 0.0).rgb;
            // The mirror holds vanilla's sky; swap it for ours.
            let d_sky = min(distance(mir, frame.sky_color), distance(mir, frame.fog_color));
            refl = mix(mir, refl, 1.0 - smoothstep(0.03, 0.12, d_sky));
        }
        rgb = mix(body, refl, fres * 0.92);
        alpha = max(alpha, fres);

        // Sun glitter.
        let l = frame.light_direction;
        let fade = smoothstep(0.0, 0.14, l.y) * smoothstep(0.55, 0.95, input.light.y);
        let rl = max(dot(r, l), 0.0);
        let glint = pow(rl, 500.0) * 14.0 + pow(rl, 40.0) * 0.35;
        rgb += direct_color() * (glint * fade * (1.0 - frame.rain));
        alpha = max(alpha, clamp(glint * fade, 0.0, 1.0));

        // Foam where the water meets the shore.
        if foam {
            let edge = 1.0 - smoothstep(0.0, 0.5, thick);
            let streak = smoothstep(0.35, 0.75, value_noise(w.xz * 3.0 + vec2<f32>(t * 0.3, 0.0)));
            let f = edge * streak * 0.6;
            rgb = mix(rgb, vec3<f32>(0.95, 0.98, 1.0) * clamp(lit, vec3<f32>(0.2), vec3<f32>(1.2)), f);
            alpha = max(alpha, f);
        }
    } else {
        // Seen from below the surface is a dim, bright-edged ceiling.
        alpha = 0.55;
    }
    return vec4<f32>(fog_blend(rgb, input.position), clamp(alpha, 0.0, 1.0));
}

fn material(input: MaterialInput) -> Surface {
    let n = input.normal;
    let m = input.material;
    let plant = m >= 1u && m <= 3u;
    let leaves = m == 4u;

    if input.fluid == 1u {
        return Surface(water_surface(input, input.tint.rgb));
    }
    if input.fluid == 2u {
        // Lava lights itself.
        let lava = input.albedo.rgb * input.tint.rgb * 1.9;
        return Surface(vec4<f32>(fog_blend(lava, input.position), 1.0));
    }

    var albedo = saturate_color(input.albedo.rgb, material_vibrance);
    var tint = input.tint.rgb;
    if !plant {
        tint = tint / face_shade(n);
    }

    var color: vec3<f32>;
    if frame.dimension != 0 {
        color = albedo * tint * dimension_light(input, n);
    } else {
        let sky_l = clamp(input.light.y, 0.0, 1.0);
        if wet_ground {
            let wet = frame.wetness * smoothstep(0.7, 1.0, sky_l) * (0.45 + 0.55 * max(n.y, 0.0));
            albedo *= 1.0 - 0.3 * wet;
        }
        let wrap = select(0.0, 0.5, plant || leaves);
        let light = surface_light(input, n, wrap, true);
        color = albedo * tint * light;
        // Sunlight glowing through foliage.
        if plant || leaves {
            let through = max(-dot(n, frame.light_direction), 0.0) * smoothstep(0.0, 0.2, frame.light_direction.y);
            color += albedo * tint * direct_color() * (through * 0.25 * smoothstep(0.55, 0.95, sky_l));
        }
    }
    color += albedo * input.emission * 1.8;

    return Surface(vec4<f32>(fog_blend(color, input.position), input.albedo.a));
}
