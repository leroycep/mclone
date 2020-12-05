const std = @import("std");
const Allocator = std.mem.Allocator;
const Mutex = std.mutex.Mutex;
const ArrayList = std.ArrayList;
const AutoHashMap = std.hash_map.AutoHashMap;
const Address = std.net.Address;
const NonblockingStreamServer = @import("./nonblocking_stream_server.zig").NonblockingStreamServer;
const core = @import("core");
const BlockType = core.chunk.BlockType;
const protocol = core.protocol;
const ClientDatagram = protocol.ClientDatagram;
const ServerDatagram = protocol.ServerDatagram;
const math = @import("math");

const MAX_CLIENTS = 2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    const localhost = try Address.parseIp("127.0.0.1", 5949);

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

    // Generate world
    var world = try core.World.init(alloc);
    try world.ensureChunkLoaded(math.Vec(3, i64).init(0, 0, 0));
    try world.ensureChunkLoaded(math.Vec(3, i64).init(1, 0, 0));
    try world.ensureChunkLoaded(math.Vec(3, i64).init(0, 0, 1));
    try world.ensureChunkLoaded(math.Vec(3, i64).init(1, 0, 1));
    try world.ensureChunkLoaded(math.Vec(3, i64).init(1, 1, 1));

    const max_players = 24;
    var num_players: usize = 0;

    var running = true;
    var next_id: u64 = 0;

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

                if (num_players >= max_players) {
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
                    .id = next_id,
                    .currentTime = 0,
                    .state = .{
                        .position = .{ .x = 1, .y = 14, .z = 1 },
                        .velocity = .{ .x = 0, .y = 0, .z = 0 },
                        .lookAngle = .{ .x = 0, .y = 0 },
                    },
                };
                next_id += 1;
                num_players += 1;

                try clients.put(new_connection.file.handle, client);

                try client.sendPacket(ServerDatagram{ .Init = .{ .id = client.id } });

                var chunk_iter = world.chunks.iterator();
                while (chunk_iter.next()) |chunk_entry| {
                    try client.sendPacket(ServerDatagram{
                        .ChunkUpdate = .{ .pos = chunk_entry.key, .chunk = chunk_entry.value },
                    });
                }
                broadcastPacket(alloc, &clients, ServerDatagram{
                    .Update = .{
                        .id = client.id,
                        .time = client.currentTime,
                        .state = client.state,
                    },
                });

                std.log.info("{} connected", .{new_connection.address});
            } else if (clients.getEntry(pollfd.fd)) |client_entry| {
                const client = &client_entry.value;
                if (client.handle()) |bare_data_opt| {
                    const bare_data = bare_data_opt orelse continue;
                    defer alloc.free(bare_data);

                    var fbs = std.io.fixedBufferStream(bare_data);

                    var reader = core.protocol.Reader.init(alloc);
                    defer reader.deinit();

                    const packet = reader.read(ClientDatagram, fbs.reader()) catch |err| switch (err) {
                        else => |other_err| return other_err,
                    };

                    handle_packet: {
                        switch (packet) {
                            .Update => |update| {
                                if (update.time < client.currentTime) {
                                    break :handle_packet;
                                }

                                const deltaTime = update.time - client.currentTime;

                                client.state.update(update.time, deltaTime, update.input, world);
                                client.currentTime = update.time;

                                broadcastPacket(alloc, &clients, ServerDatagram{
                                    .Update = .{
                                        .id = client.id,
                                        .time = client.currentTime,
                                        .state = client.state,
                                    },
                                });

                                if (update.input.breaking) |block_pos| {
                                    world.setv(block_pos, .Air);
                                    const chunk_pos = block_pos.scaleDivFloor(16);
                                    if (world.chunks.get(chunk_pos)) |chunk| {
                                        broadcastPacket(alloc, &clients, ServerDatagram{
                                            .ChunkUpdate = .{ .pos = chunk_pos, .chunk = chunk },
                                        });
                                    }
                                }

                                if (update.input.placing) |placing| {
                                    world.setv(placing.pos, placing.block);
                                    const chunk_pos = placing.pos.scaleDivFloor(16);
                                    if (world.chunks.get(chunk_pos)) |chunk| {
                                        broadcastPacket(alloc, &clients, ServerDatagram{
                                            .ChunkUpdate = .{ .pos = chunk_pos, .chunk = chunk },
                                        });
                                    }
                                }
                            },
                        }
                    }
                } else |err| switch (err) {
                    error.EndOfStream, error.ConnectionResetByPeer => {
                        disconnectClient(&pollfds, &clients, pollfd_idx);
                        num_players -= 1;
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
        client.value.send(message) catch |e| {
            std.log.warn("Error broadcasting to client: {}", .{e});
            continue;
        };
    }
}

fn broadcastPacket(alloc: *Allocator, clients: *AutoHashMap(std.os.fd_t, Client), data: anytype) void {
    var serialized = ArrayList(u8).init(alloc);
    defer serialized.deinit();

    core.protocol.Writer.init().write(data, serialized.writer()) catch return;

    broadcast(clients, serialized.items);
}

const Client = struct {
    alloc: *Allocator,
    connection: NonblockingStreamServer.Connection,
    frames: protocol.Frames = protocol.Frames.init(),

    id: u64,
    currentTime: f64,
    state: core.player.State,

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
        var serialized = ArrayList(u8).init(this.alloc);
        defer serialized.deinit();

        try core.protocol.Writer.init().write(data, serialized.writer());

        try this.send(serialized.items);
    }
};
