const std = @import("std");
const math = @import("math");
const util = @import("util");
const Vec3i = math.Vec(3, i64);
const vec3i = Vec3i.init;
const Vec3f = math.Vec(3, f64);
const vec3f = Vec3f.init;
const Vec2f = math.Vec(2, f64);
const core = @import("./core.zig");
const BlockType = core.block.BlockType;
const Side = core.block.Side;
const Block = core.block.Block;
const Chunk = core.chunk.Chunk;
const VoxelTraversal = math.VoxelTraversal;
const ArrayDeque = util.ArrayDeque;

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
        if (chunkPos.y == 7) {
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
        } else if (chunkPos.y == 0) {
            chunk.fill(.IronOre);
        } else if (chunkPos.y < 7) {
            chunk.fill(.Stone);
            chunk.layer(3, .IronOre);
            chunk.layer(11, .CoalOre);
        }

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

    pub fn setv(this: *@This(), globalPos: Vec3i, blockType: Block) void {
        const chunkPos = globalPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            const blockPos = globalPos.subv(chunkPos.scale(16));
            entry.value.setv(blockPos, blockType);
            // TODO(louis): Make a new function to do this in, and make it less hacky
            if (blockType.blockType == .Torch) {
                var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                defer _ = gpa.deinit();
                this.fillLightv(&gpa.allocator, globalPos) catch unreachable;
            }
        }
    }

    pub fn getLightv(this: @This(), blockPos: Vec3i) u8 {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getLightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn getTorchlightv(this: @This(), blockPos: Vec3i) u4 {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getTorchlightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn getSunlightv(this: @This(), blockPos: Vec3i) u4 {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getSunlightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn setTorchlightv(this: @This(), blockPos: Vec3i, lightLevel: u4) void {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            entry.value.setTorchlightv(blockPos.subv(chunkPos.scale(16)), lightLevel);
        }
    }

    pub fn setSunlightv(this: @This(), blockPos: Vec3i, lightLevel: u4) void {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            entry.value.setSunlightv(blockPos.subv(chunkPos.scale(16)), lightLevel);
        }
    }

    pub fn isOpaquev(this: *const @This(), blockPos: Vec3i) bool {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return core.block.describe(chunk.getv(blockPos.subv(chunkPos.scale(16)))).isOpaque();
        }
        return false;
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

    pub fn fillLightv(self: *@This(), alloc: *std.mem.Allocator, placePos: Vec3i) !void {
        std.log.debug("Filling light at: {}", .{placePos});
        var lightBfsQueue = ArrayDeque(Vec3i).init(alloc);
        defer lightBfsQueue.deinit();

        self.setTorchlightv(placePos, 15);
        try lightBfsQueue.push_back(placePos);

        while (lightBfsQueue.len() != 0) {
            var pos = lightBfsQueue.pop_front() orelse break;
            var lightLevel = self.getTorchlightv(pos);
            var calculatedLevel = lightLevel;
            if (lightLevel -% 2 < lightLevel) {
                calculatedLevel -= 2;
            } else {
                continue;
            }

            const west = pos.add(-1, 0, 0);
            if (self.isOpaquev(west) == false and calculatedLevel >= self.getTorchlightv(west)) {
                self.setTorchlightv(west, lightLevel - 1);
                try lightBfsQueue.push_back(west);
            }
            const east = pos.add(1, 0, 0);
            if (self.isOpaquev(east) == false and calculatedLevel >= self.getTorchlightv(east)) {
                self.setTorchlightv(east, lightLevel - 1);
                try lightBfsQueue.push_back(east);
            }
            const bottom = pos.add(0, -1, 0);
            if (self.isOpaquev(bottom) == false and calculatedLevel >= self.getTorchlightv(bottom)) {
                self.setTorchlightv(bottom, lightLevel - 1);
                try lightBfsQueue.push_back(bottom);
            }
            const up = pos.add(0, 1, 0);
            if (self.isOpaquev(up) == false and calculatedLevel >= self.getTorchlightv(up)) {
                self.setTorchlightv(up, lightLevel - 1);
                try lightBfsQueue.push_back(up);
            }
            const south = pos.add(0, 0, -1);
            if (self.isOpaquev(south) == false and calculatedLevel >= self.getTorchlightv(south)) {
                self.setTorchlightv(south, lightLevel - 1);
                try lightBfsQueue.push_back(south);
            }
            const north = pos.add(0, 0, 1);
            if (self.isOpaquev(north) == false and calculatedLevel >= self.getTorchlightv(north)) {
                self.setTorchlightv(north, lightLevel - 1);
                try lightBfsQueue.push_back(north);
            }
        }
    }
};
