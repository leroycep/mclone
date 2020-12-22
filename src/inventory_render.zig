const mesh = @import("./mesh.zig");
const Mesh = mesh.Mesh;
const Vertex = mesh.Vertex;
const core = @import("./core.zig");
const block = core.block;
const BlockType = block.BlockType;

pub const InventoryRenderer = struct {
    const item_textures: gl.GLuint;
    pub fn renderBlockToTexture(blockType: BlockType) !void {
        var blockMesh: Mesh = try Mesh.init(self.allocator);
        defer blockMesh.deinit();

        const desc = block.describe(blockType);

        if (!desc.isVisible(world, global_pos)) {
            return error.BlockIsNotVisible;
        }

        if (blk.blockType == .Wire) {
            const tex = -@bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .Top));
            const light = @bitCast(gl.GLbyte, world.getLightv(global_pos));
            const opt = blockMesh.addUpQuad(QuadBuildOptions{
                .direction = .Top,
                .x = x,
                .y = y,
                .z = z,
                .y_frac = -127,
                .tex = tex,
                .light = light,
            });
        }

        const x = 0;
        const y = 0;
        const z = 0;

        // View from positive x
        {
            const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .East));
            const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(1, 0, 0)));
            try blockMesh.addVertex(x + 1, y, z, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z, tex, 0, light);
            try blockMesh.addVertex(x + 1, y, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y, z + 1, tex, 0, light);
        }

        // View from positive y
        {
            const tex = -@bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .Top));
            const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, 1, 0)));
            try blockMesh.addVertex(x, y + 1, z, tex, 0, light);
            try blockMesh.addVertex(x, y + 1, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z, tex, 0, light);
            try blockMesh.addVertex(x, y + 1, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z + 1, tex, 0, light);
        }

        // View from positive z
        {
            const tex = @bitCast(gl.GLbyte, desc.texForSide(world, global_pos, .North));
            const light = @bitCast(gl.GLbyte, world.getLightv(global_pos.add(0, 0, 1)));
            try blockMesh.addVertex(x, y, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y, z + 1, tex, 0, light);
            try blockMesh.addVertex(x, y + 1, z + 1, tex, 0, light);
            try blockMesh.addVertex(x, y + 1, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y, z + 1, tex, 0, light);
            try blockMesh.addVertex(x + 1, y + 1, z + 1, tex, 0, light);
        }
    }
};
