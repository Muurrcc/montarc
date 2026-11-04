// Bloom, step 1: the picture's bright parts (lava, torches, the sun, glowing blocks) averaged
// down to a quarter of the size. The daytime sky is bright too, so it counts for a third.
override bloom_threshold: f32 = 0.9;

fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb;
    let sky = select(1.0, 0.35, depth_at(uv) == 0.0);
    let k = smoothstep(bloom_threshold, bloom_threshold + 0.35, luminance(c));
    return c * (k * sky);
}

fn post(input: PostInput) -> vec4<f32> {
    let px = 2.0 / frame.resolution;
    var sum = bright(input.uv + vec2<f32>(-px.x, -px.y));
    sum += bright(input.uv + vec2<f32>(px.x, -px.y));
    sum += bright(input.uv + vec2<f32>(-px.x, px.y));
    sum += bright(input.uv + vec2<f32>(px.x, px.y));
    return vec4<f32>(sum * 0.25, 1.0);
}
