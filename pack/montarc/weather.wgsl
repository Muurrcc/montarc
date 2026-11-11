// Montarc weather: rain and snow lit by the sky, the moon, torches and lightning, instead of
// vanilla's flat white. Rain is a pale silver-blue streak; at night it stays faintly visible
// without covering the screen in dark lines.
fn weather(input: WeatherInput) -> vec4<f32> {
    let sky_l = clamp(input.light.y, 0.0, 1.0);
    let block_l = clamp(input.light.x, 0.0, 1.0);
    let day = day_amount();

    var lit = ambient_color() * (0.55 + 0.9 * pow(sky_l, 1.5)) + direct_color() * (0.25 * sky_l);
    // Torches and lanterns catch the drops near them.
    lit += vec3<f32>(1.0, 0.64, 0.34) * (pow(block_l, 2.4) * 1.1);
    // Lightning flashes through the rain.
    lit += vec3<f32>(0.8, 0.9, 1.2) * (frame.thunder * 1.2);
    lit = max(lit, vec3<f32>(0.08, 0.1, 0.16));

    if input.snow {
        let col = vec3<f32>(0.95, 0.97, 1.0) * lit * 1.4;
        return vec4<f32>(col, input.color.a * 0.85);
    }
    let col = vec3<f32>(0.72, 0.82, 0.95) * lit * 1.5;
    return vec4<f32>(col, input.color.a * mix(0.42, 0.7, day));
}
