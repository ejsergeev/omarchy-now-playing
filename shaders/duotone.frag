#version 440
// The cover as a duotone: its dark tones in `dark`, its light tones in
// `light` (the theme's background and text colours). Qt Quick textures are
// premultiplied, so the brightness is taken from the straight colour and the
// result is premultiplied again with the source's alpha.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 dark;
    vec4 light;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 pixel = texture(source, qt_TexCoord0);
    vec3 straight = pixel.a > 0.0 ? pixel.rgb / pixel.a : vec3(0.0);
    float luma = dot(straight, vec3(0.2126, 0.7152, 0.0722));
    // A gentle S-curve: covers are rarely full-range, and a duotone reads
    // best with both colours clearly present.
    float tone = smoothstep(0.08, 0.92, luma);
    fragColor = vec4(mix(dark.rgb, light.rgb, tone), 1.0) * pixel.a * qt_Opacity;
}
