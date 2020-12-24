const math = @import("math");
const BlockType = @import("core").block.BlockType;

pub const Input = struct {
    left: f64 = 0,
    right: f64 = 0,
    forward: f64 = 0,
    backward: f64 = 0,
    up: f64 = 0,
    down: f64 = 0,
    equipped_item: usize = 0,
    breaking: ?math.Vec(3, i64) = null,
    placing: ?struct {
        pos: math.Vec(3, i64),
        block: BlockType,
        data: u16 = 0,
    } = null,
};
