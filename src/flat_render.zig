const std = @import("std");
const platform = @import("platform");
const gl = platform.gl;
const glUtil = platform.glUtil;
const math = @import("math");
const Vec2f = math.Vec(2, f32);
const vec2f = Vec2f.init;
const Mat4f = math.Mat4(f32);
const ArrayList = std.ArrayList;

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
};

pub const FlatRenderer = struct {
    allocator: *std.mem.Allocator,
    program: gl.GLuint,
    vertex_array_object: gl.GLuint,
    vertex_buffer_object: gl.GLuint,
    projectionMatrixUniform: gl.GLint,
    perspective: Mat4f,
    elements: gl.GLint,

    /// Font should be the name of the font texture and csv minus their extensions
    pub fn init(allocator: *std.mem.Allocator, screenSize: Vec2f) !@This() {
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

        gl.enableVertexAttribArray(0); // Position attribute
        gl.enableVertexAttribArray(1); // UV attribute

        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*const c_void, @byteOffsetOf(Vertex, "x")));
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*const c_void, @byteOffsetOf(Vertex, "u")));
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
        };
    }

    pub fn deinit(this: @This()) void {
        gl.deleteProgram(this.program);
        gl.deleteVertexArrays(1, &this.vertex_array_object);
        gl.deleteBuffers(1, &this.vertex_buffer_object);
    }

    pub fn setSize(this: *@This(), screenSize: Vec2f) !void {
        var vertices = ArrayList(Vertex).init(this.allocator);
        defer vertices.deinit();
        const width = screenSize.x;
        const height = screenSize.y;
        // for (text) |char|
        {
            try vertices.appendSlice(&[_]Vertex{
                Vertex{ // top left
                    .x = 0,
                    .y = 0,
                    .u = 0,
                    .v = 0,
                },
                Vertex{ // bot left
                    .x = 0,
                    .y = height,
                    .u = 0,
                    .v = 1,
                },
                Vertex{ // top right
                    .x = width,
                    .y = 0,
                    .u = 1,
                    .v = 0,
                },
                Vertex{ // bot left
                    .x = 0,
                    .y = height,
                    .u = 0,
                    .v = 1,
                },
                Vertex{ // top right
                    .x = width,
                    .y = 0,
                    .u = 1,
                    .v = 0,
                },
                Vertex{ // bot right
                    .x = width,
                    .y = height,
                    .u = 1,
                    .v = 1,
                },
            });
        }

        this.elements = @intCast(gl.GLint, vertices.items.len);

        gl.bindBuffer(gl.ARRAY_BUFFER, this.vertex_buffer_object);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(isize, vertices.items.len) * @sizeOf(Vertex), vertices.items.ptr, gl.STATIC_DRAW);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        this.perspective = Mat4f.orthographic(0, screenSize.x, screenSize.y, 0, -1, 1);
    }

    pub fn render(this: @This(), context: *platform.Context, fbo1: gl.GLuint, fbo2: gl.GLuint) void {
        gl.useProgram(this.program);
        defer gl.useProgram(0);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, fbo1);

        // gl.activeTexture(gl.TEXTURE1);
        // gl.bindTexture(gl.TEXTURE_2D, fbo2);

        gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &this.perspective.v);

        gl.bindVertexArray(this.vertex_array_object);
        gl.drawArrays(gl.TRIANGLES, 0, this.elements);
    }
};
