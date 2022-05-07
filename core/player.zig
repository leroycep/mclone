const std = @import("std");
const math = @import("math");
const Vec2f = math.Vec(2, f64);
const vec2f = Vec2f.init;
const Vec3f = math.Vec(3, f64);
const vec3f = Vec3f.init;
const core = @import("./core.zig");
const Block = @import("./core.zig").block.Block;
const BlockType = @import("./core.zig").block.BlockType;
const World = @import("./core.zig").World;

const MOVE_SPEED = 4.5;
const ACCEL_SPEED = 2.0;
const ACCEL_COEFFICIENT = 10.0;
const FRICTION_COEFFICIENT = 20.0;
const AIR_FRICTION = 0.2;
const FLOOR_FRICTION = 0.8;
const GRAVITY = 40.0;
const JUMP_VEL = 10.0;

pub const Input = struct {
    /// The direction the player is accelerating in
    accelDir: Vec2f,

    /// How fast does the player player want to be moving, from 0 (standing
    /// still) to 1 (max speed)
    maxVel: f64,

    jump: bool,
    crouch: bool,

    /// The angle that the player looking
    lookAngle: Vec2f,

    /// The currently equipped item
    equipped_item: usize,

    /// The block that the player is breaking
    breaking: ?math.Vec(3, i64),

    /// Where the player is placing
    placing: ?struct {
        pos: math.Vec(3, i64),
        block: Block,
    },
};

const Stack = struct {
    blockType: BlockType,
    count: usize,
};

pub fn Inventory(comptime size: usize) type {
    return struct {
        stacks: [size]?Stack,

        pub fn init() @This() {
            var stacks: [size]?Stack = undefined;
            stacks[0] = Stack{
                .blockType = .Stone,
                .count = 64,
            };
            var i: usize = 1;
            while (i < size) : (i += 1) {
                stacks[i] = null;
            }
            return @This(){
                .stacks = stacks,
            };
        }

        pub fn getItem(this: *@This(), index: usize) ?BlockType {
            if (this.stacks[index]) |stack| {
                return stack.blockType;
            }
            return null;
        }

        pub fn removeStackAtIndex(this: *@This(), index: usize) ?Stack {
            if (this.stacks[index]) |stack| {
                this.stacks[index] = null;
                return stack;
            }
            return null;
        }

        pub fn removeCountAtIndex(this: *@This(), index: usize, count: usize) ?Stack {
            if (this.stacks[index]) |stack| {
                if (stack.count >= count) {
                    var new_stack = Stack{ .blockType = stack.blockType, .count = stack.count - count };
                    if (new_stack.count == 0) {
                        this.stacks[index] = null;
                    } else {
                        this.stacks[index] = new_stack;
                    }
                    return Stack{
                        .blockType = stack.blockType,
                        .count = count,
                    };
                }
            }
            return null;
        }

        pub fn insertStack(this: *@This(), insstack: Stack) ?Stack {
            var available: ?usize = null;
            var istack = insstack;
            for (this.stacks) |stackOpt, i| {
                if (stackOpt == null) {
                    if (available == null) available = i;
                }
                if (stackOpt) |stack| {
                    var new_stack = Stack{ .blockType = stack.blockType, .count = stack.count };
                    defer this.stacks[i] = new_stack;
                    if (stack.blockType == istack.blockType) {
                        if (stack.count + istack.count < 64) {
                            new_stack.count += istack.count;
                            return null;
                        } else if (stack.count < 64) {
                            var count = 64 - stack.count;
                            new_stack.count = 64;
                            istack.count -= count;
                        }
                    }
                }
            }

            if (available) |i| {
                this.stacks[i] = istack;
                return null;
            } else {
                return istack;
            }
        }
    };
}

