//! macOS backend. Creates a real Cocoa window and presents the software
//! framebuffer through a CALayer, so no external toolkit is needed.

const std = @import("std");
const objc = @import("objc.zig");
const types = @import("types.zig");
const gfx = @import("../gfx.zig");

const id = objc.id;
const msg = objc.msg;
const sel = objc.sel;
const cls = objc.cls;
const NSRect = objc.NSRect;
const NSSize = objc.NSSize;
const NSPoint = objc.NSPoint;

// Objective-C autorelease pools: every frame creates temporary objects
// (NSDate, NSEvent, CGImage) that must be drained or the process leaks.
extern fn objc_autoreleasePoolPush() ?*anyopaque;
extern fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;

const YES: i8 = 1;
const NO: i8 = 0;

const style_titled: u64 = 1;
const style_closable: u64 = 2;
const style_miniaturizable: u64 = 4;
const style_full_size_content: u64 = 1 << 15;
const backing_buffered: u64 = 2;
const activation_policy_regular: i64 = 0;

const view_width_sizable: u64 = 2;
const view_height_sizable: u64 = 16;

/// NSVisualEffectView constants, used when Liquid Glass is not available.
const blending_behind_window: i64 = 0;
const effect_state_active: i64 = 1;
const material_under_window_background: i64 = 21;

/// How much room the glass backdrop gets around the board, in points.
const glass_side_margin: i32 = 12;
const glass_bottom_margin: i32 = 12;
/// Enough to clear the transparent title bar and the window buttons.
const glass_top_margin: i32 = 34;
const glass_corner_radius: f64 = 16.0;

const event_mask_any: u64 = std.math.maxInt(u64);

const ev_left_down: u64 = 1;
const ev_left_up: u64 = 2;
const ev_right_down: u64 = 3;
const ev_right_up: u64 = 4;
const ev_mouse_moved: u64 = 5;
const ev_left_dragged: u64 = 6;
const ev_right_dragged: u64 = 7;
const ev_key_down: u64 = 10;
const ev_other_down: u64 = 25;
const ev_other_up: u64 = 26;
const ev_other_dragged: u64 = 27;

const mod_command: u64 = 1 << 20;

// Core Graphics, for turning the framebuffer into an image the layer can show.
extern fn CGColorSpaceCreateDeviceRGB() ?*anyopaque;
extern fn CGColorSpaceRelease(space: ?*anyopaque) void;
extern fn CGDataProviderCreateWithData(
    info: ?*anyopaque,
    data: *const anyopaque,
    size: usize,
    release: ?*const fn (?*anyopaque, *const anyopaque, usize) callconv(.c) void,
) ?*anyopaque;
extern fn CGDataProviderRelease(provider: ?*anyopaque) void;
extern fn CGImageCreate(
    width: usize,
    height: usize,
    bits_per_component: usize,
    bits_per_pixel: usize,
    bytes_per_row: usize,
    space: ?*anyopaque,
    bitmap_info: u32,
    provider: ?*anyopaque,
    decode: ?*const f64,
    should_interpolate: i8,
    intent: i32,
) ?*anyopaque;
extern fn CGImageRelease(image: ?*anyopaque) void;

/// kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little, i.e. 0x00RRGGBB
/// as a little-endian u32 -- exactly what gfx.Framebuffer stores.
const bitmap_info: u32 = 6 | (2 << 12);

