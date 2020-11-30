const c = @import("c.zig");

pub const G = c.G;

pub const GLuint = c.GLuint;
pub const GLint = c.GLint;
pub const GLsizei = c.GLsizei;
pub const GLushort = c.GLushort;

pub const GL_VERTEX_SHADER = c.GL_VERTEX_SHADER;
pub const GL_FRAGMENT_SHADER = c.GL_FRAGMENT_SHADER;
pub const GL_DEPTH_TEST = c.GL_DEPTH_TEST;
pub const GL_COLOR_BUFFER_BIT = c.GL_COLOR_BUFFER_BIT;
pub const GL_ARRAY_BUFFER = c.GL_ARRAY_BUFFER;
pub const GL_ELEMENT_ARRAY_BUFFER = c.GL_ELEMENT_ARRAY_BUFFER;
pub const GL_TRIANGLES = c.GL_TRIANGLES;
pub const GL_UNSIGNED_SHORT = c.GL_UNSIGNED_SHORT;
pub const GL_STATIC_DRAW = c.GL_STATIC_DRAW;
pub const GL_FLOAT = c.GL_FLOAT;
pub const GL_UNSIGNED_BYTE = c.GL_UNSIGNED_BYTE;
pub const GL_TRUE = c.GL_TRUE;
pub const GL_FALSE = c.GL_FALSE;
pub const GL_DEPTH_BUFFER_BIT = c.GL_DEPTH_BUFFER_BIT;
pub const GL_BLEND = c.GL_BLEND;
pub const GL_SRC_ALPHA = c.GL_SRC_ALPHA;
pub const GL_ONE_MINUS_SRC_ALPHA = c.GL_ONE_MINUS_SRC_ALPHA;
pub const GL_DYNAMIC_DRAW = c.GL_DYNAMIC_DRAW;

pub const glCreateShader = c.glCreateShader;
pub const glCompileShader = c.glCompileShader;
pub const glClearColor = c.glClearColor;
pub const glCreateProgram = c.glCreateProgram;
pub const glAttachShader = c.glAttachShader;
pub const glLinkProgram = c.glLinkProgram;
pub const glBindBuffer = c.glBindBuffer;
pub const glBufferData = c.glBufferData;
pub const glUseProgram = c.glUseProgram;
pub const glEnable = c.glEnable;
pub const glClear = c.glClear;
pub const glViewport = c.glViewport;
pub const glDrawElements = c.glDrawElements;
pub const glGetAttribLocation = c.glGetAttribLocation;
pub const glVertexAttribPointer = c.glVertexAttribPointer;
pub const glEnableVertexAttribArray = c.glEnableVertexAttribArray;
pub const glBindVertexArray = c.glBindVertexArray;
pub const glGetUniformLocation = c.glGetUniformLocation;
pub const glUniformMatrix4fv = c.glUniformMatrix4fv;
pub const glBlendFunc = c.glBlendFunc;
pub const glDeleteShader = c.glDeleteShader;

pub fn glShaderSource(shader: c.GLuint, source: []const u8) void {
    c.glShaderSource(shader, 1, &source.ptr, &@intCast(c_int, source.len));
}

pub fn glCreateBuffer() GLuint {
    var res: GLuint = undefined;
    c.glCreateBuffers(1, &res);
    return res;
}

pub fn glCreateVertexArray() GLuint {
    var res: GLuint = undefined;
    c.glGenVertexArrays(1, &res);
    return res;
}
