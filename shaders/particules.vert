#version 330 core
layout(location = 0) in vec3 pos;
layout(location = 1) in vec4 off;
layout(location = 2) in vec4 particle_color;

out vec4 color;

uniform mat4 view_proj;

void main() {
    gl_Position = view_proj * vec4(off.w * pos + off.xyz, 1.0);
    color = particle_color;
}