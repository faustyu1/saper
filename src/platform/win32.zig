//! Win32 backend. Plain GDI: the framebuffer is blitted with StretchDIBits.

const std = @import("std");
const types = @import("types.zig");
const gfx = @import("../gfx.zig");
const scaleInto = @import("x11.zig").scaleInto;

const HANDLE = ?*anyopaque;
const HWND = HANDLE;
const HDC = HANDLE;
const HINSTANCE = HANDLE;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const BOOL = c_int;

const WNDPROC = *const fn (HWND, c_uint, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const POINT = extern struct { x: i32 = 0, y: i32 = 0 };

const RECT = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

const MSG = extern struct {
    hwnd: HWND = null,
    message: c_uint = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: u32 = 0,
    pt: POINT = .{},
    private: u32 = 0,
};

const WNDCLASSEXA = extern struct {
    cbSize: c_uint,
    style: c_uint,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE,
    hIcon: HANDLE = null,
    hCursor: HANDLE = null,
    hbrBackground: HANDLE = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
    hIconSm: HANDLE = null,
};

const BITMAPINFOHEADER = extern struct {
    biSize: u32,
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16,
    biBitCount: u16,
    biCompression: u32,
    biSizeImage: u32,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: u32,
    biClrImportant: u32,
};

const BITMAPINFO = extern struct {
    header: BITMAPINFOHEADER,
    colors: [1]u32,
};

extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) HINSTANCE;
extern "user32" fn LoadCursorA(instance: HINSTANCE, name: usize) callconv(.winapi) HANDLE;
extern "user32" fn RegisterClassExA(class: *const WNDCLASSEXA) callconv(.winapi) u16;
extern "user32" fn AdjustWindowRect(rect: *RECT, style: u32, menu: BOOL) callconv(.winapi) BOOL;
extern "user32" fn CreateWindowExA(
    ex_style: u32,
    class_name: [*:0]const u8,
    window_name: [*:0]const u8,
    style: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    parent: HWND,
    menu: HANDLE,
    instance: HINSTANCE,
    param: ?*anyopaque,
) callconv(.winapi) HWND;
extern "user32" fn DestroyWindow(window: HWND) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(window: HWND, cmd: c_int) callconv(.winapi) BOOL;
extern "user32" fn UpdateWindow(window: HWND) callconv(.winapi) BOOL;
extern "user32" fn DefWindowProcA(window: HWND, msg: c_uint, w: WPARAM, l: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn PeekMessageA(msg: *MSG, window: HWND, min: c_uint, max: c_uint, remove: c_uint) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageA(msg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn MsgWaitForMultipleObjects(
    count: u32,
    handles: ?*const anyopaque,
    wait_all: BOOL,
    milliseconds: u32,
    mask: u32,
) callconv(.winapi) u32;
extern "user32" fn GetDC(window: HWND) callconv(.winapi) HDC;
extern "user32" fn ReleaseDC(window: HWND, dc: HDC) callconv(.winapi) c_int;
extern "user32" fn ValidateRect(window: HWND, rect: ?*const RECT) callconv(.winapi) BOOL;
extern "user32" fn SetWindowPos(
    window: HWND,
    after: HWND,
    x: i32,
    y: i32,
    cx: i32,
    cy: i32,
    flags: u32,
) callconv(.winapi) BOOL;
extern "gdi32" fn StretchDIBits(
    dc: HDC,
    dest_x: i32,
    dest_y: i32,
    dest_w: i32,
    dest_h: i32,
    src_x: i32,
    src_y: i32,
    src_w: i32,
    src_h: i32,
    bits: *const anyopaque,
    info: *const BITMAPINFO,
    usage: c_uint,
    rop: u32,
) callconv(.winapi) c_int;

const WS_CAPTION: u32 = 0x00C00000;
const WS_SYSMENU: u32 = 0x00080000;
const WS_MINIMIZEBOX: u32 = 0x00020000;
const window_style: u32 = WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;

const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: c_int = 5;
const IDC_ARROW: usize = 32512;
const CS_OWNDC: c_uint = 0x0020;
const QS_ALLINPUT: u32 = 0x04FF;
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;
const DIB_RGB_COLORS: c_uint = 0;
const SRCCOPY: u32 = 0x00CC0020;

const WM_DESTROY: c_uint = 0x0002;
const WM_CLOSE: c_uint = 0x0010;
const WM_PAINT: c_uint = 0x000F;
const WM_ERASEBKGND: c_uint = 0x0014;
const WM_KILLFOCUS: c_uint = 0x0008;
const WM_KEYDOWN: c_uint = 0x0100;
const WM_CHAR: c_uint = 0x0102;
const WM_MOUSEMOVE: c_uint = 0x0200;
const WM_LBUTTONDOWN: c_uint = 0x0201;
const WM_LBUTTONUP: c_uint = 0x0202;
const WM_RBUTTONDOWN: c_uint = 0x0204;
const WM_RBUTTONUP: c_uint = 0x0205;
const WM_MBUTTONDOWN: c_uint = 0x0207;
const WM_MBUTTONUP: c_uint = 0x0208;

const VK_BACK: WPARAM = 0x08;
const VK_TAB: WPARAM = 0x09;
const VK_RETURN: WPARAM = 0x0D;
const VK_ESCAPE: WPARAM = 0x1B;
const VK_F2: WPARAM = 0x71;

/// The game only ever opens one window, so the procedure can find it here.
var current: ?*Window = null;

fn windowProc(hwnd: HWND, msg: c_uint, w: WPARAM, l: LPARAM) callconv(.winapi) LRESULT {
    const self = current orelse return DefWindowProcA(hwnd, msg, w, l);
    switch (msg) {
        WM_CLOSE, WM_DESTROY => {
            self.should_close = true;
            self.push(.close);
            return 0;
        },
        WM_ERASEBKGND => return 1,
        WM_PAINT => {
            _ = ValidateRect(hwnd, null);
            return 0;
        },
        WM_KILLFOCUS => {
            self.push(.focus_lost);
            return 0;
        },
        WM_MOUSEMOVE => {
            const p = self.mousePos(l);
            self.push(.{ .mouse_move = .{ .x = p.x, .y = p.y } });
            return 0;
        },
        WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN => {
            const p = self.mousePos(l);
            self.push(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = buttonOf(msg) } });
            return 0;
        },
        WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP => {
            const p = self.mousePos(l);
            self.push(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = buttonOf(msg) } });
            return 0;
        },
        WM_KEYDOWN => {
            switch (w) {
                VK_ESCAPE => self.push(.{ .key_down = .escape }),
                VK_RETURN => self.push(.{ .key_down = .enter }),
                VK_BACK => self.push(.{ .key_down = .backspace }),
                VK_TAB => self.push(.{ .key_down = .tab }),
                VK_F2 => self.push(.{ .key_down = .f2 }),
                else => {},
            }
            return 0;
        },
        WM_CHAR => {
            const ch: u8 = @truncate(w);
            if (ch >= 0x20 and ch < 0x7f) self.push(.{ .text = ch });
            return 0;
        },
        else => return DefWindowProcA(hwnd, msg, w, l),
    }
}

