//! Minesweeper rules, exactly as the classic game plays them.

const std = @import("std");

pub const max_width = 30;
pub const max_height = 24;

pub const Mark = enum { none, flag, question };

pub const Cell = struct {
    mine: bool = false,
    revealed: bool = false,
    mark: Mark = .none,
    /// Number of mines in the eight neighbouring cells.
    adjacent: u8 = 0,
    /// Set on the mine the player actually stepped on, drawn on a red field.
    exploded: bool = false,
};

pub const State = enum { ready, playing, won, lost };

pub const Difficulty = enum { beginner, intermediate, expert, custom };

pub const Config = struct {
    width: i32,
    height: i32,
    mines: i32,

    pub const beginner = Config{ .width = 9, .height = 9, .mines = 10 };
    pub const intermediate = Config{ .width = 16, .height = 16, .mines = 40 };
    pub const expert = Config{ .width = 30, .height = 16, .mines = 99 };

    pub fn of(difficulty: Difficulty) Config {
        return switch (difficulty) {
            .beginner => beginner,
            .intermediate => intermediate,
            .expert => expert,
            .custom => beginner,
        };
    }

    /// Clamp a custom board to the limits the original game enforces.
    pub fn clamped(self: Config) Config {
        const width = std.math.clamp(self.width, 9, max_width);
        const height = std.math.clamp(self.height, 9, max_height);
        const max_mines = (width - 1) * (height - 1);
        return .{
            .width = width,
            .height = height,
            .mines = std.math.clamp(self.mines, 1, max_mines),
        };
    }
};

