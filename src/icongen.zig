//! Draws the application icon at every size macOS and Windows ask for.
//! Run with `zig build icon`; the PNGs land in assets/.

const std = @import("std");
const png = @import("png.zig");
const sprites = @import("sprites.zig");

const sizes = [_]u32{ 16, 32, 64, 128, 256, 512, 1024 };

fn argb(a: u32, r: u32, g: u32, b: u32) u32 {
    return (a << 24) | (r << 16) | (g << 8) | b;
}

fn lerp(from: u32, to: u32, t: f32) u32 {
    const f: f32 = @floatFromInt(from);
    return @intFromFloat(f + (@as(f32, @floatFromInt(to)) - f) * t);
}

/// Signed distance to a rounded square, negative inside.
fn roundedRect(x: f32, y: f32, half: f32, radius: f32) f32 {
    const dx = @abs(x) - (half - radius);
    const dy = @abs(y) - (half - radius);
    const ox = @max(dx, 0.0);
    const oy = @max(dy, 0.0);
    return @sqrt(ox * ox + oy * oy) + @min(@max(dx, dy), 0.0) - radius;
}

fn blend(dest: u32, src_r: u32, src_g: u32, src_b: u32, alpha: f32) u32 {
    if (alpha <= 0.0) return dest;
    const da: f32 = @floatFromInt((dest >> 24) & 0xff);
    const dr: f32 = @floatFromInt((dest >> 16) & 0xff);
    const dg: f32 = @floatFromInt((dest >> 8) & 0xff);
    const db: f32 = @floatFromInt(dest & 0xff);
    const a = @min(alpha, 1.0);
    return argb(
        @intFromFloat(@min(255.0, da + (255.0 - da) * a)),
        @intFromFloat(dr + (@as(f32, @floatFromInt(src_r)) - dr) * a),
        @intFromFloat(dg + (@as(f32, @floatFromInt(src_g)) - dg) * a),
        @intFromFloat(db + (@as(f32, @floatFromInt(src_b)) - db) * a),
    );
}

fn render(gpa: std.mem.Allocator, size: u32) ![]u32 {
    const pixels = try gpa.alloc(u32, size * size);
    @memset(pixels, 0);

    const n: f32 = @floatFromInt(size);
    const half = n / 2.0;
    const radius = n * 0.2237; // matches the macOS app icon corner
    const samples = 4;

    // Body: a rounded square in the classic control grey, lit from the top
    // left with the same 3D bevel the game draws on every covered cell.
    const bevel = n * 0.06;
    const inner_half = half - n * 0.02;
    for (0..size) |py| {
        for (0..size) |px| {
            var coverage: f32 = 0;
            var depth: f32 = 0;
            for (0..samples) |sy| {
                for (0..samples) |sx| {
                    const fx = @as(f32, @floatFromInt(px)) + (@as(f32, @floatFromInt(sx)) + 0.5) / samples - half;
                    const fy = @as(f32, @floatFromInt(py)) + (@as(f32, @floatFromInt(sy)) + 0.5) / samples - half;
                    const d = roundedRect(fx, fy, inner_half, radius);
                    if (d <= 0) {
                        coverage += 1;
                        depth += -d;
                    }
                }
            }
            const total: f32 = samples * samples;
            if (coverage == 0) continue;

            const t = @as(f32, @floatFromInt(py)) / n;
            const base = pixels[py * size + px];
            var color = blend(
                base,
                lerp(0xCE, 0xAE, t),
                lerp(0xCE, 0xAE, t),
                lerp(0xCA, 0xAA, t),
                coverage / total,
            );

            // Distance from the edge, and the direction the edge faces.
            const fx = @as(f32, @floatFromInt(px)) + 0.5 - half;
            const fy = @as(f32, @floatFromInt(py)) + 0.5 - half;
            const edge = depth / coverage;
            if (edge < bevel) {
                const nx = roundedRect(fx + 1, fy, inner_half, radius) - roundedRect(fx - 1, fy, inner_half, radius);
                const ny = roundedRect(fx, fy + 1, inner_half, radius) - roundedRect(fx, fy - 1, inner_half, radius);
                const facing = -(nx + ny); // positive when the edge faces the light
                const strength = (1.0 - edge / bevel) * (coverage / total);
                if (facing > 0) {
                    color = blend(color, 0xff, 0xff, 0xff, strength * 0.85);
                } else {
                    color = blend(color, 0x6E, 0x6E, 0x6E, strength * 0.75);
                }
            }
            pixels[py * size + px] = color;
        }
    }

    // The classic flag, drawn from the in-game sprite so the icon and the board
    // always agree. Its bounding box inside the 16x16 tile is x 4..12, y 2..11.
    const box_x = 4;
    const box_y = 2;
    const box_w = 9;
    const box_h = 10;
    const scale: i32 = @max(1, @as(i32, @intFromFloat(@round(n * 0.055))));
    const flag_w = box_w * scale;
    const flag_h = box_h * scale;
    const origin_x = @divTrunc(@as(i32, @intCast(size)) - flag_w, 2);
    const origin_y = @divTrunc(@as(i32, @intCast(size)) - flag_h, 2);
    const shadow: i32 = @max(1, @divTrunc(scale, 3));

    for (0..2) |pass| {
        var sy: i32 = 0;
        while (sy < box_h) : (sy += 1) {
            var sx: i32 = 0;
            while (sx < box_w) : (sx += 1) {
                const index = sprites.flag[@intCast((sy + box_y) * 16 + sx + box_x)];
                if (index == 0) continue;
                var dy: i32 = 0;
                while (dy < scale) : (dy += 1) {
                    var dx: i32 = 0;
                    while (dx < scale) : (dx += 1) {
                        const offset: i32 = if (pass == 0) shadow else 0;
                        const x = origin_x + sx * scale + dx + offset;
                        const y = origin_y + sy * scale + dy + offset;
                        if (x < 0 or y < 0 or x >= size or y >= size) continue;
                        const at: usize = @intCast(y * @as(i32, @intCast(size)) + x);
                        if ((pixels[at] >> 24) == 0) continue; // stay inside the body
                        pixels[at] = if (pass == 0)
                            blend(pixels[at], 0, 0, 0, 0.28)
                        else switch (index) {
                            1 => blend(pixels[at], 0x20, 0x20, 0x20, 1.0),
                            3 => blend(pixels[at], 0xD4, 0x14, 0x14, 1.0),
                            else => blend(pixels[at], 0xff, 0xff, 0xff, 1.0),
                        };
                    }
                }
            }
        }
    }

    return pixels;
}

