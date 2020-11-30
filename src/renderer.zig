const std = @import("std");
const common = @import("./common.zig");
const platform = @import("platform");
const math = @import("math");
const Vec2f = math.Vec2f;
const vec2f = math.vec2f;
const util = @import("util");
const Rect2f = util.Rect2f;
const RGBA = util.color.RGBA;

const DEG_TO_RAD = std.math.pi / 180.0;

const VERT_SHADER_SRC =
    \\ #version 300 es
    \\
    \\ in highp vec2 coordinates;
    \\ in lowp vec4 color;
    \\
    \\ out vec4 vertexColor;
    \\
    \\ uniform mat4 projectionMatrix;
    \\
    \\ void main(void) {
    \\   gl_Position = vec4(coordinates, 0.0, 1.0);
    \\   gl_Position *= projectionMatrix;
    \\   vertexColor = color;
    \\ }
;

const FRAG_SHADER_SRC =
    \\ #version 300 es
    \\
    \\ in lowp vec4 vertexColor;
    \\
    \\ out lowp vec4 FragColor;
    \\
    \\ void main(void) {
    \\   FragColor = vertexColor;
    \\ }
;

pub const Renderer = struct {
    verts: [NUM_ATTR * MAX_VERTS]f32 = undefined,
    colors: [NUM_COLOR_ATTR * MAX_VERTS]u8 = undefined,
    vertIdx: usize,
    indices: [6 * MAX_VERTS]platform.GLushort = undefined,
    indIdx: usize,
    projectionMatrix: [16]f32,

    shaderProgram: platform.GLuint,

    vao: platform.GLuint,
    vbo: platform.GLuint,
    colorBuffer: platform.GLuint,
    ebo: platform.GLuint,

    coordinatesLocation: platform.GLuint,
    colorLocation: platform.GLuint,
    projectionMatrixUniformLocation: platform.GLint,

    const NUM_ATTR = 2;
    const NUM_COLOR_ATTR = 4;
    const MAX_VERTS = 512;

    pub fn init() Renderer {
        const vShader = platform.glCreateShader(platform.GL_VERTEX_SHADER);
        platform.glShaderSource(vShader, VERT_SHADER_SRC);
        platform.glCompileShader(vShader);
        defer platform.glDeleteShader(vShader);

        //if (!platform.getShaderCompileStatus(vShader)) {
        //    var infoLog: [512]u8 = [_]u8{0} ** 512;
        //    var infoLen: platform.GLsizei = 0;
        //    platform.glGetShaderInfoLog(vShader, infoLog.len, &infoLen, &infoLog);
        //    platform.warn("Error compiling vertex shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        //}

        const fShader = platform.glCreateShader(platform.GL_FRAGMENT_SHADER);
        platform.glShaderSource(fShader, FRAG_SHADER_SRC);
        platform.glCompileShader(fShader);
        defer platform.glDeleteShader(fShader);

        //if (!platform.getShaderCompileStatus(vShader)) {
        //    var infoLog: [512]u8 = [_]u8{0} ** 512;
        //    var infoLen: platform.GLsizei = 0;
        //    platform.glGetShaderInfoLog(fShader, infoLog.len, &infoLen, &infoLog);
        //    platform.warn("Error compiling fragment shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        //}

        const shaderProgram = platform.glCreateProgram();
        platform.glAttachShader(shaderProgram, vShader);
        platform.glAttachShader(shaderProgram, fShader);
        platform.glLinkProgram(shaderProgram);

        //if (!platform.getProgramLinkStatus(shaderProgram)) {
        //    var infoLog: [512]u8 = [_]u8{0} ** 512;
        //    var infoLen: platform.GLsizei = 0;
        //    platform.glGetProgramInfoLog(shaderProgram, infoLog.len, &infoLen, &infoLog);
        //    platform.warn("Error linking shader program: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        //}

        platform.glUseProgram(shaderProgram);
        const projectionMatrixUniformLocation = platform.glGetUniformLocation(shaderProgram, "projectionMatrix");

        // Setup Vertex Array
        const vao = platform.glCreateVertexArray();
        platform.glBindVertexArray(vao);
        platform.glEnable(platform.GL_BLEND);
        platform.glBlendFunc(platform.GL_SRC_ALPHA, platform.GL_ONE_MINUS_SRC_ALPHA);

        // Set up vertex buffers
        const coordinatesLocation = @intCast(c_uint, platform.glGetAttribLocation(shaderProgram, "coordinates"));
        const colorLocation = @intCast(c_uint, platform.glGetAttribLocation(shaderProgram, "color"));

        const vbo = platform.glCreateBuffer();
        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, vbo);
        platform.glVertexAttribPointer(coordinatesLocation, 2, platform.GL_FLOAT, platform.GL_FALSE, 0, null);
        platform.glEnableVertexAttribArray(coordinatesLocation);

        const colorBuffer = platform.glCreateBuffer();
        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, colorBuffer);
        platform.glVertexAttribPointer(colorLocation, 3, platform.GL_UNSIGNED_BYTE, platform.GL_TRUE, 0, null);
        platform.glEnableVertexAttribArray(colorLocation);

        const ebo = platform.glCreateBuffer();
        platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, ebo);

        platform.glBindVertexArray(0);

        return .{
            .projectionMatrix = [_]f32{0} ** 16,
            .vertIdx = 0,
            .indIdx = 0,
            .shaderProgram = shaderProgram,
            .vao = vao,
            .vbo = vbo,
            .colorBuffer = colorBuffer,
            .ebo = ebo,
            .coordinatesLocation = coordinatesLocation,
            .colorLocation = colorLocation,
            .projectionMatrixUniformLocation = projectionMatrixUniformLocation,
        };
    }

    fn setTranslation(self: *Renderer, vec: Vec2f) void {
        self.translation = vec;
    }

    fn pushVert(self: *Renderer, pos: Vec2f, color: RGBA) usize {
        const idx = self.vertIdx;
        defer self.vertIdx += 1;

        self.verts[idx * NUM_ATTR + 0] = pos.x;
        self.verts[idx * NUM_ATTR + 1] = pos.y;

        self.colors[idx * NUM_COLOR_ATTR + 0] = color.r;
        self.colors[idx * NUM_COLOR_ATTR + 1] = color.g;
        self.colors[idx * NUM_COLOR_ATTR + 2] = color.b;
        self.colors[idx * NUM_COLOR_ATTR + 3] = color.a;

        return idx;
    }

    fn pushElem(self: *Renderer, vertIdx: usize) void {
        self.indices[self.indIdx] = @intCast(platform.GLushort, vertIdx);
        defer self.indIdx += 1;
    }

    fn pushFontElem(self: *Renderer, vertIdx: usize) void {
        self.font_indices[self.font_indIdx] = @intCast(platform.GLushort, vertIdx);
        defer self.font_indIdx += 1;
    }

    fn wouldOverflow(self: *Renderer, numVerts: usize, numInd: usize) bool {
        return (self.vertIdx + numVerts) * NUM_ATTR >= self.verts.len or self.indIdx + numInd >= self.indices.len;
    }

    pub fn pushRect(self: *Renderer, pos: Vec2f, size: Vec2f, color: RGBA, rot: f32) void {
        if (self.wouldOverflow(4, 6)) {
            self.flush();
        }

        const top_left = vec2f(-size.x / 2, -size.y / 2).rotate(rot).addv(pos);
        const top_right = vec2f(size.x / 2, -size.y / 2).rotate(rot).addv(pos);
        const bot_left = vec2f(-size.x / 2, size.y / 2).rotate(rot).addv(pos);
        const bot_right = vec2f(size.x / 2, size.y / 2).rotate(rot).addv(pos);

        const top_left_vert = self.pushVert(top_left, color);
        const top_right_vert = self.pushVert(top_right, color);
        const bot_left_vert = self.pushVert(bot_left, color);
        const bot_right_vert = self.pushVert(bot_right, color);

        self.pushElem(top_left_vert);
        self.pushElem(top_right_vert);
        self.pushElem(bot_right_vert);

        self.pushElem(top_left_vert);
        self.pushElem(bot_right_vert);
        self.pushElem(bot_left_vert);
    }

    pub fn pushFlatHexagon(self: *Renderer, pos: Vec2f, radius: f32, color: RGBA, radians: f32) void {
        if (self.wouldOverflow(6, 4 * 3)) {
            self.flush();
        }

        const hex_points = [6]Vec2f{
            Vec2f.init(radius, 0).rotate(radians + 0 * 60.0 * DEG_TO_RAD).addv(pos),
            Vec2f.init(radius, 0).rotate(radians + 1 * 60.0 * DEG_TO_RAD).addv(pos),
            Vec2f.init(radius, 0).rotate(radians + 2 * 60.0 * DEG_TO_RAD).addv(pos),
            Vec2f.init(radius, 0).rotate(radians + 3 * 60.0 * DEG_TO_RAD).addv(pos),
            Vec2f.init(radius, 0).rotate(radians + 4 * 60.0 * DEG_TO_RAD).addv(pos),
            Vec2f.init(radius, 0).rotate(radians + 5 * 60.0 * DEG_TO_RAD).addv(pos),
        };

        const hex_verts = [6]usize{
            self.pushVert(hex_points[0], color),
            self.pushVert(hex_points[1], color),
            self.pushVert(hex_points[2], color),
            self.pushVert(hex_points[3], color),
            self.pushVert(hex_points[4], color),
            self.pushVert(hex_points[5], color),
        };

        self.pushElem(hex_verts[0]);
        self.pushElem(hex_verts[1]);
        self.pushElem(hex_verts[2]);

        self.pushElem(hex_verts[0]);
        self.pushElem(hex_verts[2]);
        self.pushElem(hex_verts[3]);

        self.pushElem(hex_verts[0]);
        self.pushElem(hex_verts[3]);
        self.pushElem(hex_verts[4]);

        self.pushElem(hex_verts[0]);
        self.pushElem(hex_verts[4]);
        self.pushElem(hex_verts[5]);
    }

    pub fn pushTriangle(self: *Renderer, points: [3]Vec2f, color: RGBA) void {
        if (self.wouldOverflow(3, 3)) {
            self.flush();
        }

        const verts = [_]usize{
            self.pushVert(points[0], color),
            self.pushVert(points[1], color),
            self.pushVert(points[2], color),
        };

        self.pushElem(verts[0]);
        self.pushElem(verts[1]);
        self.pushElem(verts[2]);
    }

    pub fn begin(self: *Renderer) void {
        self.reset();
    }

    pub fn reset(self: *Renderer) void {
        self.vertIdx = 0;
        self.indIdx = 0;
    }

    pub fn flush(self: *Renderer) void {
        defer self.reset();

        platform.glUseProgram(self.shaderProgram);
        platform.glBindVertexArray(self.vao);

        platform.glUniformMatrix4fv(self.projectionMatrixUniformLocation, 1, platform.GL_FALSE, &self.projectionMatrix);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, self.vertIdx * NUM_ATTR * @sizeOf(f32)), &self.verts, platform.GL_DYNAMIC_DRAW);
        platform.glVertexAttribPointer(self.coordinatesLocation, NUM_ATTR, platform.GL_FLOAT, platform.GL_FALSE, 0, null);
        platform.glEnableVertexAttribArray(self.coordinatesLocation);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.colorBuffer);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, self.vertIdx * NUM_COLOR_ATTR * @sizeOf(u8)), &self.colors, platform.GL_DYNAMIC_DRAW);
        platform.glVertexAttribPointer(self.colorLocation, NUM_COLOR_ATTR, platform.GL_UNSIGNED_BYTE, platform.GL_TRUE, 0, null);
        platform.glEnableVertexAttribArray(self.colorLocation);

        platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        platform.glBufferData(platform.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.indIdx * @sizeOf(platform.GLushort)), &self.indices, platform.GL_DYNAMIC_DRAW);

        platform.glDrawElements(platform.GL_TRIANGLES, @intCast(u16, self.indIdx), platform.GL_UNSIGNED_SHORT, null);

        platform.glBindVertexArray(0);
    }
};
