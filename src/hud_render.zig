const BitmapFontRenderer = @import("./font_render.zig").BitmapFontRenderer;
const FlatRenderer = @import("./flat_render.zig").FlatRenderer;
const std = @import("std");
const Texture = @import("./texture.zig").Texture;
const math = @import("math");
const Vec2f = math.Vec(2, f32);
const vec2f = Vec2f.init;
const platform = @import("platform");
const player = @import("core").player;
const Input = @import("./input.zig").Input;

pub const HudRenderer = struct {
    allocator: *std.mem.Allocator,
    itemBoxTexture: Texture,
    // itemTextures: []Texture,
    cursorTexture: Texture,
    flatRenderer: FlatRenderer,
    fontRenderer: BitmapFontRenderer,

    pub fn init(alloc: *std.mem.Allocator) !@This() {
        // var itemTextures =
        return @This(){
            .allocator = alloc,
            .itemBoxTexture = try Texture.initFromFile(alloc, "assets/item-box.png"),
            .cursorTexture = try Texture.initFromFile(alloc, "assets/cursor.png"),
            .flatRenderer = try FlatRenderer.init(alloc, vec2f(640, 480)),
            .fontRenderer = try BitmapFontRenderer.initFromFile(alloc, "assets/PressStart2P_8.fnt"),
        };
    }

    pub fn deinit(this: *@This()) void {
        this.flatRenderer.deinit();
        this.fontRenderer.deinit();
    }

    pub fn render(this: *@This(), context: *platform.Context, player_state: *player.State, input: *Input) !void {
        const screen_size = context.getScreenSize().intToFloat(f32);
        try this.flatRenderer.setSize(screen_size);
        const itemBoxSize = this.itemBoxTexture.size.intToFloat(f32).scale(2);
        const itemBoxGap = itemBoxSize.x + itemBoxSize.x / 10;
        const itemBoxGroupSize = itemBoxGap * 10;
        var i: usize = 0;
        var coords = vec2f(screen_size.x / 2 - itemBoxGroupSize / 2, screen_size.y - itemBoxSize.y - itemBoxSize.y / 10);
        while (i < 10) : (i += 1) {
            try this.flatRenderer.drawTexture(this.itemBoxTexture, coords, itemBoxSize);
            coords = coords.add(itemBoxGap, 0);
        }

        var text_buf: [1024]u8 = undefined;

        const pos_text = try std.fmt.bufPrint(&text_buf, "{d:.02}", .{player_state.position});
        try this.fontRenderer.drawText(&this.flatRenderer, pos_text, vec2f(30, 30), .{});

        if (player_state.inventory.getItem(input.equipped_item)) |item| {
            var count: usize = 0;
            if (player_state.inventory.stacks[input.equipped_item]) |inv| {
                count = inv.count;
            }
            const item_text = try std.fmt.bufPrint(&text_buf, "({}) {}", .{ count, std.meta.tagName(item) });
            try this.fontRenderer.drawText(&this.flatRenderer, item_text, vec2f(screen_size.x / 2, coords.y - 5), .{
                .textAlign = .Center,
                .textBaseline = .Bottom,
            });
        }

        const cursor_size = this.cursorTexture.size.intToFloat(f32).scale(1.1);
        const cursor_pos = screen_size.scaleDiv(2).subv(cursor_size.scaleDiv(2));
        try this.flatRenderer.drawTexture(this.cursorTexture, cursor_pos, cursor_size);

        this.flatRenderer.flush();
    }
};
