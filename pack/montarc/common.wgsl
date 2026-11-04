// Montarc: shared helpers. Only `frame` is used here, so every stage can include this file.

const PI: f32 = 3.14159265;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn saturate_color(c: vec3<f32>, amount: f32) -> vec3<f32> {
    return mix(vec3<f32>(luminance(c)), c, amount);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Interleaved gradient noise: cheap, evenly spread, for rotating sample patterns per pixel.
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm3(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var q = p;
    for (var i = 0; i < 3; i++) {
        sum += value_noise(q) * amp;
        q = q * 2.03 + vec2<f32>(17.1, 9.2);
        amp *= 0.5;
    }
    return sum;
}

// 1 by day in the Overworld, 0 at night, easing through twilight. 0 elsewhere.
fn day_amount() -> f32 {
    return select(0.0, smoothstep(-0.12, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

// 1 with the sun on the horizon, 0 from about a quarter of the way up (either side of it).
fn twilight() -> f32 {
    return 1.0 - smoothstep(0.0, 0.42, abs(frame.sun_direction.y));
}

// The colour of the sky along `d`: the sky stage draws it and distant terrain fogs into it.
fn sky_gradient(d: vec3<f32>) -> vec3<f32> {
    let day = day_amount();
    let tw = twilight();
    let h = clamp(d.y, 0.0, 1.0);
    let band = pow(1.0 - h, 3.5);

    // Day: a deep, saturated blue overhead fading to a pale horizon.
    let day_col = mix(vec3<f32>(0.10, 0.31, 0.86), vec3<f32>(0.62, 0.79, 0.98), band);
    // Night: a deep navy with a slightly lighter rim.
    let night_col = mix(vec3<f32>(0.006, 0.012, 0.045), vec3<f32>(0.035, 0.055, 0.13), band);
    var col = mix(night_col, day_col, day);

    // Sunrise and sunset: warm light low around the sun, a magenta belt higher up and a
    // lilac one on the opposite side.
    let sun = frame.sun_direction;
    let flat_d = normalize(vec3<f32>(d.x, 0.0, d.z) + vec3<f32>(0.0001, 0.0, 0.0001));
    let flat_s = normalize(vec3<f32>(sun.x, 0.0, sun.z) + vec3<f32>(0.0001, 0.0, 0.0001));
    let along = dot(flat_d, flat_s) * 0.5 + 0.5;
    let horizon_glow = pow(1.0 - h, 2.2);
    let toward = pow(max(dot(d, sun), 0.0), 5.0);
    let warm = vec3<f32>(1.0, 0.46, 0.17) * (along * along * horizon_glow * 1.15 + toward * 0.7);
    let pink = vec3<f32>(0.95, 0.32, 0.5) * along * pow(1.0 - h, 1.2) * 0.35 * smoothstep(0.0, 0.5, h + 0.2);
    let lilac = vec3<f32>(0.48, 0.38, 0.72) * (1.0 - along) * horizon_glow * 0.35;
    let sunset = (warm + pink + lilac) * tw * (1.0 - frame.rain * 0.75);
    col += sunset * smoothstep(-0.3, 0.02, sun.y);

    // Rain and thunder wash it out to grey.
    let grey = vec3<f32>(0.46, 0.5, 0.55) * mix(0.1, 1.0, day);
    col = mix(col, grey * mix(1.0, 0.55, frame.thunder), frame.rain * 0.85);
    return col;
}

// Sunlight by day, moonlight by night (the body that casts this frame's shadows).
fn direct_color() -> vec3<f32> {
    let day = day_amount();
    let low = twilight();
    let sun_col = mix(vec3<f32>(1.0, 0.93, 0.81), vec3<f32>(1.0, 0.5, 0.2), low) * 1.28;
    let moon_col = vec3<f32>(0.25, 0.36, 0.62) * 0.5;
    var c = mix(moon_col, sun_col, day);
    c *= 1.0 - frame.rain * 0.88;
    return c;
}

// The light the open sky gives a surface facing straight up.
fn ambient_color() -> vec3<f32> {
    let day = day_amount();
    let low = twilight();
    let day_col = mix(vec3<f32>(0.45, 0.62, 1.0), vec3<f32>(0.68, 0.55, 0.7), low * 0.55) * 0.66;
    let night_col = vec3<f32>(0.075, 0.11, 0.24);
    var c = mix(night_col, day_col, day);
    c = mix(c, vec3<f32>(luminance(c)) * vec3<f32>(0.95, 1.0, 1.05), frame.rain * 0.55);
    return c;
}

// Narkowicz's fit of the ACES filmic curve: a soft shoulder that keeps colour.
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