pub const Board = struct {
    cells: [max_width * max_height]Cell = undefined,
    width: i32 = 9,
    height: i32 = 9,
    mines: i32 = 10,
    flags: i32 = 0,
    revealed_count: i32 = 0,
    state: State = .ready,
    /// Milliseconds since the first reveal; frozen once the game ends.
    elapsed_ms: i64 = 0,
    start_ms: i64 = 0,
    question_marks: bool = true,
    rng: std.Random.DefaultPrng,

    pub fn init(config: Config, seed: u64) Board {
        var board = Board{ .rng = std.Random.DefaultPrng.init(seed) };
        board.reset(config);
        return board;
    }

    pub fn reset(self: *Board, config: Config) void {
        const c = config.clamped();
        self.width = c.width;
        self.height = c.height;
        self.mines = c.mines;
        self.flags = 0;
        self.revealed_count = 0;
        self.state = .ready;
        self.elapsed_ms = 0;
        self.start_ms = 0;
        for (self.cells[0..self.cellCount()]) |*cell| cell.* = .{};
    }

    pub fn cellCount(self: *const Board) usize {
        return @intCast(self.width * self.height);
    }

    pub fn inBounds(self: *const Board, x: i32, y: i32) bool {
        return x >= 0 and y >= 0 and x < self.width and y < self.height;
    }

    pub fn at(self: *Board, x: i32, y: i32) *Cell {
        return &self.cells[@intCast(y * self.width + x)];
    }

    pub fn get(self: *const Board, x: i32, y: i32) Cell {
        return self.cells[@intCast(y * self.width + x)];
    }

    pub fn minesLeft(self: *const Board) i32 {
        return self.mines - self.flags;
    }

    pub fn seconds(self: *const Board) i32 {
        return @intCast(@divFloor(self.elapsed_ms, 1000));
    }

    /// Advance the clock. Call once per frame with the current monotonic time.
    pub fn tick(self: *Board, now_ms: i64) void {
        if (self.state != .playing) return;
        self.elapsed_ms = @min(now_ms - self.start_ms, 999_000);
    }

    /// Mines are placed only after the first click, so that click is always safe.
    fn placeMines(self: *Board, safe_x: i32, safe_y: i32) void {
        const total: i32 = @intCast(self.cellCount());
        const safe_index = safe_y * self.width + safe_x;
        var placed: i32 = 0;
        var random = self.rng.random();
        while (placed < self.mines) {
            const index = random.intRangeLessThan(i32, 0, total);
            if (index == safe_index) continue;
            const cell = &self.cells[@intCast(index)];
            if (cell.mine) continue;
            cell.mine = true;
            placed += 1;
        }

        var y: i32 = 0;
        while (y < self.height) : (y += 1) {
            var x: i32 = 0;
            while (x < self.width) : (x += 1) {
                self.at(x, y).adjacent = self.countNeighbors(x, y, isMine);
            }
        }
    }

    fn isMine(cell: Cell) bool {
        return cell.mine;
    }

    fn isFlag(cell: Cell) bool {
        return cell.mark == .flag;
    }

    fn countNeighbors(self: *Board, x: i32, y: i32, predicate: *const fn (Cell) bool) u8 {
        var count: u8 = 0;
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dx == 0 and dy == 0) continue;
                const nx = x + dx;
                const ny = y + dy;
                if (!self.inBounds(nx, ny)) continue;
                if (predicate(self.get(nx, ny))) count += 1;
            }
        }
        return count;
    }

    pub fn reveal(self: *Board, x: i32, y: i32, now_ms: i64) void {
        if (self.state == .won or self.state == .lost) return;
        if (!self.inBounds(x, y)) return;
        const cell = self.at(x, y);
        if (cell.revealed or cell.mark == .flag) return;

        if (self.state == .ready) {
            self.placeMines(x, y);
            self.state = .playing;
            self.start_ms = now_ms;
        }

        if (cell.mine) {
            cell.exploded = true;
            self.lose();
            return;
        }

        self.floodReveal(x, y);
        self.checkWin();
    }

    /// Iterative flood fill so a huge Expert board can never blow the stack.
    /// Cells are revealed as they are pushed, so each one enters the stack at
    /// most once and it can never hold more than the board's cell count.
    fn floodReveal(self: *Board, start_x: i32, start_y: i32) void {
        var stack: [max_width * max_height]u16 = undefined;
        var top: usize = 0;
        if (!self.openCell(start_x, start_y)) return;
        stack[top] = @intCast(start_y * self.width + start_x);
        top += 1;

        while (top > 0) {
            top -= 1;
            const index = stack[top];
            const x = @mod(@as(i32, index), self.width);
            const y = @divFloor(@as(i32, index), self.width);
            if (self.get(x, y).adjacent != 0) continue;

            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    if (dx == 0 and dy == 0) continue;
                    const nx = x + dx;
                    const ny = y + dy;
                    if (!self.inBounds(nx, ny)) continue;
                    if (!self.openCell(nx, ny)) continue;
                    stack[top] = @intCast(ny * self.width + nx);
                    top += 1;
                }
            }
        }
    }

    /// Reveal one safe, unmarked cell; false if it was not eligible.
    fn openCell(self: *Board, x: i32, y: i32) bool {
        const cell = self.at(x, y);
        if (cell.revealed or cell.mark == .flag or cell.mine) return false;
        cell.revealed = true;
        self.revealed_count += 1;
        return true;
    }

    /// Clicking both buttons on a satisfied number opens its unflagged neighbours.
    pub fn chord(self: *Board, x: i32, y: i32) void {
        if (self.state != .playing) return;
        if (!self.inBounds(x, y)) return;
        const cell = self.get(x, y);
        if (!cell.revealed or cell.adjacent == 0) return;
        if (self.countNeighbors(x, y, isFlag) != cell.adjacent) return;

        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dx == 0 and dy == 0) continue;
                const nx = x + dx;
                const ny = y + dy;
                if (!self.inBounds(nx, ny)) continue;
                const neighbor = self.get(nx, ny);
                if (neighbor.revealed or neighbor.mark == .flag) continue;
                if (neighbor.mine) {
                    self.at(nx, ny).exploded = true;
                    self.lose();
                    return;
                }
                self.floodReveal(nx, ny);
            }
        }
        self.checkWin();
    }

    pub fn cycleMark(self: *Board, x: i32, y: i32) void {
        if (self.state == .won or self.state == .lost) return;
        if (!self.inBounds(x, y)) return;
        const cell = self.at(x, y);
        if (cell.revealed) return;
        switch (cell.mark) {
            .none => {
                cell.mark = .flag;
                self.flags += 1;
            },
            .flag => {
                self.flags -= 1;
                cell.mark = if (self.question_marks) .question else .none;
            },
            .question => cell.mark = .none,
        }
    }

    fn lose(self: *Board) void {
        self.state = .lost;
        for (self.cells[0..self.cellCount()]) |*cell| {
            if (cell.mine and cell.mark != .flag) cell.revealed = true;
        }
    }

    fn checkWin(self: *Board) void {
        const safe_cells = @as(i32, @intCast(self.cellCount())) - self.mines;
        if (self.revealed_count < safe_cells) return;
        self.state = .won;
        // The original flags every remaining mine for you on a win.
        for (self.cells[0..self.cellCount()]) |*cell| {
            if (cell.mine and cell.mark != .flag) {
                cell.mark = .flag;
                self.flags += 1;
            }
        }
    }
};

const testing = std.testing;

test "first click is never a mine" {
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var board = Board.init(Config.beginner, seed);
        board.reveal(4, 4, 0);
        try testing.expect(!board.get(4, 4).mine);
        try testing.expect(board.state != .lost);
    }
}

test "mine count matches the configuration" {
    var board = Board.init(Config.expert, 12345);
    board.reveal(0, 0, 0);
    var mines: i32 = 0;
    for (board.cells[0..board.cellCount()]) |cell| {
        if (cell.mine) mines += 1;
    }
    try testing.expectEqual(@as(i32, 99), mines);
}

test "adjacent counts agree with the placed mines" {
    var board = Board.init(Config.intermediate, 777);
    board.reveal(8, 8, 0);
    var y: i32 = 0;
    while (y < board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < board.width) : (x += 1) {
            var expected: u8 = 0;
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    if (dx == 0 and dy == 0) continue;
                    if (!board.inBounds(x + dx, y + dy)) continue;
                    if (board.get(x + dx, y + dy).mine) expected += 1;
                }
            }
            try testing.expectEqual(expected, board.get(x, y).adjacent);
        }
    }
}

