const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const util = @import("util");
const math = @import("math");
const Vec3f = math.Vec3f;
const vec3f = math.vec3f;
const Vec2f = math.Vec2f;
const vec2f = math.vec2f;
const Vec2i = math.Vec2i;
const vec2i = math.vec2i;
const pi = std.math.pi;
const OBB = collision.OBB;
const core = @import("core");
const Chunk = core.chunk.Chunk;
const ChunkRender = @import("./chunk.zig").ChunkRender;
const ArrayList = std.ArrayList;
const RGB = util.color.RGB;
const RGBA = util.color.RGBA;
const renderkit = @import("renderkit");

const DEG_TO_RAD = std.math.pi / 180.0;

const VERT_CODE = @embedFile("glescraft.vert");
const FRAG_CODE = @embedFile("glescraft.frag");


var shaderProgram: platform.GLuint = undefined;
var projectionMatrixUniform: platform.GLint = undefined;
var translation = vec2f(150, -30);

// var chunk: Chunk = undefined;
var chunkRender: ChunkRender = undefined;

pub fn main() !void {
    try platform.run(.{
        .init = onInit,
        .event = onEvent,
        .update = update,
        .render = render,
        .window = .{ .title = "mclone" },
    });
}

pub fn onInit(context: *platform.Context) !void {
    var vertShader = platform.glCreateShader(platform.GL_VERTEX_SHADER);
    platform.glShaderSource(vertShader, VERT_CODE);
    platform.glCompileShader(vertShader);

    var fragShader = platform.glCreateShader(platform.GL_FRAGMENT_SHADER);
    platform.glShaderSource(fragShader, FRAG_CODE);
    platform.glCompileShader(fragShader);

    shaderProgram = platform.glCreateProgram();
    platform.glAttachShader(shaderProgram, vertShader);
    platform.glAttachShader(shaderProgram, fragShader);
    platform.glLinkProgram(shaderProgram);
    platform.glUseProgram(shaderProgram);

    // Set up VAO
    var chunk = Chunk.init();
    chunk.fill(core.chunk.BlockType.DIRT);
    chunkRender = ChunkRender.init(chunk);

    projectionMatrixUniform = platform.glGetUniformLocation(shaderProgram, "projectionMatrix");

    std.log.warn("end app init", .{});
}

pub fn onEvent(context: *platform.Context, event: platform.event.Event) !void {
    switch (event) {
        .Quit => context.running = false,
        else => {},
    }
}

pub fn update(context: *platform.Context, current_time: f64, delta: f64) !void {
}

pub fn render(context: *platform.Context, alpha: f64) !void {
    platform.glUseProgram(shaderProgram);

    // Set the scaling matrix so that 1 unit = 1 pixel
    const screen_size = context.getScreenSize();
    const translationMatrix = [_]f32{
        1, 0, 0, translation.x,
        0, 1, 0, translation.y,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
    const scalingMatrix = [_]f32{
        2 / @intToFloat(f32, screen_size.x), 0,                                    0, -1,
        0,                                   -2 / @intToFloat(f32, screen_size.y), 0, 1,
        0,                                   0,                                    1, 0,
        0,                                   0,                                    0, 1,
    };
    const projectionMatrix = util.mat.mulMat4(scalingMatrix, translationMatrix);

    platform.glUniformMatrix4fv(projectionMatrixUniform, 1, platform.GL_FALSE, &projectionMatrix);

    // Clear the screen
    platform.glClearColor(0.5, 0.5, 0.5, 0.9);
    platform.glClear(platform.GL_COLOR_BUFFER_BIT);
    platform.glViewport(0, 0, 640, 480);

    chunkRender.render(shaderProgram);
}

