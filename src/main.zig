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
var cursor_vbo: platform.GLuint = undefined;

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
    // chunk.fill(.DIRT);
    chunk.layer(0, .Stone);
    chunk.layer(1, .Stone);
    chunk.layer(2, .Stone);
    chunk.layer(3, .Dirt);
    chunk.layer(4, .Dirt);
    chunk.layer(5, .Dirt);
    chunk.layer(6, .Grass);
    chunk.blk[0][1][0] = .IronOre;
    chunk.blk[0][2][0] = .CoalOre;
    chunk.blk[0][3][0] = .Air;

    chunk.blk[7][7][7] = .Wood;
    chunk.blk[7][8][7] = .Wood;
    chunk.blk[7][9][7] = .Wood;
    chunk.blk[7][10][7] = .Wood;
    chunk.blk[7][11][7] = .Wood;
    chunk.blk[7][12][7] = .Wood;
    chunk.blk[7][13][7] = .Wood;
    chunk.blk[7][14][7] = .Leaf;

    chunk.blk[8][10][7] = .Leaf;
    chunk.blk[8][11][7] = .Leaf;
    chunk.blk[8][12][7] = .Leaf;
    chunk.blk[8][13][7] = .Leaf;

    chunk.blk[6][10][7] = .Leaf;
    chunk.blk[6][11][7] = .Leaf;
    chunk.blk[6][12][7] = .Leaf;
    chunk.blk[6][13][7] = .Leaf;

    chunk.blk[7][10][8] = .Leaf;
    chunk.blk[7][11][8] = .Leaf;
    chunk.blk[7][12][8] = .Leaf;
    chunk.blk[7][13][8] = .Leaf;

    chunk.blk[7][10][6] = .Leaf;
    chunk.blk[7][11][6] = .Leaf;
    chunk.blk[7][12][6] = .Leaf;
    chunk.blk[7][13][6] = .Leaf;

    chunkRender = ChunkRender.init(chunk);
    platform.glGenBuffers(1, &cursor_vbo);

    projectionMatrixUniform = platform.glGetUniformLocation(shaderProgram, "mvp");

    try context.setRelativeMouseMode(true);

    tilesetTex = try loadTileset(context.alloc, &[_][]const u8{
        "assets/dirt.png",
        "assets/stone.png",
        "assets/grass-top.png",
        "assets/grass-side.png",
        "assets/wood-top.png",
        "assets/wood-side.png",
        "assets/leaf.png",
        "assets/coal-ore.png",
        "assets/iron-ore.png",
        "assets/white.png",
        "assets/black.png",
    });

    std.log.warn("end app init", .{});
}

fn loadTileset(alloc: *std.mem.Allocator, filepaths: []const []const u8) !platform.GLuint {
    var texture: platform.GLuint = undefined;
    platform.glGenTextures(1, &texture);
    platform.glBindTexture(platform.GL_TEXTURE_2D_ARRAY, texture);
    platform.glTexStorage3D(platform.GL_TEXTURE_2D_ARRAY, 2, platform.GL_RGBA8, 16, 16, @intCast(c_int, filepaths.len + 1));

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
        .MouseButtonDown => |click| switch (click.button) {
            .Left => {
                if (raycast(cam_position, camera_angle, 5)) |block| {
                    chunkRender.chunk.blk[block.x][block.y][block.z] = .Air;
                    chunkRender.update();
                }
            },
            else => {},
        },
        else => {},
    }
}