test "flagging cannot be revealed and adjusts the counter" {
    var board = Board.init(Config.beginner, 3);
    board.cycleMark(0, 0);
    try testing.expectEqual(Mark.flag, board.get(0, 0).mark);
    try testing.expectEqual(@as(i32, 9), board.minesLeft());
    board.reveal(0, 0, 0);
    try testing.expect(!board.get(0, 0).revealed);
    board.cycleMark(0, 0);
    try testing.expectEqual(Mark.question, board.get(0, 0).mark);
    try testing.expectEqual(@as(i32, 10), board.minesLeft());
    board.cycleMark(0, 0);
    try testing.expectEqual(Mark.none, board.get(0, 0).mark);
}

test "question marks can be turned off" {
    var board = Board.init(Config.beginner, 3);
    board.question_marks = false;
    board.cycleMark(0, 0);
    board.cycleMark(0, 0);
    try testing.expectEqual(Mark.none, board.get(0, 0).mark);
}

test "revealing every safe cell wins and auto-flags the mines" {
    var board = Board.init(Config.beginner, 99);
    board.reveal(0, 0, 0);
    var y: i32 = 0;
    while (y < board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < board.width) : (x += 1) {
            if (!board.get(x, y).mine) board.reveal(x, y, 0);
        }
    }
    try testing.expectEqual(State.won, board.state);
    try testing.expectEqual(@as(i32, 0), board.minesLeft());
}

test "stepping on a mine loses and exposes the field" {
    var board = Board.init(Config.beginner, 42);
    board.reveal(0, 0, 0);
    var mine_x: i32 = -1;
    var mine_y: i32 = -1;
    var y: i32 = 0;
    outer: while (y < board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < board.width) : (x += 1) {
            if (board.get(x, y).mine) {
                mine_x = x;
                mine_y = y;
                break :outer;
            }
        }
    }
    try testing.expect(mine_x >= 0);
    board.reveal(mine_x, mine_y, 0);
    try testing.expectEqual(State.lost, board.state);
    try testing.expect(board.get(mine_x, mine_y).exploded);
    for (board.cells[0..board.cellCount()]) |cell| {
        if (cell.mine) try testing.expect(cell.revealed);
    }
}

test "flood fill opens a whole empty region" {
    var board = Board.init(.{ .width = 9, .height = 9, .mines = 1 }, 5);
    board.reveal(4, 4, 0);
    // With a single mine, one click on an empty cell opens nearly everything.
    try testing.expect(board.revealed_count > 50);
}

test "flood fill on the largest empty board does not overflow" {
    var board = Board.init(.{ .width = max_width, .height = max_height, .mines = 1 }, 1);
    board.reveal(max_width / 2, max_height / 2, 0);
    try testing.expect(board.state == .won or board.state == .playing);
    try testing.expect(board.revealed_count > 600);
}

test "chording opens neighbours only when the flags match" {
    var board = Board.init(.{ .width = 9, .height = 9, .mines = 1 }, 5);
    board.reveal(4, 4, 0);
    // Find a revealed number next to the single mine.
    var target_x: i32 = -1;
    var target_y: i32 = -1;
    var y: i32 = 0;
    outer: while (y < board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < board.width) : (x += 1) {
            const cell = board.get(x, y);
            if (cell.revealed and cell.adjacent == 1) {
                target_x = x;
                target_y = y;
                break :outer;
            }
        }
    }
    try testing.expect(target_x >= 0);

    const before = board.revealed_count;
    board.chord(target_x, target_y); // no flag placed yet -> nothing happens
    try testing.expectEqual(before, board.revealed_count);

    // Flag the mine, then chording is allowed.
    y = 0;
    while (y < board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < board.width) : (x += 1) {
            if (board.get(x, y).mine) board.cycleMark(x, y);
        }
    }
    board.chord(target_x, target_y);
    try testing.expect(board.state != .lost);
}

test "custom boards are clamped to the classic limits" {
    const tiny = (Config{ .width = 2, .height = 2, .mines = 500 }).clamped();
    try testing.expectEqual(@as(i32, 9), tiny.width);
    try testing.expectEqual(@as(i32, 9), tiny.height);
    try testing.expectEqual(@as(i32, 64), tiny.mines);

    const huge = (Config{ .width = 999, .height = 999, .mines = 1 }).clamped();
    try testing.expectEqual(@as(i32, max_width), huge.width);
    try testing.expectEqual(@as(i32, max_height), huge.height);
}

test "the clock stops when the game ends" {
    var board = Board.init(Config.beginner, 7);
    board.reveal(4, 4, 0);
    board.tick(5_000);
    try testing.expectEqual(@as(i32, 5), board.seconds());
    board.state = .won;
    board.tick(60_000);
    try testing.expectEqual(@as(i32, 5), board.seconds());
}
