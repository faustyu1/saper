//! A tiny software renderer. Everything the game shows is rasterised into a
//! plain 32-bit framebuffer which each platform backend then presents.

const std = @import("std");

/// Pixels are 0x00RRGGBB. Every backend expects this exact layout.
pub const Color = u32;

pub inline fn rgb(r: u8, g: u8, b: u8) Color {
    return (@as(Color, r) << 16) | (@as(Color, g) << 8) | @as(Color, b);
}

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and py >= self.y and px < self.x + self.w and py < self.y + self.h;
    }

    pub fn inset(self: Rect, n: i32) Rect {
        return .{ .x = self.x + n, .y = self.y + n, .w = self.w - 2 * n, .h = self.h - 2 * n };
    }
};

pub const Framebuffer = struct {
    allocator: std.mem.Allocator,
    pixels: []Color,
    width: i32,
    height: i32,

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !Framebuffer {
        const count: usize = @intCast(width * height);
        const pixels = try allocator.alloc(Color, count);
        @memset(pixels, 0);
        return .{ .allocator = allocator, .pixels = pixels, .width = width, .height = height };
    }

    pub fn deinit(self: *Framebuffer) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn resize(self: *Framebuffer, width: i32, height: i32) !void {
        const count: usize = @intCast(width * height);
        if (count != self.pixels.len) {
            self.pixels = try self.allocator.realloc(self.pixels, count);
        }
        self.width = width;
        self.height = height;
    }

    pub fn clear(self: *Framebuffer, color: Color) void {
        @memset(self.pixels, color);
    }

    pub inline fn set(self: *Framebuffer, x: i32, y: i32, color: Color) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        self.pixels[@intCast(y * self.width + x)] = color;
    }

    pub fn fill(self: *Framebuffer, r: Rect, color: Color) void {
        const x0 = @max(r.x, 0);
        const y0 = @max(r.y, 0);
        const x1 = @min(r.x + r.w, self.width);
        const y1 = @min(r.y + r.h, self.height);
        if (x1 <= x0 or y1 <= y0) return;
        var y = y0;
        while (y < y1) : (y += 1) {
            const row_start: usize = @intCast(y * self.width + x0);
            const row_end: usize = @intCast(y * self.width + x1);
            @memset(self.pixels[row_start..row_end], color);
        }
    }

    pub fn hLine(self: *Framebuffer, x: i32, y: i32, len: i32, color: Color) void {
        self.fill(.{ .x = x, .y = y, .w = len, .h = 1 }, color);
    }

    pub fn vLine(self: *Framebuffer, x: i32, y: i32, len: i32, color: Color) void {
        self.fill(.{ .x = x, .y = y, .w = 1, .h = len }, color);
    }

    /// One-pixel rectangle outline.
    pub fn frame(self: *Framebuffer, r: Rect, color: Color) void {
        self.hLine(r.x, r.y, r.w, color);
        self.hLine(r.x, r.y + r.h - 1, r.w, color);
        self.vLine(r.x, r.y, r.h, color);
        self.vLine(r.x + r.w - 1, r.y, r.h, color);
    }

    /// The classic Windows 3D border: `thickness` nested L-shapes, light on the
    /// top-left and dark on the bottom-right (swap the colors for a sunken look).
    pub fn bevel(self: *Framebuffer, r: Rect, thickness: i32, light: Color, dark: Color) void {
        var i: i32 = 0;
        while (i < thickness) : (i += 1) {
            const top = r.y + i;
            const left = r.x + i;
            const bottom = r.y + r.h - 1 - i;
            const right = r.x + r.w - 1 - i;
            self.hLine(left, top, right - left + 1, light);
            self.vLine(left, top, bottom - top + 1, light);
            self.hLine(left + 1, bottom, right - left, dark);
            self.vLine(right, top + 1, bottom - top, dark);
        }
    }

    /// Draws a sprite stored as one byte per pixel indexing into `palette`.
    /// Index 0 is transparent.
    pub fn blitIndexed(
        self: *Framebuffer,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        data: []const u8,
        palette: []const Color,
    ) void {
        var sy: i32 = 0;
        while (sy < h) : (sy += 1) {
            var sx: i32 = 0;
            while (sx < w) : (sx += 1) {
                const index = data[@intCast(sy * w + sx)];
                if (index == 0) continue;
                self.set(x + sx, y + sy, palette[index]);
            }
        }
    }
};