pub const Window = struct {
    app: id,
    window: id,
    view: id,
    layer: id,
    color_space: ?*anyopaque,
    run_loop_mode: id,
    scale: i32,
    width: i32,
    height: i32,
    /// Point offsets of the pixel content inside the window's content area.
    inset_x: i32 = 0,
    inset_top: i32 = 0,
    inset_bottom: i32 = 0,
    glass: bool = false,
    should_close: bool = false,
    was_key: bool = true,
    queue: std.ArrayList(types.Event),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: types.WindowOptions) !Window {
        const pool = objc_autoreleasePoolPush();
        defer objc_autoreleasePoolPop(pool);

        const app = msg(id, cls("NSApplication"), sel("sharedApplication"), .{});
        _ = msg(i8, app, sel("setActivationPolicy:"), .{activation_policy_regular});

        // Liquid Glass on macOS 26 and later; the older blur view otherwise.
        const glass_class = cls("NSGlassEffectView") orelse cls("NSVisualEffectView");
        const use_glass = options.glass and glass_class != null;

        const inset_x: i32 = if (use_glass) glass_side_margin else 0;
        const inset_top: i32 = if (use_glass) glass_top_margin else 0;
        const inset_bottom: i32 = if (use_glass) glass_bottom_margin else 0;

        const content_w = options.width * options.scale + inset_x * 2;
        const content_h = options.height * options.scale + inset_top + inset_bottom;
        const content_rect = NSRect{
            .origin = .{ .x = 0, .y = 0 },
            .size = .{
                .width = @floatFromInt(content_w),
                .height = @floatFromInt(content_h),
            },
        };

        var style = style_titled | style_closable | style_miniaturizable;
        if (use_glass) style |= style_full_size_content;

        const window_alloc = msg(id, cls("NSWindow"), sel("alloc"), .{});
        const window = msg(
            id,
            window_alloc,
            sel("initWithContentRect:styleMask:backing:defer:"),
            .{ content_rect, style, backing_buffered, NO },
        );
        msg(void, window, sel("setTitle:"), .{objc.nsString(options.title)});
        msg(void, window, sel("setAcceptsMouseMovedEvents:"), .{YES});
        msg(void, window, sel("setReleasedWhenClosed:"), .{NO});

        // The pixel content lives in its own layer-backed view so the glass can
        // show through around it.
        const pixel_rect = NSRect{
            .origin = .{
                .x = @floatFromInt(inset_x),
                .y = @floatFromInt(inset_bottom),
            },
            .size = .{
                .width = @floatFromInt(options.width * options.scale),
                .height = @floatFromInt(options.height * options.scale),
            },
        };
        const view = msg(
            id,
            msg(id, cls("NSView"), sel("alloc"), .{}),
            sel("initWithFrame:"),
            .{if (use_glass) pixel_rect else content_rect},
        );
        msg(void, view, sel("setWantsLayer:"), .{YES});

        if (use_glass) {
            const backdrop = msg(
                id,
                msg(id, glass_class, sel("alloc"), .{}),
                sel("initWithFrame:"),
                .{content_rect},
            );
            msg(void, backdrop, sel("setAutoresizingMask:"), .{view_width_sizable | view_height_sizable});
            if (responds(backdrop, "setCornerRadius:")) {
                msg(void, backdrop, sel("setCornerRadius:"), .{glass_corner_radius});
            }
            // NSVisualEffectView needs telling what to sample and how.
            if (responds(backdrop, "setBlendingMode:")) {
                msg(void, backdrop, sel("setBlendingMode:"), .{blending_behind_window});
                msg(void, backdrop, sel("setMaterial:"), .{material_under_window_background});
                msg(void, backdrop, sel("setState:"), .{effect_state_active});
            }
            msg(void, window, sel("setContentView:"), .{backdrop});
            msg(void, backdrop, sel("addSubview:"), .{view});

            msg(void, window, sel("setTitlebarAppearsTransparent:"), .{YES});
            msg(void, window, sel("setOpaque:"), .{NO});
            const clear = msg(id, cls("NSColor"), sel("clearColor"), .{});
            msg(void, window, sel("setBackgroundColor:"), .{clear});
        } else {
            msg(void, window, sel("setContentView:"), .{view});
        }

        const layer = msg(id, view, sel("layer"), .{});
        // Nearest-neighbour keeps the pixel art crisp when scaled up.
        msg(void, layer, sel("setMagnificationFilter:"), .{objc.nsString("nearest")});
        msg(void, layer, sel("setMinificationFilter:"), .{objc.nsString("nearest")});
        msg(void, layer, sel("setContentsScale:"), .{@as(f64, 1.0)});

        buildMenu(app, options.title);

        // The run-loop mode string outlives the pool this function runs in.
        const run_loop_mode = objc.nsString("kCFRunLoopDefaultMode");
        _ = msg(id, run_loop_mode, sel("retain"), .{});

        msg(void, window, sel("center"), .{});
        msg(void, window, sel("makeKeyAndOrderFront:"), .{@as(id, null)});
        msg(void, app, sel("activateIgnoringOtherApps:"), .{YES});
        msg(void, app, sel("finishLaunching"), .{});

        return .{
            .app = app,
            .window = window,
            .view = view,
            .layer = layer,
            .color_space = CGColorSpaceCreateDeviceRGB(),
            .run_loop_mode = run_loop_mode,
            .scale = options.scale,
            .width = options.width,
            .height = options.height,
            .inset_x = inset_x,
            .inset_top = inset_top,
            .inset_bottom = inset_bottom,
            .glass = use_glass,
            .queue = .empty,
            .allocator = allocator,
        };
    }

    fn responds(object: id, comptime name: [:0]const u8) bool {
        return msg(i8, object, sel("respondsToSelector:"), .{sel(name)}) != 0;
    }

    pub fn deinit(self: *Window) void {
        CGColorSpaceRelease(self.color_space);
        self.queue.deinit(self.allocator);
        self.* = undefined;
    }

    fn buildMenu(app: id, title: [*:0]const u8) void {
        const main_menu = msg(id, msg(id, cls("NSMenu"), sel("alloc"), .{}), sel("init"), .{});
        const app_item = msg(id, msg(id, cls("NSMenuItem"), sel("alloc"), .{}), sel("init"), .{});
        msg(void, main_menu, sel("addItem:"), .{app_item});
        msg(void, app, sel("setMainMenu:"), .{main_menu});

        const app_menu = msg(id, msg(id, cls("NSMenu"), sel("alloc"), .{}), sel("init"), .{});
        var buf: [64]u8 = undefined;
        const quit_title = std.fmt.bufPrintZ(&buf, "Quit {s}", .{title}) catch "Quit";
        const quit_item = msg(
            id,
            msg(id, cls("NSMenuItem"), sel("alloc"), .{}),
            sel("initWithTitle:action:keyEquivalent:"),
            .{ objc.nsString(quit_title.ptr), sel("terminate:"), objc.nsString("q") },
        );
        msg(void, app_menu, sel("addItem:"), .{quit_item});
        msg(void, app_item, sel("setSubmenu:"), .{app_menu});
    }

    /// Resize the content area, keeping the window centred like the original
    /// Minesweeper does when the difficulty changes.
    /// Resize the content area, keeping the window centred like the original
    /// Minesweeper does when the difficulty changes.
    pub fn setSize(self: *Window, width: i32, height: i32) void {
        if (width == self.width and height == self.height) return;
        self.width = width;
        self.height = height;
        const size = NSSize{
            .width = @floatFromInt(width * self.scale + self.inset_x * 2),
            .height = @floatFromInt(height * self.scale + self.inset_top + self.inset_bottom),
        };
        msg(void, self.window, sel("setContentSize:"), .{size});
        msg(void, self.view, sel("setFrame:"), .{NSRect{
            .origin = .{
                .x = @floatFromInt(self.inset_x),
                .y = @floatFromInt(self.inset_bottom),
            },
            .size = .{
                .width = @floatFromInt(width * self.scale),
                .height = @floatFromInt(height * self.scale),
            },
        }});
        msg(void, self.window, sel("center"), .{});
    }

    fn push(self: *Window, event: types.Event) void {
        self.queue.append(self.allocator, event) catch {};
    }

    fn locate(self: *Window, event: id) struct { x: i32, y: i32 } {
        const point = msg(NSPoint, event, sel("locationInWindow"), .{});
        const scale: f64 = @floatFromInt(self.scale);
        const content_h: f64 = @floatFromInt(self.height * self.scale + self.inset_top + self.inset_bottom);
        const flipped = content_h - point.y;
        return .{
            .x = @intFromFloat(@floor((point.x - @as(f64, @floatFromInt(self.inset_x))) / scale)),
            .y = @intFromFloat(@floor((flipped - @as(f64, @floatFromInt(self.inset_top))) / scale)),
        };
    }

    fn translate(self: *Window, event: id) void {
        const kind = msg(u64, event, sel("type"), .{});
        switch (kind) {
            ev_left_down, ev_right_down, ev_other_down => {
                const p = self.locate(event);
                self.push(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = buttonOf(kind) } });
            },
            ev_left_up, ev_right_up, ev_other_up => {
                const p = self.locate(event);
                self.push(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = buttonOf(kind) } });
            },
            ev_mouse_moved, ev_left_dragged, ev_right_dragged, ev_other_dragged => {
                const p = self.locate(event);
                self.push(.{ .mouse_move = .{ .x = p.x, .y = p.y } });
            },
            ev_key_down => {
                const flags = msg(u64, event, sel("modifierFlags"), .{});
                if (flags & mod_command != 0) return; // let AppKit own the shortcuts
                const code = msg(u16, event, sel("keyCode"), .{});
                switch (code) {
                    53 => self.push(.{ .key_down = .escape }),
                    36, 76 => self.push(.{ .key_down = .enter }),
                    51 => self.push(.{ .key_down = .backspace }),
                    48 => self.push(.{ .key_down = .tab }),
                    120 => self.push(.{ .key_down = .f2 }),
                    else => {
                        const chars = msg(id, event, sel("characters"), .{});
                        if (chars == null) return;
                        const utf8 = msg(?[*:0]const u8, chars, sel("UTF8String"), .{}) orelse return;
                        const ch = utf8[0];
                        if (ch >= 0x20 and ch < 0x7f) self.push(.{ .text = ch });
                    },
                }
            },
            else => {},
        }
    }

    fn buttonOf(kind: u64) types.MouseButton {
        return switch (kind) {
            ev_right_down, ev_right_up => .right,
            ev_other_down, ev_other_up => .middle,
            else => .left,
        };
    }

    /// Drain the Cocoa event queue, waiting at most `timeout_ms` for the first
    /// event so the process stays idle when nothing happens.
    pub fn pump(self: *Window, timeout_ms: u32) void {
        const pool = objc_autoreleasePoolPush();
        defer objc_autoreleasePoolPop(pool);

        const seconds: f64 = @as(f64, @floatFromInt(timeout_ms)) / 1000.0;
        var until = msg(id, cls("NSDate"), sel("dateWithTimeIntervalSinceNow:"), .{seconds});
        while (true) {
            const event = msg(
                id,
                self.app,
                sel("nextEventMatchingMask:untilDate:inMode:dequeue:"),
                .{ event_mask_any, until, self.run_loop_mode, YES },
            );
            if (event == null) break;
            self.translate(event);
            msg(void, self.app, sel("sendEvent:"), .{event});
            until = msg(id, cls("NSDate"), sel("distantPast"), .{});
        }
        // Losing focus mid-drag must cancel whatever the player was pressing.
        const is_key = msg(i8, self.window, sel("isKeyWindow"), .{}) != 0;
        if (self.was_key and !is_key) self.push(.focus_lost);
        self.was_key = is_key;

        if (msg(i8, self.window, sel("isVisible"), .{}) == 0) {
            self.should_close = true;
            self.push(.close);
        }
    }

    pub fn pollEvent(self: *Window) ?types.Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    pub fn present(self: *Window, fb: *const gfx.Framebuffer) void {
        const pool = objc_autoreleasePoolPush();
        defer objc_autoreleasePoolPop(pool);

        const width: usize = @intCast(fb.width);
        const height: usize = @intCast(fb.height);
        const bytes = width * height * 4;
        const provider = CGDataProviderCreateWithData(null, fb.pixels.ptr, bytes, null);
        defer CGDataProviderRelease(provider);
        const image = CGImageCreate(
            width,
            height,
            8,
            32,
            width * 4,
            self.color_space,
            bitmap_info,
            provider,
            null,
            NO,
            0,
        );
        defer CGImageRelease(image);
        msg(void, self.layer, sel("setContents:"), .{@as(id, image)});
    }
};