fn raycast(origin: Vec3f, angle: Vec2f, max_len: f32) ?math.Vec(3, u8) {
    const CX = core.chunk.CX;
    const CY = core.chunk.CY;
    const CZ = core.chunk.CZ;

    const lookat = vec3f(
        std.math.sin(angle.x) * std.math.cos(angle.y),
        std.math.sin(angle.y),
        std.math.cos(angle.x) * std.math.cos(angle.y),
    );
    const start = origin;
    const end = origin.addv(lookat.scale(max_len));

    var iterations_left = @floatToInt(usize, max_len * 1.5);
    var voxel_iter = VoxelTraversal.init(start, end);
    while (voxel_iter.next()) |voxel_pos| {
        if (iterations_left == 0) break;
        iterations_left -= 1;

        if (voxel_pos.x < 0 or voxel_pos.y < 0 or voxel_pos.z < 0) continue;
        if (voxel_pos.x >= CX or voxel_pos.y >= CY or voxel_pos.z >= CZ) continue;

        const chunk_pos = voxel_pos.intCast(u8);
        const block = chunkRender.chunk.blk[chunk_pos.x][chunk_pos.y][chunk_pos.z];
        if (block == .Air) continue;

        // Break block
        return chunk_pos;
    }
    return null;
}

const VoxelTraversal = struct {
    current_voxel: math.Vec(3, i32),
    last_voxel: math.Vec(3, i32),
    step: math.Vec(3, i32),
    tMax: Vec3f,
    tDelta: Vec3f,
    returned_last_voxel: bool = false,

    pub fn init(start: Vec3f, end: Vec3f) @This() {
        var current_voxel = start.floor().floatToInt(i32);
        const last_voxel = end.floor().floatToInt(i32);
        const direction = end.subv(start);
        const step = math.Vec(3, i32){
            .x = if (direction.x >= 0) 1 else -1,
            .y = if (direction.y >= 0) 1 else -1,
            .z = if (direction.z >= 0) 1 else -1,
        };
        const next_voxel_boundary = math.Vec3f{
            .x = @intToFloat(f32, current_voxel.x + step.x),
            .y = @intToFloat(f32, current_voxel.y + step.y),
            .z = @intToFloat(f32, current_voxel.z + step.z),
        };

        var diff = math.Vec(3, i32).init(0, 0, 0);
        var neg_ray = false;
        if (current_voxel.x != last_voxel.x and direction.x < 0) {
            diff.x -= 1;
            neg_ray = true;
        }
        if (current_voxel.y != last_voxel.y and direction.y < 0) {
            diff.y -= 1;
            neg_ray = true;
        }
        if (current_voxel.z != last_voxel.z and direction.z < 0) {
            diff.z -= 1;
            neg_ray = true;
        }
        if (neg_ray) {
            current_voxel = current_voxel.addv(diff);
        }

        return @This(){
            .current_voxel = current_voxel,
            .last_voxel = last_voxel,
            .step = step,
            .tMax = math.Vec3f{
                .x = if (direction.x != 0) (next_voxel_boundary.x - start.x) / direction.x else std.math.f32_max,
                .y = if (direction.y != 0) (next_voxel_boundary.y - start.y) / direction.y else std.math.f32_max,
                .z = if (direction.z != 0) (next_voxel_boundary.z - start.z) / direction.z else std.math.f32_max,
            },
            .tDelta = math.Vec3f{
                .x = if (direction.x != 0) 1.0 / direction.x * @intToFloat(f32, step.x) else std.math.f32_max,
                .y = if (direction.y != 0) 1.0 / direction.y * @intToFloat(f32, step.y) else std.math.f32_max,
                .z = if (direction.z != 0) 1.0 / direction.z * @intToFloat(f32, step.z) else std.math.f32_max,
            },
        };
    }

    pub fn next(this: *@This()) ?math.Vec(3, i32) {
        if (this.last_voxel.eql(this.current_voxel)) {
            if (this.returned_last_voxel) {
                return null;
            } else {
                this.returned_last_voxel = true;
                return this.last_voxel;
            }
        }
        if (this.tMax.x < this.tMax.y) {
            if (this.tMax.x < this.tMax.z) {
                this.current_voxel.x += this.step.x;
                this.tMax.x += this.tDelta.x;
            } else {
                this.current_voxel.z += this.step.z;
                this.tMax.z += this.tDelta.z;
            }
        } else {
            if (this.tMax.y < this.tMax.z) {
                this.current_voxel.y += this.step.y;
                this.tMax.y += this.tDelta.y;
            } else {
                this.current_voxel.z += this.step.z;
                this.tMax.z += this.tDelta.z;
            }
        }
        return this.current_voxel;
    }
};

