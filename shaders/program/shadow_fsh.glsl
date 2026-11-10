/*
================================================================================

  Muon Shaders
  program/shadow_fsh.glsl - shadow map fragment stage

  The shadow map only needs the depth buffer, so this stage only performs the
  alpha test (leaves, grass, glass and other cutout geometry).

  RENDERTARGETS is intentionally empty: Iris writes to shadowtex0/shadowtex1.

================================================================================
*/

#include "/lib/uniforms.glsl"

in vec2 uv;

void main() {
    vec4 texture_data = texture(gtexture, uv);

    if (texture_data.a < alphaTestRef) {
        discard;
    }
}
