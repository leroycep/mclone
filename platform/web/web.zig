pub usingnamespace @import("./webgl_generated.zig");
pub const Renderer = @import("./renderer.zig").Renderer;
const std = @import("std");
const Vec2i = @import("math").Vec2i;

pub extern fn consoleLogS(_: [*]const u8, _: c_uint) void;
pub extern fn requestFullscreen() void;

pub extern fn now_f64() f64;

pub fn now() u64 {
    return @floatToInt(u64, now_f64());
}

pub fn getScreenSize() Vec2i {
    return Vec2i.init(getScreenW(), getScreenH());
}

const webGetScreenSize = getScreenSize;

pub const setShaderSource = glShaderSource;

pub fn renderPresent() void {}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    var buf: [1000]u8 = undefined;
    const text = std.fmt.bufPrint(buf[0..], fmt, args) catch {
        const message = "warn: bufPrint failed. too long? format string:";
        consoleLogS(message, message.len);
        consoleLogS(fmt.ptr, fmt.len);
        return;
    };
    consoleLogS(text.ptr, text.len);
}

pub const Context = struct {
    alloc: *std.mem.Allocator,
    running: bool = true,
    
    pub fn getScreenSize(self: @This()) Vec2i {
        return webGetScreenSize();
    }

    pub fn set_cursor(self: @This(), cursor_style: common.CursorStyle) void {
        canvas_setCursorStyle(switch (cursor_style) {
            .default => 0,
            .move => 1,
            .grabbing => 2,
        });
    }

    pub fn request_fullscreen(self: @This()) void {
        requestFullscreen();
    }
};


// TODO: Wrangle
const platform = @import("../platform.zig");
const builtin = @import("builtin");

export const SCANCODE_UNKNOWN = @enumToInt(platform.event.Scancode.UNKNOWN);
export const SCANCODE_ESCAPE = @enumToInt(platform.event.Scancode.ESCAPE);
export const SCANCODE_W = @enumToInt(platform.event.Scancode.W);
export const SCANCODE_A = @enumToInt(platform.event.Scancode.A);
export const SCANCODE_S = @enumToInt(platform.event.Scancode.S);
export const SCANCODE_D = @enumToInt(platform.event.Scancode.D);
export const SCANCODE_Z = @enumToInt(platform.event.Scancode.Z);
export const SCANCODE_R = @enumToInt(platform.event.Scancode.R);
export const SCANCODE_LEFT = @enumToInt(platform.event.Scancode.LEFT);
export const SCANCODE_RIGHT = @enumToInt(platform.event.Scancode.RIGHT);
export const SCANCODE_UP = @enumToInt(platform.event.Scancode.UP);
export const SCANCODE_DOWN = @enumToInt(platform.event.Scancode.DOWN);
export const SCANCODE_SPACE = @enumToInt(platform.event.Scancode.SPACE);
export const SCANCODE_BACKSPACE = @enumToInt(platform.event.Scancode.BACKSPACE);

export const KEYCODE_UNKNOWN = @enumToInt(platform.event.Keycode.UNKNOWN);
export const KEYCODE_BACKSPACE = @enumToInt(platform.event.Keycode.BACKSPACE);

export const MOUSE_BUTTON_LEFT = @enumToInt(platform.event.MouseButton.Left);
export const MOUSE_BUTTON_MIDDLE = @enumToInt(platform.event.MouseButton.Middle);
export const MOUSE_BUTTON_RIGHT = @enumToInt(platform.event.MouseButton.Right);
export const MOUSE_BUTTON_X1 = @enumToInt(platform.event.MouseButton.X1);
export const MOUSE_BUTTON_X2 = @enumToInt(platform.event.MouseButton.X2);

export const MAX_DELTA_SECONDS = constants.MAX_DELTA_SECONDS;
export const TICK_DELTA_SECONDS = constants.TICK_DELTA_SECONDS;

var context: platform.Context = undefined;

export fn onInit() void {
    const alloc = zee_alloc.ZeeAllocDefaults.wasm_allocator;
    context = platform.Context{
        .alloc = alloc,
        .renderer = platform.Renderer.init(),
    };
    app.onInit(&context);
}

export fn onMouseMove(x: i32, y: i32, buttons: u32) void {
    app.onEvent(&context, .{
        .MouseMotion = .{ .pos = Vec2i.init(x, y), .buttons = buttons },
    });
}

export fn onMouseButton(x: i32, y: i32, down: i32, button_int: u8) void {
    const event = platform.event.MouseButtonEvent{
        .pos = Vec2i.init(x, y),
        .button = @intToEnum(platform.event.MouseButton, button_int),
    };
    if (down == 0) {
        app.onEvent(&context, .{ .MouseButtonUp = event });
    } else {
        app.onEvent(&context, .{ .MouseButtonDown = event });
    }
}

export fn onMouseWheel(x: i32, y: i32) void {
    app.onEvent(&context, .{
        .MouseWheel = Vec2i.init(x, y),
    });
}

export fn onKeyDown(key: u16, scancode: u16) void {
    app.onEvent(&context, .{
        .KeyDown = .{
            .key = @intToEnum(platform.Keycode, key),
            .scancode = @intToEnum(platform.Scancode, scancode),
        },
    });
}

export fn onKeyUp(key: u16, scancode: u16) void {
    app.onEvent(&context, .{
        .KeyUp = .{
            .key = @intToEnum(platform.Keycode, key),
            .scancode = @intToEnum(platform.Scancode, scancode),
        },
    });
}

export const TEXT_INPUT_BUFFER: [32]u8 = undefined;
export fn onTextInput(len: u8) void {
    app.onEvent(&context, .{
        .TextInput = .{
            ._buf = TEXT_INPUT_BUFFER,
            .text = TEXT_INPUT_BUFFER[0..len],
        },
    });
}

export fn onResize() void {
    app.onEvent(&context, .{
        .ScreenResized = platform.getScreenSize(),
    });
}

export fn onCustomEvent(eventId: u32) void {
    app.onEvent(&context, .{
        .Custom = eventId,
    });
}

export fn update(current_time: f64, delta: f64) void {
    app.update(&context, current_time, delta);
}

export fn render(alpha: f64) void {
    app.render(&context, alpha);
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    platform.consoleLogS(msg.ptr, msg.len);
    //platform.warn("{}", .{error_return_trace});
    while (true) {
        @breakpoint();
    }
}
