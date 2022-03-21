#version 330 core
layout(location = 0) in vec3 pos;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main() {
    gl_Position = projection * view * model * vec4(pos, 1.0);
    // ourColor = aColor; // set ourColor to the input color we got from the vertex data
}