// Bloom, step 2: a horizontal blur (a 9-tap Gaussian in five bilinear reads).
fn post(input: PostInput) -> vec4<f32> {
    let step = vec2<f32>(1.5 / (frame.resolution.x * 0.25), 0.0);
    var sum = textureSampleLevel(bloom_a, linear_sampler, input.uv, 0.0).rgb * 0.227027;
    sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + step * 1.3846154, 0.0).rgb * 0.3162162;
    sum += textureSampleLevel(bloom_a, linear_sampler, input.uv - step * 1.3846154, 0.0).rgb * 0.3162162;
    sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + step * 3.2307692, 0.0).rgb * 0.0702703;
    sum += textureSampleLevel(bloom_a, linear_sampler, input.uv - step * 3.2307692, 0.0).rgb * 0.0702703;
    return vec4<f32>(sum, 1.0);
}
