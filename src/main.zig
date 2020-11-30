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
const Mat4f = math.Mat4f;
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
var cam_position = vec3f(10, -10, 10);

// var chunk: Chunk = undefined;
var chunkRender: ChunkRender = undefined;

const Input = struct {
    left: f32 = 0,
    right: f32 = 0,
    forward: f32 = 0,
    backward: f32 = 0,
    up: f32 = 0,
    down: f32 = 0,
};
var input = Input{};
var camera_angle = vec2f(0, 0);

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

    projectionMatrixUniform = platform.glGetUniformLocation(shaderProgram, "mvp");

    try context.setRelativeMouseMode(true);

    std.log.warn("end app init", .{});
}

pub fn onEvent(context: *platform.Context, event: platform.event.Event) !void {
    switch (event) {
        .Quit => context.running = false,
        .KeyDown, .KeyUp => |keyevent| switch (keyevent.scancode) {
            .W => input.forward = if (event == .KeyDown) 1 else 0,
            .S => input.backward = if (event == .KeyDown) 1 else 0,
            .A => input.left = if (event == .KeyDown) 1 else 0,
            .D => input.right = if (event == .KeyDown) 1 else 0,
            .SPACE => input.up = if (event == .KeyDown) 1 else 0,
            .LSHIFT => input.down = if (event == .KeyDown) 1 else 0,
            else => {},
        },
        .MouseMotion => |mouse_move| {
            const MOUSE_SPEED = 0.005;
            camera_angle = camera_angle.subv(mouse_move.rel.intToFloat(f32).scale(MOUSE_SPEED));
            if (camera_angle.x < -std.math.pi)
                camera_angle.x += std.math.pi * 2.0;
            if (camera_angle.x > std.math.pi)
                camera_angle.x -= std.math.pi * 2.0;
            if (camera_angle.y < -std.math.pi / 2.0)
                camera_angle.y = -std.math.pi / 2.0;
            if (camera_angle.y > std.math.pi / 2.0)
                camera_angle.y = std.math.pi / 2.0;
        },
        else => {},
    }
}

pub fn update(context: *platform.Context, current_time: f64, delta: f64) !void {
    const move_speed = 10;
    const right_move = (input.right - input.left) * move_speed * @floatCast(f32, delta);
    const forward_move = (input.forward - input.backward) * move_speed * @floatCast(f32, delta);
    const up_move = (input.up - input.down) * move_speed * @floatCast(f32, delta);

    // TODO: centralize forward/right vector calculations
    const forward = vec3f(std.math.sin(camera_angle.x), 0, std.math.cos(camera_angle.x));
    const right = vec3f(-std.math.cos(camera_angle.x), 0, std.math.sin(camera_angle.x));
    const lookat = vec3f(std.math.sin(camera_angle.x) * std.math.cos(camera_angle.y), std.math.sin(camera_angle.y), std.math.cos(camera_angle.x) * std.math.cos(camera_angle.y));
    const up = right.cross(lookat);


    cam_position = cam_position.addv(forward.scale(forward_move));
    cam_position = cam_position.addv(right.scale(right_move));
    cam_position = cam_position.addv(up.scale(up_move));
}

pub fn render(context: *platform.Context, alpha: f64) !void {
    platform.glUseProgram(shaderProgram);

    const forward = vec3f(std.math.sin(camera_angle.x), 0, std.math.cos(camera_angle.x));
    const right = vec3f(-std.math.cos(camera_angle.x), 0, std.math.sin(camera_angle.x));
    const lookat = vec3f(std.math.sin(camera_angle.x) * std.math.cos(camera_angle.y), std.math.sin(camera_angle.y), std.math.cos(camera_angle.x) * std.math.cos(camera_angle.y));
    const up = right.cross(lookat);

    const screen_size = context.getScreenSize().intToFloat(f32);

    const aspect = screen_size.x / screen_size.y;
    const zNear = 1;
    const zFar = 2000;
    const perspective = Mat4f.perspective(std.math.tau / 6.0, aspect, zNear, zFar);

    const projection = perspective.mul(Mat4f.lookAt(cam_position, cam_position.addv(lookat), up));

    platform.glUniformMatrix4fv(projectionMatrixUniform, 1, platform.GL_FALSE, &projection.v);

    // Clear the screen
    platform.glClearColor(0.5, 0.5, 0.5, 1.0);
    platform.glClear(platform.GL_COLOR_BUFFER_BIT | platform.GL_DEPTH_BUFFER_BIT);
    platform.glViewport(0, 0, 640, 480);

    chunkRender.render(shaderProgram);
}
