const std = @import("std");
const core = @import("core");
const BlockType = core.chunk.BlockType;
const Chunk = core.chunk.Chunk;
const World = core.World;
const platform = @import("platform");
const Vec3i = @import("math").Vec(3, i64);

const Byte4 = [4]platform.GLbyte;
const GLuint = platform.GLuint;

const CX = core.chunk.CX;
const CY = core.chunk.CY;
const CZ = core.chunk.CZ;

const Side = enum {
    Top,
    Bottom,
    North,
    East,
    South,
    West,
};

const Vertex = [5]platform.GLbyte;

const BlockDescription = struct {
    /// Block obscures other blocks
    is_opaque: bool = true, // TODO: make enum {None, Self, All}
    rendering: union(enum) {
        /// A block that is not visible
        None: void,

        /// A block with a texture for all sides
        Single: u7,

        /// A block with a different texture for each side
        Multi: [6]u7,
    },

    pub fn isOpaque(this: @This()) bool {
        return this.is_opaque;
    }

    pub fn isVisible(this: @This()) bool {
        switch (this.rendering) {
            .None => return false,
            .Single => return true,
            .Multi => return true,
        }
    }

    pub fn texForSide(this: @This(), side: Side) u8 {
        switch (this.rendering) {
            .None => return 0,
            .Single => |tex| return tex,
            .Multi => |texs| return switch(side) {
                .Top    => texs[0],
                .Bottom => texs[1],
                .North  => texs[2],
                .East   => texs[3],
                .South  => texs[4],
                .West   => texs[5],
            }
        }
    }
};

const DESCRIPTIONS = comptime describe_blocks: {
    var descriptions: [256]BlockDescription = undefined;

    descriptions[@enumToInt(BlockType.Air)] = .{
        .is_opaque = false,
        .rendering = .None,
    };
    descriptions[@enumToInt(BlockType.Stone)] = .{
        .rendering = .{ .Single = 2 },
    };
    descriptions[@enumToInt(BlockType.Dirt)] = .{
        .rendering = .{ .Single = 1 },
    };
    descriptions[@enumToInt(BlockType.Grass)] = .{
        .rendering = .{ .Multi = [6]u7{3, 1, 4, 4, 4, 4}},
    };
    descriptions[@enumToInt(BlockType.Wood)] = .{
        .rendering = .{ .Multi = [6]u7{5, 5, 6, 6, 6, 6}},
    };
    descriptions[@enumToInt(BlockType.Leaf)] = .{
        .is_opaque = false,
        .rendering = .{ .Single = 7},
    };
    descriptions[@enumToInt(BlockType.CoalOre)] = .{
        .rendering = .{ .Single = 8 },
    };
    descriptions[@enumToInt(BlockType.IronOre)] = .{
        .rendering = .{ .Single = 9 },
    };

    break :describe_blocks descriptions;
};

fn vertexAO(side1: bool, side2: bool, corner: bool) u2 {
    if (side1 and side2) {
        return 0;
    }
    const s1: u2 = @boolToInt(side1);
    const s2: u2 = @boolToInt(side2);
    const co: u2 = @boolToInt(corner);
    return 3 - (s1 + s2 + co);
}

fn blockDescFor(block: BlockType) BlockDescription {
    return DESCRIPTIONS[@enumToInt(block)];
}

