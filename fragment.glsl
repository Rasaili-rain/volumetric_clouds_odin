#version 330

uniform vec2 uResolution;
out vec4 fragColor;

void main() {
    // Generate UV from fragment coordinates
    vec2 uv = gl_FragCoord.xy / uResolution;
    
    // UV gradient (Red=U, Green=V)
    vec3 color = vec3(uv.x, uv.y, 0.0);
    
    fragColor = vec4(color, 1.0);
}