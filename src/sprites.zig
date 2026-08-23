//! Pixel art for the board tiles and the smiley button.

const std = @import("std");
const gfx = @import("gfx.zig");

pub const black = gfx.rgb(0, 0, 0);
pub const white = gfx.rgb(255, 255, 255);
pub const face_gray = gfx.rgb(192, 192, 192);
pub const shadow_gray = gfx.rgb(128, 128, 128);
pub const red = gfx.rgb(255, 0, 0);
pub const yellow = gfx.rgb(255, 255, 0);

/// The colour of each number, straight out of the original game.
pub const number_colors = [8]gfx.Color{
    gfx.rgb(0, 0, 255),
    gfx.rgb(0, 128, 0),
    gfx.rgb(255, 0, 0),
    gfx.rgb(0, 0, 128),
    gfx.rgb(128, 0, 0),
    gfx.rgb(0, 128, 128),
    gfx.rgb(0, 0, 0),
    gfx.rgb(128, 128, 128),
};

/// '.' transparent, '#' black, 'w' white, 'r' red.
fn indexOf(c: u8) u8 {
    return switch (c) {
        '.' => 0,
        '#' => 1,
        'w' => 2,
        'r' => 3,
        else => @compileError("unknown sprite character"),
    };
}

fn parse(comptime w: usize, comptime h: usize, comptime art: []const u8) [w * h]u8 {
    @setEvalBranchQuota(100_000);
    var out: [w * h]u8 = undefined;
    var lines = std.mem.splitScalar(u8, art, '\n');
    for (0..h) |y| {
        const line = lines.next() orelse @compileError("sprite art ended early");
        if (line.len != w) @compileError("sprite art row has the wrong width");
        for (line, 0..) |c, x| out[y * w + x] = indexOf(c);
    }
    if (lines.next() != null) @compileError("sprite art has extra rows");
    return out;
}

pub const digit_width = 7;
pub const digit_height = 9;

/// Numbers 1..8 plus the question mark, all 7x9 and drawn in a single colour.
pub const digits = [9][digit_width * digit_height]u8{
    parse(digit_width, digit_height,
        \\...##..
        \\..###..
        \\.####..
        \\...##..
        \\...##..
        \\...##..
        \\...##..
        \\...##..
        \\.######
    ),
    parse(digit_width, digit_height,
        \\.#####.
        \\##...##
        \\.....##
        \\....##.
        \\...##..
        \\..##...
        \\.##....
        \\##.....
        \\#######
    ),
    parse(digit_width, digit_height,
        \\.#####.
        \\##...##
        \\.....##
        \\..####.
        \\.....##
        \\.....##
        \\.....##
        \\##...##
        \\.#####.
    ),
    parse(digit_width, digit_height,
        \\....##.
        \\...###.
        \\..####.
        \\.##.##.
        \\##..##.
        \\#######
        \\....##.
        \\....##.
        \\....##.
    ),
    parse(digit_width, digit_height,
        \\#######
        \\##.....
        \\##.....
        \\######.
        \\.....##
        \\.....##
        \\.....##
        \\##...##
        \\.#####.
    ),
    parse(digit_width, digit_height,
        \\..####.
        \\.##....
        \\##.....
        \\##.....
        \\######.
        \\##...##
        \\##...##
        \\##...##
        \\.#####.
    ),
    parse(digit_width, digit_height,
        \\#######
        \\##...##
        \\.....##
        \\....##.
        \\....##.
        \\...##..
        \\...##..
        \\...##..
        \\...##..
    ),
    parse(digit_width, digit_height,
        \\.#####.
        \\##...##
        \\##...##
        \\.#####.
        \\##...##
        \\##...##
        \\##...##
        \\##...##
        \\.#####.
    ),
    parse(digit_width, digit_height,
        \\.#####.
        \\##...##
        \\.....##
        \\....##.
        \\...##..
        \\...##..
        \\.......
        \\...##..
        \\...##..
    ),
};

pub const question_index = 8;

pub const tile = 16;

pub const mine = parse(tile, tile,
    \\................
    \\.......##.......
    \\.......##.......
    \\..#....##....#..
    \\...#..####..#...
    \\.....######.....
    \\....#ww#####....
    \\.####ww########.
    \\.##############.
    \\....########....
    \\.....######.....
    \\...#..####..#...
    \\..#....##....#..
    \\.......##.......
    \\.......##.......
    \\................
);

