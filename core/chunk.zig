const std = @import("std");
const math = @import("math");
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;
const vec3f = math.vec3f;
const Vec3i = math.Vec(3, i32);
const VoxelTraversal = math.VoxelTraversal;

pub const CX = 16;
pub const CY = 16;
pub const CZ = 16;

pub const BlockType = enum(u8) {
    Air,
    Stone,
    Dirt,
    Grass,
    Wood,
    Leaf,
    CoalOre,
    IronOre,
};

pub const Chunk = struct {
    blk: [CX][CY][CZ]BlockType,
    changed: bool,

    pub fn init() @This() {
        return @This(){
            .blk = std.mem.zeroes([CX][CY][CZ]BlockType),
            .changed = true,
        };
    }

    pub fn get(self: @This(), x: i32, y: i32, z: i32) BlockType {
        return self.blk[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)];
    }

    pub fn set(self: *@This(), x: i32, y: i32, z: i32, blockType: BlockType) void {
        self.blk[@intCast(u8, x)][@intCast(u8, y)][@intCast(u8, z)] = blockType;
        self.changed = true;
    }

    pub fn fill(self: *@This(), blockType: BlockType) void {
        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi: u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi: u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    self.blk[xi][yi][zi] = blockType;
                }
            }
        }
    }

    pub fn layer(self: *@This(), y: u8, blockType: BlockType) void {
        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var zi: u8 = 0;
            while (zi < CZ) : (zi += 1) {
                self.blk[xi][y][zi] = blockType;
            }
        }
    }

    pub fn raycast(self: @This(), origin: Vec3f, angle: Vec2f, max_len: f32) ?math.Vec(3, u8) {
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
            const block = self.get(chunk_pos.x, chunk_pos.y, chunk_pos.z);
            if (block == .Air) continue;

            return chunk_pos;
        }
        return null;
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
