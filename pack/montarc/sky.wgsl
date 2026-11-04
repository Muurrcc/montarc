// Montarc sky: a saturated gradient with warm sunsets. Distant terrain fogs into the same
// gradient (see material.wgsl), so the horizon has no seam. Sun, moon, stars and clouds are
// drawn over it by Horizon.
override sky_vibrance: f32 = 1.0;

fn sky(input: SkyInput) -> vec4<f32> {
    if frame.dimension != 0 {
        return input.color;
    }
    var col = sky_gradient(input.direction);
    col = saturate_color(col, sky_vibrance);
    return vec4<f32>(col, 1.0);
}
