const std = @import("std");
const core = @import("core");
const BlockType = core.chunk.BlockType;
const Chunk = core.chunk.Chunk;
const platform = @import("platform");

const Byte4 = [4]platform.GLbyte;
const GLuint = platform.GLuint;

const CX = core.chunk.CX;
const CY = core.chunk.CY;
const CZ = core.chunk.CZ;

pub const ChunkRender = struct {
    chunk: Chunk,
    vbo: GLuint,
    elements: u32,

    pub fn init(chunk: Chunk) @This() {
        var vbo: GLuint = 0;
        platform.glGenBuffers(1, &vbo);
        var this = @This() {
            .chunk = chunk,
            .elements = 0,
            .vbo = vbo,
        };
        return this;
    }

    pub fn deinit(self: *@This()) void {
        platform.glDeleteBuffers(1, &self.vbo);
    }

    pub fn update(self: *@This()) void {
        self.chunk.changed = false;

        var vertex: [CX * CY * CZ * 6 * 6]Byte4 = undefined;
        var i : u32 = 0;

        var xi : u8 = 0;
        while (xi < CX) : (xi += 1) {
            var yi : u8 = 0;
            while (yi < CY) : (yi += 1) {
                var zi : u8 = 0;
                while (zi < CZ) : (zi += 1) {
                    var blockType = self.chunk.blk[xi][yi][zi];

                    var x = @intCast(i8, xi);
                    var y = @intCast(i8, yi);
                    var z = @intCast(i8, zi);

                    if (blockType == BlockType.AIR) {
                        continue;
                    }

                    // View from negative x
                    if (xi == 0 or (xi > 0 and self.chunk.blk[xi - 1][yi][zi] == BlockType.AIR)) {
                        vertex[i] = Byte4{x,      y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                    }

                    // View from positive x
                    if (xi == CX - 1 or (xi < CX - 1 and self.chunk.blk[xi + 1][yi][zi] == BlockType.AIR)) {
                        vertex[i] = Byte4{x + 1,  y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                    }

                    // View from negative y
                    if (yi == 0 or (yi > 0 and self.chunk.blk[xi][yi - 1][zi] == BlockType.AIR)) {
                        vertex[i] = Byte4{x,      y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                    }

                    // View from positive y
                    if (yi == CY - 1 or (yi < CY - 1 and self.chunk.blk[xi][yi + 1][zi] == BlockType.AIR)) {
                        vertex[i] = Byte4{x,      y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                    }

                    // View from negative z
                    if (zi == 0 or (zi > 0 and self.chunk.blk[xi][yi][zi - 1] == BlockType.AIR)) {
                        vertex[i] = Byte4{x,      y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z,      @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z,      @bitCast(i8, blockType)};
                        i += 1;
                    }

                    // View from positive z
                    if (zi == CZ - 1 or (zi < CZ - 1 and self.chunk.blk[xi][yi][zi + 1] == BlockType.AIR)) {
                        vertex[i] = Byte4{x,      y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x,      y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y,      z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                        vertex[i] = Byte4{x + 1,  y + 1,  z + 1,  @bitCast(i8, blockType)};
                        i += 1;
                    }
                }
            }
        }

        self.elements = i;
        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, self.elements * @sizeOf(Byte4), &vertex, platform.GL_STATIC_DRAW);
    }

    pub fn render(self: *@This(), shaderProgram: platform.GLuint) void {
        if (self.chunk.changed) {
            self.update();
        }

        if (self.elements == 0) {
            // No voxels in chunk, don't render
            return;
        }

        // Render VBO here
        platform.glEnable(platform.GL_CULL_FACE);
        platform.glEnable(platform.GL_DEPTH_TEST);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        var attribute_coord = @intCast(platform.GLuint, platform.glGetAttribLocation(shaderProgram, "coord"));
        platform.glVertexAttribPointer(attribute_coord, 4, platform.GL_BYTE, platform.GL_FALSE, 0, null);
        platform.glEnableVertexAttribArray(attribute_coord);
        platform.glDrawArrays(platform.GL_TRIANGLES, 0, @intCast(i32, self.elements));
    }
};
