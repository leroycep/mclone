const std = @import("std");
const core = @import("./core.zig");
const math = @import("math");
const World = core.World;
const Vec3i = math.Vec(3, i64);
const vec3i = Vec3i.init;

pub const BlockType = enum(u8) {
    Air,
    Stone,
    Dirt,
    Grass,
    Wood,
    Leaf,
    CoalOre,
    IronOre,
    Torch,
    Wire,
    SignalSource,
};

pub const Block = struct {
    blockType: BlockType,
    blockData: u16 = 0,
};

pub const Side = enum(u3) {
    Top = 0,
    Bottom = 1,
    North = 2,
    East = 3,
    South = 4,
    West = 5,

    pub fn fromNormal(x: i2, y: i2, z: i2) @This() {
        if (x == 0 and y == 0 and z == 1) return .North // so zig fmt doesn't eat the newlines
        else if (x == 1 and y == 0 and z == 0) return .East //
        else if (x == 0 and y == 0 and z == -1) return .South //
        else if (x == -1 and y == 0 and z == 0) return .West //
        else if (x == 0 and y == 1 and z == 0) return .Top //
        else if (x == 0 and y == -1 and z == 0) return .Bottom //
        else unreachable;
    }
};

pub const Orientation = struct {
    x: u2,
    y: u2,
    z: u2,

    pub fn init(x: u2, y: u2, z: u2) @This() {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn fromU6(b: u6) @This() {
        return .{
            .x = @intCast(u2, (b >> 0) & 0b11),
            .y = @intCast(u2, (b >> 2) & 0b11),
            .z = @intCast(u2, (b >> 4) & 0b11),
        };
    }

    pub fn toU6(this: @This()) u6 {
        return ((@intCast(u6, this.x) << 0) | (@intCast(u6, this.y) << 2) | (@intCast(u6, this.z) << 4));
    }

    pub fn fromSide(side: Side) @This() {
        return switch (side) {
            .Top => init(1, 0, 0),
            .Bottom => init(3, 0, 0),
            .North => init(0, 0, 0),
            .East => init(0, 1, 0),
            .South => init(0, 2, 0),
            .West => init(0, 3, 0),
        };
    }

    pub fn sin(v: u2) i2 {
        return switch (v) {
            0 => 0,
            1 => 1,
            2 => 0,
            3 => -1,
        };
    }

    pub fn cos(v: u2) i2 {
        return switch (v) {
            0 => 1,
            1 => 0,
            2 => -1,
            3 => 0,
        };
    }
};

pub const BlockDescription = struct {
    isUsedForAO: bool = true,
    isOpaqueFn: fn (this: *const @This(), world: *const World, pos: Vec3i) bool = returnTrueFn,
    isSolidFn: fn (this: *const @This(), world: *const World, pos: Vec3i) bool = returnTrueFn,
    isVisibleFn: fn (this: *const @This(), world: *const World, pos: Vec3i) bool = returnTrueFn,
    texForSideFn: fn (this: *const @This(), world: *const World, pos: Vec3i, side: Side) u8,
    lightEmittedFn: fn (this: *const @This(), world: *const World, pos: Vec3i) u4 = returnStaticInt(u4, 0),
    updateFn: fn (this: *const @This(), world: *World, pos: Vec3i) void = doNothing,

    pub fn isOpaque(this: *const @This(), world: *const World, pos: Vec3i) bool {
        return this.isOpaqueFn(this, world, pos);
    }

    pub fn isSolid(this: *const @This(), world: *const World, pos: Vec3i) bool {
        return this.isSolidFn(this, world, pos);
    }

    pub fn isVisible(this: *const @This(), world: *const World, pos: Vec3i) bool {
        return this.isVisibleFn(this, world, pos);
    }

    pub fn texForSide(this: *const @This(), world: *const World, pos: Vec3i, side: Side) u8 {
        return this.texForSideFn(this, world, pos, side);
    }

    pub fn lightEmitted(this: *const @This(), world: *const World, pos: Vec3i) u4 {
        return this.lightEmittedFn(this, world, pos);
    }

    pub fn update(this: *const @This(), world: *World, pos: Vec3i) void {
        return this.updateFn(this, world, pos);
    }
};

// TODO: Make this run at runtime so that texture ids can be dynamically found
const DESCRIPTIONS = comptime describe_blocks: {
    var descriptions: [256]BlockDescription = undefined;

    descriptions[@enumToInt(BlockType.Air)] = .{
        .isUsedForAO = false,
        .isOpaqueFn = returnFalseFn,
        .isSolidFn = returnFalseFn,
        .isVisibleFn = returnFalseFn,
        .texForSideFn = singleTexBlock(0),
    };
    descriptions[@enumToInt(BlockType.Stone)] = .{
        .texForSideFn = singleTexBlock(2),
    };
    descriptions[@enumToInt(BlockType.Dirt)] = .{
        .texForSideFn = singleTexBlock(1),
    };
    descriptions[@enumToInt(BlockType.Grass)] = .{
        .texForSideFn = makeOrientedBlockTex(.{ 3, 1, 4, 4, 4, 4 }),
    };
    descriptions[@enumToInt(BlockType.Wood)] = .{
        .texForSideFn = makeOrientedBlockTex(.{ 5, 5, 6, 6, 6, 6 }),
    };
    descriptions[@enumToInt(BlockType.Leaf)] = .{
        .isOpaqueFn = returnFalseFn,
        .texForSideFn = singleTexBlock(7),
    };
    descriptions[@enumToInt(BlockType.CoalOre)] = .{
        .texForSideFn = singleTexBlock(8),
    };
    descriptions[@enumToInt(BlockType.IronOre)] = .{
        .texForSideFn = singleTexBlock(9),
    };
    descriptions[@enumToInt(BlockType.Torch)] = .{
        .texForSideFn = torchGetTexForSide,
        .lightEmittedFn = torchGetLightEmitted,
        .updateFn = torchUpdate,
    };
    descriptions[@enumToInt(BlockType.Wire)] = .{
        .isUsedForAO = false,
        .isOpaqueFn = returnFalseFn,
        .isSolidFn = returnFalseFn,
        //.rendering = .{ .Wire = [6]u7{ 12, 13, 14, 15, 16, 17 } },
        .texForSideFn = singleTexBlock(17),
        .updateFn = wireUpdate,
    };
    descriptions[@enumToInt(BlockType.SignalSource)] = .{
        .texForSideFn = singleTexBlock(18),
        .lightEmittedFn = returnStaticInt(u4, 4),
        //.signal_level = .{ .Emit = 15 },
    };

    break :describe_blocks descriptions;
};

pub fn describe(block: Block) BlockDescription {
    return DESCRIPTIONS[@enumToInt(block.blockType)];
}

// Description building functions
// const BoolFn = fn (this: *const BlockDescription, world: *const World, pos: Vec3i) bool;

pub fn returnTrueFn(this: *const BlockDescription, world: *const World, pos: Vec3i) bool {
    return true;
}

pub fn returnFalseFn(this: *const BlockDescription, world: *const World, pos: Vec3i) bool {
    return false;
}

const TexForSideFn = fn (this: *const BlockDescription, world: *const World, pos: Vec3i, side: Side) u8;

fn singleTexBlock(comptime texId: u8) TexForSideFn {
    const S = struct {
        fn getTex(this: *const BlockDescription, world: *const World, pos: Vec3i, side: Side) u8 {
            return texId;
        }
    };
    return S.getTex;
}

fn makeOrientedBlockTex(comptime texIds: [6]u8) TexForSideFn {
    const S = struct {
        const sin = Orientation.sin;
        const cos = Orientation.cos;

        fn getTex(this: *const BlockDescription, world: *const World, pos: Vec3i, side: Side) u8 {
            const data = world.getv(pos).blockData;
            const o = Orientation.fromU6(@intCast(u6, data & 0b111111));
            const orientedSide = switch (side) {
                .Top => Side.fromNormal(0, cos(o.x), sin(o.x)),
                .Bottom => Side.fromNormal(0, -cos(o.x), sin(o.x)),
                .North => Side.fromNormal(-sin(o.y), cos(o.y) * -sin(o.x), cos(o.y) * cos(o.x)),
                .East => Side.fromNormal(cos(o.y), sin(o.y) * sin(o.x), sin(o.y) * cos(o.x)),
                .South => Side.fromNormal(sin(o.y), cos(o.y) * sin(o.x), cos(o.y) * cos(o.x)),
                .West => Side.fromNormal(-cos(o.y), -sin(o.y) * sin(o.x), sin(o.y) * cos(o.x)),
            };
            return switch (orientedSide) {
                .Top => texIds[0],
                .Bottom => texIds[1],
                .North => texIds[2],
                .East => texIds[3],
                .South => texIds[4],
                .West => texIds[5],
            };
        }
    };

    return S.getTex;
}

fn IntReturnedFn(comptime I: type) type {
    return fn (this: *const BlockDescription, world: *const World, pos: Vec3i) I;
}

fn returnStaticInt(comptime I: type, comptime num: I) IntReturnedFn(I) {
    const S = struct {
        fn getTex(this: *const BlockDescription, world: *const World, pos: Vec3i) I {
            return num;
        }
    };
    return S.getTex;
}

// Update FNs
const UpdateFn = fn (this: *const BlockDescription, world: *World, pos: Vec3i) void;

fn doNothing(this: *const BlockDescription, world: *World, pos: Vec3i) void {}

const ADJACENT_OFFSETS = [_]Vec3i{
    vec3i(-1, 0, 0),
    vec3i(1, 0, 0),
    vec3i(0, -1, 0),
    vec3i(0, 1, 0),
    vec3i(0, 0, -1),
    vec3i(0, 0, 1),
};

fn wireUpdate(this: *const BlockDescription, world: *World, pos: Vec3i) void {
    var block = world.getv(pos);
    const current_signal = @intCast(u4, block.blockData & 0xF);

    var max_signal_value: u4 = 0;
    for (ADJACENT_OFFSETS) |offset| {
        const offset_pos = pos.addv(offset);
        const offset_block = world.getv(offset_pos);
        switch (offset_block.blockType) {
            .SignalSource => max_signal_value = 15,
            .Wire => {
                const wire_signal = @intCast(u4, offset_block.blockData & 0xF);
                max_signal_value = std.math.max(max_signal_value, wire_signal);
            },
            else => {},
        }
    }

    const new_signal_value = if (max_signal_value == 0) 0 else max_signal_value - 1;
    if (new_signal_value != current_signal) {
        block.blockData = new_signal_value;
        world.setv(pos, block);

        for (ADJACENT_OFFSETS) |offset| {
            const offset_pos = pos.addv(offset);
            const offset_block = world.getv(offset_pos);
            switch (offset_block.blockType) {
                .Wire, .Torch => world.updated_blocks.push_back(offset_pos) catch unreachable,
                else => {},
            }
        }
    }
}

fn torchGetLightEmitted(this: *const BlockDescription, world: *const World, pos: Vec3i) u4 {
    const block = world.getv(pos);
    const has_signal = block.blockData > 0;
    return if (has_signal) 15 else 0;
}

fn torchGetTexForSide(this: *const BlockDescription, world: *const World, pos: Vec3i, side: Side) u8 {
    const block = world.getv(pos);
    const has_signal = block.blockData > 0;
    return if (has_signal) 10 else 11;
}

fn torchUpdate(this: *const BlockDescription, world: *World, pos: Vec3i) void {
    var has_signal = false;
    for (ADJACENT_OFFSETS) |offset| {
        const offset_pos = pos.addv(offset);
        const offset_block = world.getv(offset_pos);
        switch (offset_block.blockType) {
            .SignalSource => {
                has_signal = true;
                break;
            },
            .Wire => {
                const wire_signal = @intCast(u4, offset_block.blockData & 0xF);
                if (wire_signal > 0) {
                    has_signal = true;
                    break;
                }
            },
            else => {},
        }
    }

    var block = world.getv(pos);
    block.blockData = if (has_signal) 1 else 0;
    world.setv(pos, block);
}
