//! Picks the backend for the host operating system.

const builtin = @import("builtin");

pub const types = @import("types.zig");
pub const Event = types.Event;
pub const Key = types.Key;
pub const MouseButton = types.MouseButton;

pub const Window = switch (builtin.os.tag) {
    .macos => @import("macos.zig").Window,
    .windows => @import("win32.zig").Window,
    else => @import("x11.zig").Window,
};
