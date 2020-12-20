#version 300 es

in highp vec2 uv;

layout(location = 0) out highp vec4 color;

uniform lowp sampler2D render3D;
uniform lowp sampler2D render3D_translucent;

void main() {
  color = vec4(0.0); // mix(texture(render3D, uv), texture(render3D_translucent, uv), 0.5);
}
