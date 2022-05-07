# mclone

Because we haven't thought of a better title.

mclone is a minecraft inspired voxel game. We aim to add more interesting automation by default into the game, since a lot of the fun we had in Minecraft was building overly complicated bases.

## Building

mclone is written in [zig](https://ziglang.org/), and is tracking the master branch. Install the latest nightly, and then run the following commands.

```shell
git clone https://github.com/leroycep/mclone
cd mclone

# -Dfetch will automatically download git dependencies
zig build -Dfetch

# Run the server
zig build server-run

# In another shell, run the native client
zig build run
```
