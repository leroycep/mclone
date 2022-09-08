pub const World = @import("./world.zig").World;
pub const block = @import("./block.zig");
pub const chunk = @import("./chunk.zig");
pub const player = @import("./player.zig");
pub const protocol = @import("./protocol.zig");

comptime {
    _ = @import("./protocol.zig");
}
