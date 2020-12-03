const std = @import("std");
const math = @import("math");
const Vec2f = math.Vec2f;
const vec2f = math.vec2f;
const Vec3f = math.Vec3f;
const vec3f = math.vec3f;
const Chunk = @import("./core.zig").chunk.Chunk;

const MOVE_SPEED = 4.5;
const ACCEL_SPEED = 1.0;
const ACCEL_COEFFICIENT = 10.0;
const FRICTION_COEFFICIENT = 20.0;
const AIR_FRICTION = 1.0;
const FLOOR_FRICTION = 0.2;
const GRAVITY = 50.0;

pub const Input = struct {
    /// The direction the player is accelerating in
    accelDir: Vec2f,

    /// How fast does the player player want to be moving, from 0 (standing
    /// still) to 1 (max speed)
    maxVel: f32,

    jump: bool,
    crouch: bool,

    /// The angle that the player looking
    lookAngle: Vec2f,

    /// The block that the player is breaking
    breaking: ?math.Vec(3, i32),
};

pub const State = struct {
    position: Vec3f,
    velocity: Vec3f,
    lookAngle: Vec2f,

    pub fn update(this: *@This(), currentTime: f64, deltaTime: f64, input: Input, chunk: Chunk) void {
        this.lookAngle = input.lookAngle;

        const forward = vec3f(std.math.sin(this.lookAngle.x), 0, std.math.cos(this.lookAngle.x));
        const right = vec3f(-std.math.cos(this.lookAngle.x), 0, std.math.sin(this.lookAngle.x));
        const lookat = vec3f(std.math.sin(this.lookAngle.x) * std.math.cos(this.lookAngle.y), std.math.sin(this.lookAngle.y), std.math.cos(this.lookAngle.x) * std.math.cos(this.lookAngle.y));
        const up = vec3f(0, 1, 0);

        this.velocity.y += -GRAVITY * @floatCast(f32, deltaTime);

        var hvel = vec2f(this.velocity.x, this.velocity.z);

        const accelDir = if (input.accelDir.magnitude() > 0) calc_accelDir: {
            const inputAccelDir = input.accelDir.normalize();
            const absAccelDir = forward.scale(inputAccelDir.y).addv(right.scale(inputAccelDir.x));
            break :calc_accelDir vec2f(absAccelDir.x, absAccelDir.z);
        } else vec2f(0, 1);
        const maxVel = std.math.clamp(input.maxVel, 0, 1) * MOVE_SPEED;
        var accel = accelDir.scale(maxVel * ACCEL_COEFFICIENT * FLOOR_FRICTION * ACCEL_SPEED * @floatCast(f32, deltaTime));

        var fricVel = hvel.scale(FLOOR_FRICTION * FRICTION_COEFFICIENT * @floatCast(f32, deltaTime));

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

        var new_pos = this.position.addv(this.velocity.scale(@floatCast(f32, deltaTime)));

        //const collisionX = math.AABB(3, f32).init(new_pos, vec3f(1, 0.5, 0.5));
        //const collisionZ = math.AABB(3, f32).init(new_pos, vec3f(1, 0.5, 0.5));

        // Check for collisions with ground
        {
            const min_col_y = new_pos.sub(0.25, 1.5, 0.25).floatToInt(i32);
            const max_col_y = new_pos.add(0.25, 0.0, 0.25).floatToInt(i32);
            var rect_block_iter = chunk.iterateRect(min_col_y, max_col_y);
            var top_y: ?i32 = null;
            while (rect_block_iter.next()) |res| {
                if (res.block != .Air) {
                    top_y = std.math.max(res.pos.y, top_y orelse res.pos.y);
                }
            }
            if (top_y) |col_top_y| {
                // Calculate the top of the voxels they fell into
                var correction = @intToFloat(f32, col_top_y) + 2.5 - new_pos.y;
                // Don't move the player up more than they fell
                // TODO: Loosen this restriction so stairs work
                correction = std.math.clamp(correction, 0, this.position.y - new_pos.y);
                new_pos.y += correction;
                this.velocity.y = 0;
            }
        }
        // Check for collisions with ceiling
        {
            const min_col_y = new_pos.sub(0.25, 0.0, 0.25).floatToInt(i32);
            const max_col_y = new_pos.add(0.25, 0.5, 0.25).floatToInt(i32);
            var rect_block_iter = chunk.iterateRect(min_col_y, max_col_y);
            var bottom_y: ?i32 = null;
            while (rect_block_iter.next()) |res| {
                if (res.block != .Air) {
                    this.velocity.y = 0;
                    bottom_y = std.math.min(res.pos.y, bottom_y orelse res.pos.y);
                }
            }
            if (bottom_y) |col_bottom_y| {
                var correction = @intToFloat(f32, col_bottom_y) + 0.5 - new_pos.y;
                correction = std.math.clamp(correction, 0, new_pos.y - this.position.y);
                new_pos.y -= correction;
                this.velocity.y = 0;
            }
        }

        this.position = new_pos;
    }
};
