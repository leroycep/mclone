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
const Piece = core.piece.Piece;
const Board = core.Board;
const moves = core.moves;
const ArrayList = std.ArrayList;
const RGB = util.color.RGB;
const RGBA = util.color.RGBA;
const Renderer = @import("./renderer.zig").Renderer;
const renderkit = @import("renderkit");

const DEG_TO_RAD = std.math.pi / 180.0;

const VERT_CODE =
    \\ #version 300 es
    \\
    \\ in highp vec2 coordinates;
    \\ in lowp vec3 color;
    \\
    \\ out vec3 vertexColor;
    \\
    \\ uniform mat4 projectionMatrix;
    \\
    \\ void main(void) {
    \\   gl_Position = vec4(coordinates, 0.0, 1.0);
    \\   gl_Position *= projectionMatrix;
    \\   vertexColor = color;
    \\ }
;

const FRAG_CODE =
    \\ #version 300 es
    \\
    \\ in lowp vec3 vertexColor;
    \\
    \\ out lowp vec4 FragColor;
    \\
    \\ void main(void) {
    \\   FragColor = vec4(vertexColor, 1.0);
    \\ }
;

//const COLOR_HOVER = RGB.from_hsluv(213.4, 92.2, 77.4).withAlpha(0x99);
const COLOR_SELECTED = RGB.from_hsluv(213.4, 92.2, 77.4).withAlpha(0x99);
const COLOR_MOVE = RGB.from_hsluv(131.4, 55.0, 54.2).withAlpha(0x99);
const COLOR_CAPTURE = RGB.from_hsluv(12.9, 55.0, 54.2).withAlpha(0x99);
const COLOR_MOVE_OTHER = COLOR_MOVE.withAlpha(0x44); //RGB.from_hsluv(148.4, 80, 70).withAlpha(0x44);
const COLOR_CAPTURE_OTHER = COLOR_CAPTURE.withAlpha(0x77); //RGB.from_hsluv(30, 80, 70).withAlpha(0x44);

var socket: *platform.net.FramesSocket = undefined;

var shaderProgram: platform.GLuint = undefined;
var boardBackgroundMesh: Mesh = undefined;
var projectionMatrixUniform: platform.GLint = undefined;
var renderer: Renderer = undefined;
var mouse_pos = vec2f(100, 100);
var game_board = Board.init(null);
var translation = vec2f(150, -30);
var clients_player = Piece.Color.White;
var current_player = Piece.Color.White;

var selected_piece: ?Vec2i = null;
var moves_for_selected_piece: ArrayList(moves.Move) = undefined;

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
    socket = try platform.net.FramesSocket.init(context.alloc, "127.0.0.1:48836", 0);
    socket.setOnMessage(onSocketMessage);

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
    boardBackgroundMesh = genBoardTileBackgroundVAO(context.alloc, shaderProgram) catch unreachable;

    projectionMatrixUniform = platform.glGetUniformLocation(shaderProgram, "projectionMatrix");

    renderer = Renderer.init();

    moves_for_selected_piece = ArrayList(moves.Move).init(context.alloc);
    std.log.warn("end app init", .{});
}

