pub const protocol = @import("./protocol.zig");
pub const board = @import("./board.zig");
pub const piece = @import("./piece.zig");
pub const moves = @import("./moves.zig");
pub const game = @import("./game.zig");

pub const Board = board.Board(?piece.Piece, 6);

test "" {
    _ = @import("./protocol.zig");
}
