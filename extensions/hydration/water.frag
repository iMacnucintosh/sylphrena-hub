#version 440

// Water tank of the dashboard hydration widget: the same two waves, gradient and white crest the
// Canvas used to paint on the CPU, now computed per pixel on the GPU.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // item size in pixels
    float fill;      // 0..1 water level
    float phase;     // wave phase (radians)
    float amp;       // wave amplitude in pixels
    vec4 topColour;  // straight (not premultiplied) RGBA at the water line
    vec4 bottomColour;
};

const float PI = 3.14159265358979;

void main() {
    vec2 p = qt_TexCoord0 * size;
    float w = max(size.x, 1.0);
    float h = max(size.y, 1.0);
    float x = p.x / w;

    float lvl = clamp(fill, 0.06, 1.0);
    float waterTop = h * (1.0 - lvl);

    // Main wave
    float y1 = waterTop + sin(x * PI * 2.0 + phase) * amp + sin(x * PI * 4.0 - phase * 1.3) * amp * 0.35;
    float cov1 = clamp(p.y - y1 + 0.5, 0.0, 1.0);
    float t = clamp((p.y - waterTop) / max(h - waterTop, 1.0), 0.0, 1.0);
    vec4 c = mix(topColour, bottomColour, t);
    vec4 water = vec4(c.rgb * c.a, c.a) * cov1;

    // Lighter crest band over it
    float crest = waterTop + amp * 0.2 + sin(x * PI * 2.0 - phase * 0.8) * amp * 0.55;
    float cov2 = clamp(p.y - crest + 0.5, 0.0, 1.0);
    vec4 shine = vec4(1.0) * 0.14 * cov2;

    fragColor = (shine + water * (1.0 - shine.a)) * qt_Opacity;
}
