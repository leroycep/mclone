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
const trace = @import("util").tracy.trace;

pub const World = struct {
    allocator: *std.mem.Allocator,
    chunks: std.AutoHashMap(Vec3i, Chunk),
    updated: std.AutoArrayHashMap(Vec3i, void),

    pub fn init(allocator: *std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .chunks = std.AutoHashMap(Vec3i, Chunk).init(allocator),
            .updated = std.AutoArrayHashMap(Vec3i, void).init(allocator),
        };
    }

    pub fn ensureChunkLoaded(this: *@This(), chunkPos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

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
        try this.updated.put(chunkPos, {});
        try this.fillSunlight(this.allocator, chunkPos);
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.chunks.put(chunkPos, chunk);
    }

    pub fn getv(this: @This(), blockPos: Vec3i) Block {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return .{ .blockType = .Air };
        }
    }

    pub fn setv(this: *@This(), globalPos: Vec3i, blockType: Block) void {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = globalPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            const blockPos = globalPos.subv(chunkPos.scale(16));
            const removedBlock = entry.value.getv(blockPos);
            entry.value.setv(blockPos, blockType);
        }
    }

    pub fn setAndUpdatev(this: *@This(), globalPos: Vec3i, blockType: Block) void {
        const chunkPos = globalPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            const blockPos = globalPos.subv(chunkPos.scale(16));
            const removedBlock = entry.value.getv(blockPos);
            entry.value.setv(blockPos, blockType);
            // TODO(louis): Make a new function to do this in, and make it less hacky
            if (blockType.blockType == .Torch) {
                this.addLightv(this.allocator, globalPos) catch unreachable;
            } else if (blockType.blockType == .Air and removedBlock.blockType == .Torch) {
                this.removeLightv(this.allocator, globalPos) catch unreachable;
            }
            this.fillSunlight(this.allocator, chunkPos) catch unreachable;

            this.updated.put(chunkPos, {}) catch unreachable;
        }
    }

    pub fn getLightv(this: @This(), blockPos: Vec3i) u8 {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getLightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn getTorchlightv(this: @This(), blockPos: Vec3i) u4 {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getTorchlightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn getSunlightv(this: @This(), blockPos: Vec3i) u4 {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.getSunlightv(blockPos.subv(chunkPos.scale(16)));
        } else {
            return 0;
        }
    }

    pub fn setTorchlightv(this: *@This(), blockPos: Vec3i, lightLevel: u4) void {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            entry.value.setTorchlightv(blockPos.subv(chunkPos.scale(16)), lightLevel);
            this.updated.put(chunkPos, {}) catch unreachable;
        }
    }

    pub fn setSunlightv(this: *@This(), blockPos: Vec3i, lightLevel: u4) void {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            entry.value.setSunlightv(blockPos.subv(chunkPos.scale(16)), lightLevel);
            this.updated.put(chunkPos, {}) catch unreachable;
        } else {
            std.log.debug("Trying to set sunlight in unloaded chunk", .{});
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

    pub fn addLightv(self: *@This(), alloc: *std.mem.Allocator, placePos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

        var lightBfsQueue = ArrayDeque(Vec3i).init(alloc);
        defer lightBfsQueue.deinit();

        self.setTorchlightv(placePos, 15);
        try lightBfsQueue.push_back(placePos);

        while (lightBfsQueue.pop_front()) |pos| {
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

    pub fn removeLightv(self: *@This(), alloc: *std.mem.Allocator, placePos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

        const RemoveNode = struct { pos: Vec3i, level: u4 };
        var lightRemovalBfsQueue = ArrayDeque(RemoveNode).init(alloc);
        defer lightRemovalBfsQueue.deinit();
        var lightBfsQueue = ArrayDeque(Vec3i).init(alloc);
        defer lightBfsQueue.deinit();

        try lightRemovalBfsQueue.push_back(.{ .pos = placePos, .level = self.getTorchlightv(placePos) });
        self.setTorchlightv(placePos, 0);

        while (lightRemovalBfsQueue.len() != 0) {
            var node = lightRemovalBfsQueue.pop_front() orelse break;
            var pos = node.pos;
            var lightLevel = node.level;

            const west = pos.add(-1, 0, 0);
            const westLevel = self.getTorchlightv(west);
            if (westLevel != 0 and westLevel < lightLevel) {
                self.setTorchlightv(west, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = west, .level = westLevel });
            } else if (westLevel >= lightLevel) {
                try lightBfsQueue.push_back(west);
            }
            const east = pos.add(1, 0, 0);
            const eastLevel = self.getTorchlightv(east);
            if (eastLevel != 0 and eastLevel < lightLevel) {
                self.setTorchlightv(east, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = east, .level = eastLevel });
            } else if (eastLevel >= lightLevel) {
                try lightBfsQueue.push_back(east);
            }
            const bottom = pos.add(0, -1, 0);
            const bottomLevel = self.getTorchlightv(bottom);
            if (bottomLevel != 0 and bottomLevel < lightLevel) {
                self.setTorchlightv(bottom, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = bottom, .level = bottomLevel });
            } else if (bottomLevel >= lightLevel) {
                try lightBfsQueue.push_back(bottom);
            }
            const up = pos.add(0, 1, 0);
            const upLevel = self.getTorchlightv(up);
            if (upLevel != 0 and upLevel < lightLevel) {
                self.setTorchlightv(up, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = up, .level = upLevel });
            } else if (upLevel >= lightLevel) {
                try lightBfsQueue.push_back(up);
            }
            const south = pos.add(0, 0, -1);
            const southLevel = self.getTorchlightv(south);
            if (southLevel != 0 and southLevel < lightLevel) {
                self.setTorchlightv(south, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = south, .level = southLevel });
            } else if (southLevel >= lightLevel) {
                try lightBfsQueue.push_back(south);
            }
            const north = pos.add(0, 0, 1);
            const northLevel = self.getTorchlightv(north);
            if (northLevel != 0 and northLevel < lightLevel) {
                self.setTorchlightv(north, 0);
                try lightRemovalBfsQueue.push_back(.{ .pos = north, .level = northLevel });
            } else if (northLevel >= lightLevel) {
                try lightBfsQueue.push_back(north);
            }
        }

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

    pub fn fillSunlight(self: *@This(), alloc: *std.mem.Allocator, chunkPos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

        std.log.debug("Filling sunlight at {}", .{chunkPos});
        const block = @import("./block.zig");
        const CX = core.chunk.CX;
        const CY = core.chunk.CY;
        const CZ = core.chunk.CZ;

        var lightBfsQueue = @import("util").ArrayDeque(Vec3i).init(alloc);
        try lightBfsQueue.ensureCapacity(16 * 16 * 16);
        defer lightBfsQueue.deinit();

        const chunkEntry = self.chunks.getEntry(chunkPos) orelse return error.ChunkUnloaded;
        var chunk = &chunkEntry.value;
        {
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var y: u8 = 0;
                while (y < CY) : (y += 1) {
                    var z: u8 = 0;
                    while (z < CZ) : (z += 1) {
                        chunk.setSunlight(x, y, z, 0);
                    }
                }
            }
        }

        if (chunkPos.y >= 7) {
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var z: u8 = 0;
                while (z < CZ) : (z += 1) {
                    const pos = Vec3i.init(x, CY - 1, z);
                    if (block.describe(chunk.getv(pos)).isOpaque() == false) {
                        chunk.setSunlightv(pos, 15);
                        try lightBfsQueue.push_back(pos);
                    }
                }
            }
        }

        const topChunkPos = chunkPos.add(0, -1, 0);
        if (self.chunks.get(chunkPos.add(0, -1, 0))) |topChunk| {
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var z: u8 = 0;
                while (z < CZ) : (z += 1) {
                    var pos = Vec3i.init(x, 0, z);
                    if (topChunk.getSunlight(x, 0, z) > 0) {
                        try lightBfsQueue.push_back(pos);
                    }
                }
            }
        }

        while (lightBfsQueue.pop_front()) |pos| {
            var lightLevel: u4 = undefined;
            if (pos.x >= 0 and pos.y >= 0 and pos.z >= 0 and pos.x < CX and pos.y < CY and pos.z < CZ) {
                lightLevel = chunk.getSunlightv(pos);
            } else {
                // TODO: inform other chunk it needs light update
                continue;
                //lightLevel = self.getSunlightv(chunkPos.scale(16).addv(pos));
            }

            var calculatedLevel = lightLevel;
            if (lightLevel -% 2 < lightLevel) {
                calculatedLevel -= 2;
            } else {
                continue;
            }

            // const west = pos.add(-1, 0, 0);
            // if (block.describe(self.getv(west)).isOpaque() == false and
            //     calculatedLevel >= self.getSunlightv(west))
            // {
            //     self.setSunlightv(west, lightLevel - 1);
            //     try lightBfsQueue.push_back(west);
            // }
            // const east = pos.add(1, 0, 0);
            // if (block.describe(self.getv(east)).isOpaque() == false and
            //     calculatedLevel >= self.getSunlightv(east))
            // {
            //     self.setSunlightv(east, lightLevel - 1);
            //     try lightBfsQueue.push_back(east);
            // }
            // Special logic for sunlight!
            const bottom = pos.add(0, -1, 0);

            if (bottom.y < 0) {
                continue;
            }

            if (block.describe(chunk.getv(bottom)).isOpaque() == false and
                calculatedLevel >= chunk.getSunlightv(bottom))
            {
                if (lightLevel == 15) {
                    chunk.setSunlightv(bottom, lightLevel);
                } else {
                    chunk.setSunlightv(bottom, lightLevel - 1);
                }
                try lightBfsQueue.push_back(bottom);
            }
            // const up = pos.add(0, 1, 0);
            // if (block.describe(self.getv(up)).isOpaque() == false and
            //     calculatedLevel >= self.getSunlightv(up))
            // {
            //     self.setSunlightv(up, lightLevel - 1);
            //     try lightBfsQueue.push_back(up);
            // }
            // const south = pos.add(0, 0, -1);
            // if (block.describe(self.getv(south)).isOpaque() == false and
            //     calculatedLevel >= self.getSunlightv(south))
            // {
            //     self.setSunlightv(south, lightLevel - 1);
            //     try lightBfsQueue.push_back(south);
            // }
            // const north = pos.add(0, 0, 1);
            // if (block.describe(self.getv(north)).isOpaque() == false and
            //     calculatedLevel >= self.getSunlightv(north))
            // {
            //     self.setSunlightv(north, lightLevel - 1);
            //     try lightBfsQueue.push_back(north);
            // }
        }
    }
};
