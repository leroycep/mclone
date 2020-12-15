const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const gl = platform.gl;
const util = @import("util");
const math = @import("math");
const Vec3f = math.Vec(3, f64);
const vec3f = Vec3f.init;
const Vec2f = math.Vec(2, f64);
const vec2f = Vec2f.init;
const Vec2i = math.Vec(2, i64);
const vec2i = Vec2i.init;
const Mat4f = math.Mat4(f64);
const pi = std.math.pi;
const OBB = collision.OBB;
const core = @import("core");
const BlockType = core.block.BlockType;
const WorldRenderer = @import("./world_render.zig").WorldRenderer;
const ArrayList = std.ArrayList;
const RGB = util.color.RGB;
const RGBA = util.color.RGBA;
const zigimg = @import("zigimg");
const net = platform.net;

const DEG_TO_RAD = std.math.pi / 180.0;

const chunk_vert_code = @embedFile("chunk_render.vert");
const chunk_frag_code = @embedFile("chunk_render.frag");

const line_vert_code = @embedFile("line.vert");
const line_frag_code = @embedFile("line.frag");

var shaderProgram: gl.GLuint = undefined;
var lineShader: gl.GLuint = undefined;
var projectionMatrixUniform: gl.GLint = undefined;
var modelTransformUniform: gl.GLint = undefined;
var daytimeUniform: gl.GLint = undefined;
var daytime: u32 = 0;

var worldRenderer: WorldRenderer = undefined;
var cursor_vbo: gl.GLuint = undefined;

var tilesetTex: gl.GLuint = undefined;

var socket: *net.FramesSocket = undefined;
var client_id: u64 = undefined;

const Input = struct {
    left: f64 = 0,
    right: f64 = 0,
    forward: f64 = 0,
    backward: f64 = 0,
    up: f64 = 0,
    down: f64 = 0,
    breaking: ?math.Vec(3, i64) = null,
    placing: ?struct {
        pos: math.Vec(3, i64),
        block: BlockType,
        data: u16 = 0,
    } = null,
};
var input = Input{};
var item: BlockType = .Stone;
var mouse_captured: bool = true;
var camera_angle = vec2f(0, 0);

var previous_player_state = core.player.State{ .position = vec3f(0, 0, 0), .lookAngle = vec2f(0, 0), .velocity = vec3f(0, 0, 0) };
var player_state = core.player.State{ .position = vec3f(0, 0, 0), .lookAngle = vec2f(0, 0), .velocity = vec3f(0, 0, 0) };
var other_player_states: std.AutoHashMap(u64, core.player.State) = undefined;

var chunks_requested: std.ArrayList(math.Vec(3, i64)) = undefined;

const Move = struct {
    time: f64,
    input: core.player.Input,
    state: core.player.State,
};

// TODO: Make this a fixed size so that only so much lag will be tolerated
var moves: util.ArrayDeque(Move) = undefined;

pub fn main() !void {
    try platform.run(.{
        .init = onInit,
        .deinit = onDeinit,
        .event = onEvent,
        .update = update,
        .render = render,
        .window = .{ .title = "mclone" },
    });
}

pub fn onInit(context: *platform.Context) !void {
    var vertShader = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vertShader);
    gl.shaderSourceZ(vertShader, chunk_vert_code);
    gl.compileShader(vertShader);

    var fragShader = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(fragShader);
    gl.shaderSourceZ(fragShader, chunk_frag_code);
    gl.compileShader(fragShader);

    shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vertShader);
    gl.attachShader(shaderProgram, fragShader);
    gl.linkProgram(shaderProgram);
    gl.useProgram(shaderProgram);

    var lineVertShader = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(lineVertShader);
    gl.shaderSourceZ(lineVertShader, line_vert_code);
    gl.compileShader(lineVertShader);

    var lineFragShader = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(lineFragShader);
    gl.shaderSourceZ(lineFragShader, line_frag_code);
    gl.compileShader(lineFragShader);

    lineShader = gl.createProgram();
    gl.attachShader(lineShader, lineVertShader);
    gl.attachShader(lineShader, lineFragShader);
    gl.linkProgram(lineShader);

    // Set up VAO
    worldRenderer = try WorldRenderer.init(context.alloc);

    gl.genBuffers(1, &cursor_vbo);

    projectionMatrixUniform = gl.getUniformLocation(shaderProgram, "mvp");
    modelTransformUniform = gl.getUniformLocation(shaderProgram, "modelTransform");
    daytimeUniform = gl.getUniformLocation(shaderProgram, "daytime");

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
        "assets/wire-1.png",
        "assets/wire-2.png",
        "assets/wire-3.png",
        "assets/wire-4.png",
        "assets/wire-5.png",
        "assets/wire-6.png",
        "assets/signal-source.png",
    });

    socket = try net.FramesSocket.init(context.alloc, "127.0.0.1:5949", 0);
    socket.setOnMessage(onSocketMessage);

    moves = util.ArrayDeque(Move).init(context.alloc);
    other_player_states = std.AutoHashMap(u64, core.player.State).init(context.alloc);

    chunks_requested = std.ArrayList(math.Vec(3, i64)).init(context.alloc);

    std.log.warn("end app init", .{});
}

