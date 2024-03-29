const std = @import("std");
const platform = @import("platform");
const gl = platform.gl;
const math = @import("math");
const zigimg = @import("zigimg");

pub const Texture = struct {
    glTexture: gl.GLuint,
    size: math.Vec(2, usize),

    pub fn initFromFile(alloc: std.mem.Allocator, filePath: []const u8) !@This() {
        const cwd = std.fs.cwd();
        const image_contents = try cwd.readFileAlloc(alloc, filePath, 500000);
        defer alloc.free(image_contents);

        var load_res = try zigimg.Image.fromMemory(alloc, image_contents);
        defer load_res.deinit();

        var pixelData = try alloc.alloc(u8, load_res.width * load_res.height * 4);
        defer alloc.free(pixelData);

        // TODO: skip converting to RGBA and let OpenGL handle it by telling it what format it is in
        var pixelsIterator = zigimg.color.PixelStorageIterator.init(&load_res.pixels);

        var i: usize = 0;
        while (pixelsIterator.next()) |color| : (i += 1) {
            const integer_color = color.toRgba(u8);
            pixelData[i * 4 + 0] = integer_color.r;
            pixelData[i * 4 + 1] = integer_color.g;
            pixelData[i * 4 + 2] = integer_color.b;
            pixelData[i * 4 + 3] = integer_color.a;
        }

        var tex: gl.GLuint = 0;
        gl.genTextures(1, &tex);
        if (tex == 0)
            return error.OpenGLFailure;

        gl.bindTexture(gl.TEXTURE_2D, tex);
        defer gl.bindTexture(gl.TEXTURE_2D, 0);
        const width = @intCast(c_int, load_res.width);
        const height = @intCast(c_int, load_res.height);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixelData.ptr);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

        gl.generateMipmap(gl.TEXTURE_2D);

        return @This(){
            .glTexture = tex,
            .size = math.Vec(2, usize).init(load_res.width, load_res.height),
        };
    }
};
