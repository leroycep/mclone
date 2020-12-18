const gl = @import("./gl_es_3v0.zig");

/// Custom functions to make loading easier
pub fn shaderSource(shader: gl.GLuint, source: []const u8) void {
    gl.shaderSource(shader, 1, &source.ptr, &@intCast(c_int, source.len));
}
