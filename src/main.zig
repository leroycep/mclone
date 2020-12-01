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
const zigimg = @import("zigimg");

const DEG_TO_RAD = std.math.pi / 180.0;

const VERT_CODE = @embedFile("glescraft.vert");
const FRAG_CODE = @embedFile("glescraft.frag");

var shaderProgram: platform.GLuint = undefined;
var projectionMatrixUniform: platform.GLint = undefined;
var cam_position = vec3f(10, -10, 10);

// var chunk: Chunk = undefined;
var chunkRender: ChunkRender = undefined;

var tilesetTex: platform.GLuint = undefined;

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
    chunk.layer(15, core.chunk.BlockType.GRASS);
    chunk.layer(0, core.chunk.BlockType.STONE);
    chunk.layer(1, core.chunk.BlockType.STONE);
    chunk.layer(2, core.chunk.BlockType.STONE);
    chunk.blk[0][3][0] = .AIR;
    chunk.blk[0][4][0] = .AIR;
    chunk.blk[0][5][0] = .AIR;

    chunkRender = ChunkRender.init(chunk);

    projectionMatrixUniform = platform.glGetUniformLocation(shaderProgram, "mvp");

    try context.setRelativeMouseMode(true);

    tilesetTex = try loadTileset(context.alloc, &[_][]const u8{
        "assets/dirt.png",
        "assets/stone.png",
        "assets/grass.png",
        "assets/grass-side.png"
    });

    std.log.warn("end app init", .{});
}

fn loadTileset(alloc: *std.mem.Allocator, filepaths: []const []const u8) !platform.GLuint {
    var texture: platform.GLuint = undefined;
    platform.glGenTextures(1, &texture);
    platform.glBindTexture(platform.GL_TEXTURE_2D_ARRAY, texture);
    platform.glTexStorage3D(platform.GL_TEXTURE_2D_ARRAY, 2, platform.GL_RGBA8, 16, 16, 10);

    for (filepaths) |filepath, i| {
        try loadTile(alloc, @intCast(c_int, i + 1), filepath);
    }

    platform.glTexParameteri(platform.GL_TEXTURE_2D_ARRAY, platform.GL_TEXTURE_WRAP_S, platform.GL_REPEAT);
    platform.glTexParameteri(platform.GL_TEXTURE_2D_ARRAY, platform.GL_TEXTURE_WRAP_T, platform.GL_REPEAT);
    platform.glTexParameteri(platform.GL_TEXTURE_2D_ARRAY, platform.GL_TEXTURE_MIN_FILTER, platform.GL_NEAREST);
    platform.glTexParameteri(platform.GL_TEXTURE_2D_ARRAY, platform.GL_TEXTURE_MAG_FILTER, platform.GL_NEAREST);

    return texture;
}

fn loadTile(alloc: *std.mem.Allocator, layer: platform.GLint, filepath: []const u8) !void {
    const cwd = std.fs.cwd();
    const image_contents = try cwd.readFileAlloc(alloc, filepath, 50000);
    defer alloc.free(image_contents);

    const load_res = try zigimg.Image.fromMemory(alloc, image_contents);
    defer load_res.deinit();
    if (load_res.pixels == null) return error.ImageLoadFailed;

    var pixelData = try alloc.alloc(u8, load_res.width * load_res.height * 4);
    defer alloc.free(pixelData);

    // TODO: skip converting to RGBA and let OpenGL handle it by telling it what format it is in
    var pixelsIterator = zigimg.color.ColorStorageIterator.init(&load_res.pixels.?);

    var i: usize = 0;
    while (pixelsIterator.next()) |color| : (i += 1) {
        const integer_color = color.toIntegerColor8();
        pixelData[i * 4 + 0] = integer_color.R;
        pixelData[i * 4 + 1] = integer_color.G;
        pixelData[i * 4 + 2] = integer_color.B;
        pixelData[i * 4 + 3] = integer_color.A;
    }

    platform.glTexSubImage3D(platform.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer, @intCast(c_int, load_res.width), @intCast(c_int, load_res.height), 1, platform.GL_RGBA, platform.GL_UNSIGNED_BYTE, pixelData.ptr);
    //platform.glGenerateMipmap(platform.GL_TEXTURE_2D);
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

    platform.glBindTexture(platform.GL_TEXTURE_2D_ARRAY, tilesetTex);

    chunkRender.render(shaderProgram);
}
