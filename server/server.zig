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
const trace = @import("util").tracy.trace;

pub const enable_tracy = @import("build_options").enable_tracy;

const MAX_CLIENTS = 2;

pub fn main() !void {
    const tracy = trace(@src());
    defer tracy.end();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    const localhost = try Address.parseIp("0.0.0.0", 5949);

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
    try world.chunks.ensureCapacity(16 * 16 * 16);

    var pos = math.Vec(3, i64).init(0, 0, 0);
    while (pos.z < 16) {
        try world.ensureChunkLoaded(pos);

        pos.x += 1;
        if (pos.x > 16) {
            pos.x = 0;
            pos.y += 1;
            if (pos.y > 16) {
                pos.y = 0;
                pos.z += 1;
            }
        }
    }
    world.blocks_that_were_updated.clearRetainingCapacity();
    world.chunks_where_light_was_updated.clearRetainingCapacity();

    const max_players = 24;
    var num_players: usize = 0;

    var timer = try std.time.Timer.start();
    var tickTime: f64 = 0.0;
    var accumulator: f64 = 0.0;

    var running = true;
    var next_id: u64 = 0;

    while (running) {
        var poll_count = try std.os.poll(pollfds.items, -1);

        for (pollfds.items) |pollfd, pollfd_idx| {
            if (poll_count == 0) break;
            //std.log.debug("polls ready: {}", .{poll_count});

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
                        .position = .{ .x = 7 * 16 + 7, .y = 8 * 16, .z = 7 * 16 + 7 },
                        .velocity = .{ .x = 0, .y = 0, .z = 0 },
                        .lookAngle = .{ .x = 0, .y = 0 },
                    },
                };
                next_id += 1;
                num_players += 1;

                try clients.put(new_connection.file.handle, client);

                try client.sendPacket(ServerDatagram{ .Init = .{ .id = client.id } });

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
                            .RequestChunk => |chunk_request_pos| {
                                if (world.chunks.get(chunk_request_pos)) |chunk| {
                                    try client.sendPacket(ServerDatagram{
                                        .ChunkUpdate = .{ .pos = chunk_request_pos, .chunk = chunk },
                                    });
                                    std.log.debug("served chunk: {}", .{chunk_request_pos});
                                } else {
                                    try client.sendPacket(ServerDatagram{
                                        .EmptyChunk = chunk_request_pos,
                                    });
                                }
                            },
                            .Update => |update| {
                                if (update.time < client.currentTime) {
                                    break :handle_packet;
                                }

                                const deltaTime = update.time - client.currentTime;

                                const prev_player_chunk_pos = client.state.position.floatToInt(i64).scaleDivFloor(16);

                                client.state.update(update.time, deltaTime, update.input, &world);
                                client.currentTime = update.time;

                                broadcastPacket(alloc, &clients, ServerDatagram{
                                    .Update = .{
                                        .id = client.id,
                                        .time = client.currentTime,
                                        .state = client.state,
                                    },
                                });

                                if (update.input.breaking) |block_pos| {
                                    try world.setAndUpdatev(block_pos, .{ .blockType = .Air });
                                }

                                if (update.input.placing) |placing| {
                                    try world.setAndUpdatev(placing.pos, placing.block);
                                }

                                const num_updated = world.blocks_that_were_updated.items().len;
                                if (num_updated > 0) {
                                    var block_update_list = std.ArrayList(protocol.BlockUpdate).init(alloc);
                                    defer block_update_list.deinit();
                                    for (world.blocks_that_were_updated.items()) |entry| {
                                        //try world.fillSunlight(chunk_pos);
                                        try block_update_list.append(.{
                                            .pos = entry.key,
                                            .block = world.getv(entry.key),
                                        });
                                    }

                                    broadcastPacket(alloc, &clients, ServerDatagram{
                                        .BlockUpdate = block_update_list.items,
                                    });

                                    world.blocks_that_were_updated.clearRetainingCapacity();
                                }

                                const num_light_updated = world.chunks_where_light_was_updated.items().len;
                                if (num_light_updated > 0) {
                                    var light_update_list = std.ArrayList(protocol.LightUpdate).init(alloc);
                                    defer light_update_list.deinit();
                                    for (world.chunks_where_light_was_updated.items()) |chunk_pos_entry| {
                                        if (world.chunks.getEntry(chunk_pos_entry.key)) |chunk_entry| {
                                            try chunk_entry.value.getLightDiffs(chunk_pos_entry.key, &light_update_list);
                                        }
                                    }

                                    broadcastPacket(alloc, &clients, ServerDatagram{
                                        .LightUpdate = light_update_list.items,
                                    });

                                    world.chunks_where_light_was_updated.clearRetainingCapacity();
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

        const MAX_DELTA = 0.25;
        const TICK_DELTA = 50.0 / 1000.0;

        // Update the world if enough time has passed
        var delta = @intToFloat(f64, timer.lap()) / std.time.ns_per_s; // Delta in seconds
        if (delta > MAX_DELTA) {
            std.log.warn("delta was too great, reducing from {} to max {}", .{ delta, MAX_DELTA });
            delta = MAX_DELTA; // Try to avoid spiral of death when lag hits
        }

        accumulator += delta;

        while (accumulator >= TICK_DELTA) {
            try world.tick(tickTime, TICK_DELTA);
            accumulator -= TICK_DELTA;
            tickTime += TICK_DELTA;
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