fn onDeinit(context: *platform.Context) void {
    worldRenderer.deinit();
    gl.deleteProgram(shaderProgram);
    gl.deleteProgram(lineShader);
    moves.deinit();
    other_player_states.deinit();
    socket.deinit();
    chunks_requested.deinit();
}

fn loadTileset(alloc: *std.mem.Allocator, filepaths: []const []const u8) !gl.GLuint {
    var texture: gl.GLuint = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, texture);
    gl.texStorage3D(gl.TEXTURE_2D_ARRAY, 2, gl.RGBA8, 16, 16, @intCast(c_int, filepaths.len + 1));

    for (filepaths) |filepath, i| {
        try loadTile(alloc, @intCast(c_int, i + 1), filepath);
    }

    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    gl.generateMipmap(gl.TEXTURE_2D);
    return texture;
}

fn loadTile(alloc: *std.mem.Allocator, layer: gl.GLint, filepath: []const u8) !void {
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

    gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, layer, @intCast(c_int, load_res.width), @intCast(c_int, load_res.height), 1, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
}

pub fn onEvent(context: *platform.Context, event: platform.event.Event) !void {
    switch (event) {
        .Quit => context.running = false,
        .KeyDown, .KeyUp => |keyevent| switch (keyevent.scancode) {
            .W => input.forward = if (event == .KeyDown) 1 else 0,
            .S => input.backward = if (event == .KeyDown) 1 else 0,
            .A => input.left = if (event == .KeyDown) 1 else 0,
            .D => input.right = if (event == .KeyDown) 1 else 0,
            .E => if (event == .KeyDown) {
                daytime += 1;
                daytime = daytime % 3;
            },
            .SPACE => input.up = if (event == .KeyDown) 1 else 0,
            .LSHIFT => input.down = if (event == .KeyDown) 1 else 0,
            .TAB => if (event == .KeyDown) {
                mouse_captured = !mouse_captured;
                try context.setRelativeMouseMode(mouse_captured);
            },
            ._0 => item = .Stone,
            ._1 => item = .Dirt,
            ._2 => item = .Grass,
            ._3 => item = .Wood,
            ._4 => item = .Leaf,
            ._5 => item = .CoalOre,
            ._6 => item = .IronOre,
            ._7 => item = .Torch,
            ._8 => item = .Wire,
            ._9 => item = .SignalSource,
            else => {},
        },
        .MouseMotion => |mouse_move| {
            if (!mouse_captured) return;
            const MOUSE_SPEED = 0.005;
            camera_angle = camera_angle.subv(mouse_move.rel.intToFloat(f64).scale(MOUSE_SPEED));
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
                if (worldRenderer.world.raycast(player_state.position, camera_angle, 5)) |raycast| {
                    input.breaking = raycast.pos;
                }
            },
            .Middle => {
                if (worldRenderer.world.raycast(player_state.position, camera_angle, 5)) |raycast| {
                    if (raycast.prev) |block_pos| {
                        var torchlight: u16 = worldRenderer.world.getTorchlightv(block_pos);
                        var sunlight: u16 = worldRenderer.world.getSunlightv(block_pos);
                        var totalLight = (@intToFloat(f32, torchlight) / 16) + (@intToFloat(f32, sunlight) / 16);

                        std.log.debug("Pos: {}, Light: {} {}, Div: {}", .{ block_pos, sunlight, torchlight, totalLight });
                    }

                    const block = worldRenderer.world.getv(raycast.pos);
                    const desc = core.block.describe(block);
                    //const signal = desc.signalLevel(block.blockData);
                    //std.log.debug("Signal: {}", .{ signal });
                }
            },
            .Right => {
                if (worldRenderer.world.raycast(player_state.position, camera_angle, 5)) |raycast| {
                    if (raycast.prev) |block_pos| {
                        if (item == .Wood) {
                            const orient = core.block.Orientation.init;
                            const orientation = switch (raycast.side.?) {
                                .Top => orient(2, 0, 0),
                                .Bottom => orient(0, 0, 0),
                                .North => orient(1, 0, 0),
                                .East => orient(1, 1, 0),
                                .South => orient(3, 0, 0),
                                .West => orient(3, 1, 0),
                            };
                            input.placing = .{
                                .pos = block_pos,
                                .block = item,
                                .data = orientation.toU6(),
                            };
                        } else {
                            input.placing = .{
                                .pos = block_pos,
                                .block = item,
                            };
                        }
                    }
                }
            },
            else => {},
        },
        else => {},
    }
}

