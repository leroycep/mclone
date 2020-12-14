#version 310 es

in vec3 coord;
in vec3 frac_coord;
in float tex;
in float ao;
in float light;
uniform mat4 mvp;
uniform mat4 modelTransform;
uniform uint daytime;
out vec4 texcoord;
out float fragment_ao;
out float fragment_light;

void main(void) {
  texcoord = vec4(coord.xyz, tex);
  fragment_ao = (1.0 + ao) / 4.0;
  float sun = (mod(light / float(0xF + 1), float(0xF + 1)) / float(0xF));
  float torch = mod(light, float(0xF + 1)) / float(0xF);
  if (daytime == 0u) {
    fragment_light = torch;
  } else if (daytime == 1u) {
    fragment_light = sun;
  } else {
    fragment_light = max(sun, torch);
  }
  gl_Position = mvp * modelTransform * vec4(coord.xyz + (frac_coord.xyz / 128.0), 1);
}
