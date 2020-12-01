#version 300 es

in highp vec4 texcoord;

out highp vec4 FragColor;

uniform sampler2D texture;

void main(void) {
  if (texcoord.w < 0.0) {
    FragColor = texture2D(texture, vec2(fract(texcoord.x), texcoord.z));
  } else {
    FragColor = texture2D(texture, vec2(fract(texcoord.x + texcoord.z), texcoord.y)) * 0.85;
  }
}
