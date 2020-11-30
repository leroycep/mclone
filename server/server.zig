const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.mutex.Mutex;
const ArrayList = std.ArrayList;
const AutoHashMap = std.hash_map.AutoHashMap;
const Address = std.net.Address;
const NonblockingStreamServer = @import("./nonblocking_stream_server.zig").NonblockingStreamServer;
const core = @import("core");
const protocol = core.protocol;

const MAX_CLIENTS = 2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    const localhost = try Address.parseIp("127.0.0.1", 48836);

    var server = NonblockingStreamServer.init(.{ .reuse_address = true });
    defer server.deinit();

    try server.listen(localhost);
    std.log.info("listening on {}", .{server.listen_address});

    // Create client threads
    var clients = AutoHashMap(std.os.fd_t, Client).init(alloc);
    defer {
        var clients_iter = clients.iterator();
        while (clients_iter.next()) |client| {
            client.value.connection.file.close();
        }

        clients.deinit();
    }

    var pollfds = std.ArrayList(std.os.pollfd).init(alloc);
    defer pollfds.deinit();

    try pollfds.append(.{
        .fd = server.sockfd.?,
        .events = std.os.POLLIN,
        .revents = undefined,
    });

    var game = core.game.Game.init(alloc);

    var unassigned_colors = ArrayList(core.piece.Piece.Color).init(alloc);
    defer unassigned_colors.deinit();
    try unassigned_colors.append(.Black);
    try unassigned_colors.append(.White);

    var running = true;
    var next_id: u32 = 0;

    while (running) {
        var poll_count = try std.os.poll(pollfds.items, -1);

        for (pollfds.items) |pollfd, pollfd_idx| {
            if (poll_count == 0) break;

            if (pollfd.revents & std.os.POLLIN != std.os.POLLIN) continue;
            poll_count -= 1;

            if (pollfd.fd == server.sockfd.?) {
                var new_connection = server.accept() catch |e| switch (e) {
                    error.WouldBlock => continue,
                    else => |oe| return oe,
                };

                if (unassigned_colors.items.len == 0) {
                    new_connection.file.close();
                    continue;
                }

                try pollfds.append(.{
                    .fd = new_connection.file.handle,
                    .events = std.os.POLLIN,
                    .revents = undefined,
                });

                var client = Client{
                    .alloc = alloc,
                    .connection = new_connection,
                    .color = unassigned_colors.pop(),
                };
                try clients.put(new_connection.file.handle, client);

                try client.sendPacket(protocol.ServerPacket{ .Init = .{ .color = client.color } });
                try client.sendPacket(protocol.ServerPacket{ .BoardUpdate = game.board.serialize() });
                try client.sendPacket(protocol.ServerPacket{ .TurnChange = game.currentPlayer });

                std.log.info("{} connected", .{new_connection.address});
            } else if (clients.get(pollfd.fd)) |*client| {
                if (client.handle()) |json_data_opt| {
                    const json_data = json_data_opt orelse continue;
                    defer alloc.free(json_data);

                    std.log.debug("{}: {}", .{ client.connection.address, json_data });

                    const packet = core.protocol.ClientPacket.parse(json_data) catch |err| switch (err) {
                        else => |other_err| return other_err,
                    };

                    switch (packet) {
                        .MovePiece => |move_piece| {
                            try game.move(move_piece.startPos, move_piece.endPos);
                            broadcastPacket(alloc, &clients, protocol.ServerPacket{ .BoardUpdate = game.board.serialize() });
                            broadcastPacket(alloc, &clients, protocol.ServerPacket{ .TurnChange = game.currentPlayer });
                        },
                    }

                    std.log.debug("{} parsed: {}", .{ client.connection.address, packet });
                } else |err| switch (err) {
                    error.EndOfStream => {
                        disconnectClient(&pollfds, &clients, pollfd_idx);
                        try unassigned_colors.append(client.color);
                        break;
                    },
                    else => |other_err| return other_err,
                }
            }
        }
    }
}

fn disconnectClient(pollfds: *ArrayList(std.os.pollfd), clients: *AutoHashMap(std.os.fd_t, Client), pollfd_idx: usize) void {
    const client = clients.remove(pollfds.items[pollfd_idx].fd).?;
    client.value.connection.file.close();
    _ = pollfds.swapRemove(pollfd_idx);
    std.log.info("{} disconnected", .{client.value.connection.address});
}

fn broadcast(clients: *AutoHashMap(std.os.fd_t, Client), message: []const u8) void {
    var clients_iter = clients.iterator();
    while (clients_iter.next()) |client| {
        client.value.send(message) catch continue;
    }
}

fn broadcastPacket(alloc: *Allocator, clients: *AutoHashMap(std.os.fd_t, Client), data: anytype) void {
    var json = ArrayList(u8).init(alloc);
    defer json.deinit();
    data.stringify(json.writer()) catch return;

    broadcast(clients, json.items);
}

const Client = struct {
    alloc: *Allocator,
    connection: NonblockingStreamServer.Connection,
    frames: protocol.Frames = protocol.Frames.init(),
    color: core.piece.Piece.Color,

    pub fn handle(this: *@This()) !?[]u8 {
        const reader = this.connection.file.reader();
        return this.frames.update(this.alloc, reader);
    }

    pub fn send(this: *@This(), data: []const u8) !void {
        const writer = this.connection.file.writer();
        try writer.writeIntLittle(u32, @intCast(u32, data.len));
        _ = try writer.write(data);
    }

    pub fn sendPacket(this: *@This(), data: anytype) !void {
        var json = ArrayList(u8).init(this.alloc);
        defer json.deinit();
        try data.stringify(json.writer());

        try this.send(json.items);
    }
};
