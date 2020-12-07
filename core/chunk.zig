const std = @import("std");
const math = @import("math");
const Vec2f = math.Vec(2, f64);
const Vec3f = math.Vec(3, f64);
const vec3f = Vec3f.init;
const Vec3i = math.Vec(3, i64);
const VoxelTraversal = math.VoxelTraversal;
const Block = @import("./block.zig").Block;
const BlockType = @import("./block.zig").BlockType;

pub const CX = 16;
pub const CY = 16;
pub const CZ = 16;

pub const Light = struct {
    sunlight: u8,
    torchlight: u8,
};

pub const Chunk = struct {
    blk: [CX][CY][CZ]Block,
    light: [CX][CY][CZ]Light,
    changed: bool,

    pub fn init() @This() {
        return @This(){
            .blk = std.mem.zeroes([CX][CY][CZ]Block),
            .light = std.mem.zeroes([CX][CY][CZ]Light),
            .changed = true,
        };
    }

    pub fn get(self: @This(), x: i64, y: i64, z: i64) Block {
        return self.blk[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)];
    }

    pub fn getv(self: @This(), pos: Vec3i) Block {
        return self.blk[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)];
    }

    pub fn getSunlight(self: @This(), x: i64, y: i64, z: i64) u4 {
        return self.light[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)].sunlight;
    }

    pub fn getSunlightv(self: @This(), pos: Vec3i) u4 {
        return self.light[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)].sunlight;
    }

    pub fn getTorchlight(self: @This(), x: i64, y: i64, z: i64) u4 {
        return self.light[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)].torchlight;
    }

    pub fn getTorchlightv(self: @This(), pos: Vec3i) u4 {
        return self.light[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)].torchlight;
    }

    pub fn set(self: *@This(), x: i64, y: i64, z: i64, block: Block) void {
        self.blk[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)] = block;
        self.changed = true;
    }

    pub fn setv(self: *@This(), pos: Vec3i, block: Block) void {
        self.blk[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)] = block;
        self.changed = true;
    }

    pub fn setSunlight(self: *@This(), x: i64, y: i64, z: i64, level: u4) void {
        self.light[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)].sunlight = level;
        self.changed = true;
    }

    pub fn setSunlightv(self: *@This(), pos: Vec3i, level: u4) void {
        self.light[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)].sunlight = level;
        self.changed = true;
    }

    pub fn setTorchlight(self: *@This(), x: i64, y: i64, z: i64, level: u4) void {
        return self.light[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)].torchlight = level;
        self.changed = true;
    }

    pub fn setTorchlightv(self: *@This(), pos: Vec3i, level: u4) void {
        return self.light[@intCast(u8, pos.x)][@intCast(u8, pos.y)][@intCast(u8, pos.z)].torchlight = level;
        self.changed = true;
    }

    pub fn fill(self: *@This(), blockType: BlockType) void {
        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi: u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi: u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    self.blk[xi][yi][zi] = .{ .blockType = blockType };
                }
            }
        }
    }

    pub fn layer(self: *@This(), y: u8, blockType: BlockType) void {
        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var zi: u8 = 0;
            while (zi < CZ) : (zi += 1) {
                self.blk[xi][y][zi] = .{ .blockType = blockType };
            }
        }
    }

    pub fn raycast(self: @This(), origin: Vec3f, angle: Vec2f, max_len: f64) ?math.Vec(3, u8) {
        const lookat = vec3f(
            std.math.sin(angle.x) * std.math.cos(angle.y),
            std.math.sin(angle.y),
            std.math.cos(angle.x) * std.math.cos(angle.y),
        );
        const start = origin;
        const end = origin.addv(lookat.scale(max_len));

        var iterations_left = @floatToInt(usize, max_len * 1.5);
        var voxel_iter = VoxelTraversal(f64, i64).init(start, end);
        while (voxel_iter.next()) |voxel_pos| {
            if (iterations_left == 0) break;
            iterations_left -= 1;

            if (voxel_pos.x < 0 or voxel_pos.y < 0 or voxel_pos.z < 0) continue;
            if (voxel_pos.x >= CX or voxel_pos.y >= CY or voxel_pos.z >= CZ) continue;

            const chunk_pos = voxel_pos.intCast(u8);
            const block = self.get(chunk_pos.x, chunk_pos.y, chunk_pos.z);
            if (block == .Air) continue;

            return chunk_pos;
        }
        return null;
    }

    pub fn raycastLastEmpty(self: @This(), origin: Vec3f, angle: Vec2f, max_len: f64) ?math.Vec(3, u8) {
        const lookat = vec3f(
            std.math.sin(angle.x) * std.math.cos(angle.y),
            std.math.sin(angle.y),
            std.math.cos(angle.x) * std.math.cos(angle.y),
        );
        const start = origin;
        const end = origin.addv(lookat.scale(max_len));

        var iterations_left = @floatToInt(usize, max_len * 1.5);
        var voxel_iter = VoxelTraversal(f64, i64).init(start, end);
        var previous_voxel: ?math.Vec(3, u8) = null;
        while (voxel_iter.next()) |voxel_pos| {
            if (iterations_left == 0) break;
            iterations_left -= 1;

            if (voxel_pos.x < 0 or voxel_pos.y < 0 or voxel_pos.z < 0) continue;
            if (voxel_pos.x >= CX or voxel_pos.y >= CY or voxel_pos.z >= CZ) continue;

            const chunk_pos = voxel_pos.intCast(u8);
            const block = self.get(chunk_pos.x, chunk_pos.y, chunk_pos.z);
            if (block == .Air) {
                previous_voxel = chunk_pos;
            } else {
                break;
            }
        }
        return previous_voxel;
    }

    pub const RectIterator = struct {
        chunk: *const Chunk,
        min: Vec3i,
        max: Vec3i,
        current: Vec3i,

        pub const Result = struct {
            pos: Vec3i,
            block: BlockType,
        };

        pub fn next(this: *@This()) ?Result {
            if (this.current.z > this.max.z) return null;
            defer {
                this.current.x += 1;
                if (this.current.x > this.max.x) {
                    this.current.x = this.min.x;
                    this.current.y += 1;
                    if (this.current.y > this.max.y) {
                        this.current.y = this.min.y;
                        this.current.z += 1;
                    }
                }
            }
            if (this.current.x < 0 or this.current.y < 0 or this.current.z < 0 or this.current.x >= CX or this.current.y >= CY or this.current.z >= CZ) {
                return Result{
                    .pos = this.current,
                    .block = .Air,
                };
            }
            return Result{
                .pos = this.current,
                .block = this.chunk.blk[@intCast(usize, this.current.x)][@intCast(usize, this.current.y)][@intCast(usize, this.current.z)],
            };
        }
    };

    pub fn iterateRect(self: *const @This(), a: Vec3i, b: Vec3i) RectIterator {
        const min = a.minComponentsv(b);
        const max = a.maxComponentsv(b);
        return RectIterator{
            .chunk = self,
            .min = min,
            .max = max,
            .current = min,
        };
    }
};
