const std = @import("std");
const math = @import("math");
const Vec2i = math.Vec2i;

pub fn Board(comptime T: type, comptime side_len: comptime_int) type {
    return struct {
        tiles: [SIZE * SIZE]T,

        pub const SIDE_LEN = side_len;
        pub const SIZE = side_len * 2 - 1;
        const NUM_BLANK_TILES = (SIDE_LEN - 1) * SIDE_LEN / 2;
        pub const NUM_TILES = SIZE * SIZE - NUM_BLANK_TILES;

        const MIN_POS_SUM = side_len - 1;
        const MAX_POS_SUM = MIN_POS_SUM * 3;
        const ThisBoard = @This();

        pub fn init(filler: T) @This() {
            var this = @This(){
                .tiles = undefined,
            };
            std.mem.set(T, &this.tiles, filler);
            return this;
        }

        fn idx(this: @This(), pos: Vec2i) ?usize {
            if (pos.x < 0 or pos.x >= SIZE or pos.y < 0 or pos.y >= SIZE) {
                return null;
            }
            var q = @intCast(usize, pos.x);
            var r = @intCast(usize, pos.y);
            if (q + r < MIN_POS_SUM or q + r > MAX_POS_SUM) {
                return null;
            }
            return r * SIZE + q;
        }

        pub fn get(this: @This(), pos: Vec2i) ?T {
            const i = this.idx(pos) orelse return null;
            return this.tiles[i];
        }

        pub fn getMut(this: *@This(), pos: Vec2i) ?*T {
            const i = this.idx(pos) orelse return null;
            return &this.tiles[i];
        }

        pub fn set(this: *@This(), pos: Vec2i, value: T) void {
            const i = this.idx(pos) orelse return;
            this.tiles[i] = value;
        }

        pub fn iterator(this: *@This()) Iterator {
            return .{
                .board = this,
                .pos = Vec2i.init(0, 0),
            };
        }

        const Iterator = struct {
            board: *ThisBoard,
            pos: Vec2i,

            const Result = struct {
                pos: Vec2i,
                tile: *T,
            };

            pub fn next(this: *@This()) ?Result {
                while (true) {
                    if (this.pos.y > SIZE) return null;
                    defer {
                        this.pos.x += 1;
                        if (this.pos.x > SIZE) {
                            this.pos.x = 0;
                            this.pos.y += 1;
                        }
                    }

                    if (this.board.idx(this.pos)) |tile_idx| {
                        return Result{
                            .pos = this.pos,
                            .tile = &this.board.tiles[tile_idx],
                        };
                    }
                }
            }
        };

        pub const Serialized = [NUM_TILES]T;

        pub fn serialize(this: *@This()) Serialized {
            var res: [NUM_TILES]T = undefined;

            var i: usize = 0;
            var board_iter = this.iterator();
            while (board_iter.next()) |tile| : (i += 1) {
                res[i] = tile.tile.*;
            }

            return res;
        }

        pub fn deserialize(array: Serialized) @This() {
            var this: @This() = undefined;

            var i: usize = 0;
            var board_iter = this.iterator();
            while (board_iter.next()) |tile| : (i += 1) {
                tile.tile.* = array[i];
            }

            return this;
        }
    };
}
