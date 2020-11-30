const std = @import("std");
const math = @import("math");
const Vec2i = math.Vec2i;

pub const Piece = struct {
    kind: Kind,
    color: Color,

    numMoves: u32 = 0,
    enPassant: ?Vec2i = null,

    pub const Kind = enum(u8) {
        Pawn,
        Rook,
        Knight,
        Bishop,
        Queen,
        King,

        pub fn jsonStringify(this: @This(), options: std.json.StringifyOptions, writer: anytype) !void {
            const text = switch (this) {
                .Pawn => "Pawn",
                .Rook => "Rook",
                .Knight => "Knight",
                .Bishop => "Bishop",
                .Queen => "Queen",
                .King => "King",
            };
            try std.json.stringify(text, options, writer);
        }
    };

    pub const Color = enum(u1) {
        Black,
        White,

        pub fn jsonStringify(this: @This(), options: std.json.StringifyOptions, writer: anytype) !void {
            const text = switch (this) {
                .Black => "Black",
                .White => "White",
            };
            try std.json.stringify(text, options, writer);
        }
    };

    pub fn withOneMoreMove(this: @This()) @This() {
        return .{
            .kind = this.kind,
            .color = this.color,
            .numMoves = this.numMoves + 1,
        };
    }

    pub fn updateEndOfTurn(this: *@This(), player: Color) void {
        if (player == this.color) {
            this.enPassant = null;
        }
    }
};
