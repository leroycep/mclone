const std = @import("std");
const core = @import("core");
const block = core.block;
const BlockType = core.block.BlockType;
const Side = core.chunk.Side;
const Chunk = core.chunk.Chunk;
const World = core.World;
const platform = @import("platform");
const Vec3i = @import("math").Vec(3, i64);

const Byte4 = [4]platform.GLbyte;
const GLuint = platform.GLuint;

const CX = core.chunk.CX;
const CY = core.chunk.CY;
const CZ = core.chunk.CZ;

const Vertex = [6]platform.GLbyte;

fn vertexAO(side1: bool, side2: bool, corner: bool) u2 {
    if (side1 and side2) {
        return 0;
    }
    const s1: u2 = @boolToInt(side1);
    const s2: u2 = @boolToInt(side2);
    const co: u2 = @boolToInt(corner);
    return 3 - (s1 + s2 + co);
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

    pub fn update(self: *@This(), chunk: Chunk, chunkPos: Vec3i, world: World) void {
        var vertex: [CX * CY * CZ * 6 * 6]Vertex = undefined;
        var i: u32 = 0;

        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi: u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi: u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    const desc = block.describe(chunk.get(xi, yi, zi));
                    const data = chunk.blk[xi][yi][zi].blockData;

                    var x = @intCast(i8, xi);
                    var y = @intCast(i8, yi);
                    var z = @intCast(i8, zi);
                    const global_pos = chunkPos.scale(16).add(x, y, z);

                    if (!desc.isVisible()) {
                        continue;
                    }

                    // View from negative x
                    if (world.isOpaquev(global_pos.add(-1, 0, 0)) == false) {
                        const tex = @bitCast(platform.GLbyte, desc.texForSide(.West, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(-1, 0, 0)));
                        const top = block.describe(world.getv(global_pos.add(-1, 1, 0))).isVisible();
                        const bottom = block.describe(world.getv(global_pos.add(-1, -1, 0))).isVisible();
                        const north = block.describe(world.getv(global_pos.add(-1, 0, 1))).isVisible();
                        const south = block.describe(world.getv(global_pos.add(-1, 0, -1))).isVisible();
                        const north_top = block.describe(world.getv(global_pos.add(-1, 1, 1))).isVisible();
                        const north_bottom = block.describe(world.getv(global_pos.add(-1, -1, 1))).isVisible();
                        const south_top = block.describe(world.getv(global_pos.add(-1, 1, -1))).isVisible();
                        const south_bottom = block.describe(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(bottom, south, south_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(top, south, south_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(top, south, south_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(top, north, north_top), light };
                        i += 1;
                    }

                    // View from positive x
                    if (world.isOpaquev(global_pos.add(1, 0, 0)) == false) {
                        const tex = @bitCast(platform.GLbyte, desc.texForSide(.East, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(1, 0, 0)));
                        const top = block.describe(world.getv(global_pos.add(1, 1, 0))).isVisible();
                        const bottom = block.describe(world.getv(global_pos.add(1, -1, 0))).isVisible();
                        const north = block.describe(world.getv(global_pos.add(1, 0, 1))).isVisible();
                        const south = block.describe(world.getv(global_pos.add(1, 0, -1))).isVisible();
                        const north_top = block.describe(world.getv(global_pos.add(1, 1, 1))).isVisible();
                        const north_bottom = block.describe(world.getv(global_pos.add(1, -1, 1))).isVisible();
                        const south_top = block.describe(world.getv(global_pos.add(1, 1, -1))).isVisible();
                        const south_bottom = block.describe(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(bottom, south, south_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(top, south, south_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(top, south, south_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(top, north, north_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light };
                        i += 1;
                    }

                    // View from negative y
                    if (world.isOpaquev(global_pos.add(0, -1, 0)) == false) {
                        const tex = -@bitCast(platform.GLbyte, desc.texForSide(.Bottom, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(0, -1, 0)));
                        const east = block.describe(world.getv(global_pos.add(1, -1, 0))).isVisible();
                        const west = block.describe(world.getv(global_pos.add(-1, -1, 0))).isVisible();
                        const north = block.describe(world.getv(global_pos.add(0, -1, 1))).isVisible();
                        const south = block.describe(world.getv(global_pos.add(0, -1, -1))).isVisible();
                        const north_east = block.describe(world.getv(global_pos.add(1, -1, 1))).isVisible();
                        const north_west = block.describe(world.getv(global_pos.add(-1, -1, 1))).isVisible();
                        const south_east = block.describe(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        const south_west = block.describe(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(south, west, south_west), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(south, east, south_east), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(north, west, north_west), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(south, east, south_east), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(north, east, north_east), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(north, west, north_west), light };
                        i += 1;
                    }

                    // View from positive y
                    if (world.isOpaquev(global_pos.add(0, 1, 0)) == false) {
                        const tex = -@bitCast(platform.GLbyte, desc.texForSide(.Top, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(0, 1, 0)));
                        const east = block.describe(world.getv(global_pos.add(1, 1, 0))).isVisible();
                        const west = block.describe(world.getv(global_pos.add(-1, 1, 0))).isVisible();
                        const north = block.describe(world.getv(global_pos.add(0, 1, 1))).isVisible();
                        const south = block.describe(world.getv(global_pos.add(0, 1, -1))).isVisible();
                        const north_east = block.describe(world.getv(global_pos.add(1, 1, 1))).isVisible();
                        const north_west = block.describe(world.getv(global_pos.add(-1, 1, 1))).isVisible();
                        const south_east = block.describe(world.getv(global_pos.add(1, 1, -1))).isVisible();
                        const south_west = block.describe(world.getv(global_pos.add(-1, 1, -1))).isVisible();
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(south, west, south_west), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(north, east, north_east), light };
                        i += 1;
                    }

                    // View from negative z
                    if (world.isOpaquev(global_pos.add(0, 0, -1)) == false) {
                        const tex = @bitCast(platform.GLbyte, desc.texForSide(.South, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(0, 0, -1)));
                        const east = block.describe(world.getv(global_pos.add(1, 0, -1))).isVisible();
                        const west = block.describe(world.getv(global_pos.add(-1, 0, -1))).isVisible();
                        const top = block.describe(world.getv(global_pos.add(0, 1, -1))).isVisible();
                        const bottom = block.describe(world.getv(global_pos.add(0, -1, -1))).isVisible();
                        const east_top = block.describe(world.getv(global_pos.add(1, 1, -1))).isVisible();
                        const east_bottom = block.describe(world.getv(global_pos.add(1, -1, -1))).isVisible();
                        const west_top = block.describe(world.getv(global_pos.add(-1, 1, -1))).isVisible();
                        const west_bottom = block.describe(world.getv(global_pos.add(-1, -1, -1))).isVisible();
                        vertex[i] = Vertex{ x, y, z, tex, vertexAO(west, bottom, west_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(west, top, west_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(east, bottom, east_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z, tex, vertexAO(west, top, west_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z, tex, vertexAO(east, top, east_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z, tex, vertexAO(east, bottom, east_bottom), light };
                        i += 1;
                    }

                    // View from positive z
                    if (world.isOpaquev(global_pos.add(0, 0, 1)) == false) {
                        const tex = @bitCast(platform.GLbyte, desc.texForSide(.North, data));
                        const light = @bitCast(platform.GLbyte, world.getLightv(global_pos.add(0, 0, 1)));
                        const east = block.describe(world.getv(global_pos.add(1, 0, 1))).isVisible();
                        const west = block.describe(world.getv(global_pos.add(-1, 0, 1))).isVisible();
                        const top = block.describe(world.getv(global_pos.add(0, 1, 1))).isVisible();
                        const bottom = block.describe(world.getv(global_pos.add(0, -1, 1))).isVisible();
                        const east_top = block.describe(world.getv(global_pos.add(1, 1, 1))).isVisible();
                        const east_bottom = block.describe(world.getv(global_pos.add(1, -1, 1))).isVisible();
                        const west_top = block.describe(world.getv(global_pos.add(-1, 1, 1))).isVisible();
                        const west_bottom = block.describe(world.getv(global_pos.add(-1, -1, 1))).isVisible();
                        vertex[i] = Vertex{ x, y, z + 1, tex, vertexAO(west, bottom, west_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(west, top, west_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x, y + 1, z + 1, tex, vertexAO(west, top, west_top), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom), light };
                        i += 1;
                        vertex[i] = Vertex{ x + 1, y + 1, z + 1, tex, vertexAO(east, top, east_top), light };
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
        const stride = 6;
        var attribute_coord = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "coord"));
        platform.glEnableVertexAttribArray(attribute_coord);
        platform.glVertexAttribPointer(attribute_coord, 4, platform.GL_BYTE, platform.GL_FALSE, stride, null);
        var attribute_ao = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "ao"));
        platform.glEnableVertexAttribArray(attribute_ao);
        platform.glVertexAttribPointer(attribute_ao, 1, platform.GL_BYTE, platform.GL_FALSE, stride, @intToPtr(*c_void, 4));
        var attribute_light_result = platform.glGetAttribLocation(shaderProgram, "light");
        // if (attribute_light_result > 0) {
            var attribute_light = @intCast(platform.GLuint, attribute_light_result);
            platform.glEnableVertexAttribArray(attribute_light);
            platform.glVertexAttribPointer(attribute_light, 1, platform.GL_BYTE, platform.GL_FALSE, stride, @intToPtr(*c_void, 5));
        // }

        platform.glDrawArrays(platform.GL_TRIANGLES, 0, @intCast(i32, self.elements));
    }
};
