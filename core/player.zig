const std = @import("std");
const math = @import("math");
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;
const vec3f = math.vec3f;

const MOVE_SPEED = 10;

pub const Input = struct {
    // left/right and forward/back
    move: Vec2f,
    jump: bool,
    crouch: bool,
    /// The angle that the player looking
    lookAngle: Vec2f,
};

pub const State = struct {
    position: Vec3f,
    lookAngle: Vec2f,

    pub fn update(this: *@This(), currentTime: f64, deltaTime: f64, input: Input) void {
        this.lookAngle = input.lookAngle;

        const speed = std.math.clamp(input.move.magnitude(), 0, 1);
        const move = input.move.normalize().scale(MOVE_SPEED * speed * @floatCast(f32, deltaTime));

        var vertical_move: f32 = 0;
        if (input.jump) vertical_move += MOVE_SPEED * @floatCast(f32, deltaTime);
        if (input.crouch) vertical_move -= MOVE_SPEED * @floatCast(f32, deltaTime);
        
        const forward = vec3f(std.math.sin(this.lookAngle.x), 0, std.math.cos(this.lookAngle.x));
        const right = vec3f(-std.math.cos(this.lookAngle.x), 0, std.math.sin(this.lookAngle.x));
        const lookat = vec3f(std.math.sin(this.lookAngle.x) * std.math.cos(this.lookAngle.y), std.math.sin(this.lookAngle.y), std.math.cos(this.lookAngle.x) * std.math.cos(this.lookAngle.y));
        const up = vec3f(0, 1, 0);

        this.position = this.position.addv(forward.scale(move.y));
        this.position = this.position.addv(right.scale(move.x));
        this.position = this.position.addv(up.scale(vertical_move));
    }
};
