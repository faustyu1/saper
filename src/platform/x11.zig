//! X11 backend for Linux and the other Unixes. Talks to Xlib directly.

const std = @import("std");
const types = @import("types.zig");
const gfx = @import("../gfx.zig");

const Display = opaque {};
const Visual = opaque {};
const GC = *opaque {};
const XID = c_ulong;
const Atom = c_ulong;

const XImage = extern struct {
    width: c_int,
    height: c_int,
    xoffset: c_int,
    format: c_int,
    data: ?[*]u8,
    byte_order: c_int,
    bitmap_unit: c_int,
    bitmap_bit_order: c_int,
    bitmap_pad: c_int,
    depth: c_int,
    bytes_per_line: c_int,
    bits_per_pixel: c_int,
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
    obdata: ?*anyopaque,
    funcs: [6]?*anyopaque,
};

const XButtonEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: XID,
    root: XID,
    subwindow: XID,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    button: c_uint,
    same_screen: c_int,
};

const XKeyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: XID,
    root: XID,
    subwindow: XID,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    keycode: c_uint,
    same_screen: c_int,
};

const XMotionEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: XID,
    root: XID,
    subwindow: XID,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    is_hint: u8,
    same_screen: c_int,
};

const XClientMessageEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: XID,
    message_type: Atom,
    format: c_int,
    data: extern union {
        b: [20]u8,
        s: [10]c_short,
        l: [5]c_long,
    },
};

const XEvent = extern union {
    type: c_int,
    xkey: XKeyEvent,
    xbutton: XButtonEvent,
    xmotion: XMotionEvent,
    xclient: XClientMessageEvent,
    pad: [24]c_long,
};

const XSizeHints = extern struct {
    flags: c_long = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    min_width: c_int = 0,
    min_height: c_int = 0,
    max_width: c_int = 0,
    max_height: c_int = 0,
    width_inc: c_int = 0,
    height_inc: c_int = 0,
    min_aspect_x: c_int = 0,
    min_aspect_y: c_int = 0,
    max_aspect_x: c_int = 0,
    max_aspect_y: c_int = 0,
    base_width: c_int = 0,
    base_height: c_int = 0,
    win_gravity: c_int = 0,
};

extern fn XOpenDisplay(name: ?[*:0]const u8) ?*Display;
extern fn XCloseDisplay(display: *Display) c_int;
extern fn XDefaultScreen(display: *Display) c_int;
extern fn XDefaultRootWindow(display: *Display) XID;
extern fn XDefaultVisual(display: *Display, screen: c_int) *Visual;
extern fn XDefaultDepth(display: *Display, screen: c_int) c_int;
extern fn XWhitePixel(display: *Display, screen: c_int) c_ulong;
extern fn XCreateSimpleWindow(
    display: *Display,
    parent: XID,
    x: c_int,
    y: c_int,
    width: c_uint,
    height: c_uint,
    border_width: c_uint,
    border: c_ulong,
    background: c_ulong,
) XID;
extern fn XDestroyWindow(display: *Display, window: XID) c_int;
extern fn XSelectInput(display: *Display, window: XID, mask: c_long) c_int;
extern fn XMapWindow(display: *Display, window: XID) c_int;
extern fn XStoreName(display: *Display, window: XID, name: [*:0]const u8) c_int;
extern fn XCreateGC(display: *Display, drawable: XID, mask: c_ulong, values: ?*anyopaque) GC;
extern fn XFreeGC(display: *Display, gc: GC) c_int;
extern fn XCreateImage(
    display: *Display,
    visual: *Visual,
    depth: c_uint,
    format: c_int,
    offset: c_int,
    data: [*]u8,
    width: c_uint,
    height: c_uint,
    bitmap_pad: c_int,
    bytes_per_line: c_int,
) ?*XImage;
extern fn XPutImage(
    display: *Display,
    drawable: XID,
    gc: GC,
    image: *XImage,
    src_x: c_int,
    src_y: c_int,
    dest_x: c_int,
    dest_y: c_int,
    width: c_uint,
    height: c_uint,
) c_int;
extern fn XPending(display: *Display) c_int;
extern fn XNextEvent(display: *Display, event: *XEvent) c_int;
extern fn XFlush(display: *Display) c_int;
extern fn XSync(display: *Display, discard: c_int) c_int;
extern fn XInternAtom(display: *Display, name: [*:0]const u8, only_if_exists: c_int) Atom;
extern fn XSetWMProtocols(display: *Display, window: XID, protocols: [*]Atom, count: c_int) c_int;
extern fn XResizeWindow(display: *Display, window: XID, width: c_uint, height: c_uint) c_int;
extern fn XSetWMNormalHints(display: *Display, window: XID, hints: *XSizeHints) void;
extern fn XLookupString(
    event: *XKeyEvent,
    buffer: [*]u8,
    length: c_int,
    keysym: ?*c_ulong,
    status: ?*anyopaque,
) c_int;
extern fn XFree(data: ?*anyopaque) c_int;
extern fn XConnectionNumber(display: *Display) c_int;

