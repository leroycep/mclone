id: swi77lv1z34ezlarqeeu227tfqgqbc6tq84upoqfjeaycnlb
name: mclone
main: core/core.zig
dependencies:
- src: git https://github.com/leroycep/zigmath.git
- src: git https://github.com/mlarouche/zigimg.git
  name: zigimg
  main: zigimg.zig
- src: git https://git.sr.ht/~alva/zig-bare
  name: bare
  main: src/bare.zig

dev_dependencies:
- src: git https://github.com/leroycep/zigmath.git
- src: git https://github.com/leecannon/zigimg.git branch-zig-master
- src: git https://git.sr.ht/~alva/zig-bare
  name: bare
  main: src/bare.zig
