#version 310 es

layout (location = 0) in vec4 coord;
layout (location = 1) in uint ao;
layout (location = 2) in uint light;
uniform mat4 mvp;
uniform mat4 modelTransform;
uniform uint daytime;
out vec4 texcoord;
out float fragment_ao;
out float fragment_light;

void main(void) {
  texcoord = coord;
  if (ao == uint(0)) fragment_ao = 0.3;
  else if (ao == uint(1)) fragment_ao = 0.5;
  else if (ao == uint(2)) fragment_ao = 0.7;
  else if (ao == uint(3)) fragment_ao = 1.0;
  // float sun = (float((light >> 28) & 0xFu) / 16.0);
  // float torch = (float((light >> 20) & 0xFu) / 16.0);
  uint lightReversed = bitfieldReverse(light);
  float sun = (float((lightReversed >> 9) & 0xFu)) / 16.0;
  float torch = (float((lightReversed) & 0xFu)) / 16.0;
  if (daytime == 0u) {
    fragment_light = torch;
  } else {
    fragment_light = sun;
  }
  gl_Position = mvp * modelTransform * vec4(coord.xyz, 1);
}
