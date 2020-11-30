const std = @import("std");
const util = @import("./util.zig");
const math = @import("math");
const vec3f = math.vec3f;

pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn from_u32(color_code: u32) @This() {
        return .{
            .r = @intCast(u8, (color_code & 0xFF000000) >> 24),
            .g = @intCast(u8, (color_code & 0x00FF0000) >> 16),
            .b = @intCast(u8, (color_code & 0x0000FF00) >> 8),
            .a = @intCast(u8, (color_code & 0x000000FF)),
        };
    }

    pub fn withAlpha(this: @This(), a: u8) @This() {
        return @This(){
            .r = this.r,
            .g = this.g,
            .b = this.b,
            .a = a,
        };
    }
};

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn from_u24(color_code: u24) @This() {
        return .{
            .r = @truncate(u8, color_code >> 16),
            .g = @truncate(u8, color_code >> 8),
            .b = @truncate(u8, color_code),
        };
    }
    pub fn from_hsluv(h: f32, s: f32, l: f32) @This() {
        return HSLuv.init(h, s, l).toHCL().toLUV().toXYZ().toRGB();
    }

    pub fn withAlpha(this: @This(), a: u8) RGBA {
        return RGBA{
            .r = this.r,
            .g = this.g,
            .b = this.b,
            .a = a,
        };
    }
};

const KAPPA = 903.29629629629629629630;
const EPSILON = 0.00885645167903563082;
const M = [3]math.Vec3f{
    vec3f(3.24096994190452134377, -1.53738317757009345794, -0.49861076029300328366),
    vec3f(-0.96924363628087982613, 1.87596750150772066772, 0.04155505740717561247),
    vec3f(0.05563007969699360846, -0.20397695888897656435, 1.05697151424287856072),
};

pub const HSLuv = struct {
    hue: f32,
    saturation: f32,
    lightness: f32,

    pub fn init(h: f32, s: f32, l: f32) @This() {
        return .{
            .hue = h,
            .saturation = s,
            .lightness = l,
        };
    }

    pub fn toHCL(this: @This()) HCL {
        return HCL{
            .hue = if (this.saturation < 0.00000001) 0 else this.hue,
            .chroma = if (this.lightness > 99.999999 or this.lightness < 0.00000001)
                0.0
            else
                this.max_chroma_for_hl() / 100.0 * this.saturation,
            .luminance = this.lightness,
        };
    }

    fn max_chroma_for_hl(this: @This()) f32 {
        const hrad = this.hue * std.math.tau / 360;

        var bounds_list = get_bounds(this.lightness);
        var min_len: f32 = 1e37;
        for (bounds_list) |bounds| {
            const len = ray_length_until_intersect(hrad, bounds);

            if (len >= 0 and len < min_len) min_len = len;
        }

        return min_len;
    }

    const Bounds = struct {
        a: f32,
        b: f32,
    };

    fn get_bounds(l: f32) [6]Bounds {
        var res: [6]Bounds = undefined;

        const tl = l + 16;
        const sub1 = (tl * tl * tl) / 1560896.0;
        const sub2 = if (sub1 > EPSILON) sub1 else l / KAPPA;

        var channel: usize = 0;
        while (channel < 3) : (channel += 1) {
            const m1 = M[channel].x;
            const m2 = M[channel].y;
            const m3 = M[channel].z;

            var t: usize = 0;
            while (t < 2) : (t += 1) {
                const top1 = (284517.0 * m1 - 94839 * m3) * sub2;
                const top2 = (838422.0 * m3 + 769860.0 * m2 + 731718.0 * m1) * l * sub2 - 769860.0 * @intToFloat(f32, t) * l;
                const bottom = (632260.0 * m3 - 126452.0 * m2) * sub2 + 126452.0 * @intToFloat(f32, t);

                res[channel * 2 + t].a = top1 / bottom;
                res[channel * 2 + t].b = top2 / bottom;
            }
        }

        return res;
    }

    fn ray_length_until_intersect(theta: f32, line: Bounds) f32 {
        return line.b / (std.math.sin(theta) - line.a * std.math.cos(theta));
    }
};

pub const HCL = struct {
    hue: f32,
    chroma: f32,
    luminance: f32,

    pub fn toLUV(this: @This()) LUV {
        const hrad = this.hue * (std.math.pi / 180.0);
        return LUV{
            .l = this.luminance,
            .u = std.math.cos(hrad) * this.chroma,
            .v = std.math.sin(hrad) * this.chroma,
        };
    }
};

pub const LUV = struct {
    l: f32,
    u: f32,
    v: f32,

    pub fn toXYZ(this: @This()) XYZ {
        if (this.l <= 0.00000001) {
            return XYZ{
                .x = 0,
                .y = 0,
                .z = 0,
            };
        }

        const ref_u = 0.19783000664283680764;
        const ref_v = 0.46831999493879100370;

        const var_u = this.u / (13.0 * this.l) + ref_u;
        const var_v = this.v / (13.0 * this.l) + ref_v;

        const y = l2y(this.l);
        const x = -(9 * y * var_u) / ((var_u - 4) * var_v - var_u * var_v);
        const z = (9 * y - (15 * var_v * y) - (var_v * x)) / (3.0 * var_v);

        return XYZ{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    fn l2y(l: f32) f32 {
        if (l <= 8.0) {
            return l / KAPPA;
        } else {
            const x = (l + 16) / 116;
            return x * x * x;
        }
    }
};

pub const XYZ = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn toRGB(this: @This()) RGB {
        const vec = math.vec3f(this.x, this.y, this.z);
        return RGB{
            .r = @floatToInt(u8, from_linear(M[0].dotv(vec)) * 255),
            .g = @floatToInt(u8, from_linear(M[1].dotv(vec)) * 255),
            .b = @floatToInt(u8, from_linear(M[2].dotv(vec)) * 255),
        };
    }

    fn from_linear(c: f32) f32 {
        if (c <= 0.0031308) {
            return 12.92 * c;
        } else {
            return 1.055 * std.math.pow(f32, c, 1 / 2.4) - 0.055;
        }
    }
};
