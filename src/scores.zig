//! Best times, persisted between runs the way the original kept its WINMINE.INI.

const std = @import("std");
const game = @import("game.zig");

pub const max_name = 24;

pub const Entry = struct {
    seconds: i32 = 999,
    name: [max_name]u8 = [_]u8{0} ** max_name,
    name_len: usize = 0,

    pub fn nameSlice(self: *const Entry) []const u8 {
        if (self.name_len == 0) return "Anonymous";
        return self.name[0..self.name_len];
    }
};

pub const Scores = struct {
    entries: [3]Entry = .{ .{}, .{}, .{} },

    pub fn indexOf(difficulty: game.Difficulty) ?usize {
        return switch (difficulty) {
            .beginner => 0,
            .intermediate => 1,
            .expert => 2,
            .custom => null,
        };
    }

    pub fn reset(self: *Scores) void {
        self.* = .{};
        for (&self.entries) |*entry| setName(entry, "Anonymous");
    }

    pub fn isBest(self: *const Scores, difficulty: game.Difficulty, seconds: i32) bool {
        const index = indexOf(difficulty) orelse return false;
        return seconds < self.entries[index].seconds;
    }

    pub fn record(self: *Scores, difficulty: game.Difficulty, seconds: i32, name: []const u8) void {
        const index = indexOf(difficulty) orelse return;
        self.entries[index].seconds = seconds;
        setName(&self.entries[index], name);
    }

    fn setName(entry: *Entry, name: []const u8) void {
        const len = @min(name.len, max_name);
        @memcpy(entry.name[0..len], name[0..len]);
        entry.name_len = len;
    }

    fn path(buf: []u8, home: ?[]const u8) ?[]const u8 {
        const dir = home orelse return null;
        if (dir.len == 0) return null;
        return std.fmt.bufPrint(buf, "{s}/.saper-scores", .{dir}) catch null;
    }

    pub fn load(self: *Scores, io: std.Io, home: ?[]const u8) void {
        self.reset();
        var buf: [512]u8 = undefined;
        const file_path = path(&buf, home) orelse return;
        var content: [1024]u8 = undefined;
        const text = std.Io.Dir.cwd().readFile(io, file_path, &content) catch return;

        var lines = std.mem.splitScalar(u8, text, '\n');
        for (&self.entries) |*entry| {
            const line = lines.next() orelse break;
            var parts = std.mem.splitScalar(u8, line, '\t');
            const seconds_text = parts.next() orelse continue;
            const seconds = std.fmt.parseInt(i32, std.mem.trim(u8, seconds_text, " \r"), 10) catch continue;
            entry.seconds = std.math.clamp(seconds, 1, 999);
            const name = std.mem.trim(u8, parts.next() orelse "", " \r");
            if (name.len > 0) setName(entry, name);
        }
    }

    pub fn save(self: *const Scores, io: std.Io, home: ?[]const u8) void {
        var buf: [512]u8 = undefined;
        const file_path = path(&buf, home) orelse return;
        var out: [1024]u8 = undefined;
        var used: usize = 0;
        for (&self.entries) |*entry| {
            const line = std.fmt.bufPrint(out[used..], "{d}\t{s}\n", .{ entry.seconds, entry.nameSlice() }) catch return;
            used += line.len;
        }
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = out[0..used] }) catch return;
    }
};
