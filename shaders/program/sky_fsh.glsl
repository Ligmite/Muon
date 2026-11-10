#include "/lib/uniforms.glsl"

layout(location = 0) out vec4 out_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

void main() {
    // The sky, sun and moon are drawn analytically in deferred4. Vanilla's sky
    // geometry only needs to clear the buffers so that depth == 1 marks sky.
    out_color = vec4(0.0, 0.0, 0.0, 1.0);
}
