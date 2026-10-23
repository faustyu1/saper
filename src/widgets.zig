//! The reusable chrome: 3D borders, buttons, LED counters, text fields.

const std = @import("std");
const gfx = @import("gfx.zig");
const font = @import("font.zig");
const layout = @import("layout.zig");

pub const face = gfx.rgb(192, 192, 192);
pub const light = gfx.rgb(255, 255, 255);
pub const shadow = gfx.rgb(128, 128, 128);
pub const dark = gfx.rgb(0, 0, 0);
pub const text = gfx.rgb(0, 0, 0);
pub const highlight = gfx.rgb(0, 0, 128);
pub const highlight_text = gfx.rgb(255, 255, 255);
pub const led_on = gfx.rgb(255, 0, 0);
pub const led_off = gfx.rgb(42, 0, 0);
pub const led_bg = gfx.rgb(0, 0, 0);

pub fn raised(fb: *gfx.Framebuffer, r: gfx.Rect, thickness: i32) void {
    fb.bevel(r, thickness, light, shadow);
}

pub fn sunken(fb: *gfx.Framebuffer, r: gfx.Rect, thickness: i32) void {
    fb.bevel(r, thickness, shadow, light);
}

pub fn panel(fb: *gfx.Framebuffer, r: gfx.Rect, thickness: i32) void {
    fb.fill(r, face);
    raised(fb, r, thickness);
}

pub fn centerText(fb: *gfx.Framebuffer, r: gfx.Rect, label: []const u8, color: gfx.Color) void {
    const tw = font.textWidth(label);
    const x = r.x + @divTrunc(r.w - tw, 2);
    const y = r.y + @divTrunc(r.h - font.glyph_height, 2);
    font.drawText(fb, x, y, label, color);
}

pub fn button(fb: *gfx.Framebuffer, r: gfx.Rect, label: []const u8, pressed: bool) void {
    fb.fill(r, face);
    if (pressed) {
        sunken(fb, r, 1);
        centerText(fb, .{ .x = r.x + 1, .y = r.y + 1, .w = r.w, .h = r.h }, label, text);
    } else {
        raised(fb, r, 2);
        centerText(fb, r, label, text);
    }
}

/// Marks the default button with the extra dark outline Windows used.
pub fn defaultButton(fb: *gfx.Framebuffer, r: gfx.Rect, label: []const u8, pressed: bool) void {
    fb.frame(r, dark);
    button(fb, r.inset(1), label, pressed);
}

const Segments = packed struct {
    a: bool = false,
    b: bool = false,
    c: bool = false,
    d: bool = false,
    e: bool = false,
    f: bool = false,
    g: bool = false,
};

fn segmentsFor(ch: u8) Segments {
    return switch (ch) {
        '0' => .{ .a = true, .b = true, .c = true, .d = true, .e = true, .f = true },
        '1' => .{ .b = true, .c = true },
        '2' => .{ .a = true, .b = true, .g = true, .e = true, .d = true },
        '3' => .{ .a = true, .b = true, .g = true, .c = true, .d = true },
        '4' => .{ .f = true, .g = true, .b = true, .c = true },
        '5' => .{ .a = true, .f = true, .g = true, .c = true, .d = true },
        '6' => .{ .a = true, .f = true, .g = true, .e = true, .c = true, .d = true },
        '7' => .{ .a = true, .b = true, .c = true },
        '8' => .{ .a = true, .b = true, .c = true, .d = true, .e = true, .f = true, .g = true },
        '9' => .{ .a = true, .b = true, .c = true, .d = true, .f = true, .g = true },
        '-' => .{ .g = true },
        else => .{},
    };
}

fn segmentColor(lit: bool) gfx.Color {
    return if (lit) led_on else led_off;
}

/// One seven-segment digit, 11×21 pixels. Each segment is a three-pixel bar
/// with bevelled ends, so neighbouring segments meet on a diagonal and never
/// overlap; the two spare columns of the 13-pixel slot keep digits apart.
fn ledDigit(fb: *gfx.Framebuffer, x: i32, y: i32, ch: u8) void {
    const s = segmentsFor(ch);
    const on = [_]bool{ s.a, s.b, s.c, s.d, s.e, s.f, s.g };
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        // Horizontal bars: a (top), d (bottom), g (middle, tapering both ways).
        fb.fill(.{ .x = x + 1 + k, .y = y + k, .w = 9 - k * 2, .h = 1 }, segmentColor(on[0]));
        fb.fill(.{ .x = x + 1 + k, .y = y + 20 - k, .w = 9 - k * 2, .h = 1 }, segmentColor(on[3]));
        const gw: i32 = if (k == 1) 9 else 7;
        fb.fill(.{ .x = x + 1 + @divTrunc(9 - gw, 2), .y = y + 9 + k, .w = gw, .h = 1 }, segmentColor(on[6]));
        // Vertical bars: f, e on the left, b, c on the right.
        fb.fill(.{ .x = x + k, .y = y + 1 + k, .w = 1, .h = 9 - k * 2 }, segmentColor(on[5]));
        fb.fill(.{ .x = x + k, .y = y + 11 + k, .w = 1, .h = 9 - k * 2 }, segmentColor(on[4]));
        fb.fill(.{ .x = x + 10 - k, .y = y + 1 + k, .w = 1, .h = 9 - k * 2 }, segmentColor(on[1]));
        fb.fill(.{ .x = x + 10 - k, .y = y + 11 + k, .w = 1, .h = 9 - k * 2 }, segmentColor(on[2]));
    }
}

