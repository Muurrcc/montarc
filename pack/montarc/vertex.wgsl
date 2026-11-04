// Montarc wind: plants sway from the tip, leaves tremble and water breathes. It is a function of
// the corner's world position only, so neighbouring blocks move together and never open gaps.
// The same code moves the corners in the shadow map, so shadows follow the wind.
override waving: bool = true;
override wave_strength: f32 = 1.0;

fn wind(w: vec3<f32>, t: f32) -> vec2<f32> {
    let gust = value_noise(w.xz * 0.12 + vec2<f32>(t * 0.35, t * 0.2));
    let a = sin(t * 1.7 + w.x * 0.8 + w.z * 0.6) * 0.5 + sin(t * 2.9 + w.x * 1.7 - w.z * 1.3) * 0.25;
    let b = sin(t * 1.4 + w.z * 0.9 - w.x * 0.5) * 0.5 + sin(t * 3.3 + w.z * 1.9 + w.x * 0.7) * 0.25;
    let strength = 0.35 + gust * 0.9 + frame.rain * 0.6 + frame.thunder * 0.5;
    return vec2<f32>(a, b) * strength;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    if !waving || frame.dimension != 0 {
        return p;
    }
    let w = p + frame.camera_position;
    let t = frame.time;
    let m = input.material;

    // 1 short plants, 2 and 3 the lower and upper half of tall ones.
    if m >= 1u && m <= 3u {
        var amount = 1.0 - clamp(input.uv.y, 0.0, 1.0);
        var reach = 0.07;
        if m == 2u {
            amount = amount * 0.5;
            reach = 0.11;
        } else if m == 3u {
            amount = 0.5 + amount * 0.5;
            reach = 0.11;
        }
        let k = wind(w, t);
        let sway = amount * amount * reach * wave_strength;
        p += vec3<f32>(k.x * sway, 0.0, k.y * sway);
        return p;
    }

    // Leaves: a small shiver of every corner.
    if m == 4u {
        let k = wind(w * 1.7, t * 1.3);
        p += vec3<f32>(k.x, k.y * 0.6, k.y) * 0.022 * wave_strength;
        return p;
    }

    // Water: only the corners that sit on the surface (not on a block boundary) move.
    if input.fluid == 1u {
        let fy = fract(w.y + 0.001);
        if fy > 0.04 && fy < 0.97 {
            let swell = sin(t * 1.3 + w.x * 0.9 + w.z * 0.7) * 0.5 + sin(t * 2.1 - w.x * 0.6 + w.z * 1.2) * 0.5;
            p.y += swell * 0.03 * wave_strength;
        }
    }
    return p;
}
