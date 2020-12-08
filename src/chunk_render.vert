#version 300 es

layout (location = 0) in vec4 coord;
layout (location = 1) in uint ao;
layout (location = 2) in uint light;
uniform mat4 mvp;
uniform mat4 modelTransform;
out vec4 texcoord;
out float fragment_ao;
out float fragment_light;

void main(void) {
  texcoord = coord;
  if (ao == uint(0)) fragment_ao = 0.3;
  else if (ao == uint(1)) fragment_ao = 0.5;
  else if (ao == uint(2)) fragment_ao = 0.7;
  else if (ao == uint(3)) fragment_ao = 1.0;
  float torch = floor(float(light) / 16.0) / 15.0;
  float sun = mod(float(light), 16.0) / 15.0;
  fragment_light = clamp(torch + sun, 0.0, 1.0);
  gl_Position = mvp * modelTransform * vec4(coord.xyz, 1);
}
