#version 310 es

in vec3 coord;
in vec3 frac_coord;
in float tex;
in uint ao;
in float light;
uniform mat4 mvp;
uniform mat4 modelTransform;
uniform uint daytime;
out vec4 texcoord;
out float fragment_ao;
out float fragment_light;

void main(void) {
  texcoord = vec4(coord.xyz, tex);
  if (ao == uint(0)) fragment_ao = 0.3;
  else if (ao == uint(1)) fragment_ao = 0.5;
  else if (ao == uint(2)) fragment_ao = 0.7;
  else if (ao == uint(3)) fragment_ao = 1.0;
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
