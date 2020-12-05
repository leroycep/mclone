const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core");
const World = core.World;
const Chunk = core.chunk.Chunk;
const math = @import("math");
const Vec3i = math.Vec(3, i64);
const vec3i = Vec3i.init;
const ChunkRender = @import("./chunk.zig").ChunkRender;
const platform = @import("platform");

pub const WorldRenderer = struct {
    allocator: *Allocator,
    world: World,
    renderedChunks: std.AutoHashMap(Vec3i, ChunkRender),

    pub fn init(allocator: *Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .world = try World.init(allocator),
            .renderedChunks = std.AutoHashMap(Vec3i, ChunkRender).init(allocator),
        };
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.world.loadChunkFromMemory(chunkPos, chunk);
        const gop = try this.renderedChunks.getOrPut(chunkPos);
        if (!gop.found_existing) {
            gop.entry.value = ChunkRender.init();
        }
        gop.entry.value.update(chunk);
    }

    pub fn render(this: @This(), shader: platform.GLuint, modelTranformUniform: platform.GLint) void {
        var rendered_iter = this.renderedChunks.iterator();
        while (rendered_iter.next()) |entry| {
            const mat = math.Mat4(f32).translation(entry.key.intToFloat(f32).scale(16));
            platform.glUniformMatrix4fv(modelTranformUniform, 1, platform.GL_FALSE, &mat.v);
            entry.value.render(shader);
        }
    }
};
