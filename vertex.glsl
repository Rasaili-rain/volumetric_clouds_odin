#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
out vec2 vUv;

uniform mat4 mvp;

void main() {
    // Pass the texture coordinates directly
    vUv = vertexTexCoord;
    
    // For a fullscreen quad, we want it to cover the entire screen
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}