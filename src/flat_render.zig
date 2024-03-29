const std = @import("std");
const platform = @import("platform");
const gl = platform.gl;
const glUtil = platform.glUtil;
const math = @import("math");
const Vec2f = math.Vec(2, f32);
const vec2f = Vec2f.init;
const Mat4f = math.Mat4(f32);
const ArrayList = std.ArrayList;
const Texture = @import("./texture.zig").Texture;

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    opacity: f32,
};

pub const FlatRenderer = struct {
    allocator: std.mem.Allocator,
    program: gl.GLuint,
    vertex_array_object: gl.GLuint,
    vertex_buffer_object: gl.GLuint,
    projectionMatrixUniform: gl.GLint,
    perspective: Mat4f,
    elements: gl.GLint,
    draw_buffer: ArrayList(Vertex),
    texture: gl.GLuint,

    /// Font should be the name of the font texture and csv minus their extensions
    pub fn init(allocator: std.mem.Allocator, screenSize: Vec2f) !@This() {
        const program = try glUtil.compileShader(
            allocator,
            @embedFile("flat_render.vert"),
            @embedFile("flat_render.frag"),
        );

        var vbo: gl.GLuint = 0;
        gl.genBuffers(1, &vbo);
        if (vbo == 0)
            return error.OpenGlFailure;

        var vao: gl.GLuint = 0;
        gl.genVertexArrays(1, &vao);
        if (vao == 0)
            return error.OpenGlFailure;

        gl.bindVertexArray(vao);
        defer gl.bindVertexArray(0);

        gl.enableVertexAttribArray(0); // Position attribute
        gl.enableVertexAttribArray(1); // UV attribute
        gl.enableVertexAttribArray(2); // UV attribute

        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*const anyopaque, @offsetOf(Vertex, "x")));
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*const anyopaque, @offsetOf(Vertex, "u")));
        gl.vertexAttribPointer(2, 1, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*const anyopaque, @offsetOf(Vertex, "opacity")));
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        const projection = gl.getUniformLocation(program, "mvp");

        return @This(){
            .allocator = allocator,
            .program = program,
            .vertex_array_object = vao,
            .vertex_buffer_object = vbo,
            .projectionMatrixUniform = projection,
            .perspective = Mat4f.orthographic(0, screenSize.x, screenSize.y, 0, -1, 1),
            .elements = 0,
            .draw_buffer = ArrayList(Vertex).init(allocator),
            .texture = 0,
        };
    }

    pub fn deinit(this: @This()) void {
        this.draw_buffer.deinit();
        gl.deleteProgram(this.program);
        gl.deleteVertexArrays(1, &this.vertex_array_object);
        gl.deleteBuffers(1, &this.vertex_buffer_object);
    }

    pub fn setSize(this: *@This(), screenSize: Vec2f) !void {
        this.perspective = Mat4f.orthographic(0, screenSize.x, screenSize.y, 0, -1, 1);
    }

    pub fn drawTexture(this: *@This(), texture: Texture, pos: Vec2f, size: Vec2f) !void {
        try this.drawGLTexture(texture.glTexture, vec2f(0, 0), vec2f(1.0, 1.0), pos, size);
    }

    pub fn drawTextureRect(this: *@This(), texture: Texture, texPos1: Vec2f, texPos2: Vec2f, pos: Vec2f, size: Vec2f) !void {
        try this.drawGLTexture(texture.glTexture, texPos1, texPos2, pos, size);
    }

    pub fn drawGLTexture(this: *@This(), texture: gl.GLuint, texPos1: Vec2f, texPos2: Vec2f, pos: Vec2f, size: Vec2f) !void {
        if (texture != this.texture) {
            this.flush();
            this.texture = texture;
        }
        const opacity = 1.0;
        try this.draw_buffer.appendSlice(&[_]Vertex{
            Vertex{ // top left
                .x = pos.x,
                .y = pos.y,
                .u = texPos1.x,
                .v = texPos1.y,
                .opacity = opacity,
            },
            Vertex{ // bot left
                .x = pos.x,
                .y = pos.y + size.y,
                .u = texPos1.x,
                .v = texPos2.y,
                .opacity = opacity,
            },
            Vertex{ // top right
                .x = pos.x + size.x,
                .y = pos.y,
                .u = texPos2.x,
                .v = texPos1.y,
                .opacity = opacity,
            },
            Vertex{ // bot left
                .x = pos.x,
                .y = pos.y + size.y,
                .u = texPos1.x,
                .v = texPos2.y,
                .opacity = opacity,
            },
            Vertex{ // top right
                .x = pos.x + size.x,
                .y = pos.y,
                .u = texPos2.x,
                .v = texPos1.y,
                .opacity = opacity,
            },
            Vertex{ // bot right
                .x = pos.x + size.x,
                .y = pos.y + size.y,
                .u = texPos2.x,
                .v = texPos2.y,
                .opacity = opacity,
            },
        });
    }

    pub fn flush(this: *@This()) void {
        gl.bindVertexArray(this.vertex_array_object);
        gl.bindBuffer(gl.ARRAY_BUFFER, this.vertex_buffer_object);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(isize, this.draw_buffer.items.len) * @sizeOf(Vertex), this.draw_buffer.items.ptr, gl.STATIC_DRAW);
        defer this.draw_buffer.shrinkRetainingCapacity(0);
        gl.bindVertexArray(0);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        gl.useProgram(this.program);
        defer gl.useProgram(0);

        gl.disable(gl.DEPTH_TEST);
        defer gl.enable(gl.DEPTH_TEST);
        gl.disable(gl.CULL_FACE);
        defer gl.enable(gl.CULL_FACE);
        gl.enable(gl.BLEND);
        defer gl.disable(gl.BLEND);
        gl.depthFunc(gl.ALWAYS);
        defer gl.depthFunc(gl.LESS);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this.texture);

        gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &this.perspective.v);

        gl.bindVertexArray(this.vertex_array_object);
        defer gl.bindVertexArray(0);
        gl.drawArrays(gl.TRIANGLES, 0, @intCast(c_int, this.draw_buffer.items.len));
    }
};
