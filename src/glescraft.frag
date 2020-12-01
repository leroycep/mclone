#version 300 es

in highp vec4 texcoord;

out highp vec4 FragColor;

uniform highp sampler2DArray textureArray;

void main(void) {
  if (texcoord.w < 0.0) {
    FragColor = texture(textureArray, vec3(fract(texcoord.x), texcoord.z, -texcoord.w));
  } else {
    FragColor = texture(textureArray, vec3(fract(texcoord.x + texcoord.z), texcoord.y, texcoord.w)) * 0.85;
  }
}
