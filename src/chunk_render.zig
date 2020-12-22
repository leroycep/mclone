const std = @import("std");
const core = @import("core");
const block = core.block;
const Block = block.Block;
const BlockType = core.block.BlockType;
const Side = core.chunk.Side;
const Chunk = core.chunk.Chunk;
const World = core.World;
const platform = @import("platform");
const gl = platform.gl;
const Vec3i = @import("math").Vec(3, i64);
const mesh = @import("./mesh.zig");
const Mesh = mesh.Mesh;
const Vertex = mesh.Vertex;

const Byte4 = [4]gl.GLbyte;
const GLuint = gl.GLuint;

const CX = core.chunk.CX;
const CY = core.chunk.CY;
const CZ = core.chunk.CZ;

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
    elements: usize,
    allocator: *std.mem.Allocator,

    pub fn init(alloc: *std.mem.Allocator) @This() {
        var vbo: GLuint = 0;
        gl.genBuffers(1, &vbo);
        var this = @This(){
            .elements = 0,
            .vbo = vbo,
            .allocator = alloc,
        };
        return this;
    }

    pub fn deinit(self: *@This()) void {
        gl.deleteBuffers(1, &self.vbo);
    }

    pub fn update(self: *@This(), chunk: Chunk, chunkPos: Vec3i, world: *const World) !void {
        var chunkMesh: Mesh = try Mesh.init(self.allocator);
        defer chunkMesh.deinit();
        var i: u32 = 0;

        var xi: u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi: u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi: u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    const blk = chunk.get(xi, yi, zi);
                    const desc = block.describe(blk);
                    const data = blk.blockData;

                    var x = @intCast(i8, xi);
                    var y = @intCast(i8, yi);
                    var z = @intCast(i8, zi);
                    const global_pos = chunkPos.scale(16).add(x, y, z);

                    if (!desc.isVisible(world, global_pos)) {
                        continue;
                    }

                    if (blk.blockType == .Wire) {
                        const tex = -@bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .Top));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos));
                        const opt = chunkMesh.addUpQuad(.{
                            .direction = .Top,
                            .x = x,
                            .y = y,
                            .z = z,
                            .y_frac = -127,
                            .tex = tex,
                            .light = light,
                        });
                        continue;
                    }
                    // View from negative x
                    if (world.isOpaquev(global_pos.add(-1, 0, 0)) == false) {
                        const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .West));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(-1, 0, 0)));
                        const top = block.describe(world.getv(global_pos.add(-1, 1, 0))).isUsedForAO;
                        const bottom = block.describe(world.getv(global_pos.add(-1, -1, 0))).isUsedForAO;
                        const north = block.describe(world.getv(global_pos.add(-1, 0, 1))).isUsedForAO;
                        const south = block.describe(world.getv(global_pos.add(-1, 0, -1))).isUsedForAO;
                        const north_top = block.describe(world.getv(global_pos.add(-1, 1, 1))).isUsedForAO;
                        const north_bottom = block.describe(world.getv(global_pos.add(-1, -1, 1))).isUsedForAO;
                        const south_top = block.describe(world.getv(global_pos.add(-1, 1, -1))).isUsedForAO;
                        const south_bottom = block.describe(world.getv(global_pos.add(-1, -1, -1))).isUsedForAO;
                        try chunkMesh.addVertex(x, y, z, tex, vertexAO(bottom, south, south_bottom), light);
                        try chunkMesh.addVertex(x, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light);
                        try chunkMesh.addVertex(x, y + 1, z, tex, vertexAO(top, south, south_top), light);
                        try chunkMesh.addVertex(x, y + 1, z, tex, vertexAO(top, south, south_top), light);
                        try chunkMesh.addVertex(x, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light);
                        try chunkMesh.addVertex(x, y + 1, z + 1, tex, vertexAO(top, north, north_top), light);
                    }

                    // View from positive x
                    if (world.isOpaquev(global_pos.add(1, 0, 0)) == false) {
                        const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .East));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(1, 0, 0)));
                        const top = block.describe(world.getv(global_pos.add(1, 1, 0))).isUsedForAO;
                        const bottom = block.describe(world.getv(global_pos.add(1, -1, 0))).isUsedForAO;
                        const north = block.describe(world.getv(global_pos.add(1, 0, 1))).isUsedForAO;
                        const south = block.describe(world.getv(global_pos.add(1, 0, -1))).isUsedForAO;
                        const north_top = block.describe(world.getv(global_pos.add(1, 1, 1))).isUsedForAO;
                        const north_bottom = block.describe(world.getv(global_pos.add(1, -1, 1))).isUsedForAO;
                        const south_top = block.describe(world.getv(global_pos.add(1, 1, -1))).isUsedForAO;
                        const south_bottom = block.describe(world.getv(global_pos.add(1, -1, -1))).isUsedForAO;
                        try chunkMesh.addVertex(x + 1, y, z, tex, vertexAO(bottom, south, south_bottom), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z, tex, vertexAO(top, south, south_top), light);
                        try chunkMesh.addVertex(x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z, tex, vertexAO(top, south, south_top), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z + 1, tex, vertexAO(top, north, north_top), light);
                        try chunkMesh.addVertex(x + 1, y, z + 1, tex, vertexAO(bottom, north, north_bottom), light);
                    }

                    // View from negative y
                    if (world.isOpaquev(global_pos.add(0, -1, 0)) == false) {
                        const tex = -@bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .Bottom));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, -1, 0)));
                        const east = block.describe(world.getv(global_pos.add(1, -1, 0))).isUsedForAO;
                        const west = block.describe(world.getv(global_pos.add(-1, -1, 0))).isUsedForAO;
                        const north = block.describe(world.getv(global_pos.add(0, -1, 1))).isUsedForAO;
                        const south = block.describe(world.getv(global_pos.add(0, -1, -1))).isUsedForAO;
                        const north_east = block.describe(world.getv(global_pos.add(1, -1, 1))).isUsedForAO;
                        const north_west = block.describe(world.getv(global_pos.add(-1, -1, 1))).isUsedForAO;
                        const south_east = block.describe(world.getv(global_pos.add(1, -1, -1))).isUsedForAO;
                        const south_west = block.describe(world.getv(global_pos.add(-1, -1, -1))).isUsedForAO;
                        try chunkMesh.addVertex(x, y, z, tex, vertexAO(south, west, south_west), light);
                        try chunkMesh.addVertex(x + 1, y, z, tex, vertexAO(south, east, south_east), light);
                        try chunkMesh.addVertex(x, y, z + 1, tex, vertexAO(north, west, north_west), light);
                        try chunkMesh.addVertex(x + 1, y, z, tex, vertexAO(south, east, south_east), light);
                        try chunkMesh.addVertex(x + 1, y, z + 1, tex, vertexAO(north, east, north_east), light);
                        try chunkMesh.addVertex(x, y, z + 1, tex, vertexAO(north, west, north_west), light);
                    }

                    // View from positive y
                    if (world.isOpaquev(global_pos.add(0, 1, 0)) == false) {
                        const tex = -@bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .Top));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, 1, 0)));
                        const east = block.describe(world.getv(global_pos.add(1, 1, 0))).isUsedForAO;
                        const west = block.describe(world.getv(global_pos.add(-1, 1, 0))).isUsedForAO;
                        const north = block.describe(world.getv(global_pos.add(0, 1, 1))).isUsedForAO;
                        const south = block.describe(world.getv(global_pos.add(0, 1, -1))).isUsedForAO;
                        const north_east = block.describe(world.getv(global_pos.add(1, 1, 1))).isUsedForAO;
                        const north_west = block.describe(world.getv(global_pos.add(-1, 1, 1))).isUsedForAO;
                        const south_east = block.describe(world.getv(global_pos.add(1, 1, -1))).isUsedForAO;
                        const south_west = block.describe(world.getv(global_pos.add(-1, 1, -1))).isUsedForAO;
                        try chunkMesh.addVertex(x, y + 1, z, tex, vertexAO(south, west, south_west), light);
                        try chunkMesh.addVertex(x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light);
                        try chunkMesh.addVertex(x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z + 1, tex, vertexAO(north, east, north_east), light);
                    }

                    // View from negative z
                    if (world.isOpaquev(global_pos.add(0, 0, -1)) == false) {
                        const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .South));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, 0, -1)));
                        const east = block.describe(world.getv(global_pos.add(1, 0, -1))).isUsedForAO;
                        const west = block.describe(world.getv(global_pos.add(-1, 0, -1))).isUsedForAO;
                        const top = block.describe(world.getv(global_pos.add(0, 1, -1))).isUsedForAO;
                        const bottom = block.describe(world.getv(global_pos.add(0, -1, -1))).isUsedForAO;
                        const east_top = block.describe(world.getv(global_pos.add(1, 1, -1))).isUsedForAO;
                        const east_bottom = block.describe(world.getv(global_pos.add(1, -1, -1))).isUsedForAO;
                        const west_top = block.describe(world.getv(global_pos.add(-1, 1, -1))).isUsedForAO;
                        const west_bottom = block.describe(world.getv(global_pos.add(-1, -1, -1))).isUsedForAO;
                        try chunkMesh.addVertex(x, y, z, tex, vertexAO(west, bottom, west_bottom), light);
                        try chunkMesh.addVertex(x, y + 1, z, tex, vertexAO(west, top, west_top), light);
                        try chunkMesh.addVertex(x + 1, y, z, tex, vertexAO(east, bottom, east_bottom), light);
                        try chunkMesh.addVertex(x, y + 1, z, tex, vertexAO(west, top, west_top), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z, tex, vertexAO(east, top, east_top), light);
                        try chunkMesh.addVertex(x + 1, y, z, tex, vertexAO(east, bottom, east_bottom), light);
                    }

                    // View from positive z
                    if (world.isOpaquev(global_pos.add(0, 0, 1)) == false) {
                        const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .North));
                        const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, 0, 1)));
                        const east = block.describe(world.getv(global_pos.add(1, 0, 1))).isUsedForAO;
                        const west = block.describe(world.getv(global_pos.add(-1, 0, 1))).isUsedForAO;
                        const top = block.describe(world.getv(global_pos.add(0, 1, 1))).isUsedForAO;
                        const bottom = block.describe(world.getv(global_pos.add(0, -1, 1))).isUsedForAO;
                        const east_top = block.describe(world.getv(global_pos.add(1, 1, 1))).isUsedForAO;
                        const east_bottom = block.describe(world.getv(global_pos.add(1, -1, 1))).isUsedForAO;
                        const west_top = block.describe(world.getv(global_pos.add(-1, 1, 1))).isUsedForAO;
                        const west_bottom = block.describe(world.getv(global_pos.add(-1, -1, 1))).isUsedForAO;
                        try chunkMesh.addVertex(x, y, z + 1, tex, vertexAO(west, bottom, west_bottom), light);
                        try chunkMesh.addVertex(x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom), light);
                        try chunkMesh.addVertex(x, y + 1, z + 1, tex, vertexAO(west, top, west_top), light);
                        try chunkMesh.addVertex(x, y + 1, z + 1, tex, vertexAO(west, top, west_top), light);
                        try chunkMesh.addVertex(x + 1, y, z + 1, tex, vertexAO(east, bottom, east_bottom), light);
                        try chunkMesh.addVertex(x + 1, y + 1, z + 1, tex, vertexAO(east, top, east_top), light);
                    }
                }
            }
        }

        self.elements = chunkMesh.vertex.items.len;
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(c_long, chunkMesh.vertex.items.len) * @sizeOf(Vertex), chunkMesh.vertex.items.ptr, gl.STATIC_DRAW);
    }

    pub fn render(self: *@This(), shaderProgram: gl.GLuint) void {
        if (self.elements == 0) {
            // No voxels in chunk, don't render
            return;
        }

        // Render VBO here
        gl.enable(gl.CULL_FACE);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        const stride = 9;
        var attribute_coord_result = gl.getAttribLocation(shaderProgram, "coord");
        if (attribute_coord_result >= 0) {
            var attribute_coord = @intCast(gl.GLuint, attribute_coord_result);
            gl.enableVertexAttribArray(attribute_coord);
            gl.vertexAttribPointer(attribute_coord, 3, gl.BYTE, gl.FALSE, stride, null);
        } else {
            std.log.debug("no coord attribute err {}", .{attribute_coord_result});
        }

        var attribute_coord_frac_result = gl.getAttribLocation(shaderProgram, "frac_coord");
        if (attribute_coord_frac_result >= 0) {
            var attribute_coord_frac = @intCast(gl.GLuint, attribute_coord_frac_result);
            gl.enableVertexAttribArray(attribute_coord_frac);
            gl.vertexAttribPointer(attribute_coord_frac, 3, gl.BYTE, gl.FALSE, stride, @intToPtr(*c_void, 3));
        } else {
            std.log.debug("no coord_frac attribute", .{});
        }

        var attribute_tex_result = gl.getAttribLocation(shaderProgram, "tex");
        if (attribute_tex_result >= 0) {
            var attribute_tex = @intCast(gl.GLuint, attribute_tex_result);
            gl.enableVertexAttribArray(attribute_tex);
            gl.vertexAttribPointer(attribute_tex, 1, gl.BYTE, gl.FALSE, stride, @intToPtr(*c_void, 6));
        } else {
            std.log.debug("no tex attribute", .{});
        }

        var attribute_ao_result = gl.getAttribLocation(shaderProgram, "ao");
        if (attribute_ao_result >= 0) {
            var attribute_ao = @intCast(gl.GLuint, attribute_ao_result);
            gl.enableVertexAttribArray(attribute_ao);
            gl.vertexAttribPointer(attribute_ao, 1, gl.BYTE, gl.FALSE, stride, @intToPtr(*c_void, 7));
        } else {
            std.log.debug("no ao attribute", .{});
        }

        var attribute_light_result = gl.getAttribLocation(shaderProgram, "light");
        if (attribute_light_result >= 0) {
            var attribute_light = @intCast(gl.GLuint, attribute_light_result);
            gl.enableVertexAttribArray(attribute_light);
            gl.vertexAttribPointer(attribute_light, 1, gl.BYTE, gl.FALSE, stride, @intToPtr(*c_void, 8));
        } else {
            std.log.debug("no light attribute", .{});
        }

        gl.drawArrays(gl.TRIANGLES, 0, @intCast(i32, self.elements));
    }
};
