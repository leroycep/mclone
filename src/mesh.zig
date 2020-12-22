const std = @import("std");
const platform = @import("platform");
const gl = platform.gl;
const core = @import("core");
const block = core.block;
const Block = block.Block;

const CX = core.chunk.CX;
const CY = core.chunk.CY;
const CZ = core.chunk.CZ;

pub const Vertex = [9]gl.GLbyte;

pub const QuadBuildOptions = struct {
    direction: block.Side,
    x: gl.GLbyte,
    y: gl.GLbyte,
    z: gl.GLbyte,
    x_frac: gl.GLbyte = 0,
    y_frac: gl.GLbyte = 0,
    z_frac: gl.GLbyte = 0,
    tex: gl.GLbyte,
    /// The 9 blocks that will affect AO for the quad
    ao: ?[3][3]Block = null,
    light: gl.GLbyte,
};

pub const Mesh = struct {
    allocator: *std.mem.Allocator,
    vertex: std.ArrayList(Vertex),

    pub fn init(alloc: *std.mem.Allocator) !@This() {
        return @This(){
            .allocator = alloc,
            .vertex = try std.ArrayList(Vertex).initCapacity(alloc, CX * CY * CZ * 6 * 6),
        };
    }

    pub fn deinit(this: *@This()) void {
        this.vertex.deinit();
    }

    pub fn addVertex(this: *@This(), x: gl.GLbyte, y: gl.GLbyte, z: gl.GLbyte, tex: gl.GLbyte, ao: gl.GLbyte, light: gl.GLbyte) !void {
        try this.vertex.append(Vertex{ x, y, z, 0, 0, 0, tex, ao, light });
    }

    pub fn addVertexRaw(this: *@This(), x: gl.GLbyte, y: gl.GLbyte, z: gl.GLbyte, x_frac: gl.GLbyte, y_frac: gl.GLbyte, z_frac: gl.GLbyte, tex: gl.GLbyte, ao: gl.GLbyte, light: gl.GLbyte) !void {
        try this.vertex.append(Vertex{ x, y, z, x_frac, y_frac, z_frac, tex, ao, light });
    }

    pub fn addUpQuad(this: *@This(), options: QuadBuildOptions) !void {
        const x = options.x;
        const y = options.y;
        const z = options.z;
        const x_frac = options.x_frac;
        const y_frac = options.y_frac;
        const z_frac = options.z_frac;
        const tex = options.tex;
        const light = options.tex;
        if (options.ao) |ao| {
            // TODO: Fix ambient occlusion
            //const east = block.describe(ao[2][1]).isVisible(world, vec3i(x, y, z));
            //const west = block.describe(ao[0][1]).isVisible(world, vec3i(x, y, z));
            //const north = block.describe(ao[1][2]).isVisible(world, vec3i(x, y, z));
            //const south = block.describe(ao[1][0]).isVisible(world, vec3i(x, y, z));
            //const north_east = block.describe(ao[2][2]).isVisible(world, vec3i(x, y, z));
            //const north_west = block.describe(ao[0][2]).isVisible(world, vec3i(x, y, z));
            //const south_east = block.describe(ao[2][0]).isVisible(world, vec3i(x, y, z));
            //const south_west = block.describe(ao[0][0]).isVisible(world, vec3i(x, y, z));
            //try this.addVertex(x, y + 1, z, tex, vertexAO(south, west, south_west), light);
            //try this.addVertex(x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light);
            //try this.addVertex(x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light);
            //try this.addVertex(x + 1, y + 1, z, tex, vertexAO(south, east, south_east), light);
            //try this.addVertex(x, y + 1, z + 1, tex, vertexAO(north, west, north_west), light);
            //try this.addVertex(x + 1, y + 1, z + 1, tex, vertexAO(north, east, north_east), light);
        } else {
            try this.addVertexRaw(x, y + 1, z, x_frac, y_frac, z_frac, tex, 0, light);
            try this.addVertexRaw(x, y + 1, z + 1, x_frac, y_frac, z_frac, tex, 0, light);
            try this.addVertexRaw(x + 1, y + 1, z, x_frac, y_frac, z_frac, tex, 0, light);
            try this.addVertexRaw(x + 1, y + 1, z, x_frac, y_frac, z_frac, tex, 0, light);
            try this.addVertexRaw(x, y + 1, z + 1, x_frac, y_frac, z_frac, tex, 0, light);
            try this.addVertexRaw(x + 1, y + 1, z + 1, x_frac, y_frac, z_frac, tex, 0, light);
        }
    }
};
