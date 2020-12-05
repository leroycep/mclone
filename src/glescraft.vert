#version 300 es

in vec4 coord;
uniform mat4 mvp;
uniform mat4 modelTransform;
out vec4 texcoord;

void main(void) {
  texcoord = coord;
  gl_Position = mvp * modelTransform * vec4(coord.xyz, 1);
}