fn buttonOf(msg: c_uint) types.MouseButton {
    return switch (msg) {
        WM_RBUTTONDOWN, WM_RBUTTONUP => .right,
        WM_MBUTTONDOWN, WM_MBUTTONUP => .middle,
        else => .left,
    };
}

pub const Window = struct {
    hwnd: HWND,
    scaled: []u32,
    scale: i32,
    width: i32,
    height: i32,
    should_close: bool = false,
    queue: std.ArrayList(types.Event),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: types.WindowOptions) !Window {
        const title = options.title;
        const width = options.width;
        const height = options.height;
        const scale = options.scale;
        const instance = GetModuleHandleA(null);
        const class_name = "SaperWindow";
        const class = WNDCLASSEXA{
            .cbSize = @sizeOf(WNDCLASSEXA),
            .style = CS_OWNDC,
            .lpfnWndProc = windowProc,
            .hInstance = instance,
            .hCursor = LoadCursorA(null, IDC_ARROW),
            .lpszClassName = class_name,
        };
        if (RegisterClassExA(&class) == 0) return error.RegisterClassFailed;

        var rect = RECT{
            .left = 0,
            .top = 0,
            .right = width * scale,
            .bottom = height * scale,
        };
        _ = AdjustWindowRect(&rect, window_style, 0);

        const hwnd = CreateWindowExA(
            0,
            class_name,
            title,
            window_style,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            rect.right - rect.left,
            rect.bottom - rect.top,
            null,
            null,
            instance,
            null,
        ) orelse return error.CreateWindowFailed;

        var self = Window{
            .hwnd = hwnd,
            .scaled = try allocator.alloc(u32, @intCast(width * scale * height * scale)),
            .scale = scale,
            .width = width,
            .height = height,
            .queue = .empty,
            .allocator = allocator,
        };
        current = &self;
        _ = ShowWindow(hwnd, SW_SHOW);
        _ = UpdateWindow(hwnd);
        return self;
    }

    pub fn deinit(self: *Window) void {
        current = null;
        _ = DestroyWindow(self.hwnd);
        self.allocator.free(self.scaled);
        self.queue.deinit(self.allocator);
        self.* = undefined;
    }

    /// Keeps `current` valid if the struct is moved after construction.
    pub fn rebind(self: *Window) void {
        current = self;
    }

    fn mousePos(self: *Window, l: LPARAM) struct { x: i32, y: i32 } {
        const raw: u32 = @truncate(@as(usize, @bitCast(l)));
        const x: i32 = @as(i16, @bitCast(@as(u16, @truncate(raw))));
        const y: i32 = @as(i16, @bitCast(@as(u16, @truncate(raw >> 16))));
        return .{ .x = @divFloor(x, self.scale), .y = @divFloor(y, self.scale) };
    }

    fn push(self: *Window, event: types.Event) void {
        self.queue.append(self.allocator, event) catch {};
    }

    pub fn setSize(self: *Window, width: i32, height: i32) void {
        if (width == self.width and height == self.height) return;
        self.width = width;
        self.height = height;
        const count: usize = @intCast(width * self.scale * height * self.scale);
        self.scaled = self.allocator.realloc(self.scaled, count) catch return;

        var rect = RECT{
            .left = 0,
            .top = 0,
            .right = width * self.scale,
            .bottom = height * self.scale,
        };
        _ = AdjustWindowRect(&rect, window_style, 0);
        _ = SetWindowPos(
            self.hwnd,
            null,
            0,
            0,
            rect.right - rect.left,
            rect.bottom - rect.top,
            SWP_NOMOVE | SWP_NOZORDER,
        );
    }

    pub fn pump(self: *Window, timeout_ms: u32) void {
        _ = self;
        var msg: MSG = .{};
        if (PeekMessageA(&msg, null, 0, 0, 0) == 0) {
            _ = MsgWaitForMultipleObjects(0, null, 0, timeout_ms, QS_ALLINPUT);
        }
        while (PeekMessageA(&msg, null, 0, 0, 1) != 0) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }
    }

    pub fn pollEvent(self: *Window) ?types.Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    pub fn present(self: *Window, fb: *const gfx.Framebuffer) void {
        scaleInto(self.scaled, fb, self.scale);
        const pixel_w = self.width * self.scale;
        const pixel_h = self.height * self.scale;
        const info = BITMAPINFO{
            .header = .{
                .biSize = @sizeOf(BITMAPINFOHEADER),
                .biWidth = pixel_w,
                .biHeight = -pixel_h, // negative means top-down
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = 0,
                .biSizeImage = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .colors = .{0},
        };
        const dc = GetDC(self.hwnd);
        defer _ = ReleaseDC(self.hwnd, dc);
        _ = StretchDIBits(
            dc,
            0,
            0,
            pixel_w,
            pixel_h,
            0,
            0,
            pixel_w,
            pixel_h,
            self.scaled.ptr,
            &info,
            DIB_RGB_COLORS,
            SRCCOPY,
        );
    }
};
