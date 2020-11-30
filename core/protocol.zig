const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("./core.zig");
const Vec2i = @import("math").Vec2i;

pub const Frames = union(enum) {
    WaitingForSize: void,
    WaitingForData: struct {
        buffer: []u8,
        bytes_recevied: usize,
    },

    pub fn init() @This() {
        return @This(){ .WaitingForSize = {} };
    }

    pub fn update(this: *@This(), alloc: *Allocator, reader: anytype) !?[]u8 {
        while (true) {
            switch (this.*) {
                .WaitingForSize => {
                    const n = reader.readIntLittle(u32) catch |e| switch (e) {
                        error.WouldBlock => return null,
                        else => |other_err| return other_err,
                    };
                    this.* = .{
                        .WaitingForData = .{
                            .buffer = try alloc.alloc(u8, n),
                            .bytes_recevied = 0,
                        },
                    };
                },

                .WaitingForData => |*data| {
                    data.bytes_recevied += reader.read(data.buffer[data.bytes_recevied..]) catch |e| switch (e) {
                        error.WouldBlock => return null,
                        else => |other_err| return other_err,
                    };
                    if (data.bytes_recevied == data.buffer.len) {
                        const message = data.buffer;
                        this.* = .{ .WaitingForSize = {} };
                        return message;
                    }
                },
            }
        }
    }
};

// Packets from the server
pub const ServerPacketTag = enum(u8) {
    Init = 1,
    ErrorMessage = 2,
    BoardUpdate = 3,
    TurnChange = 4,
};

pub const ServerPacket = union(enum) {
    Init: struct {
        // The color the client will be
        color: core.piece.Piece.Color,
    },
    ErrorMessage: ServerError,
    BoardUpdate: core.Board.Serialized,
    TurnChange: core.piece.Piece.Color,

    pub fn stringify(this: @This(), writer: anytype) !void {
        try writer.writeAll(std.meta.tagName(this));
        try writer.writeAll(":");

        const Tag = @TagType(@This());

        inline for (std.meta.fields(Tag)) |field| {
            if (this == @field(Tag, field.name)) {
                try std.json.stringify(@field(this, field.name), .{}, writer);
                return;
            }
        }
    }

    pub fn parse(data: []const u8) !@This() {
        var split_iter = std.mem.split(data, ":");

        const tag = split_iter.next().?;
        const packet_data = split_iter.rest();

        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, field.name, tag)) {
                const parsed = try std.json.parse(field.field_type, &std.json.TokenStream.init(packet_data), .{});
                return @unionInit(@This(), field.name, parsed);
            }
        }

        return error.InvalidFormat;
    }
};

pub const ServerError = enum(u8) {
    IllegalMove = 1,

    pub fn jsonStringify(this: @This(), options: std.json.StringifyOptions, writer: anytype) !void {
        const text = switch (this) {
            .IllegalMove => "IllegalMove",
        };
        try std.json.stringify(text, options, writer);
    }
};

// Packets from the client
pub const ClientPacket = union(enum) {
    MovePiece: struct {
        startPos: Vec2i,
        endPos: Vec2i,
    },

    pub fn stringify(this: @This(), writer: anytype) !void {
        try writer.writeAll(std.meta.tagName(this));
        try writer.writeAll(":");

        const Tag = @TagType(@This());

        inline for (std.meta.fields(Tag)) |field| {
            if (this == @field(Tag, field.name)) {
                try std.json.stringify(@field(this, field.name), .{}, writer);
                return;
            }
        }
    }

    pub fn parse(data: []const u8) !@This() {
        var split_iter = std.mem.split(data, ":");

        const tag = split_iter.next().?;
        const packet_data = split_iter.rest();

        inline for (std.meta.fields(@This())) |field| {
            if (std.mem.eql(u8, field.name, tag)) {
                const parsed = try std.json.parse(field.field_type, &std.json.TokenStream.init(packet_data), .{});
                return @unionInit(@This(), field.name, parsed);
            }
        }

        return error.InvalidFormat;
    }
};

test "convert serverpacket to json" {
    var json = std.ArrayList(u8).init(std.testing.allocator);
    defer json.deinit();

    try (ServerPacket{ .Init = .{ .color = .Black } }).stringify(json.writer());

    std.testing.expectEqualSlices(u8,
        \\Init:{"color":"Black"}
    , json.items);
}

fn test_packet_JSON_roundtrip(data: anytype) !void {
    var json = std.ArrayList(u8).init(std.testing.allocator);
    defer json.deinit();

    try data.stringify(json.writer());
    const parsed = try @TypeOf(data).parse(json.items);

    std.testing.expectEqual(data, parsed);
}

test "serverpacket json stringify than parse" {
    try test_packet_JSON_roundtrip(ServerPacket{ .Init = .{ .color = .Black } });
    try test_packet_JSON_roundtrip(ServerPacket{ .ErrorMessage = .IllegalMove });
    try test_packet_JSON_roundtrip(ServerPacket{ .BoardUpdate = core.Board.init(null).serialize() });
    try test_packet_JSON_roundtrip(ServerPacket{ .BoardUpdate = core.Board.init(null).serialize() });
}

test "clientpacket json stringify than parse" {
    const vec2i = @import("util").vec2i;
    try test_packet_JSON_roundtrip(ClientPacket{ .MovePiece = .{ .startPos = vec2i(5, 6), .endPos = vec2i(5, 5) } });
}
