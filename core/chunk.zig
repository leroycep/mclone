const std = @import("std");

pub const CX = 16;
pub const CY = 16;
pub const CZ = 16;

pub const BlockType = enum(u8) {
    AIR,
    DIRT,
    STONE,
};

pub const Chunk = struct {
    blk: [CX][CY][CZ]BlockType,
    changed: bool,

    pub fn init() @This() {
        return @This() {
            .blk = std.mem.zeroes([CX][CY][CZ]BlockType),
            .changed = true,
        };
    }

    pub fn get(self: *@This(), x: i16, y: i16, z: i16) BlockType {
        return self.blk[x][y][z];
    }

    pub fn set(self: *@This(), x: i16, y: i16, z: i16, blockType: BlockType) void {
        self.blk[x][y][z] = blockType;
        self.changed = true;
    }

    pub fn fill(self: *@This(), blockType: BlockType) void {
        var xi : u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi : u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi : u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    self.blk[xi][yi][zi] = blockType;
                }
            }
        }
    }

};
