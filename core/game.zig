const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Vec2i = @import("math").Vec2i;
const vec2i = @import("math").vec2i;
const core = @import("./core.zig");
const Piece = core.piece.Piece;

pub const Game = struct {
    alloc: *Allocator,
    board: core.Board,
    currentPlayer: core.piece.Piece.Color,

    pub fn init(alloc: *Allocator) @This() {
        var board = core.Board.init(null);

        board.set(vec2i(1, 4), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(2, 4), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(3, 4), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(4, 4), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(5, 4), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(6, 3), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(7, 2), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(8, 1), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(9, 0), Piece{ .kind = .Pawn, .color = .Black });
        board.set(vec2i(2, 3), Piece{ .kind = .Rook, .color = .Black });
        board.set(vec2i(3, 2), Piece{ .kind = .Knight, .color = .Black });
        board.set(vec2i(4, 1), Piece{ .kind = .Queen, .color = .Black });
        board.set(vec2i(5, 0), Piece{ .kind = .Bishop, .color = .Black });
        board.set(vec2i(5, 1), Piece{ .kind = .Bishop, .color = .Black });
        board.set(vec2i(5, 2), Piece{ .kind = .Bishop, .color = .Black });
        board.set(vec2i(6, 0), Piece{ .kind = .King, .color = .Black });
        board.set(vec2i(7, 0), Piece{ .kind = .Knight, .color = .Black });
        board.set(vec2i(8, 0), Piece{ .kind = .Rook, .color = .Black });

        board.set(vec2i(1, 10), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(2, 9), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(3, 8), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(4, 7), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(5, 6), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(6, 6), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(7, 6), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(8, 6), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(9, 6), Piece{ .kind = .Pawn, .color = .White });
        board.set(vec2i(2, 10), Piece{ .kind = .Rook, .color = .White });
        board.set(vec2i(3, 10), Piece{ .kind = .Knight, .color = .White });
        board.set(vec2i(4, 10), Piece{ .kind = .Queen, .color = .White });
        board.set(vec2i(5, 10), Piece{ .kind = .Bishop, .color = .White });
        board.set(vec2i(5, 9), Piece{ .kind = .Bishop, .color = .White });
        board.set(vec2i(5, 8), Piece{ .kind = .Bishop, .color = .White });
        board.set(vec2i(6, 9), Piece{ .kind = .King, .color = .White });
        board.set(vec2i(7, 8), Piece{ .kind = .Knight, .color = .White });
        board.set(vec2i(8, 7), Piece{ .kind = .Rook, .color = .White });

        return .{
            .alloc = alloc,
            .board = board,
            .currentPlayer = .White,
        };
    }

    pub fn move(this: *@This(), startPos: Vec2i, endPos: Vec2i) !void {
        var possible_moves = ArrayList(core.moves.Move).init(this.alloc);
        defer possible_moves.deinit();

        const startTile = this.board.get(startPos) orelse return error.IllegalMove;
        const startPiece = startTile orelse return error.IllegalMove;
        if (startPiece.color != this.currentPlayer) {
            return error.IllegalMove;
        }

        try core.moves.getMovesForPieceAtLocation(this.board, startPos, &possible_moves);

        for (possible_moves.items) |possible_move| {
            if (possible_move.end_location.eql(endPos) and possible_move.start_location.eql(startPos)) {
                possible_move.perform(&this.board);

                this.currentPlayer = switch (this.currentPlayer) {
                    .White => .Black,
                    .Black => .White,
                };

                return;
            }
        }

        return error.IllegalMove;
    }
};