pub const State = struct {
    position: Vec3f,
    velocity: Vec3f,
    lookAngle: Vec2f,
    onGround: bool = false,
    inventory: Inventory(40),

    pub fn update(this: *@This(), currentTime: f64, deltaTime: f64, input: Input, world: *World) void {
        _ = currentTime;
        this.lookAngle = input.lookAngle;

        const forward = vec3f(@sin(this.lookAngle.x), 0, @cos(this.lookAngle.x));
        const right = vec3f(-@cos(this.lookAngle.x), 0, @sin(this.lookAngle.x));
        // const lookat = vec3f(@sin(this.lookAngle.x) * @cos(this.lookAngle.y), @sin(this.lookAngle.y), @cos(this.lookAngle.x) * @cos(this.lookAngle.y));
        // const up = vec3f(0, 1, 0);

        this.velocity.y += -GRAVITY * deltaTime;
        if (this.onGround and input.jump) {
            this.velocity.y = JUMP_VEL;
            this.onGround = false;
        }

        const fric = if (this.onGround) @as(f64, FLOOR_FRICTION) else AIR_FRICTION;

        var hvel = vec2f(this.velocity.x, this.velocity.z);

        const accelDir = if (input.accelDir.magnitude() > 0) calc_accelDir: {
            const inputAccelDir = input.accelDir.normalize();
            const absAccelDir = forward.scale(inputAccelDir.y).addv(right.scale(inputAccelDir.x));
            break :calc_accelDir vec2f(absAccelDir.x, absAccelDir.z);
        } else vec2f(0, 1);
        const maxVel = std.math.clamp(input.maxVel, 0, 1) * MOVE_SPEED;
        var accel = accelDir.scale(maxVel * ACCEL_COEFFICIENT * fric * ACCEL_SPEED * deltaTime);

        var fricVel = hvel.scale(fric * FRICTION_COEFFICIENT * deltaTime);

        var speed = hvel.magnitude();
        if (speed <= maxVel) {
            // Remove friction from forward movement as long as the player is moving below max speed
            const dot = accelDir.dotv(fricVel);
            if (dot >= 0) {
                fricVel = fricVel.subv(accelDir.scale(dot));
            }
        }

        this.velocity.x += accel.x;
        this.velocity.z += accel.y;

        hvel = vec2f(this.velocity.x, this.velocity.z);
        if (hvel.magnitude() > std.math.max(speed, maxVel)) {
            hvel = hvel.normalize().scale(std.math.max(speed, maxVel));
            this.velocity.x = hvel.x;
            this.velocity.z = hvel.y;
        }

        this.velocity.x -= fricVel.x;
        this.velocity.z -= fricVel.y;

        var new_pos = this.position.addv(this.velocity.scale(deltaTime));

        // Check for horizontal collisions
        {
            const min_col_x = new_pos.sub(0.5, 0.5, 0.25).floatToInt(i64);
            const max_col_x = new_pos.add(0.0, 0.25, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_x, max_col_x);
            var top_x: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    top_x = std.math.max(res.pos.x, top_x orelse res.pos.x);
                }
            }
            if (top_x) |col_top_x| {
                // Calculate the top of the voxels they fell into
                var correction = @intToFloat(f64, col_top_x) + 1.5 - new_pos.x;
                correction = std.math.max(0, std.math.min(correction, this.position.x - new_pos.x));
                new_pos.x += correction;
                this.velocity.x = 0;
            }
        }
        {
            const min_col_x = new_pos.sub(0.0, 0.5, 0.25).floatToInt(i64);
            const max_col_x = new_pos.add(0.5, 0.25, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_x, max_col_x);
            var bottom_x: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    bottom_x = std.math.min(res.pos.x, bottom_x orelse res.pos.x);
                }
            }
            if (bottom_x) |col_bottom_x| {
                var correction = @intToFloat(f64, col_bottom_x) + 1.5 - new_pos.x;
                correction = std.math.max(0, std.math.min(correction, new_pos.x - this.position.x));
                new_pos.x -= correction;
                this.velocity.x = 0;
            }
        }
        {
            const min_col_z = new_pos.sub(0.5, 0.5, 0.25).floatToInt(i64);
            const max_col_z = new_pos.add(0.0, 0.25, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_z, max_col_z);
            var top_z: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    top_z = std.math.max(res.pos.z, top_z orelse res.pos.z);
                }
            }
            if (top_z) |col_top_z| {
                // Calculate the top of the voxels they fell into
                var correction = @intToFloat(f64, col_top_z) + 1.5 - new_pos.z;
                correction = std.math.max(0, std.math.min(correction, this.position.z - new_pos.z));
                new_pos.z += correction;
                this.velocity.z = 0;
            }
        }
        {
            const min_col_z = new_pos.sub(0.0, 0.5, 0.25).floatToInt(i64);
            const max_col_z = new_pos.add(0.5, 0.25, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_z, max_col_z);
            var bottom_z: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    bottom_z = std.math.min(res.pos.z, bottom_z orelse res.pos.z);
                }
            }
            if (bottom_z) |col_bottom_z| {
                var correction = @intToFloat(f64, col_bottom_z) + 1.5 - new_pos.z;
                correction = std.math.max(0, std.math.min(correction, new_pos.z - this.position.z));
                new_pos.z -= correction;
                this.velocity.z = 0;
            }
        }

        // Check for collisions with ground
        {
            this.onGround = false;
            const min_col_y = new_pos.sub(0.25, 1.5, 0.25).floatToInt(i64);
            const max_col_y = new_pos.add(0.25, 0.0, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_y, max_col_y);
            var top_y: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    top_y = std.math.max(res.pos.y, top_y orelse res.pos.y);
                }
            }
            if (top_y) |col_top_y| {
                // Calculate the top of the voxels they fell into
                var correction = @intToFloat(f64, col_top_y) + 2.5 - new_pos.y;
                // Don't move the player up more than they fell
                // TODO: Loosen this restriction so stairs work
                correction = std.math.max(0, std.math.min(correction, this.position.y - new_pos.y));
                new_pos.y += correction;
                this.velocity.y = 0;
                this.onGround = true;
            }
        }
        // Check for collisions with ceiling
        {
            const min_col_y = new_pos.sub(0.25, 0.0, 0.25).floatToInt(i64);
            const max_col_y = new_pos.add(0.25, 0.5, 0.25).floatToInt(i64);
            var rect_block_iter = world.iterateRect(min_col_y, max_col_y);
            var bottom_y: ?i64 = null;
            while (rect_block_iter.next()) |res| {
                if (core.block.describe(res.block).isSolid(world, res.pos)) {
                    bottom_y = std.math.min(res.pos.y, bottom_y orelse res.pos.y);
                }
            }
            if (bottom_y) |col_bottom_y| {
                var correction = @intToFloat(f64, col_bottom_y) + 0.5 - new_pos.y;
                correction = std.math.max(0, std.math.min(correction, new_pos.y - this.position.y));
                new_pos.y -= correction;
                this.velocity.y = 0;
            }
        }

        this.position = new_pos;
    }
};
