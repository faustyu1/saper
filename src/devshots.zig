const std = @import("std");
const gfx = @import("gfx.zig");
const game = @import("game.zig");
const app_mod = @import("app.zig");
const dump = @import("dump.zig");
const types = @import("platform/types.zig");

const shot_scale = 3;

fn shot(io: std.Io, allocator: std.mem.Allocator, app: *app_mod.App, name: []const u8) !void {
    var fb = try gfx.Framebuffer.init(allocator, app.metrics.width, app.metrics.height);
    defer fb.deinit();
    app.render(&fb);
    try dump.writeBmp(io, name, &fb, shot_scale);
}

fn click(app: *app_mod.App, x: i32, y: i32, button: types.MouseButton) void {
    app.handle(.{ .mouse_move = .{ .x = x, .y = y } });
    app.handle(.{ .mouse_down = .{ .x = x, .y = y, .button = button } });
    app.handle(.{ .mouse_up = .{ .x = x, .y = y, .button = button } });
}

fn cellPos(app: *app_mod.App, cx: i32, cy: i32) struct { x: i32, y: i32 } {
    return .{ .x = app.metrics.field.x + cx * 16 + 8, .y = app.metrics.field.y + cy * 16 + 8 };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // 1. mid-game board
    var app = app_mod.App.init(io, null, 12345);
    app.tick(0);
    app.setDifficulty(.intermediate);
    const p = cellPos(&app, 4, 4);
    click(&app, p.x, p.y, .left);

    // Open a handful more safe cells and flag a few mines so the shot looks
    // like a game actually in progress.
    var opened: i32 = 0;
    var y0: i32 = 0;
    while (y0 < app.board.height and opened < 24) : (y0 += 1) {
        var x0: i32 = 0;
        while (x0 < app.board.width and opened < 24) : (x0 += 2) {
            if (app.board.get(x0, y0).mine or app.board.get(x0, y0).revealed) continue;
            const c = cellPos(&app, x0, y0);
            click(&app, c.x, c.y, .left);
            opened += 1;
        }
    }
    var flagged: i32 = 0;
    y0 = 0;
    while (y0 < app.board.height and flagged < 5) : (y0 += 1) {
        var x0: i32 = 0;
        while (x0 < app.board.width and flagged < 5) : (x0 += 1) {
            if (!app.board.get(x0, y0).mine) continue;
            const c = cellPos(&app, x0, y0);
            click(&app, c.x, c.y, .right);
            flagged += 1;
        }
    }
    const q = cellPos(&app, 1, 0);
    click(&app, q.x, q.y, .right);
    click(&app, q.x, q.y, .right);
    app.tick(42_000);
    try shot(io, allocator, &app, "s1_playing.bmp");

    // 2. lost board
    var y: i32 = 0;
    outer: while (y < app.board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < app.board.width) : (x += 1) {
            if (app.board.get(x, y).mine) {
                const m = cellPos(&app, x, y);
                click(&app, m.x, m.y, .left);
                break :outer;
            }
        }
    }
    try shot(io, allocator, &app, "s2_lost.bmp");

    // 3. menu open
    var app3 = app_mod.App.init(io, null, 7);
    app3.handle(.{ .mouse_down = .{ .x = 15, .y = 9, .button = .left } });
    try shot(io, allocator, &app3, "s3_menu.bmp");

    // 4. custom dialog
    var app4 = app_mod.App.init(io, null, 7);
    app4.applyMenuAction(.set_custom);
    try shot(io, allocator, &app4, "s4_custom.bmp");

    // 5. best times
    var app5 = app_mod.App.init(io, null, 7);
    app5.applyMenuAction(.best_times);
    try shot(io, allocator, &app5, "s5_best.bmp");

    // 6. about
    var app6 = app_mod.App.init(io, null, 7);
    app6.applyMenuAction(.about);
    try shot(io, allocator, &app6, "s6_about.bmp");

    // 7. expert board, won
    var app7 = app_mod.App.init(io, null, 99);
    app7.setDifficulty(.expert);
    const e = cellPos(&app7, 5, 5);
    click(&app7, e.x, e.y, .left);
    app7.tick(120_000);
    try shot(io, allocator, &app7, "s7_expert.bmp");

    // 8. win + new best dialog
    var app8 = app_mod.App.init(io, null, 4);
    const w = cellPos(&app8, 4, 4);
    click(&app8, w.x, w.y, .left);
    y = 0;
    while (y < app8.board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < app8.board.width) : (x += 1) {
            if (!app8.board.get(x, y).mine) {
                const c = cellPos(&app8, x, y);
                click(&app8, c.x, c.y, .left);
            }
        }
    }
    try shot(io, allocator, &app8, "s8_win.bmp");

    // 9. the four smiley states, plus the tiles, on a bare canvas
    const sprites = @import("sprites.zig");
    const widgets = @import("widgets.zig");
    var canvas = try gfx.Framebuffer.init(allocator, 120, 40);
    defer canvas.deinit();
    canvas.clear(widgets.face);
    for ([_]sprites.Face{ .smile, .surprised, .dead, .cool }, 0..) |f2, i| {
        const bx = 4 + @as(i32, @intCast(i)) * 28;
        const r = gfx.Rect{ .x = bx, .y = 4, .w = 26, .h = 26 };
        widgets.raised(&canvas, r, 2);
        sprites.drawFace(&canvas, bx + 4, 8, f2);
    }
    try dump.writeBmp(io, "s9_faces.bmp", &canvas, shot_scale);

    // 10. pressed cell, chord preview and a hovered menu item
    var app10 = app_mod.App.init(io, null, 5);
    const c10 = cellPos(&app10, 3, 3);
    app10.handle(.{ .mouse_move = .{ .x = c10.x, .y = c10.y } });
    app10.handle(.{ .mouse_down = .{ .x = c10.x, .y = c10.y, .button = .left } });
    try shot(io, allocator, &app10, "s10_pressed.bmp");
    app10.handle(.{ .mouse_down = .{ .x = c10.x, .y = c10.y, .button = .right } });
    try shot(io, allocator, &app10, "s11_chord.bmp");

    var app12 = app_mod.App.init(io, null, 5);
    app12.handle(.{ .mouse_down = .{ .x = 15, .y = 9, .button = .left } });
    app12.handle(.{ .mouse_move = .{ .x = 40, .y = 76 } });
    try shot(io, allocator, &app12, "s12_hover.bmp");
}
