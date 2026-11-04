// Anti-aliasing. A pack's post chain replaces Horizon's own TAA and FXAA, so Montarc brings a
// spatial FXAA (Lottes' compact form) as its last pass.
override fxaa: bool = true;

fn tap(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    if !fxaa {
        return input.color;
    }
    let uv = input.uv;
    let texel = 1.0 / vec2<f32>(textureDimensions(previous));
    let nw = tap(uv + vec2<f32>(-1.0, -1.0) * texel);
    let ne = tap(uv + vec2<f32>(1.0, -1.0) * texel);
    let sw = tap(uv + vec2<f32>(-1.0, 1.0) * texel);
    let se = tap(uv + vec2<f32>(1.0, 1.0) * texel);
    let mid = tap(uv);

    let l_nw = luminance(nw);
    let l_ne = luminance(ne);
    let l_sw = luminance(sw);
    let l_se = luminance(se);
    let l_m = luminance(mid);
    let l_min = min(l_m, min(min(l_nw, l_ne), min(l_sw, l_se)));
    let l_max = max(l_m, max(max(l_nw, l_ne), max(l_sw, l_se)));

    // No edge, nothing to do.
    if l_max - l_min < max(0.0312, l_max * 0.125) {
        return input.color;
    }

    var dir = vec2<f32>(-((l_nw + l_ne) - (l_sw + l_se)), (l_nw + l_sw) - (l_ne + l_se));
    let reduce = max((l_nw + l_ne + l_sw + l_se) * 0.03125, 0.0078125);
    let rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
    dir = clamp(dir * rcp, vec2<f32>(-8.0), vec2<f32>(8.0)) * texel;

    let a = 0.5 * (tap(uv + dir * (1.0 / 3.0 - 0.5)) + tap(uv + dir * (2.0 / 3.0 - 0.5)));
    let b = a * 0.5 + 0.25 * (tap(uv + dir * -0.5) + tap(uv + dir * 0.5));
    let l_b = luminance(b);
    let out_rgb = select(b, a, l_b < l_min || l_b > l_max);
    return vec4<f32>(out_rgb, input.color.a);
}
