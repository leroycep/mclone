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

const BlockDescription = struct {
    /// Block obscures other blocks
    is_opaque: bool = true, // TODO: make enum {None, Self, All}
    is_solid: bool = true,
    rendering: union(enum) {
        /// A block that is not visible
        None: void,

        /// A block with a texture for all sides
        Single: u7,

        /// A block with a different texture for each side
        Oriented: [6]u7,

        /// A block that only renders as a quad on other surfaces
        Wire: [6]u7,
    },
    light_level: union(enum) {
        Static: u4,
    } = .{ .Static = 0 },

    pub fn isOpaque(this: @This()) bool {
        return this.is_opaque;
    }

    pub fn isSolid(this: @This()) bool {
        return this.is_solid;
    }

    pub fn isVisible(this: @This()) bool {
        switch (this.rendering) {
            .None => return false,
            .Single => return true,
            .Oriented => return true,
            .Wire => return true,
        }
    }

    pub fn texForSide(this: @This(), side: Side, data: u16) u8 {
        const sin = Orientation.sin;
        const cos = Orientation.cos;

        switch (this.rendering) {
            .None => return 0,
            .Single => |tex| return tex,
            .Oriented => |texs| {
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
                    .Top => texs[0],
                    .Bottom => texs[1],
                    .North => texs[2],
                    .East => texs[3],
                    .South => texs[4],
                    .West => texs[5],
                };
            },
            .Wire => |texs| {
                return texs[5];
            },
        }
    }

    pub fn lightLevel(this: @This(), data: u16) u4 {
        switch (this.light_level) {
            .Static => |level| return level,
        }
    }
};

const DESCRIPTIONS = comptime describe_blocks: {
    var descriptions: [256]BlockDescription = undefined;

    descriptions[@enumToInt(BlockType.Air)] = .{
        .is_opaque = false,
        .is_solid = false,
        .rendering = .None,
    };
    descriptions[@enumToInt(BlockType.Stone)] = .{
        .rendering = .{ .Single = 2 },
    };
    descriptions[@enumToInt(BlockType.Dirt)] = .{
        .rendering = .{ .Single = 1 },
    };
    descriptions[@enumToInt(BlockType.Grass)] = .{
        .rendering = .{ .Oriented = [6]u7{ 3, 1, 4, 4, 4, 4 } },
    };
    descriptions[@enumToInt(BlockType.Wood)] = .{
        .rendering = .{ .Oriented = [6]u7{ 5, 5, 6, 6, 6, 6 } },
    };
    descriptions[@enumToInt(BlockType.Leaf)] = .{
        .is_opaque = false,
        .rendering = .{ .Single = 7 },
    };
    descriptions[@enumToInt(BlockType.CoalOre)] = .{
        .rendering = .{ .Single = 8 },
    };
    descriptions[@enumToInt(BlockType.IronOre)] = .{
        .rendering = .{ .Single = 9 },
    };
    descriptions[@enumToInt(BlockType.Torch)] = .{
        .rendering = .{ .Single = 10 },
        .light_level = .{ .Static = 15 },
    };
    descriptions[@enumToInt(BlockType.Wire)] = .{
        .is_opaque = false,
        .is_solid = false,
        .rendering = .{ .Wire = [6]u7{12, 13, 14, 15, 16, 17} },
    };

    break :describe_blocks descriptions;
};

pub fn describe(block: Block) BlockDescription {
    return DESCRIPTIONS[@enumToInt(block.blockType)];
}