fn onSocketMessage(_socket: *net.FramesSocket, user_data: usize, message: []const u8) void {
    var fbs = std.io.fixedBufferStream(message);

    var reader = core.protocol.Reader.init(socket.alloc);
    defer reader.deinit();

    const packet = reader.read(core.protocol.ServerDatagram, fbs.reader()) catch |err| {
        std.log.err("Could not read packet", .{});
        return;
    };

    switch (packet) {
        .Init => |init_data| client_id = init_data.id,
        .Update => |update_data| if (update_data.id == client_id) {
            while (true) {
                if (moves.len() == 0) {
                    // There is nothing in the move buffer, just set the state to what the server sent
                    player_state = update_data.state;
                    return;
                }
                const move = moves.idx(0).?;
                if (update_data.time > move.time) {
                    moves.discard_front(1);
                } else {
                    break;
                }
            }

            const move_at_time = moves.pop_front().?;
            if (move_at_time.time > update_data.time) {
                // We have a newer packet from the server, so we can ignore this one
                return;
            }
            const state_then = move_at_time.state;

            var should_rewind_and_replay = false;

            {
                const difference = update_data.state.position.subv(state_then.position);
                const distance = difference.magnitude();
                if (distance > 2.0) should_rewind_and_replay = true;
            }

            // TODO: Check for orientation changes

            if (should_rewind_and_replay) {
                var corrected_state = update_data.state;

                var prev_time = update_data.time;
                var idx: usize = 0;
                while (idx < moves.len()) : (idx += 1) {
                    const move_to_replay = moves.idxMut(idx).?;
                    const delta_time = prev_time - move_to_replay.time;

                    // TODO: store state of chunk at time
                    corrected_state.update(move_at_time.time, delta_time, move_at_time.input, &worldRenderer.world);
                    move_to_replay.state = corrected_state;

                    prev_time = move_to_replay.time;
                }

                // Apply corrected state
                const difference = corrected_state.position.subv(player_state.position);
                const distance = difference.magnitude();

                if (distance > 2.0) {
                    player_state.position = corrected_state.position;
                } else if (distance > 0.1) {
                    player_state.position = player_state.position.addv(difference.scale(0.1));
                }

                player_state.velocity = corrected_state.velocity;
            }
        } else {
            // TODO: Integrate other clients with client side state prediction
            const gop = other_player_states.getOrPut(update_data.id) catch return;
            gop.entry.value = update_data.state;
        },
        .ChunkUpdate => |chunk_update| {
            worldRenderer.loadChunkFromMemory(chunk_update.pos, chunk_update.chunk) catch unreachable;
            for (chunks_requested.items) |requested_pos, idx| {
                if (requested_pos.eql(chunk_update.pos)) {
                    _ = chunks_requested.swapRemove(idx);
                    break;
                }
            }
        },
        .EmptyChunk => |empty_chunk_pos| {
            for (chunks_requested.items) |requested_pos, idx| {
                if (requested_pos.eql(empty_chunk_pos)) {
                    _ = chunks_requested.swapRemove(idx);
                    break;
                }
            }
        },
    }
}

