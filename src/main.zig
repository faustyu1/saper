//! Saper - a classic Minesweeper written in Zig with a native window on every
//! supported platform and no third-party dependencies.

const std = @import("std");
const gfx = @import("gfx.zig");
const App = @import("app.zig").App;
const platform = @import("platform/platform.zig");
const dump = @import("dump.zig");

const default_scale = 2;

const usage =
    \\Saper - classic minesweeper
    \\
    \\  --scale N    integer zoom factor for the window (default 2)
    \\  --dump FILE  render one frame to a BMP file and exit
    \\  --no-glass   plain opaque window instead of the macOS Liquid Glass one
    \\  --help       show this message
    \\
;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var scale: i32 = default_scale;
    var dump_path: ?[]const u8 = null;
    var glass = true;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--scale")) {
            const value = args.next() orelse break;
            scale = std.fmt.parseInt(i32, value, 10) catch default_scale;
        } else if (std.mem.eql(u8, arg, "--dump")) {
            const value = args.next() orelse break;
            dump_path = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "--no-glass")) {
            glass = false;
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print(usage, .{});
            return;
        }
    }
    defer if (dump_path) |path| allocator.free(path);
    scale = std.math.clamp(scale, 1, 8);

    const home = init.environ_map.get("HOME") orelse init.environ_map.get("USERPROFILE");

    const io = init.io;
    const seed: u64 = @truncate(@as(u96, @bitCast(std.Io.Timestamp.now(io, .real).nanoseconds)));

    var app = App.init(io, home, seed);
    var fb = try gfx.Framebuffer.init(allocator, app.metrics.width, app.metrics.height);
    defer fb.deinit();

    if (dump_path) |path| {
        app.render(&fb);
        try dump.writeBmp(io, path, &fb, @intCast(scale));
        return;
    }

    var window = try platform.Window.init(allocator, .{
        .title = "Saper",
        .width = fb.width,
        .height = fb.height,
        .scale = scale,
        .glass = glass,
    });
    defer window.deinit();
    if (@hasDecl(platform.Window, "rebind")) window.rebind();

    while (!app.should_quit and !window.should_close) {
        window.pump(50);
        app.tick(@intCast(@divFloor(std.Io.Timestamp.now(io, .awake).nanoseconds, std.time.ns_per_ms)));
        while (window.pollEvent()) |event| app.handle(event);

        if (fb.width != app.metrics.width or fb.height != app.metrics.height) {
            try fb.resize(app.metrics.width, app.metrics.height);
            window.setSize(fb.width, fb.height);
            app.dirty = true;
        }

        // Nothing moved, so there is nothing to redraw: stay off the CPU.
        if (!app.needsRedraw()) continue;

        app.render(&fb);
        window.present(&fb);
    }
}
