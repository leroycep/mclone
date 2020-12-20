const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core");
const World = core.World;
const Chunk = core.chunk.Chunk;
const math = @import("math");
const Vec3i = math.Vec(3, i64);
const vec3i = Vec3i.init;
const Mat4f = math.Mat4(f32);
const ChunkRender = @import("./chunk_render.zig").ChunkRender;
const platform = @import("platform");
const gl = platform.gl;
const glUtil = platform.glUtil;
const ArrayDeque = @import("util").ArrayDeque;

const UpdateTag = enum {
    LoadChunk,
    Remesh,
};

const Update = union(UpdateTag) {
    LoadChunk: Chunk,
    Remesh: void,
};

pub const WorldRenderer = struct {
    allocator: *Allocator,
    world: World,
    renderedChunks: std.AutoHashMap(Vec3i, ChunkRender),
    updateQueue: std.AutoArrayHashMap(Vec3i, Update),

    program: gl.GLuint,
    projectionMatrixUniform: gl.GLint = undefined,
    modelTransformUniform: gl.GLint = undefined,
    daytimeUniform: gl.GLint = undefined,
    tilesetTex: gl.GLuint = undefined,

    pub fn init(allocator: *Allocator, tilesetTex: gl.GLuint) !@This() {
        var this = @This(){
            .allocator = allocator,
            .world = try World.init(allocator),
            .renderedChunks = std.AutoHashMap(Vec3i, ChunkRender).init(allocator),
            .program = try glUtil.compileShader(
                allocator,
                @embedFile("chunk_render.vert"),
                @embedFile("chunk_render.frag"),
            ),
            .updateQueue = std.AutoArrayHashMap(Vec3i, Update).init(allocator),
        };

        gl.useProgram(this.program);
        defer gl.useProgram(0);

        this.projectionMatrixUniform = gl.getUniformLocation(this.program, "mvp");
        this.modelTransformUniform = gl.getUniformLocation(this.program, "modelTransform");
        this.daytimeUniform = gl.getUniformLocation(this.program, "daytime");
        this.tilesetTex = tilesetTex;

        return this;
    }

    pub fn deinit(this: *@This()) void {
        gl.deleteProgram(this.program);
        var rendered_iter = this.renderedChunks.iterator();
        while (rendered_iter.next()) |entry| {
            entry.value.deinit();
        }
        this.world.deinit();
        this.renderedChunks.deinit();
        this.updateQueue.deinit();
    }

    pub fn queueLoadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.updateQueue.put(chunkPos, Update{
            .LoadChunk = chunk,
        });
    }

    pub fn queueRemeshChunk(this: *@This(), chunkPos: Vec3i) !void {
        const gop = try this.updateQueue.getOrPut(chunkPos);
        if (!gop.found_existing) {
            gop.entry.value = .Remesh;
        }
    }

    pub fn update(this: *@This()) !void {
        for (this.updateQueue.items()) |entry| {
            switch (entry.value) {
                .LoadChunk => |chunk| {
                    try this.loadChunkFromMemory(entry.key, chunk);
                },
                .Remesh => |pos| {
                    try this.remeshChunk(entry.key);
                },
            }
            _ = this.updateQueue.remove(entry.key);
            break;
        }
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.world.loadChunkFromMemory(chunkPos, chunk);
        const gop = try this.renderedChunks.getOrPut(chunkPos);
        if (!gop.found_existing) {
            gop.entry.value = ChunkRender.init(this.allocator);
        }
        try gop.entry.value.update(chunk, chunkPos, &this.world);
    }

    pub fn render(this: @This(), context: *platform.Context, projection: Mat4f, daytime: u32) void {
        gl.useProgram(this.program);
        defer gl.useProgram(0);
        const screen_size_int = context.getScreenSize();
        const screen_size = screen_size_int.intToFloat(f64);
        gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.tilesetTex);
        gl.uniform1ui(this.daytimeUniform, daytime);
        gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &projection.v);
    }

    pub fn remeshChunk(this: *@This(), chunkPos: Vec3i) !void {
        if (this.renderedChunks.get(chunkPos)) |*chunkRender| {
            if (this.world.chunks.get(chunkPos)) |*chunk| {
                try chunkRender.update(chunk.*, chunkPos, &this.world);
            }
        }
    }
};