pub const flag = parse(tile, tile,
    \\................
    \\................
    \\......rrrr#.....
    \\.....rrrrr#.....
    \\....rrrrrr#.....
    \\.....rrrrr#.....
    \\......rrrr#.....
    \\..........#.....
    \\..........#.....
    \\..........#.....
    \\.......#####....
    \\......#######...
    \\................
    \\................
    \\................
    \\................
);

pub const sprite_palette = [_]gfx.Color{ 0, black, white, red };

/// Draws a 16x16 indexed sprite through the shared palette.
pub fn drawTile(fb: *gfx.Framebuffer, x: i32, y: i32, data: []const u8) void {
    fb.blitIndexed(x, y, tile, tile, data, &sprite_palette);
}

pub fn drawDigit(fb: *gfx.Framebuffer, x: i32, y: i32, index: usize, color: gfx.Color) void {
    const palette = [_]gfx.Color{ 0, color };
    fb.blitIndexed(x, y, digit_width, digit_height, &digits[index], &palette);
}

pub const Face = enum { smile, surprised, dead, cool };

pub const face_size = 17;

/// The smiley is drawn with maths rather than art so the circle stays smooth.
pub fn drawFace(fb: *gfx.Framebuffer, ox: i32, oy: i32, face: Face) void {
    const center: f32 = 8.0;
    var y: i32 = 0;
    while (y < face_size) : (y += 1) {
        var x: i32 = 0;
        while (x < face_size) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) - center;
            const dy = @as(f32, @floatFromInt(y)) - center;
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist <= 7.4) {
                fb.set(ox + x, oy + y, yellow);
            } else if (dist <= 8.4) {
                fb.set(ox + x, oy + y, black);
            }
        }
    }

    switch (face) {
        .smile, .surprised => {
            fb.fill(.{ .x = ox + 5, .y = oy + 5, .w = 2, .h = 3 }, black);
            fb.fill(.{ .x = ox + 10, .y = oy + 5, .w = 2, .h = 3 }, black);
        },
        .dead => {
            drawCross(fb, ox + 2, oy + 4);
            drawCross(fb, ox + 10, oy + 4);
        },
        .cool => {
            // Sunglasses: two lenses joined by a thin bridge.
            fb.fill(.{ .x = ox + 2, .y = oy + 5, .w = 5, .h = 5 }, black);
            fb.fill(.{ .x = ox + 10, .y = oy + 5, .w = 5, .h = 5 }, black);
            fb.fill(.{ .x = ox + 7, .y = oy + 6, .w = 3, .h = 2 }, black);
        },
    }

    switch (face) {
        .smile, .cool => {
            const mouth = [_][2]i32{ .{ 5, 11 }, .{ 6, 12 }, .{ 7, 13 }, .{ 8, 13 }, .{ 9, 13 }, .{ 10, 12 }, .{ 11, 11 } };
            for (mouth) |p| fb.set(ox + p[0], oy + p[1], black);
        },
        .dead => {
            const mouth = [_][2]i32{ .{ 5, 13 }, .{ 6, 12 }, .{ 7, 11 }, .{ 8, 11 }, .{ 9, 11 }, .{ 10, 12 }, .{ 11, 13 } };
            for (mouth) |p| fb.set(ox + p[0], oy + p[1], black);
        },
        .surprised => {
            fb.frame(.{ .x = ox + 6, .y = oy + 10, .w = 5, .h = 5 }, black);
        },
    }
}

fn drawCross(fb: *gfx.Framebuffer, x: i32, y: i32) void {
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        fb.set(x + i, y + i, black);
        fb.set(x + 4 - i, y + i, black);
    }
}

/// The red X drawn over a flag that turned out to be wrong.
pub fn drawWrongMark(fb: *gfx.Framebuffer, x: i32, y: i32) void {
    var i: i32 = 0;
    while (i < 12) : (i += 1) {
        fb.set(x + 2 + i, y + 2 + i, red);
        fb.set(x + 3 + i, y + 2 + i, red);
        fb.set(x + 13 - i, y + 2 + i, red);
        fb.set(x + 12 - i, y + 2 + i, red);
    }
}
