const std = @import("std");
const platform = @import("platform");
const core = @import("core");
const gl = platform.gl;
const glUtil = platform.glUtil;
const math = @import("math");
const Mat4f = math.Mat4(f32);

pub const LineRenderer = struct {
    allocator: *std.mem.Allocator,

    program: gl.GLuint,
    projectionMatrixUniform: gl.GLint = undefined,
    modelTransformUniform: gl.GLint = undefined,
    tilesetTex: gl.GLuint = undefined,
    cursor_vbo: gl.GLuint = undefined,

    pub fn init(allocator: *std.mem.Allocator, tilesetTex: gl.GLuint) !@This() {
        var this = @This(){
            .allocator = allocator,
            .program = try glUtil.compileShader(
                allocator,
                @embedFile("line.vert"),
                @embedFile("line.frag"),
            ),
        };

        this.projectionMatrixUniform = gl.getUniformLocation(this.program, "mvp");
        this.modelTransformUniform = gl.getUniformLocation(this.program, "modelTransform");
        this.tilesetTex = tilesetTex;
        gl.genBuffers(1, &this.cursor_vbo);

        return this;
    }

    pub fn deinit(this: @This()) void {
        gl.deleteProgram(this.program);
    }

    pub fn render(this: *@This(), context: *platform.Context, projection: Mat4f, other_player_states: *std.AutoHashMap(u64, core.player.State), selected_block: ?core.World.RaycastResult) void {
        // Line Drawing Code
        gl.useProgram(this.program);
        defer gl.useProgram(0);
        gl.enable(gl.POLYGON_OFFSET_FILL);
        gl.polygonOffset(1, 0);
        gl.lineWidth(1);
        // Draw box around selected box
        gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &projection.v);
        gl.uniformMatrix4fv(this.modelTransformUniform, 1, gl.FALSE, &math.Mat4(f32).ident().v);
        gl.bindBuffer(gl.ARRAY_BUFFER, this.cursor_vbo);
        var attribute_coord = @intCast(gl.GLuint, gl.getAttribLocation(this.program, "coord"));
        gl.vertexAttribPointer(attribute_coord, 4, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(attribute_coord);

        var other_player_states_iter = other_player_states.iterator();
        while (other_player_states_iter.next()) |entry| {
            const pos = entry.value.position.floatCast(f32);
            const box = [24][4]f32{
                .{ pos.x + 0, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 1, 10 },
                .{ pos.x + 0, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 1, 10 },
                .{ pos.x + 0, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 0, pos.z + 1, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 0, pos.y + 1, pos.z + 1, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 0, 10 },
                .{ pos.x + 1, pos.y + 1, pos.z + 1, 10 },
            };

            gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(box)), &box, gl.DYNAMIC_DRAW);

            gl.drawArrays(gl.LINES, 0, 24);
        }

        gl.disable(gl.POLYGON_OFFSET_FILL);
        gl.disable(gl.CULL_FACE);

        if (selected_block) |raycast| {
            const selected = raycast.pos.intToFloat(f32);
            const box = [24][4]f32{
                .{ selected.x + 0, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 1, 11 },
                .{ selected.x + 0, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 1, 11 },
                .{ selected.x + 0, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 0, selected.z + 1, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 0, selected.y + 1, selected.z + 1, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 0, 11 },
                .{ selected.x + 1, selected.y + 1, selected.z + 1, 11 },
            };

            gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(box)), &box, gl.DYNAMIC_DRAW);

            gl.drawArrays(gl.LINES, 0, 24);
        }

        // const cross = [4][4]f32{
        //     .{ -0.05, 0, -2, 10 },
        //     .{ 0.05, 0, -2, 10 },
        //     .{ 0, -0.05, -2, 10 },
        //     .{ 0, 0.05, -2, 10 },
        // };

        // gl.disable(gl.DEPTH_TEST);
        // gl.uniformMatrix4fv(this.projectionMatrixUniform, 1, gl.FALSE, &perspective.floatCast(f32).v);
        // gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(cross)), &cross, gl.DYNAMIC_DRAW);

        // gl.drawArrays(gl.LINES, 0, cross.len);
    }
};