pub fn update(context: *platform.Context, current_time: f64, delta: f64) !void {
    const dir = vec2f(input.right - input.left, input.forward - input.backward);
    const maxVel = dir.magnitude();
    const player_input = core.player.Input{
        .accelDir = if (maxVel > 0) dir.normalize() else vec2f(0, 1),
        .maxVel = maxVel,
        .jump = input.up > 0,
        .crouch = input.down > 0,
        .lookAngle = camera_angle,
        .breaking = input.breaking,
        .placing = if (input.placing) |placing|
            .{
                .pos = placing.pos,
                .block = .{ .blockType = placing.block, .blockData = placing.data },
            }
        else
            null,
    };

    previous_player_state = player_state;
    player_state.update(current_time, delta, player_input, &worldRenderer.world);

    try moves.push_back(.{
        .time = current_time,
        .input = player_input,
        .state = player_state,
    });

    {
        const packet = core.protocol.ClientDatagram{
            .Update = .{
                .time = current_time,
                .input = player_input,
            },
        };

        var serialized = ArrayList(u8).init(context.alloc);
        defer serialized.deinit();

        try core.protocol.Writer.init().write(packet, serialized.writer());

        try socket.send(serialized.items);
    }

    // Request nearby chunks
    const player_chunk_pos = player_state.position.floatToInt(i64).scaleDivFloor(16);
    var request_pos = math.Vec(3, i64).init(-1, -1, -1);
    while (chunks_requested.items.len < 5 and request_pos.z <= 1) {
        defer {
            request_pos.x += 1;
            if (request_pos.x > 1) {
                request_pos.x = -1;
                request_pos.y += 1;
                if (request_pos.y > 1) {
                    request_pos.y = -1;
                    request_pos.z += 1;
                }
            }
        }

        const chunk_pos = player_chunk_pos.addv(request_pos);
        if (worldRenderer.world.chunks.get(chunk_pos) == null) {
            // Request chunk
            const packet = core.protocol.ClientDatagram{
                .RequestChunk = chunk_pos,
            };

            var serialized = ArrayList(u8).init(context.alloc);
            defer serialized.deinit();

            try core.protocol.Writer.init().write(packet, serialized.writer());

            try socket.send(serialized.items);

            try chunks_requested.append(chunk_pos);
        }
    }

    net.update_sockets();

    input.breaking = null;
    input.placing = null;
}

pub fn render(context: *platform.Context, alpha: f64) !void {
    gl.useProgram(shaderProgram);

    const render_pos = player_state.position.scale(alpha).addv(previous_player_state.position.scale(1 - alpha));

    const forward = vec3f(std.math.sin(camera_angle.x), 0, std.math.cos(camera_angle.x));
    const right = vec3f(-std.math.cos(camera_angle.x), 0, std.math.sin(camera_angle.x));
    const lookat = vec3f(std.math.sin(camera_angle.x) * std.math.cos(camera_angle.y), std.math.sin(camera_angle.y), std.math.cos(camera_angle.x) * std.math.cos(camera_angle.y));
    const up = right.cross(lookat);

    const screen_size_int = context.getScreenSize();
    const screen_size = screen_size_int.intToFloat(f64);

    const aspect = screen_size.x / screen_size.y;
    const zNear = 0.25;
    const zFar = 200;
    const perspective = Mat4f.perspective(std.math.tau / 6.0, aspect, zNear, zFar);

    const projection = perspective.mul(Mat4f.lookAt(render_pos, render_pos.addv(lookat), up)).floatCast(f32);

    gl.uniformMatrix4fv(projectionMatrixUniform, 1, gl.FALSE, &projection.v);

    // Clear the screen
    gl.clearColor(0.5, 0.5, 0.5, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.viewport(0, 0, screen_size_int.x, screen_size_int.y);
    gl.enable(gl.POLYGON_OFFSET_FILL);

    gl.polygonOffset(1, 0.25);

    gl.bindTexture(gl.TEXTURE_2D_ARRAY, tilesetTex);
    gl.uniform1ui(daytimeUniform, daytime);
    worldRenderer.render(shaderProgram, modelTransformUniform);

    // Line Drawing Code
    gl.useProgram(lineShader);
    gl.enable(gl.POLYGON_OFFSET_FILL);
    gl.polygonOffset(1, 0);
    gl.lineWidth(1);
    // Draw box around selected box
    gl.uniformMatrix4fv(projectionMatrixUniform, 1, gl.FALSE, &projection.v);
    gl.uniformMatrix4fv(modelTransformUniform, 1, gl.FALSE, &math.Mat4(f32).ident().v);
    gl.bindBuffer(gl.ARRAY_BUFFER, cursor_vbo);
    var attribute_coord = @intCast(gl.GLuint, gl.getAttribLocation(shaderProgram, "coord"));
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

    if (worldRenderer.world.raycast(render_pos, camera_angle, 5)) |raycast| {
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

    const cross = [4][4]f32{
        .{ -0.05, 0, -2, 10 },
        .{ 0.05, 0, -2, 10 },
        .{ 0, -0.05, -2, 10 },
        .{ 0, 0.05, -2, 10 },
    };

    gl.disable(gl.DEPTH_TEST);
    gl.uniformMatrix4fv(projectionMatrixUniform, 1, gl.FALSE, &perspective.floatCast(f32).v);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(cross)), &cross, gl.DYNAMIC_DRAW);

    gl.drawArrays(gl.LINES, 0, cross.len);
}
