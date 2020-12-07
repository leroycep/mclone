#version 300 es

in highp vec4 texcoord;
in highp float fragment_ao;
in highp float fragment_light;

out highp vec4 FragColor;

uniform highp sampler2DArray textureArray;

void main(void) {
  // if (texcoord.w < 0.0) {
  //   FragColor = texture(textureArray, vec3(fract(texcoord.x), texcoord.z, -texcoord.w));
  // } else {
  FragColor = texture(textureArray, vec3(fract(texcoord.x + texcoord.z), texcoord.y, texcoord.w));
  // }
  highp vec3 light = vec3(fragment_light);
  light *= 0.0625;

  FragColor.xyz -= light;
  if (FragColor.a < 0.5)
    discard;
}
