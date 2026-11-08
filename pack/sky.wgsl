// Overworld sky. This is the only sky: the manifest turns the engine's own
// clouds, sun and stars off, and the pack draws all of them here. Drawing the
// sky in the sky stage (not reconstructing it in a post pass) is what keeps the
// clouds fixed in the world as the camera walks.
fn sky(input: SkyInput) -> vec4<f32> {
    let dir = normalize(input.direction);
    return vec4<f32>(mu_sky_encoded(dir, true), 1.0);
}
