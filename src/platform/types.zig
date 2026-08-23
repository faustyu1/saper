//! Types shared by every platform backend.

pub const MouseButton = enum { left, right, middle };

pub const Key = enum {
    escape,
    enter,
    backspace,
    tab,
    f2,
    other,
};

pub const Event = union(enum) {
    close,
    mouse_down: struct { x: i32, y: i32, button: MouseButton },
    mouse_up: struct { x: i32, y: i32, button: MouseButton },
    mouse_move: struct { x: i32, y: i32 },
    /// A non-printable key was pressed.
    key_down: Key,
    /// A printable character was typed.
    text: u8,
    /// The window lost focus; the game uses this to cancel a pressed cell.
    focus_lost,
};

/// How a window should be created. Backends ignore what they cannot provide.
pub const WindowOptions = struct {
    title: [*:0]const u8,
    /// Logical framebuffer size, before the scale factor is applied.
    width: i32,
    height: i32,
    scale: i32,
    /// Ask for the macOS Liquid Glass backdrop when the system offers it.
    glass: bool = true,
};