pub fn onEvent(context: *platform.Context, event: platform.event.Event) !void {
    switch (event) {
        .Quit => context.running = false,
        .MouseMotion => |move_ev| {
            mouse_pos = move_ev.pos.intToFloat(f32);

            if (selected_piece == null) {
                moves_for_selected_piece.resize(0) catch unreachable;

                const hover_tile = pixel_to_flat_hex(20, move_ev.pos.intToFloat(f32).subv(translation));
                const tile = game_board.get(hover_tile);
                if (tile != null and tile.? != null) {
                    moves.getMovesForPieceAtLocation(game_board, hover_tile, &moves_for_selected_piece) catch unreachable;
                }
            }
        },
        .MouseButtonDown => |click_ev| if (click_ev.button == .Left) {
            const clicked_tile = pixel_to_flat_hex(20, click_ev.pos.intToFloat(f32).subv(translation));

            for (moves_for_selected_piece.items) |move_for_selected_piece| {
                if (move_for_selected_piece.piece.color != current_player) break;
                if (move_for_selected_piece.piece.color != clients_player) break;
                if (move_for_selected_piece.end_location.eql(clicked_tile)) {
                    const packet = core.protocol.ClientPacket{
                        .MovePiece = .{
                            .startPos = move_for_selected_piece.start_location,
                            .endPos = move_for_selected_piece.end_location,
                        },
                    };

                    var packet_data = ArrayList(u8).init(context.alloc);
                    defer packet_data.deinit();

                    packet.stringify(packet_data.writer()) catch unreachable;

                    socket.send(packet_data.items) catch unreachable;
                    std.log.debug("Sending packet: {}", .{packet_data.items});

                    //move_for_selected_piece.perform(&game_board);

                    //current_player = switch (current_player) {
                    //    .White => .Black,
                    //    .Black => .White,
                    //};

                    moves_for_selected_piece.resize(0) catch unreachable;
                    selected_piece = null;

                    return;
                }
            }

            moves_for_selected_piece.resize(0) catch unreachable;

            if (!std.meta.eql(selected_piece, clicked_tile)) {
                const tile = game_board.get(clicked_tile);
                if (tile != null and tile.? != null) {
                    moves.getMovesForPieceAtLocation(game_board, clicked_tile, &moves_for_selected_piece) catch unreachable;
                    selected_piece = clicked_tile;
                } else {
                    selected_piece = null;
                }
            } else {
                selected_piece = null;
            }
        },
        else => {},
    }
}

pub fn onSocketMessage(_socket: *platform.net.FramesSocket, user_data: usize, message: []const u8) void {
    std.log.info("Received message {}", .{message});
    const packet = core.protocol.ServerPacket.parse(message) catch |e| {
        std.log.err("Could not read packet: {}", .{e});
        return;
    };
    switch (packet) {
        .Init => |init_data| clients_player = init_data.color,
        .BoardUpdate => |board_update| game_board = Board.deserialize(board_update),
        .TurnChange => |turn_change| current_player = turn_change,
        else => {},
    }
}