/// One foreground layer for the Icon Composer document, as a white mask on a
/// transparent canvas: the pole (`want` = 1) or the banner (`want` = 3).
/// macOS supplies the colour, glass, shadow and background itself.
fn renderLayer(gpa: std.mem.Allocator, size: u32, want: u8) ![]u32 {
    const pixels = try gpa.alloc(u32, size * size);
    @memset(pixels, 0);

    const n: f32 = @floatFromInt(size);
    const box_x = 4;
    const box_y = 2;
    const box_w = 9;
    const box_h = 10;
    const scale: i32 = @max(1, @as(i32, @intFromFloat(@round(n * 0.062))));
    const origin_x = @divTrunc(@as(i32, @intCast(size)) - box_w * scale, 2);
    const origin_y = @divTrunc(@as(i32, @intCast(size)) - box_h * scale, 2);

    var sy: i32 = 0;
    while (sy < box_h) : (sy += 1) {
        var sx: i32 = 0;
        while (sx < box_w) : (sx += 1) {
            const index = sprites.flag[@intCast((sy + box_y) * 16 + sx + box_x)];
            if (index != want) continue;
            // The layer is a mask: macOS recolours it per appearance.
            const color: u32 = argb(255, 0xFF, 0xFF, 0xFF);
            var dy: i32 = 0;
            while (dy < scale) : (dy += 1) {
                var dx: i32 = 0;
                while (dx < scale) : (dx += 1) {
                    const x = origin_x + sx * scale + dx;
                    const y = origin_y + sy * scale + dy;
                    if (x < 0 or y < 0 or x >= size or y >= size) continue;
                    pixels[@intCast(y * @as(i32, @intCast(size)) + x)] = color;
                }
            }
        }
    }
    return pixels;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.skip();
    const out_dir = args.next() orelse "assets";

    for (sizes) |size| {
        const pixels = try render(gpa, size);
        defer gpa.free(pixels);
        const bytes = try png.encode(gpa, pixels, size, size);
        defer gpa.free(bytes);

        var path_buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/icon_{d}.png", .{ out_dir, size });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
        std.debug.print("wrote {s} ({d} bytes)\n", .{ path, bytes.len });
    }

    // The layered macOS 26 icon wants the pole and the banner separately, so
    // each can take its own colour in light and dark appearances.
    for ([_]struct { want: u8, name: []const u8 }{
        .{ .want = 1, .name = "icon_layer_pole" },
        .{ .want = 3, .name = "icon_layer_banner" },
    }) |layer| {
        const mask = try renderLayer(gpa, 1024, layer.want);
        defer gpa.free(mask);
        const mask_bytes = try png.encode(gpa, mask, 1024, 1024);
        defer gpa.free(mask_bytes);
        var mask_path_buf: [256]u8 = undefined;
        const mask_path = try std.fmt.bufPrint(&mask_path_buf, "{s}/{s}.png", .{ out_dir, layer.name });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = mask_path, .data = mask_bytes });
        std.debug.print("wrote {s} ({d} bytes)\n", .{ mask_path, mask_bytes.len });
    }
}
