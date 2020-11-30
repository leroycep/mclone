#version 300 es

in highp vec4 texcoord;

out highp vec4 FragColor;

void main(void) {
  FragColor = vec4(texcoord.w / 128.0, texcoord.w / 256.0, texcoord.w / 512.0, 1.0);
}