pub fn update(context: *platform.Context, current_time: f64, delta: f64) !void {
    platform.net.update_sockets();
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

    // Draw the vertices
    platform.glBindVertexArray(boardBackgroundMesh.vao);
    platform.glDrawElements(platform.GL_TRIANGLES, boardBackgroundMesh.count, platform.GL_UNSIGNED_SHORT, null);

    const selection_pos = flat_hex_to_pixel(20, pixel_to_flat_hex(20, mouse_pos.subv(translation)));

    renderer.projectionMatrix = projectionMatrix;
    renderer.begin();

    if (selected_piece) |pos| {
        const selected_piece_pixel_pos = flat_hex_to_pixel(20, pos);
        renderer.pushFlatHexagon(selected_piece_pixel_pos, 20, COLOR_SELECTED, 0);
    }

    for (moves_for_selected_piece.items) |move| {
        const move_pos = flat_hex_to_pixel(20, move.end_location);

        const move_color = if (move.piece.color == current_player) COLOR_MOVE else COLOR_MOVE_OTHER;
        const capture_color = if (move.piece.color == current_player) COLOR_CAPTURE else COLOR_CAPTURE_OTHER;

        if (std.meta.eql(move.captured_piece, move.end_location)) {
            renderer.pushFlatHexagon(move_pos, 20, capture_color, 0);
        } else if (move.captured_piece) |captured_piece_location| {
            renderer.pushFlatHexagon(move_pos, 20, move_color, 0);
            renderer.pushFlatHexagon(flat_hex_to_pixel(20, captured_piece_location), 20, capture_color, 0);
        } else {
            renderer.pushFlatHexagon(move_pos, 20, move_color, 0);
        }
    }

    var board_iter = game_board.iterator();
    while (board_iter.next()) |res| {
        if (res.tile.* == null) continue;
        const tile = res.tile.*.?;

        const piece_pos = flat_hex_to_pixel(20, res.pos);
        const color = switch (tile.color) {
            .Black => RGBA.from_u32(0x000000FF),
            .White => RGBA.from_u32(0xFFFFFFFF),
        };
        switch (tile.kind) {
            .Rook => {
                renderer.pushRect(piece_pos, vec2f(10, 15), color, 0);
                renderer.pushRect(piece_pos.add(6, -8), vec2f(4, 7), color, 0);
                renderer.pushRect(piece_pos.add(0, -8), vec2f(4, 7), color, 0);
                renderer.pushRect(piece_pos.add(-6, -8), vec2f(4, 7), color, 0);
            },
            .Pawn => {
                renderer.pushFlatHexagon(piece_pos.add(0, 3), 7, color, 0);
                renderer.pushFlatHexagon(piece_pos.add(0, -5), 5, color, 0);
            },
            .Bishop => {
                renderer.pushRect(piece_pos.add(0, 5), vec2f(15, 4), color, 0);
                renderer.pushRect(piece_pos.add(0, -2), vec2f(6, 15), color, 0);
            },
            .Knight => {
                renderer.pushRect(piece_pos.add(0, 0), vec2f(6, 15), color, 0);
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(-10, -2),
                    piece_pos.add(3, -2),
                    piece_pos.add(3, -11),
                }, color);
            },
            .Queen, .King => {
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(5, 5),
                    piece_pos.add(10, 5),
                    piece_pos.add(10, -5),
                }, color);
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(2, 5),
                    piece_pos.add(6, 5),
                    piece_pos.add(6, -5),
                }, color);
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(-4, 5),
                    piece_pos.add(0, -9),
                    piece_pos.add(4, 5),
                }, color);
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(-2, 5),
                    piece_pos.add(-6, 5),
                    piece_pos.add(-6, -5),
                }, color);
                renderer.pushTriangle([3]Vec2f{
                    piece_pos.add(-5, 5),
                    piece_pos.add(-10, 5),
                    piece_pos.add(-10, -5),
                }, color);
                if (tile.kind == .King) {
                    renderer.pushRect(piece_pos.add(0, -9), vec2f(2, 10), color, 0);
                    renderer.pushRect(piece_pos.add(0, -9), vec2f(10, 2), color, 0);
                }
            },
        }
    }

    renderer.pushFlatHexagon(selection_pos, 20, RGBA.from_u32(0xFFFFFF33), 0);

    renderer.flush();

    // Set projection matrix
    renderer.projectionMatrix = scalingMatrix;
    renderer.pushRect(vec2f(8, 8), vec2f(16, 16), switch (clients_player) {
        .White => RGBA.from_u32(0xFFFFFFFF),
        .Black => RGBA.from_u32(0x000000FF),
    }, 0);
    renderer.pushRect(vec2f(screen_size.intToFloat(f32).x - 8, 8), vec2f(16, 16), switch (current_player) {
        .White => RGBA.from_u32(0xFFFFFFFF),
        .Black => RGBA.from_u32(0x000000FF),
    }, 0);

    renderer.flush();
}

const Mesh = struct {
    vao: platform.GLuint,
    count: platform.GLsizei,
};

