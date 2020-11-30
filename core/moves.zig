const std = @import("std");
const ArrayList = std.ArrayList;
const math = @import("math");
const Vec2i = math.Vec2i;
const vec2i = math.vec2i;
const Piece = @import("./piece.zig").Piece;
const Board = @import("./board.zig").Board(?Piece, 6);

pub const Move = struct {
    // Where the piece is
    start_location: Vec2i,

    // Where the piece will end up
    end_location: Vec2i,

    // The state of the piece after moving ot end location
    piece: Piece,

    // The location of the piece that will be captured, if any
    captured_piece: ?Vec2i,

    // Pawns that would be passed and then have an opportunity to perform an en passant
    passed_pawns: [2]?Vec2i = [_]?Vec2i{null} ** 2,

    pub fn perform(this: @This(), board: *Board) void {
        if (this.captured_piece) |capture| {
            board.set(capture, null);
        }
        for (this.passed_pawns) |passed_pawn_location_opt| {
            if (passed_pawn_location_opt) |passed_pawn_location| {
                const passed_piece_ptr = board.getMut(passed_pawn_location) orelse continue;
                if (passed_piece_ptr.*) |*passed_piece| {
                    passed_piece.enPassant = this.end_location;
                }
            }
        }
        board.set(this.end_location, this.piece.withOneMoreMove());
        board.set(this.start_location, null);

        // update each piece (mostly to remove en passant, as it can only be done as a reaction)
        var board_iter = board.iterator();
        while (board_iter.next()) |result| {
            if (result.tile.*) |*piece| {
                piece.updateEndOfTurn(this.piece.color);
            }
        }
    }
};

