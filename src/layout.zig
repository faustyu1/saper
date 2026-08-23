//! Window metrics. Every measurement is in logical pixels; the platform layer
//! multiplies by an integer scale factor when presenting.

const gfx = @import("gfx.zig");

pub const cell = 16;
pub const outer_bevel = 3;
pub const margin = 6;
pub const panel_bevel = 2;
pub const field_bevel = 3;
pub const header_inner_h = 30;
pub const menu_h = 19;

pub const led_w = 13;
pub const led_h = 23;
pub const counter_w = led_w * 3 + 2;
pub const counter_h = led_h + 2;
pub const face_size = 26;

pub const Layout = struct {
    width: i32,
    height: i32,
    menu_bar: gfx.Rect,
    /// Everything below the menu bar, carrying the outer raised border.
    body: gfx.Rect,
    header: gfx.Rect,
    header_inner: gfx.Rect,
    mine_counter: gfx.Rect,
    timer: gfx.Rect,
    face: gfx.Rect,
    /// Sunken frame around the minefield.
    field_frame: gfx.Rect,
    /// The minefield itself, cell (0,0) starts at its top-left corner.
    field: gfx.Rect,
    cols: i32,
    rows: i32,
};

pub fn compute(cols: i32, rows: i32) Layout {
    const panel_w = cols * cell + field_bevel * 2;
    const width = outer_bevel * 2 + margin * 2 + panel_w;
    const header_h = header_inner_h + panel_bevel * 2;

    const body_y = menu_h;
    const content_x = outer_bevel + margin;
    const header_y = body_y + outer_bevel + margin;
    const field_y = header_y + header_h + margin;
    const field_h = rows * cell + field_bevel * 2;
    const height = field_y + field_h + margin + outer_bevel;

    const header = gfx.Rect{ .x = content_x, .y = header_y, .w = panel_w, .h = header_h };
    const header_inner = header.inset(panel_bevel);

    const counter_y = header_inner.y + @divTrunc(header_inner.h - counter_h, 2);
    const mine_counter = gfx.Rect{
        .x = header_inner.x + 4,
        .y = counter_y,
        .w = counter_w,
        .h = counter_h,
    };
    const timer = gfx.Rect{
        .x = header_inner.x + header_inner.w - 4 - counter_w,
        .y = counter_y,
        .w = counter_w,
        .h = counter_h,
    };
    const face = gfx.Rect{
        .x = header_inner.x + @divTrunc(header_inner.w - face_size, 2),
        .y = header_inner.y + @divTrunc(header_inner.h - face_size, 2),
        .w = face_size,
        .h = face_size,
    };

    const field_frame = gfx.Rect{ .x = content_x, .y = field_y, .w = panel_w, .h = field_h };

    return .{
        .width = width,
        .height = height,
        .menu_bar = .{ .x = 0, .y = 0, .w = width, .h = menu_h },
        .body = .{ .x = 0, .y = body_y, .w = width, .h = height - body_y },
        .header = header,
        .header_inner = header_inner,
        .mine_counter = mine_counter,
        .timer = timer,
        .face = face,
        .field_frame = field_frame,
        .field = field_frame.inset(field_bevel),
        .cols = cols,
        .rows = rows,
    };
}

/// Converts a window position to a cell coordinate, or null if it is off-field.
pub fn cellAt(self: Layout, x: i32, y: i32) ?struct { x: i32, y: i32 } {
    if (!self.field.contains(x, y)) return null;
    return .{
        .x = @divTrunc(x - self.field.x, cell),
        .y = @divTrunc(y - self.field.y, cell),
    };
}