/// The three-digit red counter used for mines left and elapsed seconds.
pub fn ledCounter(fb: *gfx.Framebuffer, r: gfx.Rect, value: i32) void {
    fb.fill(r, led_bg);
    var buf: [8]u8 = undefined;
    const clamped = std.math.clamp(value, -99, 999);
    // Formatted as unsigned: a padded signed integer gets a leading '+'.
    const magnitude: u32 = @abs(clamped);
    const digits = if (clamped < 0)
        std.fmt.bufPrint(&buf, "-{d:0>2}", .{magnitude}) catch "000"
    else
        std.fmt.bufPrint(&buf, "{d:0>3}", .{magnitude}) catch "000";

    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        ledDigit(fb, r.x + 2 + i * layout.led_w, r.y + 2, digits[@intCast(i)]);
    }
}

pub fn checkMark(fb: *gfx.Framebuffer, x: i32, y: i32, color: gfx.Color) void {
    const points = [_][2]i32{
        .{ 0, 3 }, .{ 0, 4 }, .{ 1, 4 }, .{ 1, 5 }, .{ 2, 5 }, .{ 2, 6 },
        .{ 3, 5 }, .{ 3, 4 }, .{ 4, 3 }, .{ 4, 2 }, .{ 5, 1 }, .{ 5, 0 },
        .{ 6, 0 },
    };
    for (points) |p| {
        fb.set(x + p[0], y + p[1], color);
        fb.set(x + p[0], y + p[1] + 1, color);
    }
}

pub fn bullet(fb: *gfx.Framebuffer, x: i32, y: i32, color: gfx.Color) void {
    fb.fill(.{ .x = x + 1, .y = y, .w = 2, .h = 4 }, color);
    fb.fill(.{ .x = x, .y = y + 1, .w = 4, .h = 2 }, color);
}

/// A sunken white entry box. `caret` shows the insertion point when focused.
pub fn textField(fb: *gfx.Framebuffer, r: gfx.Rect, content: []const u8, focused: bool) void {
    fb.fill(r, light);
    sunken(fb, r, 1);
    fb.frame(r, shadow);
    const tx = r.x + 3;
    const ty = r.y + @divTrunc(r.h - font.glyph_height, 2);
    font.drawText(fb, tx, ty, content, text);
    if (focused) {
        const caret_x = tx + font.textWidth(content) + (if (content.len == 0) @as(i32, 0) else 1);
        fb.fill(.{ .x = caret_x, .y = ty - 1, .w = 1, .h = font.glyph_height + 2 }, text);
    }
}

/// Window-style title bar with the classic close box on the right.
pub fn titleBar(fb: *gfx.Framebuffer, r: gfx.Rect, title: []const u8) gfx.Rect {
    fb.fill(r, highlight);
    font.drawText(fb, r.x + 3, r.y + @divTrunc(r.h - font.glyph_height, 2), title, highlight_text);
    const close = gfx.Rect{ .x = r.x + r.w - 15, .y = r.y + 2, .w = 13, .h = r.h - 4 };
    fb.fill(close, face);
    raised(fb, close, 1);
    // The little "x".
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        fb.set(close.x + 4 + i, close.y + 3 + i, dark);
        fb.set(close.x + 8 - i, close.y + 3 + i, dark);
    }
    return close;
}

fn litAt(fb: *const gfx.Framebuffer, x: i32, y: i32) bool {
    return fb.pixels[@intCast(y * fb.width + x)] == led_on;
}

test "led counter shows every digit of three-digit values" {
    var fb = try gfx.Framebuffer.init(std.testing.allocator, layout.counter_w, layout.counter_h);
    defer fb.deinit();
    const r = gfx.Rect{ .x = 0, .y = 0, .w = layout.counter_w, .h = layout.counter_h };

    // 100: the leading "1" lights segment b of the first slot, and the
    // second slot is a "0", so its segment f is lit too.
    ledCounter(&fb, r, 100);
    try std.testing.expect(litAt(&fb, 2 + 10, 2 + 5));
    try std.testing.expect(litAt(&fb, 2 + layout.led_w, 2 + 5));

    // -5: minus in the first slot, a lit "0" in the second.
    ledCounter(&fb, r, -5);
    try std.testing.expect(litAt(&fb, 2 + 5, 2 + 10));
    try std.testing.expect(litAt(&fb, 2 + layout.led_w, 2 + 5));
}

test "led digits keep a gap between slots" {
    var fb = try gfx.Framebuffer.init(std.testing.allocator, layout.counter_w, layout.counter_h);
    defer fb.deinit();
    ledCounter(&fb, .{ .x = 0, .y = 0, .w = layout.counter_w, .h = layout.counter_h }, 888);
    var y: i32 = 0;
    while (y < layout.counter_h) : (y += 1) {
        try std.testing.expectEqual(led_bg, fb.pixels[@intCast(y * fb.width + 2 + 11)]);
        try std.testing.expectEqual(led_bg, fb.pixels[@intCast(y * fb.width + 2 + 12)]);
    }
}