pub fn getMovesForPieceAtLocation(board: Board, piece_location: Vec2i, possible_moves: *ArrayList(Move)) !void {
    const piece = board.get(piece_location) orelse return orelse return;

    switch (piece.kind) {
        .Pawn => {
            // TODO: account for promotion tiles
            const possible_attacks = switch (piece.color) {
                .White => [2]Vec2i{ vec2i(-1, 0), vec2i(1, -1) },
                .Black => [2]Vec2i{ vec2i(1, 0), vec2i(-1, 1) },
            };
            for (possible_attacks) |attack_offset| {
                const usual_attack_location = piece_location.addv(attack_offset);
                const attack_location = if (piece.enPassant != null and piece.enPassant.?.x == usual_attack_location.x) piece.enPassant.? else usual_attack_location;
                const tile = board.get(attack_location);
                if (tile == null) continue; // tile does not exist
                if (tile.? == null) continue; // there is no piece on the tile
                if (tile.?.?.color == piece.color) continue;
                try possible_moves.append(.{
                    .start_location = piece_location,
                    .end_location = usual_attack_location,
                    .piece = piece,
                    .captured_piece = attack_location,
                });
            }

            const direction = switch (piece.color) {
                .Black => vec2i(0, 1),
                .White => vec2i(0, -1),
            };
            const one_forward = piece_location.addv(direction);
            const tile_one_forward = board.get(one_forward);

            // Pawn can move forward if there is no one in front of them
            if (tile_one_forward == null or tile_one_forward.? != null) return;
            try possible_moves.append(.{
                .start_location = piece_location,
                .end_location = one_forward,
                .piece = piece,
                .captured_piece = null,
            });

            // Pawn can move two forward if it is their first move (and if they could move
            // forward one)
            if (piece.numMoves > 0) return;
            const two_forward = piece_location.addv(direction.scale(2));
            const tile_two_forward = board.get(two_forward);
            if (tile_one_forward == null or tile_two_forward.? != null) return;

            var move = Move{
                .start_location = piece_location,
                .end_location = two_forward,
                .piece = piece,
                .captured_piece = null,
            };

            // The locations that would be passed
            const en_passant_locations = switch (piece.color) {
                .White => [2]Vec2i{ vec2i(-1, -1), vec2i(1, -2) },
                .Black => [2]Vec2i{ vec2i(1, 1), vec2i(-1, 2) },
            };
            for (en_passant_locations) |offset, idx| {
                const pos = piece_location.addv(offset);
                if (board.get(pos)) |en_passant_tile| {
                    if (en_passant_tile) |en_passant_piece| {
                        if (en_passant_piece.color != piece.color and en_passant_piece.kind == .Pawn) {
                            move.passed_pawns[idx] = pos;
                        }
                    }
                }
            }

            try possible_moves.append(move);
        },
        .Rook => {
            try straightLineMoves(board, piece_location, &[6]Vec2i{
                vec2i(0, -1),
                vec2i(1, -1),
                vec2i(1, 0),
                vec2i(0, 1),
                vec2i(-1, 1),
                vec2i(-1, 0),
            }, 100, possible_moves);
        },
        .Bishop => {
            try straightLineMoves(board, piece_location, &[6]Vec2i{
                vec2i(1, -2),
                vec2i(2, -1),
                vec2i(1, 1),
                vec2i(-1, 2),
                vec2i(-2, 1),
                vec2i(-1, -1),
            }, 100, possible_moves);
        },
        .Queen => {
            try straightLineMoves(board, piece_location, &[12]Vec2i{
                // Rook moves
                vec2i(0, -1),
                vec2i(1, -1),
                vec2i(1, 0),
                vec2i(0, 1),
                vec2i(-1, 1),
                vec2i(-1, 0),
                // Bishop moves
                vec2i(1, -2),
                vec2i(2, -1),
                vec2i(1, 1),
                vec2i(-1, 2),
                vec2i(-2, 1),
                vec2i(-1, -1),
            }, 100, possible_moves);
        },
        .King => {
            try straightLineMoves(board, piece_location, &[12]Vec2i{
                // Rook moves
                vec2i(0, -1),
                vec2i(1, -1),
                vec2i(1, 0),
                vec2i(0, 1),
                vec2i(-1, 1),
                vec2i(-1, 0),
                // Bishop moves
                vec2i(1, -2),
                vec2i(2, -1),
                vec2i(1, 1),
                vec2i(-1, 2),
                vec2i(-2, 1),
                vec2i(-1, -1),
            }, 1, possible_moves);
        },
        .Knight => {
            const knight_possible_moves = [_]Vec2i{
                vec2i(1, -3),
                vec2i(2, -3),
                vec2i(3, -2),
                vec2i(3, -1),
                vec2i(2, 1),
                vec2i(1, 2),
                vec2i(-1, 3),
                vec2i(-2, 3),
                vec2i(-3, 1),
                vec2i(-3, 2),
                vec2i(-2, -1),
                vec2i(-1, -2),
            };

            for (knight_possible_moves) |move_offset| {
                const move_location = piece_location.addv(move_offset);
                const tile = board.get(move_location) orelse continue;
                if (tile) |other_piece| {
                    if (other_piece.color == piece.color) continue;
                    // Capture other piece
                    try possible_moves.append(.{
                        .start_location = piece_location,
                        .end_location = move_location,
                        .piece = piece,
                        .captured_piece = move_location,
                    });
                } else {
                    try possible_moves.append(.{
                        .start_location = piece_location,
                        .end_location = move_location,
                        .piece = piece,
                        .captured_piece = null,
                    });
                }
            }
        },
    }
}

fn straightLineMoves(board: Board, piece_location: Vec2i, directions: []const Vec2i, max_distance: usize, possible_moves: *ArrayList(Move)) !void {
    const piece = board.get(piece_location) orelse return orelse return;

    for (directions) |direction| {
        var current_location = piece_location.addv(direction);
        var distance: usize = 0;
        while (board.get(current_location)) |tile| : (current_location = current_location.addv(direction)) {
            defer distance += 1;
            if (distance >= max_distance) break;

            if (tile) |other_piece| {
                if (other_piece.color != piece.color) {
                    // Capture other piece
                    try possible_moves.append(.{
                        .start_location = piece_location,
                        .end_location = current_location,
                        .piece = piece,
                        .captured_piece = current_location,
                    });
                }
                break;
            } else {
                try possible_moves.append(.{
                    .start_location = piece_location,
                    .end_location = current_location,
                    .piece = piece,
                    .captured_piece = null,
                });
            }
        }
    }
}
