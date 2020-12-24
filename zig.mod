id: swi77lv1z34ezlarqeeu227tfqgqbc6tq84upoqfjeaycnlb
name: mclone
main: core/core.zig
dependencies:
- type: git
  path: https://github.com/leroycep/zigmath.git
- type: git
  path: https://github.com/mlarouche/zigimg.git
  name: zigimg
  main: zigimg.zig
- type: git
  path: https://git.sr.ht/~alva/zig-bare
  name: bare
  main: src/bare.zig
