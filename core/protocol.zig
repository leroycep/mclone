const std = @import("std");
const core = @import("./core.zig");
const player = @import("./core.zig").player;
const bare = @import("bare");
const Allocator = std.mem.Allocator;
const math = @import("math");

// Export the reader and writer types that both sides will need
pub const Reader = bare.Reader;
pub const Writer = bare.Writer;

// Unreliable datagram/packet sent from the client to the server
pub const ClientDatagram = union(enum) {
    Update: struct {
        time: f64,
        input: player.Input,
    },
};

// Unreliable datagram/packet sent from the server to the client
pub const ServerDatagram = union(enum) {
    // TODO: Move this to reliable packet once that distinction exists
    Init: struct {
        /// The entity id for the client's player entity
        id: u64,
    },
    Update: struct {
        id: u64,
        time: f64,
        state: player.State,
    },
    // TODO: Move this to reliable packet once that distinction exists
    ChunkUpdate: struct {
        chunk: core.chunk.Chunk,
    },
};

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
                    if (n > 10000) {
                        std.log.err("Message claims to be {} bytes long", .{n});
                        return error.MessageIsToLong;
                    }
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
