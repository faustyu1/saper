//! Aggregates every module that carries unit tests.

test {
    _ = @import("game.zig");
    _ = @import("app.zig");
    _ = @import("png.zig");
}
