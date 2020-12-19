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

pub const WorldRenderer = struct {
    allocator: *Allocator,
    world: World,
    renderedChunks: std.AutoHashMap(Vec3i, ChunkRender),

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
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.world.loadChunkFromMemory(chunkPos, chunk);
        const gop = try this.renderedChunks.getOrPut(chunkPos);
        if (!gop.found_existing) {
            gop.entry.value = ChunkRender.init(this.allocator);
        }
        try gop.entry.value.update(chunk, chunkPos, &this.world);
    }

    pub fn render(this: @This(), context: *platform.Context, projection: Mat4f) void {
        gl.useProgram(this.program);
        defer gl.useProgram(0);
        const screen_size_int = context.getScreenSize();
        const screen_size = screen_size_int.intToFloat(f64);
        gl.clearColor(0.5, 0.5, 0.5, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.viewport(0, 0, screen_size_int.x, screen_size_int.y);
        gl.enable(gl.POLYGON_OFFSET_FILL);

        gl.polygonOffset(1, 0.25);

        gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.tilesetTex);
        gl.uniform1ui(this.daytimeUniform, 2);
        gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &projection.v);
        var rendered_iter = this.renderedChunks.iterator();
        while (rendered_iter.next()) |entry| {
            const mat = math.Mat4(f32).translation(entry.key.intToFloat(f32).scale(16));
            gl.uniformMatrix4fv(this.modelTransformUniform, 1, gl.FALSE, &mat.v);
            entry.value.render(this.program);
        }
    }
};
