//! Writes the framebuffer to a 24-bit BMP. Used by the --dump developer flag
//! to check the rendering without a display.

const std = @import("std");
const gfx = @import("gfx.zig");

/// `scale` repeats each pixel that many times, so the pixel art survives being
/// viewed at normal size.
pub fn writeBmp(io: std.Io, path: []const u8, fb: *const gfx.Framebuffer, scale: u32) !void {
    const width: usize = @as(usize, @intCast(fb.width)) * scale;
    const height: usize = @as(usize, @intCast(fb.height)) * scale;
    const row_bytes = (width * 3 + 3) & ~@as(usize, 3);
    const pixel_bytes = row_bytes * height;
    const header_size = 54;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.heap.page_allocator);

    var header: [header_size]u8 = [_]u8{0} ** header_size;
    header[0] = 'B';
    header[1] = 'M';
    std.mem.writeInt(u32, header[2..6], @intCast(header_size + pixel_bytes), .little);
    std.mem.writeInt(u32, header[10..14], header_size, .little);
    std.mem.writeInt(u32, header[14..18], 40, .little);
    std.mem.writeInt(i32, header[18..22], @intCast(width), .little);
    std.mem.writeInt(i32, header[22..26], @intCast(height), .little);
    std.mem.writeInt(u16, header[26..28], 1, .little);
    std.mem.writeInt(u16, header[28..30], 24, .little);
    std.mem.writeInt(u32, header[34..38], @intCast(pixel_bytes), .little);
    try out.appendSlice(std.heap.page_allocator, &header);

    const row = try std.heap.page_allocator.alloc(u8, row_bytes);
    defer std.heap.page_allocator.free(row);

    var y: usize = height;
    while (y > 0) {
        y -= 1;
        @memset(row, 0);
        for (0..width) |x| {
            const source = (y / scale) * @as(usize, @intCast(fb.width)) + x / scale;
            const color = fb.pixels[source];
            row[x * 3 + 0] = @intCast(color & 0xff);
            row[x * 3 + 1] = @intCast((color >> 8) & 0xff);
            row[x * 3 + 2] = @intCast((color >> 16) & 0xff);
        }
        try out.appendSlice(std.heap.page_allocator, row);
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}