pub const ChunkRender = struct {
    vbo: GLuint,
    elements: u32,

    pub fn init() @This() {
        var vbo: GLuint = 0;
        platform.glGenBuffers(1, &vbo);
        var this = @This(){
            .elements = 0,
            .vbo = vbo,
        };
        return this;
    }

    pub fn deinit(self: *@This()) void {
        platform.glDeleteBuffers(1, &self.vbo);
    }

    // Get description for block at coord
    pub fn descFor(chunk: Chunk, x: u8, y: u8, z: u8) BlockDescription {
        var blockType = chunk.blk[x][y][z];
        return DESCRIPTIONS[@enumToInt(blockType)];
    }

    pub fn update(self: *@This(), chunk: Chunk, chunkPos: Vec3i, world: World) void {
        var vertex: [CX * CY * CZ * 6 * 6]Vertex = undefined;
        var i: u32 = 0;

        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi: u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi: u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    const desc = descFor(chunk, xi, yi, zi);

                    var x = @intCast(i8, xi);
                    var y = @intCast(i8, yi);
                    var z = @intCast(i8, zi);
                    const global_pos = chunkPos.scale(16).add(x, y, z);

                    if (!desc.isVisible()) {
                        continue;
                    }

                    // View from negative x
                    if (xi == 0 or (xi > 0 and !descFor(chunk, xi - 1, yi, zi).isOpaque())) {
                        const top           = blockDescFor(world.getv(global_pos.add(-1,  1,  0))).isVisible();
                        const bottom        = blockDescFor(world.getv(global_pos.add(-1, -1,  0))).isVisible();
                        const north         = blockDescFor(world.getv(global_pos.add(-1,  0,  1))).isVisible();
                        const south         = blockDescFor(world.getv(global_pos.add(-1,  0, -1))).isVisible();
                        const north_top     = blockDescFor(world.getv(global_pos.add(-1,  1,  1))).isVisible();
                        const north_bottom  = blockDescFor(world.getv(global_pos.add(-1, -1,  1))).isVisible();
                        const south_top     = blockDescFor(world.getv(global_pos.add(-1,  1, -1))).isVisible();
                        const south_bottom  = blockDescFor(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        const tex = @bitCast(i8, desc.texForSide(.West));
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(bottom, south, south_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(bottom, north, north_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(top, south, south_top) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(top, south, south_top) };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(bottom, north, north_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(top, north, north_top) };
                        i += 1;
                    }

                    // View from positive x
                    if (xi == CX - 1 or (xi < CX - 1 and !descFor(chunk, xi + 1, yi, zi).isOpaque())) {
                        const top           = blockDescFor(world.getv(global_pos.add(1,  1,  0))).isVisible();
                        const bottom        = blockDescFor(world.getv(global_pos.add(1, -1,  0))).isVisible();
                        const north         = blockDescFor(world.getv(global_pos.add(1,  0,  1))).isVisible();
                        const south         = blockDescFor(world.getv(global_pos.add(1,  0, -1))).isVisible();
                        const north_top     = blockDescFor(world.getv(global_pos.add(1,  1,  1))).isVisible();
                        const north_bottom  = blockDescFor(world.getv(global_pos.add(1, -1,  1))).isVisible();
                        const south_top     = blockDescFor(world.getv(global_pos.add(1,  1, -1))).isVisible();
                        const south_bottom  = blockDescFor(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        const tex = @bitCast(i8, desc.texForSide(.East));
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(bottom, south, south_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(top, south, south_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(top, south, south_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(top, north, north_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom) };
                        i += 1;
                    }

                    // View from negative y
                    if (yi == 0 or (yi > 0 and !descFor(chunk, xi, yi - 1, zi).isOpaque())) {
                        const east          = blockDescFor(world.getv(global_pos.add(1, -1, 0))).isVisible();
                        const west          = blockDescFor(world.getv(global_pos.add(-1, -1, 0))).isVisible();
                        const north         = blockDescFor(world.getv(global_pos.add(0, -1, 1))).isVisible();
                        const south         = blockDescFor(world.getv(global_pos.add(0, -1, -1))).isVisible();
                        const north_east    = blockDescFor(world.getv(global_pos.add(1, -1, 1))).isVisible();
                        const north_west    = blockDescFor(world.getv(global_pos.add(-1, -1, 1))).isVisible();
                        const south_east    = blockDescFor(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        const south_west    = blockDescFor(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        const tex = -@bitCast(i8, desc.texForSide(.Bottom));
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(south, west, south_west) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(south, east, south_east) };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(north, west, north_west) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(south, east, south_east) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(north, east, north_east) };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(north, west, north_west) };
                        i += 1;
                    }

                    // View from positive y
                    if (yi == CY - 1 or (yi < CY - 1 and !descFor(chunk, xi, yi + 1, zi).isOpaque())) {
                        const east          = blockDescFor(world.getv(global_pos.add( 1,  1,  0))).isVisible();
                        const west          = blockDescFor(world.getv(global_pos.add(-1,  1,  0))).isVisible();
                        const north         = blockDescFor(world.getv(global_pos.add( 0,  1,  1))).isVisible();
                        const south         = blockDescFor(world.getv(global_pos.add( 0,  1, -1))).isVisible();
                        const north_east    = blockDescFor(world.getv(global_pos.add( 1,  1,  1))).isVisible();
                        const north_west    = blockDescFor(world.getv(global_pos.add(-1,  1,  1))).isVisible();
                        const south_east    = blockDescFor(world.getv(global_pos.add( 1,  1, -1))).isVisible();
                        const south_west    = blockDescFor(world.getv(global_pos.add(-1,  1, -1))).isVisible();
                        const tex = -@bitCast(i8, desc.texForSide(.Top));
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(south, west, south_west) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(north, west, north_west) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(south, east, south_east) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(south, east, south_east) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(north, west, north_west) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(north, east, north_east) };
                        i += 1;
                    }

                    // View from negative z
                    if (zi == 0 or (zi > 0 and !descFor(chunk, xi, yi, zi - 1).isOpaque())) {
                        const east          = blockDescFor(world.getv(global_pos.add(1, 0, -1))).isVisible();
                        const west          = blockDescFor(world.getv(global_pos.add(-1, 0, -1))).isVisible();
                        const top           = blockDescFor(world.getv(global_pos.add(0, 1, -1))).isVisible();
                        const bottom        = blockDescFor(world.getv(global_pos.add(0, -1, -1))).isVisible();
                        const east_top      = blockDescFor(world.getv(global_pos.add(1, 1, -1))).isVisible();
                        const east_bottom   = blockDescFor(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        const west_top      = blockDescFor(world.getv(global_pos.add(-1, 1, -1))).isVisible();
                        const west_bottom   = blockDescFor(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        const tex = @bitCast(i8, desc.texForSide(.South));
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(west, bottom, west_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(west, top, west_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(east, bottom, east_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(west, top, west_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(east, top, east_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(east, bottom, east_bottom) };
                        i += 1;
                    }

                    // View from positive z
                    if (zi == CZ - 1 or (zi < CZ - 1 and !descFor(chunk, xi, yi, zi + 1).isOpaque())) {
                        const east          = blockDescFor(world.getv(global_pos.add(1, 0, 1))).isVisible();
                        const west          = blockDescFor(world.getv(global_pos.add(-1, 0, 1))).isVisible();
                        const top           = blockDescFor(world.getv(global_pos.add(0, 1, 1))).isVisible();
                        const bottom        = blockDescFor(world.getv(global_pos.add(0, -1, 1))).isVisible();
                        const east_top      = blockDescFor(world.getv(global_pos.add(1, 1, 1))).isVisible();
                        const east_bottom   = blockDescFor(world.getv(global_pos.add(1, -1, 1))).isVisible();
                        const west_top      = blockDescFor(world.getv(global_pos.add(-1, 1, 1))).isVisible();
                        const west_bottom   = blockDescFor(world.getv(global_pos.add(-1, -1, 1))).isVisible();
                        const tex = @bitCast(i8, desc.texForSide(.North));
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(west, bottom, west_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(west, top, west_top) };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(west, top, west_top) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom) };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(east, top, east_top) };
                        i += 1;
                    }
                }
            }
        }

        self.elements = i;
        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, self.elements * @sizeOf(Vertex), &vertex, platform.GL_STATIC_DRAW);
    }

    pub fn render(self: *@This(), shaderProgram: platform.GLuint) void {
        if (self.elements == 0) {
            // No voxels in chunk, don't render
            return;
        }

        // Render VBO here
        platform.glEnable(platform.GL_CULL_FACE);
        platform.glEnable(platform.GL_DEPTH_TEST);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        var attribute_coord = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "coord"));
        platform.glEnableVertexAttribArray(attribute_coord);
        platform.glVertexAttribPointer(attribute_coord, 4, platform.GL_BYTE, platform.GL_FALSE, 5, null);
        var attribute_ao = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "ao"));
        platform.glEnableVertexAttribArray(attribute_ao);
        platform.glVertexAttribPointer(1, 1, platform.GL_BYTE, platform.GL_FALSE, 5, @intToPtr(*c_void, 4));

        platform.glDrawArrays(platform.GL_TRIANGLES, 0, @intCast(i32, self.elements));
    }
};
