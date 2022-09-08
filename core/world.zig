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

const ADJACENT_OFFSETS = [_]Vec3i{
    vec3i(-1, 0, 0),
    vec3i(1, 0, 0),
    vec3i(0, -1, 0),
    vec3i(0, 1, 0),
    vec3i(0, 0, -1),
    vec3i(0, 0, 1),
};

pub const World = struct {
    allocator: std.mem.Allocator,
    chunks: std.AutoHashMap(Vec3i, Chunk),
    blocks_to_update: ArrayDeque(Vec3i),
    blocks_that_were_updated: std.AutoArrayHashMap(Vec3i, void),
    blocks_to_tick: ArrayDeque(Vec3i),
    chunks_where_light_was_updated: std.AutoArrayHashMap(Vec3i, void),

    const BlockUpdate = struct {
        // The block that was updated
        pos: Vec3i,
        // The side it was updated from
        side: ?Side,
    };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .chunks = std.AutoHashMap(Vec3i, Chunk).init(allocator),
            .blocks_that_were_updated = std.AutoArrayHashMap(Vec3i, void).init(allocator),
            .blocks_to_update = ArrayDeque(Vec3i).init(allocator),
            .blocks_to_tick = ArrayDeque(Vec3i).init(allocator),
            .chunks_where_light_was_updated = std.AutoArrayHashMap(Vec3i, void).init(allocator),
        };
    }

    pub fn deinit(this: *@This()) void {
        this.chunks.deinit();
        this.blocks_that_were_updated.deinit();
        this.blocks_to_update.deinit();
        this.blocks_to_tick.deinit();
        this.chunks_where_light_was_updated.deinit();
    }

    pub fn ensureChunkLoaded(this: *@This(), chunkPos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

        if (this.chunks.get(chunkPos)) |chunk| {
            _ = chunk;
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
        try this.fillSunlight(chunkPos);
    }

    pub fn loadChunkFromMemory(this: *@This(), chunkPos: Vec3i, chunk: Chunk) !void {
        try this.chunks.put(chunkPos, chunk);
    }

    pub fn tick(this: *@This(), time: f64, delta: f64) !void {
        _ = time;
        _ = delta;
        var lightRemovalBfsQueue = ArrayDeque(RemoveLightNode).init(this.allocator);
        defer lightRemovalBfsQueue.deinit();
        var lightBfsQueue = ArrayDeque(Vec3i).init(this.allocator);
        defer lightBfsQueue.deinit();

        while (this.blocks_to_tick.pop_front()) |updated_pos| {
            const updated_block = this.getv(updated_pos);
            const updated_desc = core.block.describe(updated_block);

            //std.log.debug("{} {} {}", .{@src().file, @src().fn_name, @src().line});
            updated_desc.tick(this, updated_pos);

            // Update light
            if (updated_desc.isOpaque(this, updated_pos) or updated_block.blockType == .Air) {
                //try this.removeLightv(updated_pos);
                const light_level = this.getTorchlightv(updated_pos);
                this.setTorchlightv(updated_pos, 0);
                for (ADJACENT_OFFSETS) |offset| {
                    try lightRemovalBfsQueue.push_back(.{
                        .pos = updated_pos.addv(offset),
                        .expected_level = light_level,
                    });
                }
            }
            if (updated_desc.lightEmitted(this, updated_pos) > 0) {
                //try this.addLightv(updated_pos);
                const light_level = updated_desc.lightEmitted(this, updated_pos);
                this.setTorchlightv(updated_pos, light_level);
                try lightBfsQueue.push_back(updated_pos);
            }
            //try this.updated.put(updated_pos.scaleDivFloor(16), {});
        }

        while (this.blocks_to_update.pop_front()) |updated_pos| {
            const updated_block = this.getv(updated_pos);
            const updated_desc = core.block.describe(updated_block);

            updated_desc.update(this, updated_pos);

            // Update light
            if (updated_desc.isOpaque(this, updated_pos) or updated_block.blockType == .Air) {
                //try this.removeLightv(updated_pos);
                const light_level = this.getTorchlightv(updated_pos);
                this.setTorchlightv(updated_pos, 0);
                for (ADJACENT_OFFSETS) |offset| {
                    try lightRemovalBfsQueue.push_back(.{
                        .pos = updated_pos.addv(offset),
                        .expected_level = light_level,
                    });
                }
            }
            if (updated_desc.lightEmitted(this, updated_pos) > 0) {
                //try this.addLightv(updated_pos);
                const light_level = updated_desc.lightEmitted(this, updated_pos);
                this.setTorchlightv(updated_pos, light_level);
                try lightBfsQueue.push_back(updated_pos);
            }
            //try this.updated.put(updated_pos.scaleDivFloor(16), {});
        }

        // Remove lights
        try this.removeLightv(&lightRemovalBfsQueue, &lightBfsQueue);
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
            entry.value_ptr.setv(blockPos, blockType);
            this.blocks_that_were_updated.put(globalPos, {}) catch unreachable;
        } else {
            std.log.debug("Block is not in loaded chunk: {} {}", .{ globalPos, blockType });
        }
    }

    pub fn setAndUpdatev(this: *@This(), globalPos: Vec3i, block: Block) !void {
        try this.setAndQueueUpdatev(globalPos, block);

        var lightRemovalBfsQueue = ArrayDeque(RemoveLightNode).init(this.allocator);
        defer lightRemovalBfsQueue.deinit();
        var lightBfsQueue = ArrayDeque(Vec3i).init(this.allocator);
        defer lightBfsQueue.deinit();

        // Update light for blocks in updated queue
        while (this.blocks_to_update.pop_front()) |updated_pos| {
            const updated_block = this.getv(updated_pos);
            const updated_desc = core.block.describe(updated_block);

            updated_desc.update(this, updated_pos);

            // Update light
            if (updated_desc.isOpaque(this, updated_pos) or updated_block.blockType == .Air) {
                //try this.removeLightv(updated_pos);
                const light_level = this.getTorchlightv(updated_pos);
                this.setTorchlightv(updated_pos, 0);
                for (ADJACENT_OFFSETS) |offset| {
                    try lightRemovalBfsQueue.push_back(.{
                        .pos = updated_pos.addv(offset),
                        .expected_level = light_level,
                    });
                }
            }
            if (updated_desc.lightEmitted(this, updated_pos) > 0) {
                //try this.addLightv(updated_pos);
                const light_level = updated_desc.lightEmitted(this, updated_pos);
                this.setTorchlightv(updated_pos, light_level);
                try lightBfsQueue.push_back(updated_pos);
            }
            //try this.updated.put(updated_pos.scaleDivFloor(16), {});
        }

        // Remove lights
        try this.removeLightv(&lightRemovalBfsQueue, &lightBfsQueue);
    }

    pub fn setAndQueueUpdatev(this: *@This(), globalPos: Vec3i, block: Block) !void {
        const chunkPos = globalPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            const blockPos = globalPos.subv(chunkPos.scale(16));

            entry.value_ptr.setv(blockPos, block);
            try this.blocks_to_update.push_back(globalPos);
            this.blocks_that_were_updated.put(globalPos, {}) catch unreachable;

            for (ADJACENT_OFFSETS) |offset| {
                try this.blocks_to_update.push_back(globalPos.addv(offset));
            }
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

    pub fn setLightv(this: *@This(), blockPos: Vec3i, light: u8) void {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |chunk_entry| {
            chunk_entry.value_ptr.setLightv(blockPos.subv(chunkPos.scale(16)), light);
            this.chunks_where_light_was_updated.put(chunkPos, {}) catch unreachable;
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
            entry.value_ptr.setTorchlightv(blockPos.subv(chunkPos.scale(16)), lightLevel);
            this.chunks_where_light_was_updated.put(chunkPos, {}) catch unreachable;
        }
    }

    pub fn setSunlightv(this: *@This(), blockPos: Vec3i, lightLevel: u4) void {
        const tracy = trace(@src());
        defer tracy.end();

        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.getEntry(chunkPos)) |entry| {
            if (entry.value.setSunlightv(blockPos.subv(chunkPos.scale(16)), lightLevel)) {
                this.light_that_was_updated.put(blockPos, {}) catch unreachable;
            }
        } else {
            std.log.debug("Trying to set sunlight in unloaded chunk", .{});
        }
    }

    pub fn isOpaquev(this: *const @This(), blockPos: Vec3i) bool {
        const chunkPos = blockPos.scaleDivFloor(16);
        if (this.chunks.get(chunkPos)) |chunk| {
            return core.block.describe(chunk.getv(blockPos.subv(chunkPos.scale(16)))).isOpaque(this, blockPos);
        }
        return false;
    }

    pub fn isChunkSunlightCalculated(this: *const @This(), chunkPos: Vec3i) bool {
        if (this.chunks.get(chunkPos)) |chunk| {
            return chunk.isSunlightCalculated;
        }
        return false;
    }

    pub const RaycastResult = struct {
        pos: Vec3i,
        side: ?Side,
        prev: ?Vec3i,
    };

    pub fn raycast(self: @This(), origin: Vec3f, angle: Vec2f, max_len: f64) ?RaycastResult {
        const lookat = vec3f(
            @sin(angle.x) * @cos(angle.y),
            @sin(angle.y),
            @cos(angle.x) * @cos(angle.y),
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

    const RemoveLightNode = struct { pos: Vec3i, expected_level: u4 };

    pub fn removeLightv(self: *@This(), lightRemovalBfsQueue: *ArrayDeque(RemoveLightNode), lightBfsQueue: *ArrayDeque(Vec3i)) !void {
        const tracy = trace(@src());
        defer tracy.end();

        while (lightRemovalBfsQueue.pop_front()) |node| {
            const pos = node.pos;
            const light_level = self.getTorchlightv(pos);
            const expected_light_level = node.expected_level;
            if (light_level != 0 and light_level < expected_light_level) {
                const block = self.getv(pos);
                const desc = core.block.describe(block);
                const emitted_light = desc.lightEmitted(self, pos);

                self.setTorchlightv(pos, emitted_light);

                if (emitted_light > 0) {
                    try lightBfsQueue.push_back(pos);
                    continue;
                }

                for (ADJACENT_OFFSETS) |offset| {
                    try lightRemovalBfsQueue.push_back(.{
                        .pos = pos.addv(offset),
                        .expected_level = light_level,
                    });
                }
            } else if (light_level >= expected_light_level) {
                try lightBfsQueue.push_back(pos);
            }
        }

        try self.propogateLight(lightBfsQueue);
    }

    pub fn propogateLight(self: *@This(), lightBfsQueue: *ArrayDeque(Vec3i)) !void {
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

    pub fn fillSunlight(self: *@This(), chunkPos: Vec3i) !void {
        const tracy = trace(@src());
        defer tracy.end();

        const block = @import("./block.zig");
        const CX = core.chunk.CX;
        const CY = core.chunk.CY;
        const CZ = core.chunk.CZ;

        var lightBfsQueue = @import("util").ArrayDeque(Vec3i).init(self.allocator);
        try lightBfsQueue.ensureCapacity(16 * 16 * 16);
        defer lightBfsQueue.deinit();

        const chunkEntry = self.chunks.getEntry(chunkPos) orelse return error.ChunkUnloaded;
        var chunk = chunkEntry.value_ptr;
        {
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var y: u8 = 0;
                while (y < CY) : (y += 1) {
                    var z: u8 = 0;
                    while (z < CZ) : (z += 1) {
                        _ = chunk.setSunlight(x, y, z, 0);
                    }
                }
            }
        }

        const topChunkPos = chunkPos.add(0, 1, 0);
        if (self.isChunkSunlightCalculated(topChunkPos)) {
            const topChunkEntry = self.chunks.getEntry(topChunkPos) orelse return error.TopChunkUnloaded;
            var topChunk = topChunkEntry.value_ptr;
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var z: u8 = 0;
                while (z < CZ) : (z += 1) {
                    const lightLevel = topChunk.getSunlight(x, 0, z);
                    const globalPos = chunkPos.scale(16).add(x, CY - 1, z);
                    if (lightLevel > 1 and !chunk.describe(x, CY - 1, z).isOpaque(self, globalPos)) {
                        var pos = Vec3i.init(x, CY - 1, z);
                        if (lightLevel == 15) {
                            _ = chunk.setSunlightv(pos, lightLevel);
                        } else {
                            _ = chunk.setSunlightv(pos, lightLevel - 1);
                        }
                        try lightBfsQueue.push_back(pos);
                    }
                }
            }
        } else if (chunkPos.y >= 7) {
            std.log.debug("Top chunk not loaded {}", .{chunkPos});
            var x: u8 = 0;
            while (x < CX) : (x += 1) {
                var z: u8 = 0;
                while (z < CZ) : (z += 1) {
                    const pos = Vec3i.init(x, CY - 1, z);
                    const globalPos = chunkPos.scale(16).add(x, CY - 1, z);
                    if (!chunk.describev(pos).isOpaque(self, globalPos)) {
                        _ = chunk.setSunlightv(pos, 15);
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

            for (ADJACENT_OFFSETS) |offset| {
                const offset_pos = pos.addv(offset);

                if (offset_pos.x < 0 or offset_pos.x >= CX or offset_pos.y < 0 or offset_pos.y >= CY or offset_pos.z < 0 or offset_pos.z >= CZ) {
                    continue;
                }

                const globalPos = chunkPos.scale(16).addv(offset_pos);
                if (block.describe(chunk.getv(offset_pos)).isOpaque(self, globalPos) == false and
                    calculatedLevel >= chunk.getSunlightv(offset_pos))
                {
                    if (offset.y < 0) {
                        _ = chunk.setSunlightv(offset_pos, lightLevel);
                    } else {
                        _ = chunk.setSunlightv(offset_pos, lightLevel - 1);
                    }
                    try lightBfsQueue.push_back(offset_pos);
                }
            }
        }

        chunk.isSunlightCalculated = true;
        self.chunks_where_light_was_updated.put(chunkPos, {}) catch unreachable;
    }
};
