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
    var chunk = core.chunk.Chunk.init();
    chunk.layer(0, .Stone);
    chunk.layer(1, .Stone);
    chunk.layer(2, .Stone);
    chunk.layer(3, .Dirt);
    chunk.layer(4, .Dirt);
    chunk.layer(5, .Dirt);
    chunk.layer(6, .Grass);
    chunk.blk[0][1][0] = .IronOre;
    chunk.blk[0][2][0] = .CoalOre;
    chunk.blk[0][3][0] = .Air;

    chunk.blk[7][7][7] = .Wood;
    chunk.blk[7][8][7] = .Wood;
    chunk.blk[7][9][7] = .Wood;
    chunk.blk[7][10][7] = .Wood;
    chunk.blk[7][11][7] = .Wood;
    chunk.blk[7][12][7] = .Wood;
    chunk.blk[7][13][7] = .Wood;
    chunk.blk[7][14][7] = .Leaf;

    chunk.blk[8][10][7] = .Leaf;
    chunk.blk[8][11][7] = .Leaf;
    chunk.blk[8][12][7] = .Leaf;
    chunk.blk[8][13][7] = .Leaf;

    chunk.blk[6][10][7] = .Leaf;
    chunk.blk[6][11][7] = .Leaf;
    chunk.blk[6][12][7] = .Leaf;
    chunk.blk[6][13][7] = .Leaf;

    chunk.blk[7][10][8] = .Leaf;
    chunk.blk[7][11][8] = .Leaf;
    chunk.blk[7][12][8] = .Leaf;
    chunk.blk[7][13][8] = .Leaf;

    chunk.blk[7][10][6] = .Leaf;
    chunk.blk[7][11][6] = .Leaf;
    chunk.blk[7][12][6] = .Leaf;
    chunk.blk[7][13][6] = .Leaf;

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
                try client.sendPacket(ServerDatagram{
                    .ChunkUpdate = .{ .chunk = chunk },
                });
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

                                client.state.update(update.time, deltaTime, update.input, chunk);
                                client.currentTime = update.time;

                                broadcastPacket(alloc, &clients, ServerDatagram{
                                    .Update = .{
                                        .id = client.id,
                                        .time = client.currentTime,
                                        .state = client.state,
                                    },
                                });

                                if (update.input.breaking) |block_pos| {
                                    chunk.set(block_pos.x, block_pos.y, block_pos.z, .Air);
                                    broadcastPacket(alloc, &clients, ServerDatagram{
                                        .ChunkUpdate = .{ .chunk = chunk },
                                    });
                                }

                                if (update.input.placing) |placing| {
                                    chunk.set(placing.pos.x, placing.pos.y, placing.pos.z, placing.block);
                                    broadcastPacket(alloc, &clients, ServerDatagram{
                                        .ChunkUpdate = .{ .chunk = chunk },
                                    });
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