fn genBoardTileBackgroundVAO(allocator: *std.mem.Allocator, shader: platform.GLuint) !Mesh {
    const UNIT = 20;
    const HEXAGON_X = UNIT * std.math.cos(@as(f32, 60.0 * DEG_TO_RAD));
    const HEXAGON_Y = UNIT * std.math.sin(@as(f32, 60.0 * DEG_TO_RAD));

    var vertices = ArrayList(f32).init(allocator);
    defer vertices.deinit();
    var colors = ArrayList(u8).init(allocator);
    defer colors.deinit();
    var indices = ArrayList(u16).init(allocator);
    defer indices.deinit();

    var board_iter = game_board.iterator();
    while (board_iter.next()) |res| {
        const baseIdx = @intCast(u16, @divExact(vertices.items.len, 2));
        const pcoords = flat_hex_to_pixel(UNIT, res.pos);

        try vertices.appendSlice(&[_]f32{
            pcoords.x - UNIT,      pcoords.y + 0.0,
            pcoords.x - HEXAGON_X, pcoords.y + HEXAGON_Y,
            pcoords.x + HEXAGON_X, pcoords.y + HEXAGON_Y,
            pcoords.x + UNIT,      pcoords.y + 0.0,
            pcoords.x + HEXAGON_X, pcoords.y - HEXAGON_Y,
            pcoords.x - HEXAGON_X, pcoords.y - HEXAGON_Y,
        });

        // Add to color data
        {
            const color = switch (@mod(res.pos.x + res.pos.y * Board.SIZE, 3)) {
                0 => RGB.from_hsluv(47.8, 45.4, 24.3),
                1 => RGB.from_hsluv(47.8, 45.4, 31.2),
                2 => RGB.from_hsluv(47.8, 45.4, 39.0),
                else => unreachable,
            };

            var i: usize = 0;
            while (i < 6) : (i += 1) {
                try colors.appendSlice(&[_]u8{ color.r, color.g, color.b });
            }
        }

        try indices.appendSlice(&[_]u16{
            baseIdx + 0, baseIdx + 1, baseIdx + 2,
            baseIdx + 0, baseIdx + 2, baseIdx + 3,
            baseIdx + 0, baseIdx + 3, baseIdx + 4,
            baseIdx + 0, baseIdx + 4, baseIdx + 5,
        });
    }

    // Set up VAO
    const vao = platform.glCreateVertexArray();
    platform.glBindVertexArray(vao);

    // Create buffers and load data into them
    const vertexBuffer = platform.glCreateBuffer();
    platform.glBindBuffer(platform.GL_ARRAY_BUFFER, vertexBuffer);
    platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, vertices.items.len) * @sizeOf(f32), vertices.items.ptr, platform.GL_STATIC_DRAW);

    const coordinates = @intCast(c_uint, platform.glGetAttribLocation(shader, "coordinates"));
    platform.glVertexAttribPointer(coordinates, 2, platform.GL_FLOAT, platform.GL_FALSE, 0, null);
    platform.glEnableVertexAttribArray(coordinates);

    const colorBuffer = platform.glCreateBuffer();
    platform.glBindBuffer(platform.GL_ARRAY_BUFFER, colorBuffer);
    platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, colors.items.len) * @sizeOf(u8), colors.items.ptr, platform.GL_STATIC_DRAW);

    const color_loc = @intCast(c_uint, platform.glGetAttribLocation(shader, "color"));
    platform.glVertexAttribPointer(color_loc, 3, platform.GL_UNSIGNED_BYTE, platform.GL_TRUE, 0, null);
    platform.glEnableVertexAttribArray(color_loc);

    const indexBuffer = platform.glCreateBuffer();
    platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
    platform.glBufferData(platform.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, indices.items.len) * @sizeOf(u16), indices.items.ptr, platform.GL_STATIC_DRAW);

    return Mesh{
        .vao = vao,
        .count = @intCast(platform.GLsizei, indices.items.len),
    };
}

fn flat_hex_to_pixel(size: f32, hex: Vec2i) Vec2f {
    var x = size * (3.0 / 2.0 * @intToFloat(f32, hex.x));
    var y = size * (std.math.sqrt(@as(f32, 3.0)) / 2.0 * @intToFloat(f32, hex.x) + std.math.sqrt(@as(f32, 3.0)) * @intToFloat(f32, hex.y));
    return Vec2f.init(x, y);
}

fn pixel_to_flat_hex(size: f32, pixel: Vec2f) Vec2i {
    var q = (2.0 / 3.0 * pixel.x) / size;
    var r = (-1.0 / 3.0 * pixel.x + std.math.sqrt(@as(f32, 3)) / 3 * pixel.y) / size;
    return hex_round(Vec2f.init(q, r)).floatToInt(i32);
}

fn hex_round(hex: Vec2f) Vec2f {
    return cube_to_axial(cube_round(axial_to_cube(hex)));
}

fn cube_round(cube: Vec3f) Vec3f {
    var rx = std.math.round(cube.x);
    var ry = std.math.round(cube.y);
    var rz = std.math.round(cube.z);

    var x_diff = std.math.absFloat(rx - cube.x);
    var y_diff = std.math.absFloat(ry - cube.y);
    var z_diff = std.math.absFloat(rz - cube.z);

    if (x_diff > y_diff and x_diff > z_diff) {
        rx = -ry - rz;
    } else if (y_diff > z_diff) {
        ry = -rx - rz;
    } else {
        rz = -rx - ry;
    }

    return Vec3f.init(rx, ry, rz);
}

fn axial_to_cube(axial: Vec2f) Vec3f {
    return vec3f(
        axial.x,
        -axial.x - axial.y,
        axial.y,
    );
}

fn cube_to_axial(cube: Vec3f) Vec2f {
    return vec2f(cube.x, cube.z);
}
