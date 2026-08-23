//! Minimal Objective-C runtime bindings for the macOS backend.
//! We talk to AppKit directly through objc_msgSend so the game has no
//! third-party dependencies at all.

pub const id = ?*anyopaque;
pub const SEL = ?*anyopaque;
pub const Class = ?*anyopaque;

pub extern fn objc_getClass(name: [*:0]const u8) Class;
pub extern fn sel_registerName(name: [*:0]const u8) SEL;
extern fn objc_msgSend() void;

pub const CGFloat = f64;

pub const NSPoint = extern struct { x: CGFloat = 0, y: CGFloat = 0 };
pub const NSSize = extern struct { width: CGFloat = 0, height: CGFloat = 0 };
pub const NSRect = extern struct { origin: NSPoint = .{}, size: NSSize = .{} };

pub inline fn cls(comptime name: [:0]const u8) id {
    return objc_getClass(name.ptr);
}

pub inline fn sel(comptime name: [:0]const u8) SEL {
    return sel_registerName(name.ptr);
}

/// Call an Objective-C method. `Ret` is the return type, `args` is a tuple of
/// the arguments after the implicit self/_cmd pair.
pub inline fn msg(comptime Ret: type, obj: id, s: SEL, args: anytype) Ret {
    const Args = @TypeOf(args);
    const fields = @typeInfo(Args).@"struct".fields;
    const F = switch (fields.len) {
        0 => *const fn (id, SEL) callconv(.c) Ret,
        1 => *const fn (id, SEL, fields[0].type) callconv(.c) Ret,
        2 => *const fn (id, SEL, fields[0].type, fields[1].type) callconv(.c) Ret,
        3 => *const fn (id, SEL, fields[0].type, fields[1].type, fields[2].type) callconv(.c) Ret,
        4 => *const fn (id, SEL, fields[0].type, fields[1].type, fields[2].type, fields[3].type) callconv(.c) Ret,
        else => @compileError("too many arguments"),
    };
    const f: F = @ptrCast(&objc_msgSend);
    return @call(.auto, f, .{ obj, s } ++ args);
}

/// Shorthand: message a class by name.
pub inline fn msgc(comptime Ret: type, comptime name: [:0]const u8, comptime s: [:0]const u8, args: anytype) Ret {
    return msg(Ret, cls(name), sel(s), args);
}

pub fn nsString(text: [*:0]const u8) id {
    return msgc(id, "NSString", "stringWithUTF8String:", .{text});
}
