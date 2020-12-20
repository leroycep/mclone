#version 300 es

layout(location = 0) in vec2 vertexPosition;
layout(location = 1) in vec2 vertexUV;

uniform mat4 mvp;

out vec2 uv;

void main() {
  uv = vertexUV;
  gl_Position = mvp * vec4(vertexPosition, 0.0, 1.0);
}
