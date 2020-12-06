const std = @import("std");
const math = @import("math");
const Vec3i = math.Vec(3, i64);
const vec3i = Vec3i.init;
const Vec3f = math.Vec(3, f64);
const vec3f = Vec3f.init;
const Vec2f = math.Vec(2, f64);
const BlockType = @import("./core.zig").chunk.BlockType;
const Side = @import("./core.zig").chunk.Side;
const Block = @import("./core.zig").chunk.Block;
const Chunk = @import("./core.zig").chunk.Chunk;
const VoxelTraversal = math.VoxelTraversal;

pub const World = struct {
    allocator: *std.mem.Allocator,
    chunks: std.AutoHashMap(Vec3i, Chunk),

    pub fn init(allocator: *std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .chunks = std.AutoHashMap(Vec3i, Chunk).init(allocator),
        };
    }

    pub fn ensureChunkLoaded(this: *@This(), chunkPos: Vec3i) !void {
        if (this.chunks.get(chunkPos)) |chunk| {
            // Chunk is loaded, ignore it
            return;
        }
        // Generate the chunk
        var chunk = Chunk.init();
        chunk.layer(0, .Stone);
        chunk.layer(1, .Stone);
        chunk.layer(2, .Stone);
        chunk.layer(3, .Dirt);
        chunk.layer(4, .Dirt);
        chunk.layer(5, .Dirt);
        chunk.layer(6, .Grass);
        chunk.blk[0][1][0] = .{ .blockType = .IronOre };
        chunk.blk[0][2][0] = .{ .blockType = .CoalOre };
        chunk.blk[0][3][0] = .{ .blockType = .Air };

        chunk.blk[7][7][7] = .{ .blockType = .Wood };
        chunk.blk[7][8][7] = .{ .blockType = .Wood };
        chunk.blk[7][9][7] = .{ .blockType = .Wood };
        chunk.blk[7][10][7] = .{ .blockType = .Wood };
        chunk.blk[7][11][7] = .{ .blockType = .Wood };
        chunk.blk[7][12][7] = .{ .blockType = .Wood };
        chunk.blk[7][13][7] = .{ .blockType = .Wood };
        chunk.blk[7][14][7] = .{ .blockType = .Leaf };

        chunk.blk[8][10][7] = .{ .blockType = .Leaf };
        chunk.blk[8][11][7] = .{ .blockType = .Leaf };
        chunk.blk[8][12][7] = .{ .blockType = .Leaf };
        chunk.blk[8][13][7] = .{ .blockType = .Leaf };

        chunk.blk[6][10][7] = .{ .blockType = .Leaf };
        chunk.blk[6][11][7] = .{ .blockType = .Leaf };
        chunk.blk[6][12][7] = .{ .blockType = .Leaf };
        chunk.blk[6][13][7] = .{ .blockType = .Leaf };

        chunk.blk[7][10][8] = .{ .blockType = .Leaf };
        chunk.blk[7][11][8] = .{ .blockType = .Leaf };
        chunk.blk[7][12][8] = .{ .blockType = .Leaf };
        chunk.blk[7][13][8] = .{ .blockType = .Leaf };

        chunk.blk[7][10][6] = .{ .blockType = .Leaf };
        chunk.blk[7][11][6] = .{ .blockType = .Leaf };
        chunk.blk[7][12][6] = .{ .blockType = .Leaf };
        chunk.blk[7][13][6] = .{ .blockType = .Leaf };

        try this.chunks.put(chunkPos, chunk);
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.chunks.put(chunkPos, chunk);
    }

    pub fn getv(this: @This(), blockPos: Vec3i) Block {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return .{ .blockType = .Air };
        }
    }

    pub fn setv(this: *@This(), blockPos: Vec3i, blockType: Block) void {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            return entry.value.setv(blockPos.subv(chunkPos.scale(16)), blockType);
        }
    }

    const RaycastResult = struct {
        pos: Vec3i,
        side: ?Side,
        prev: ?Vec3i,
    };

    pub fn raycast(self: @This(), origin: Vec3f, angle: Vec2f, max_len: f64) ?RaycastResult {
        const lookat = vec3f(
            std.math.sin(angle.x) * std.math.cos(angle.y),
            std.math.sin(angle.y),
            std.math.cos(angle.x) * std.math.cos(angle.y),
        );
        const start = origin;
        const end = origin.addv(lookat.scale(max_len));

        var prev_voxel: ?Vec3i = null;

        var iterations_left = @floatToInt(usize, max_len * 1.5);
        var voxel_iter = VoxelTraversal(f64, i64).init(start, end);
        while (voxel_iter.next()) |voxel_pos| {
            if (iterations_left == 0) break;
            iterations_left -= 1;

            const block = self.getv(voxel_pos);
            if (block.blockType == .Air) {
                prev_voxel = voxel_pos;
                continue;
            }

            return RaycastResult{
                .pos = voxel_pos,
                .side = if (prev_voxel) |pvoxel| bv: {
                    const n = voxel_pos.subv(pvoxel);
                    break :bv Side.fromNormal(@intCast(i2, n.x), @intCast(i2, n.y), @intCast(i2, n.z));
                } else null,
                .prev = prev_voxel,
            };
        }
        return null;
    }

    pub const RectIterator = struct {
        world: *const World,
        min: Vec3i,
        max: Vec3i,
        current: Vec3i,

        pub const Result = struct {
            pos: Vec3i,
            block: Block,
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
            return Result{
                .pos = this.current,
                .block = this.world.getv(this.current),
            };
        }
    };

    pub fn iterateRect(self: *const @This(), a: Vec3i, b: Vec3i) RectIterator {
        const min = a.minComponentsv(b);
        const max = a.maxComponentsv(b);
        return RectIterator{
            .world = self,
            .min = min,
            .max = max,
            .current = min,
        };
    }
};