pub fn update(context: *platform.Context, current_time: f64, delta: f64) !void {
    const move_speed = 10;
    const right_move = (input.right - input.left) * move_speed * @floatCast(f32, delta);
    const forward_move = (input.forward - input.backward) * move_speed * @floatCast(f32, delta);
    const up_move = (input.up - input.down) * move_speed * @floatCast(f32, delta);

    // TODO: centralize forward/right vector calculations
    const forward = vec3f(std.math.sin(camera_angle.x), 0, std.math.cos(camera_angle.x));
    const right = vec3f(-std.math.cos(camera_angle.x), 0, std.math.sin(camera_angle.x));
    const lookat = vec3f(std.math.sin(camera_angle.x) * std.math.cos(camera_angle.y), std.math.sin(camera_angle.y), std.math.cos(camera_angle.x) * std.math.cos(camera_angle.y));
    const up = vec3f(0, 1, 0);

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

    const screen_size_int = context.getScreenSize();
    const screen_size = screen_size_int.intToFloat(f32);

    const aspect = screen_size.x / screen_size.y;
    const zNear = 0.01;
    const zFar = 2000;
    const perspective = Mat4f.perspective(std.math.tau / 6.0, aspect, zNear, zFar);

    const projection = perspective.mul(Mat4f.lookAt(cam_position, cam_position.addv(lookat), up));

    platform.glUniformMatrix4fv(projectionMatrixUniform, 1, platform.GL_FALSE, &projection.v);

    // Clear the screen
    platform.glClearColor(0.5, 0.5, 0.5, 1.0);
    platform.glClear(platform.GL_COLOR_BUFFER_BIT | platform.GL_DEPTH_BUFFER_BIT);
    platform.glViewport(0, 0, screen_size_int.x, screen_size_int.y);
    platform.glEnable(platform.GL_POLYGON_OFFSET_FILL);

    platform.glPolygonOffset(1, 1);

    platform.glBindTexture(platform.GL_TEXTURE_2D_ARRAY, tilesetTex);
    chunkRender.render(shaderProgram);

    // Draw box around selected box
    platform.glBindBuffer(platform.GL_ARRAY_BUFFER, cursor_vbo);
    var attribute_coord = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "coord"));
    platform.glVertexAttribPointer(attribute_coord, 4, platform.GL_FLOAT, platform.GL_FALSE, 0, null);
    platform.glEnableVertexAttribArray(attribute_coord);

    platform.glDisable(platform.GL_POLYGON_OFFSET_FILL);
    platform.glDisable(platform.GL_CULL_FACE);

    if (raycast(cam_position, camera_angle, 5)) |selected_int| {
        const selected = selected_int.intToFloat(f32);
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

        platform.glBufferData(platform.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(box)), &box, platform.GL_DYNAMIC_DRAW);

        platform.glDrawArrays(platform.GL_LINES, 0, 24);
    }

    const cross = [4][4]f32{
        .{ -0.05, 0, -2, 10 },
        .{ 0.05, 0, -2, 10 },
        .{ 0, -0.05, -2, 10 },
        .{ 0, 0.05, -2, 10 },
    };

    platform.glDisable(platform.GL_DEPTH_TEST);
    platform.glUniformMatrix4fv(projectionMatrixUniform, 1, platform.GL_FALSE, &perspective.v);
    platform.glBufferData(platform.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(cross)), &cross, platform.GL_DYNAMIC_DRAW);

    platform.glDrawArrays(platform.GL_LINES, 0, cross.len);
}
