// Depth-aware volumetric clouds.
//
// The sky stage cannot draw a cloud deck that lies below the camera: the sky
// dome only covers rays above the horizon. This pass rays from the world camera
// through every pixel, stops at the scene depth, and composites the clouds in
// front of whatever is there. That keeps clouds visible from above and lets
// them occlude terrain correctly.
fn post(input: PostInput) -> vec4<f32> {
    if (!clouds_enabled) { return input.color; }

    var max_dist = 1.0e9;
    if (input.depth > 0.0) {
        max_dist = length(view_position(input.uv, input.depth));
    }

    let near = view_position(input.uv, 1.0);
    let dir = normalize(near);
    let cl = mu_clouds(frame.camera_position, dir, max_dist);

    let base = mu_scene_decode(input.color.rgb);
    let out_color = base * cl.w + cl.xyz;
    return vec4<f32>(mu_scene_encode(out_color), input.color.a);
}