const KeyPressMask: c_long = 1 << 0;
const ButtonPressMask: c_long = 1 << 2;
const ButtonReleaseMask: c_long = 1 << 3;
const PointerMotionMask: c_long = 1 << 6;
const ExposureMask: c_long = 1 << 15;
const StructureNotifyMask: c_long = 1 << 17;
const FocusChangeMask: c_long = 1 << 21;

const KeyPress = 2;
const ButtonPress = 4;
const ButtonRelease = 5;
const MotionNotify = 6;
const FocusOut = 10;
const Expose = 12;
const ClientMessage = 33;

const ZPixmap = 2;
const PMinSize: c_long = 1 << 4;
const PMaxSize: c_long = 1 << 5;

const XK_BackSpace = 0xff08;
const XK_Tab = 0xff09;
const XK_Return = 0xff0d;
const XK_Escape = 0xff1b;
const XK_F2 = 0xffbf;

pub const Window = struct {
    display: *Display,
    handle: XID,
    gc: GC,
    image: ?*XImage = null,
    scaled: []u32,
    scale: i32,
    width: i32,
    height: i32,
    wm_delete: Atom,
    should_close: bool = false,
    queue: std.ArrayList(types.Event),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: types.WindowOptions) !Window {
        const title = options.title;
        const width = options.width;
        const height = options.height;
        const scale = options.scale;
        const display = XOpenDisplay(null) orelse return error.NoDisplay;
        const screen = XDefaultScreen(display);
        const root = XDefaultRootWindow(display);
        const pixel_w: c_uint = @intCast(width * scale);
        const pixel_h: c_uint = @intCast(height * scale);

        const handle = XCreateSimpleWindow(
            display,
            root,
            0,
            0,
            pixel_w,
            pixel_h,
            0,
            0,
            XWhitePixel(display, screen),
        );
        _ = XStoreName(display, handle, title);
        _ = XSelectInput(
            display,
            handle,
            KeyPressMask | ButtonPressMask | ButtonReleaseMask |
                PointerMotionMask | ExposureMask | StructureNotifyMask | FocusChangeMask,
        );

        var wm_delete = XInternAtom(display, "WM_DELETE_WINDOW", 0);
        _ = XSetWMProtocols(display, handle, @ptrCast(&wm_delete), 1);

        const gc = XCreateGC(display, handle, 0, null);
        _ = XMapWindow(display, handle);
        _ = XFlush(display);

        var self = Window{
            .display = display,
            .handle = handle,
            .gc = gc,
            .scaled = try allocator.alloc(u32, @intCast(width * scale * height * scale)),
            .scale = scale,
            .width = width,
            .height = height,
            .wm_delete = wm_delete,
            .queue = .empty,
            .allocator = allocator,
        };
        self.lockSize();
        try self.makeImage();
        return self;
    }

    pub fn deinit(self: *Window) void {
        if (self.image) |image| _ = XFree(image);
        _ = XFreeGC(self.display, self.gc);
        _ = XDestroyWindow(self.display, self.handle);
        _ = XCloseDisplay(self.display);
        self.allocator.free(self.scaled);
        self.queue.deinit(self.allocator);
        self.* = undefined;
    }

    /// The board never resizes itself, so the window manager is told to keep
    /// the window exactly the size we asked for.
    fn lockSize(self: *Window) void {
        var hints = XSizeHints{
            .flags = PMinSize | PMaxSize,
            .min_width = self.width * self.scale,
            .min_height = self.height * self.scale,
            .max_width = self.width * self.scale,
            .max_height = self.height * self.scale,
        };
        XSetWMNormalHints(self.display, self.handle, &hints);
    }

    fn makeImage(self: *Window) !void {
        if (self.image) |image| _ = XFree(image);
        const screen = XDefaultScreen(self.display);
        const pixel_w = self.width * self.scale;
        const pixel_h = self.height * self.scale;
        self.image = XCreateImage(
            self.display,
            XDefaultVisual(self.display, screen),
            @intCast(XDefaultDepth(self.display, screen)),
            ZPixmap,
            0,
            @ptrCast(self.scaled.ptr),
            @intCast(pixel_w),
            @intCast(pixel_h),
            32,
            pixel_w * 4,
        ) orelse return error.ImageFailed;
    }

    pub fn setSize(self: *Window, width: i32, height: i32) void {
        if (width == self.width and height == self.height) return;
        self.width = width;
        self.height = height;
        const count: usize = @intCast(width * self.scale * height * self.scale);
        self.scaled = self.allocator.realloc(self.scaled, count) catch return;
        self.lockSize();
        _ = XResizeWindow(
            self.display,
            self.handle,
            @intCast(width * self.scale),
            @intCast(height * self.scale),
        );
        self.makeImage() catch {};
    }

    fn push(self: *Window, event: types.Event) void {
        self.queue.append(self.allocator, event) catch {};
    }

    fn buttonOf(button: c_uint) ?types.MouseButton {
        return switch (button) {
            1 => .left,
            2 => .middle,
            3 => .right,
            else => null,
        };
    }

    pub fn pump(self: *Window, timeout_ms: u32) void {
        _ = XFlush(self.display);
        if (XPending(self.display) == 0) {
            waitForInput(XConnectionNumber(self.display), timeout_ms);
        }
        while (XPending(self.display) > 0) {
            var event: XEvent = undefined;
            _ = XNextEvent(self.display, &event);
            self.translate(&event);
        }
    }

    fn translate(self: *Window, event: *XEvent) void {
        switch (event.type) {
            ButtonPress, ButtonRelease => {
                const b = event.xbutton;
                const button = buttonOf(b.button) orelse return;
                const x = @divFloor(@as(i32, b.x), self.scale);
                const y = @divFloor(@as(i32, b.y), self.scale);
                if (event.type == ButtonPress) {
                    self.push(.{ .mouse_down = .{ .x = x, .y = y, .button = button } });
                } else {
                    self.push(.{ .mouse_up = .{ .x = x, .y = y, .button = button } });
                }
            },
            MotionNotify => {
                const m = event.xmotion;
                self.push(.{ .mouse_move = .{
                    .x = @divFloor(@as(i32, m.x), self.scale),
                    .y = @divFloor(@as(i32, m.y), self.scale),
                } });
            },
            KeyPress => {
                var buffer: [8]u8 = undefined;
                var keysym: c_ulong = 0;
                const n = XLookupString(&event.xkey, &buffer, buffer.len, &keysym, null);
                switch (keysym) {
                    XK_Escape => self.push(.{ .key_down = .escape }),
                    XK_Return => self.push(.{ .key_down = .enter }),
                    XK_BackSpace => self.push(.{ .key_down = .backspace }),
                    XK_Tab => self.push(.{ .key_down = .tab }),
                    XK_F2 => self.push(.{ .key_down = .f2 }),
                    else => {
                        if (n > 0 and buffer[0] >= 0x20 and buffer[0] < 0x7f) {
                            self.push(.{ .text = buffer[0] });
                        }
                    },
                }
            },
            FocusOut => self.push(.focus_lost),
            ClientMessage => {
                if (event.xclient.data.l[0] == @as(c_long, @bitCast(self.wm_delete))) {
                    self.should_close = true;
                    self.push(.close);
                }
            },
            else => {},
        }
    }

    pub fn pollEvent(self: *Window) ?types.Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    pub fn present(self: *Window, fb: *const gfx.Framebuffer) void {
        scaleInto(self.scaled, fb, self.scale);
        const image = self.image orelse return;
        _ = XPutImage(
            self.display,
            self.handle,
            self.gc,
            image,
            0,
            0,
            0,
            0,
            @intCast(self.width * self.scale),
            @intCast(self.height * self.scale),
        );
        _ = XFlush(self.display);
    }
};

/// Nearest-neighbour integer upscale, shared by the backends that have to do
/// the scaling themselves.
pub fn scaleInto(dest: []u32, fb: *const gfx.Framebuffer, scale: i32) void {
    const dest_w: usize = @intCast(fb.width * scale);
    var y: usize = 0;
    while (y < @as(usize, @intCast(fb.height))) : (y += 1) {
        const src_row = fb.pixels[y * @as(usize, @intCast(fb.width)) ..][0..@intCast(fb.width)];
        var sy: usize = 0;
        while (sy < @as(usize, @intCast(scale))) : (sy += 1) {
            const row = dest[(y * @as(usize, @intCast(scale)) + sy) * dest_w ..][0..dest_w];
            for (src_row, 0..) |pixel, x| {
                var sx: usize = 0;
                while (sx < @as(usize, @intCast(scale))) : (sx += 1) {
                    row[x * @as(usize, @intCast(scale)) + sx] = pixel;
                }
            }
        }
    }
}

/// Blocks on the X connection until an event arrives or the timeout expires.
fn waitForInput(fd: c_int, timeout_ms: u32) void {
    var poll_fd = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    _ = std.posix.poll(&poll_fd, @intCast(timeout_ms)) catch {};
}
