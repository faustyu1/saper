//! Application state: the board, the menus, the dialogs and all input handling.

const std = @import("std");
const gfx = @import("gfx.zig");
const font = @import("font.zig");
const game = @import("game.zig");
const layout = @import("layout.zig");
const sprites = @import("sprites.zig");
const widgets = @import("widgets.zig");
const scores_mod = @import("scores.zig");
const types = @import("platform/types.zig");

const Event = types.Event;
const Rect = gfx.Rect;

// ---------------------------------------------------------------- menu model

pub const Action = enum {
    none,
    new_game,
    set_beginner,
    set_intermediate,
    set_expert,
    set_custom,
    toggle_marks,
    best_times,
    exit,
    about,
};

const ItemKind = enum { command, radio, check, separator };

const Item = struct {
    label: []const u8 = "",
    shortcut: []const u8 = "",
    kind: ItemKind = .command,
    action: Action = .none,
};

const Menu = struct {
    title: []const u8,
    items: []const Item,
};

const game_items = [_]Item{
    .{ .label = "New", .shortcut = "F2", .action = .new_game },
    .{ .kind = .separator },
    .{ .label = "Beginner", .kind = .radio, .action = .set_beginner },
    .{ .label = "Intermediate", .kind = .radio, .action = .set_intermediate },
    .{ .label = "Expert", .kind = .radio, .action = .set_expert },
    .{ .label = "Custom...", .kind = .radio, .action = .set_custom },
    .{ .kind = .separator },
    .{ .label = "Marks (?)", .kind = .check, .action = .toggle_marks },
    .{ .kind = .separator },
    .{ .label = "Best Times...", .action = .best_times },
    .{ .kind = .separator },
    .{ .label = "Exit", .action = .exit },
};

const help_items = [_]Item{
    .{ .label = "About Saper...", .action = .about },
};

const menus = [_]Menu{
    .{ .title = "Game", .items = &game_items },
    .{ .title = "Help", .items = &help_items },
};

const menu_item_h = 15;
const menu_sep_h = 7;
const menu_gutter = 16;
const menu_gap = 22;
const menu_right_pad = 10;

// -------------------------------------------------------------- text buffers

const TextBuf = struct {
    data: [scores_mod.max_name]u8 = undefined,
    len: usize = 0,

    fn slice(self: *const TextBuf) []const u8 {
        return self.data[0..self.len];
    }

    fn set(self: *TextBuf, value: []const u8) void {
        self.len = @min(value.len, self.data.len);
        @memcpy(self.data[0..self.len], value[0..self.len]);
    }

    fn setInt(self: *TextBuf, value: i32) void {
        var buf: [12]u8 = undefined;
        self.set(std.fmt.bufPrint(&buf, "{d}", .{value}) catch "0");
    }

    fn push(self: *TextBuf, ch: u8, limit: usize) void {
        if (self.len >= @min(limit, self.data.len)) return;
        self.data[self.len] = ch;
        self.len += 1;
    }

    fn pop(self: *TextBuf) void {
        if (self.len > 0) self.len -= 1;
    }

    fn toInt(self: *const TextBuf, fallback: i32) i32 {
        return std.fmt.parseInt(i32, self.slice(), 10) catch fallback;
    }
};

// ------------------------------------------------------------------ dialogs

const CustomDialog = struct {
    fields: [3]TextBuf = .{ .{}, .{}, .{} },
    focus: usize = 0,
};

const NewBestDialog = struct {
    level: usize,
    seconds: i32,
    name: TextBuf = .{},
};

const Dialog = union(enum) {
    none,
    custom: CustomDialog,
    best_times,
    about,
    new_best: NewBestDialog,
};

const level_names = [3][]const u8{ "Beginner", "Intermediate", "Expert" };

// ---------------------------------------------------------------------- app

pub const App = struct {
    board: game.Board,
    metrics: layout.Layout,
    difficulty: game.Difficulty = .beginner,
    custom_config: game.Config = game.Config.beginner,
    marks_enabled: bool = true,
    scores: scores_mod.Scores = .{},
    /// Directory the best-times file lives in; null disables persistence.
    home: ?[]const u8 = null,
    io: std.Io,
    /// Wall-clock milliseconds, refreshed once per frame by the main loop.
    now_ms: i64 = 0,
    /// Set whenever something visible changed, so the loop can idle otherwise.
    dirty: bool = true,
    shown_seconds: i32 = -1,
    shown_mines: i32 = std.math.minInt(i32),
    should_quit: bool = false,

    // Pointer state.
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    left_down: bool = false,
    right_down: bool = false,
    chording: bool = false,
    swallow_release: bool = false,
    face_pressed: bool = false,
    pressed_cell: ?struct { x: i32, y: i32 } = null,

    // Menu state.
    open_menu: ?usize = null,
    menu_hover: ?usize = null,

    // Dialog state.
    dialog: Dialog = .none,
    dialog_pressed: ?usize = null,

    pub fn init(io: std.Io, home: ?[]const u8, seed: u64) App {
        var scores: scores_mod.Scores = .{};
        scores.load(io, home);
        const config = game.Config.beginner;
        return .{
            .board = game.Board.init(config, seed),
            .metrics = layout.compute(config.width, config.height),
            .scores = scores,
            .home = home,
            .io = io,
        };
    }

    fn currentConfig(self: *const App) game.Config {
        return switch (self.difficulty) {
            .custom => self.custom_config,
            else => game.Config.of(self.difficulty),
        };
    }

    /// Runs a menu command directly. Used by keyboard shortcuts and by the
    /// screenshot tool.
    pub fn applyMenuAction(self: *App, action: Action) void {
        self.runAction(action);
    }

    pub fn setDifficulty(self: *App, difficulty: game.Difficulty) void {
        self.difficulty = difficulty;
        self.newGame();
    }

    pub fn newGame(self: *App) void {
        const config = self.currentConfig().clamped();
        self.board.reset(config);
        self.board.question_marks = self.marks_enabled;
        self.metrics = layout.compute(config.width, config.height);
        self.pressed_cell = null;
        self.left_down = false;
        self.right_down = false;
        self.chording = false;
        self.face_pressed = false;
    }

    // ------------------------------------------------------------- updating

    pub fn tick(self: *App, now_ms: i64) void {
        self.now_ms = now_ms;
        self.board.tick(now_ms);
        if (self.board.seconds() != self.shown_seconds or self.board.minesLeft() != self.shown_mines) {
            self.dirty = true;
        }
    }

    /// True when the framebuffer needs to be redrawn and presented again.
    pub fn needsRedraw(self: *const App) bool {
        return self.dirty;
    }

    fn faceOf(self: *const App) sprites.Face {
        if (self.board.state == .lost) return .dead;
        if (self.board.state == .won) return .cool;
        if (self.pressed_cell != null) return .surprised;
        return .smile;
    }

    // -------------------------------------------------------------- input

    /// A fingerprint of everything the pointer position can change on screen.
    /// Plain movement that does not alter it needs no redraw.
    fn hoverSignature(self: *const App) u64 {
        var h: u64 = 0;
        if (self.pressed_cell) |p| {
            h |= (@as(u64, @intCast(p.x + 1)) << 1) | (@as(u64, @intCast(p.y + 1)) << 9);
        }
        h |= @as(u64, @intFromBool(self.chording)) << 17;
        if (self.menu_hover) |m| h |= (@as(u64, m) + 1) << 18;
        if (self.face_pressed and self.metrics.face.contains(self.mouse_x, self.mouse_y)) h |= 1 << 30;
        if (self.dialog_pressed) |i| {
            const hit = if (i < 2) self.dialogPressed(i) else self.dialogClosePressed();
            if (hit) h |= @as(u64, 1) << 31;
        }
        return h;
    }

    pub fn handle(self: *App, event: Event) void {
        const before = self.hoverSignature();
        defer switch (event) {
            .mouse_move => if (self.hoverSignature() != before) {
                self.dirty = true;
            },
            else => self.dirty = true,
        };
        switch (event) {
            .close => self.should_quit = true,
            .focus_lost => {
                self.left_down = false;
                self.right_down = false;
                self.chording = false;
                self.pressed_cell = null;
                self.face_pressed = false;
            },
            .mouse_move => |m| {
                self.mouse_x = m.x;
                self.mouse_y = m.y;
                self.onMouseMove();
            },
            .mouse_down => |m| {
                self.mouse_x = m.x;
                self.mouse_y = m.y;
                self.onMouseDown(m.button);
            },
            .mouse_up => |m| {
                self.mouse_x = m.x;
                self.mouse_y = m.y;
                self.onMouseUp(m.button);
            },
            .key_down => |key| self.onKey(key),
            .text => |ch| self.onText(ch),
        }
    }

    fn onMouseMove(self: *App) void {
        if (self.dialog != .none) return;
        if (self.open_menu) |open| {
            // Sliding across the menu bar switches menus, as it should.
            if (self.metrics.menu_bar.contains(self.mouse_x, self.mouse_y)) {
                if (self.menuBarHit()) |index| self.open_menu = index;
                self.menu_hover = null;
                return;
            }
            self.menu_hover = self.menuItemHit(open);
            return;
        }
        if (self.left_down or self.chording) self.updatePressedCell();
        if (self.face_pressed) {
            // nothing extra: the button redraws from mouse position
        }
    }

    fn onMouseDown(self: *App, button: types.MouseButton) void {
        if (self.dialog != .none) {
            if (button == .left) self.dialogMouseDown();
            return;
        }

        if (self.open_menu != null) {
            self.menuMouseDown();
            return;
        }

        if (self.metrics.menu_bar.contains(self.mouse_x, self.mouse_y)) {
            if (self.menuBarHit()) |index| {
                self.open_menu = index;
                self.menu_hover = null;
            }
            return;
        }

        if (self.metrics.face.contains(self.mouse_x, self.mouse_y) and button == .left) {
            self.face_pressed = true;
            return;
        }

        switch (button) {
            .left => {
                self.left_down = true;
                if (self.right_down) self.chording = true;
                self.updatePressedCell();
            },
            .right => {
                self.right_down = true;
                if (self.left_down) {
                    self.chording = true;
                    self.updatePressedCell();
                } else if (layout.cellAt(self.metrics, self.mouse_x, self.mouse_y)) |c| {
                    self.board.cycleMark(c.x, c.y);
                }
            },
            .middle => {
                self.chording = true;
                self.updatePressedCell();
            },
        }
    }

    fn onMouseUp(self: *App, button: types.MouseButton) void {
        if (self.dialog != .none) {
            if (button == .left) self.dialogMouseUp();
            return;
        }

        if (self.face_pressed and button == .left) {
            self.face_pressed = false;
            if (self.metrics.face.contains(self.mouse_x, self.mouse_y)) self.newGame();
            return;
        }

        const was_chording = self.chording;
        switch (button) {
            .left => self.left_down = false,
            .right => self.right_down = false,
            .middle => {},
        }

        const cell = layout.cellAt(self.metrics, self.mouse_x, self.mouse_y);
        self.pressed_cell = null;

        if (was_chording) {
            self.chording = false;
            self.swallow_release = self.left_down or self.right_down;
            if (cell) |c| self.board.chord(c.x, c.y);
            self.afterMove();
            return;
        }

        if (self.swallow_release) {
            if (!self.left_down and !self.right_down) self.swallow_release = false;
            return;
        }

        if (button == .left) {
            if (cell) |c| {
                self.board.reveal(c.x, c.y, self.now_ms);
                self.afterMove();
            }
        }
    }

    fn updatePressedCell(self: *App) void {
        if (self.board.state == .won or self.board.state == .lost) {
            self.pressed_cell = null;
            return;
        }
        if (layout.cellAt(self.metrics, self.mouse_x, self.mouse_y)) |c| {
            self.pressed_cell = .{ .x = c.x, .y = c.y };
        } else {
            self.pressed_cell = null;
        }
    }

    /// Checks for a new record once a move has resolved.
    fn afterMove(self: *App) void {
        if (self.board.state != .won) return;
        const seconds = self.board.seconds();
        if (!self.scores.isBest(self.difficulty, seconds)) return;
        const level = scores_mod.Scores.indexOf(self.difficulty) orelse return;
        var dialog = NewBestDialog{ .level = level, .seconds = seconds };
        dialog.name.set(self.scores.entries[level].nameSlice());
        self.dialog = .{ .new_best = dialog };
    }

    fn onKey(self: *App, key: types.Key) void {
        switch (self.dialog) {
            .none => switch (key) {
                .f2 => self.newGame(),
                .escape => self.open_menu = null,
                else => {},
            },
            .custom => |*d| switch (key) {
                .escape => self.dialog = .none,
                .enter => self.applyCustom(),
                .tab => d.focus = (d.focus + 1) % 3,
                .backspace => d.fields[d.focus].pop(),
                else => {},
            },
            .new_best => |*d| switch (key) {
                .enter, .escape => self.commitNewBest(d.*),
                .backspace => d.name.pop(),
                else => {},
            },
            .best_times, .about => switch (key) {
                .escape, .enter => self.dialog = .none,
                else => {},
            },
        }
    }

    fn onText(self: *App, ch: u8) void {
        switch (self.dialog) {
            .custom => |*d| {
                if (ch >= '0' and ch <= '9') d.fields[d.focus].push(ch, 3);
            },
            .new_best => |*d| d.name.push(ch, scores_mod.max_name),
            else => {},
        }
    }

    // --------------------------------------------------------------- menus

    fn menuBarRect(index: usize) Rect {
        var x: i32 = 4;
        for (menus, 0..) |menu, i| {
            const w = font.textWidth(menu.title) + 14;
            if (i == index) return .{ .x = x, .y = 1, .w = w, .h = layout.menu_h - 2 };
            x += w;
        }
        unreachable;
    }

    fn menuBarHit(self: *const App) ?usize {
        for (menus, 0..) |_, i| {
            if (menuBarRect(i).contains(self.mouse_x, self.mouse_y)) return i;
        }
        return null;
    }

    fn dropdownRect(index: usize) Rect {
        const menu = menus[index];
        var label_w: i32 = 0;
        var shortcut_w: i32 = 0;
        var height: i32 = 4;
        for (menu.items) |item| {
            if (item.kind == .separator) {
                height += menu_sep_h;
                continue;
            }
            height += menu_item_h;
            label_w = @max(label_w, font.textWidth(item.label));
            shortcut_w = @max(shortcut_w, font.textWidth(item.shortcut));
        }
        const width = menu_gutter + label_w + menu_gap + shortcut_w + menu_right_pad;
        const bar = menuBarRect(index);
        return .{ .x = bar.x, .y = layout.menu_h, .w = width, .h = height };
    }

    fn menuItemRect(index: usize, item_index: usize) Rect {
        const drop = dropdownRect(index);
        var y = drop.y + 2;
        for (menus[index].items, 0..) |item, i| {
            const h: i32 = if (item.kind == .separator) menu_sep_h else menu_item_h;
            if (i == item_index) return .{ .x = drop.x + 2, .y = y, .w = drop.w - 4, .h = h };
            y += h;
        }
        unreachable;
    }

    fn menuItemHit(self: *const App, index: usize) ?usize {
        for (menus[index].items, 0..) |item, i| {
            if (item.kind == .separator) continue;
            if (menuItemRect(index, i).contains(self.mouse_x, self.mouse_y)) return i;
        }
        return null;
    }

    fn menuMouseDown(self: *App) void {
        const open = self.open_menu.?;
        if (self.metrics.menu_bar.contains(self.mouse_x, self.mouse_y)) {
            const hit = self.menuBarHit();
            self.open_menu = if (hit != null and hit.? == open) null else hit;
            return;
        }
        if (self.menuItemHit(open)) |item_index| {
            const action = menus[open].items[item_index].action;
            self.open_menu = null;
            self.menu_hover = null;
            self.runAction(action);
            return;
        }
        self.open_menu = null;
        self.menu_hover = null;
    }

    fn runAction(self: *App, action: Action) void {
        switch (action) {
            .none => {},
            .new_game => self.newGame(),
            .set_beginner => {
                self.difficulty = .beginner;
                self.newGame();
            },
            .set_intermediate => {
                self.difficulty = .intermediate;
                self.newGame();
            },
            .set_expert => {
                self.difficulty = .expert;
                self.newGame();
            },
            .set_custom => {
                var d = CustomDialog{};
                d.fields[0].setInt(self.custom_config.height);
                d.fields[1].setInt(self.custom_config.width);
                d.fields[2].setInt(self.custom_config.mines);
                self.dialog = .{ .custom = d };
            },
            .toggle_marks => {
                self.marks_enabled = !self.marks_enabled;
                self.board.question_marks = self.marks_enabled;
            },
            .best_times => self.dialog = .best_times,
            .about => self.dialog = .about,
            .exit => self.should_quit = true,
        }
    }

    fn applyCustom(self: *App) void {
        const d = switch (self.dialog) {
            .custom => |c| c,
            else => return,
        };
        self.custom_config = (game.Config{
            .height = d.fields[0].toInt(9),
            .width = d.fields[1].toInt(9),
            .mines = d.fields[2].toInt(10),
        }).clamped();
        self.difficulty = .custom;
        self.dialog = .none;
        self.newGame();
    }

    fn commitNewBest(self: *App, d: NewBestDialog) void {
        const name = if (d.name.len == 0) "Anonymous" else d.name.slice();
        self.scores.record(self.difficulty, d.seconds, name);
        self.scores.save(self.io, self.home);
        self.dialog = .best_times;
    }

    // ------------------------------------------------------------- dialogs

    const DialogLayout = struct {
        frame: Rect,
        title: Rect,
        close: Rect,
        buttons: [2]Rect,
        button_count: usize,
        fields: [3]Rect,
        field_count: usize,
    };

    /// Dialogs are drawn inside the game window, so they are laid out to fit
    /// even the narrow Beginner board and clamped to stay on screen.
    fn dialogLayout(self: *const App) ?DialogLayout {
        const size: struct { w: i32, h: i32 } = switch (self.dialog) {
            .none => return null,
            .custom => .{ .w = 158, .h = 120 },
            .best_times => .{ .w = 158, .h = 126 },
            .about => .{ .w = 158, .h = 150 },
            .new_best => .{ .w = 158, .h = 114 },
        };
        const frame = Rect{
            .x = std.math.clamp(@divTrunc(self.metrics.width - size.w, 2), 2, @max(2, self.metrics.width - size.w - 2)),
            .y = std.math.clamp(@divTrunc(self.metrics.height - size.h, 2), 2, @max(2, self.metrics.height - size.h - 2)),
            .w = size.w,
            .h = size.h,
        };
        const title = Rect{ .x = frame.x + 3, .y = frame.y + 3, .w = frame.w - 6, .h = 16 };
        const close = Rect{ .x = title.x + title.w - 15, .y = title.y + 2, .w = 13, .h = title.h - 4 };

        const empty = Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        var out = DialogLayout{
            .frame = frame,
            .title = title,
            .close = close,
            .buttons = .{ empty, empty },
            .button_count = 0,
            .fields = .{ empty, empty, empty },
            .field_count = 0,
        };

        switch (self.dialog) {
            .custom => {
                var i: i32 = 0;
                while (i < 3) : (i += 1) {
                    out.fields[@intCast(i)] = .{
                        .x = frame.x + 80,
                        .y = frame.y + 26 + i * 21,
                        .w = 48,
                        .h = 15,
                    };
                }
                out.field_count = 3;
                out.buttons[0] = .{ .x = frame.x + 16, .y = frame.y + 92, .w = 54, .h = 20 };
                out.buttons[1] = .{ .x = frame.x + 88, .y = frame.y + 92, .w = 54, .h = 20 };
                out.button_count = 2;
            },
            .best_times => {
                out.buttons[0] = .{ .x = frame.x + 8, .y = frame.y + 96, .w = 78, .h = 20 };
                out.buttons[1] = .{ .x = frame.x + 94, .y = frame.y + 96, .w = 56, .h = 20 };
                out.button_count = 2;
            },
            .about => {
                out.buttons[0] = .{ .x = frame.x + @divTrunc(frame.w - 54, 2), .y = frame.y + 120, .w = 54, .h = 20 };
                out.button_count = 1;
            },
            .new_best => {
                out.fields[0] = .{ .x = frame.x + 10, .y = frame.y + 64, .w = frame.w - 20, .h = 15 };
                out.field_count = 1;
                out.buttons[0] = .{ .x = frame.x + @divTrunc(frame.w - 54, 2), .y = frame.y + 86, .w = 54, .h = 20 };
                out.button_count = 1;
            },
            else => {},
        }
        return out;
    }

    fn dialogMouseDown(self: *App) void {
        const dl = self.dialogLayout() orelse return;
        if (dl.close.contains(self.mouse_x, self.mouse_y)) {
            self.dialog_pressed = 99;
            return;
        }
        var i: usize = 0;
        while (i < dl.button_count) : (i += 1) {
            if (dl.buttons[i].contains(self.mouse_x, self.mouse_y)) {
                self.dialog_pressed = i;
                return;
            }
        }
        switch (self.dialog) {
            .custom => |*d| {
                var f: usize = 0;
                while (f < dl.field_count) : (f += 1) {
                    if (dl.fields[f].contains(self.mouse_x, self.mouse_y)) d.focus = f;
                }
            },
            else => {},
        }
    }

    fn dialogMouseUp(self: *App) void {
        const pressed = self.dialog_pressed orelse return;
        self.dialog_pressed = null;
        const dl = self.dialogLayout() orelse return;

        if (pressed == 99) {
            if (dl.close.contains(self.mouse_x, self.mouse_y)) self.closeDialog();
            return;
        }
        if (!dl.buttons[pressed].contains(self.mouse_x, self.mouse_y)) return;

        switch (self.dialog) {
            .custom => {
                if (pressed == 0) self.applyCustom() else self.dialog = .none;
            },
            .best_times => {
                if (pressed == 0) {
                    self.scores.reset();
                    self.scores.save(self.io, self.home);
                } else {
                    self.dialog = .none;
                }
            },
            .about => self.dialog = .none,
            .new_best => |d| self.commitNewBest(d),
            .none => {},
        }
    }

    fn closeDialog(self: *App) void {
        switch (self.dialog) {
            .new_best => |d| self.commitNewBest(d),
            else => self.dialog = .none,
        }
    }

    // -------------------------------------------------------------- drawing

    pub fn render(self: *App, fb: *gfx.Framebuffer) void {
        self.dirty = false;
        self.shown_seconds = self.board.seconds();
        self.shown_mines = self.board.minesLeft();
        const m = self.metrics;
        fb.clear(widgets.face);

        self.drawMenuBar(fb);

        widgets.panel(fb, m.body, layout.outer_bevel);

        widgets.sunken(fb, m.header, layout.panel_bevel);
        widgets.ledCounter(fb, m.mine_counter, self.board.minesLeft());
        widgets.ledCounter(fb, m.timer, self.board.seconds());
        self.drawFaceButton(fb);

        widgets.sunken(fb, m.field_frame, layout.field_bevel);
        self.drawField(fb);

        if (self.open_menu) |index| self.drawDropdown(fb, index);
        self.drawDialog(fb);
    }

    fn drawMenuBar(self: *const App, fb: *gfx.Framebuffer) void {
        fb.fill(self.metrics.menu_bar, widgets.face);
        for (menus, 0..) |menu, i| {
            const r = menuBarRect(i);
            const open = self.open_menu != null and self.open_menu.? == i;
            if (open) fb.fill(r, widgets.highlight);
            widgets.centerText(fb, r, menu.title, if (open) widgets.highlight_text else widgets.text);
        }
        fb.hLine(0, layout.menu_h - 1, self.metrics.width, widgets.shadow);
    }

    fn drawDropdown(self: *const App, fb: *gfx.Framebuffer, index: usize) void {
        const drop = dropdownRect(index);
        fb.fill(drop, widgets.face);
        widgets.raised(fb, drop, 1);
        fb.frame(drop, widgets.shadow);
        widgets.raised(fb, drop.inset(1), 1);

        for (menus[index].items, 0..) |item, i| {
            const r = menuItemRect(index, i);
            if (item.kind == .separator) {
                fb.hLine(r.x + 2, r.y + @divTrunc(r.h, 2), r.w - 4, widgets.shadow);
                fb.hLine(r.x + 2, r.y + @divTrunc(r.h, 2) + 1, r.w - 4, widgets.light);
                continue;
            }
            const hovered = self.menu_hover != null and self.menu_hover.? == i;
            if (hovered) fb.fill(r, widgets.highlight);
            const color = if (hovered) widgets.highlight_text else widgets.text;
            const ty = r.y + @divTrunc(r.h - font.glyph_height, 2);
            font.drawText(fb, r.x + menu_gutter, ty, item.label, color);
            if (item.shortcut.len > 0) {
                const sx = r.x + r.w - menu_right_pad - font.textWidth(item.shortcut);
                font.drawText(fb, sx, ty, item.shortcut, color);
            }
            switch (item.kind) {
                .radio => if (self.isSelected(item.action)) widgets.bullet(fb, r.x + 6, ty + 2, color),
                .check => if (self.marks_enabled) widgets.checkMark(fb, r.x + 5, ty, color),
                else => {},
            }
        }
    }

    fn isSelected(self: *const App, action: Action) bool {
        return switch (action) {
            .set_beginner => self.difficulty == .beginner,
            .set_intermediate => self.difficulty == .intermediate,
            .set_expert => self.difficulty == .expert,
            .set_custom => self.difficulty == .custom,
            else => false,
        };
    }

    fn drawFaceButton(self: *const App, fb: *gfx.Framebuffer) void {
        const r = self.metrics.face;
        fb.fill(r, widgets.face);
        const held = self.face_pressed and r.contains(self.mouse_x, self.mouse_y);
        if (held) {
            widgets.sunken(fb, r, 1);
        } else {
            widgets.raised(fb, r, 2);
        }
        const offset: i32 = if (held) 1 else 0;
        const fx = r.x + @divTrunc(r.w - sprites.face_size, 2) + offset;
        const fy = r.y + @divTrunc(r.h - sprites.face_size, 2) + offset;
        sprites.drawFace(fb, fx, fy, self.faceOf());
    }

    fn drawField(self: *const App, fb: *gfx.Framebuffer) void {
        const m = self.metrics;
        var y: i32 = 0;
        while (y < m.rows) : (y += 1) {
            var x: i32 = 0;
            while (x < m.cols) : (x += 1) {
                const px = m.field.x + x * layout.cell;
                const py = m.field.y + y * layout.cell;
                self.drawCell(fb, px, py, x, y);
            }
        }
    }

    fn isPressedCell(self: *const App, x: i32, y: i32) bool {
        const p = self.pressed_cell orelse return false;
        if (self.chording) {
            return @abs(p.x - x) <= 1 and @abs(p.y - y) <= 1;
        }
        return p.x == x and p.y == y;
    }

    fn drawCell(self: *const App, fb: *gfx.Framebuffer, px: i32, py: i32, x: i32, y: i32) void {
        const cell = self.board.get(x, y);
        const r = Rect{ .x = px, .y = py, .w = layout.cell, .h = layout.cell };
        const lost = self.board.state == .lost;

        if (!cell.revealed) {
            const pressed = self.isPressedCell(x, y) and cell.mark != .flag;
            if (pressed) {
                fb.fill(r, widgets.face);
                fb.hLine(px, py, layout.cell, widgets.shadow);
                fb.vLine(px, py, layout.cell, widgets.shadow);
            } else {
                fb.fill(r, widgets.face);
                fb.bevel(r, 2, widgets.light, widgets.shadow);
            }
            switch (cell.mark) {
                .flag => {
                    sprites.drawTile(fb, px, py, &sprites.flag);
                    if (lost and !cell.mine) {
                        fb.fill(r.inset(2), widgets.face);
                        sprites.drawTile(fb, px, py, &sprites.mine);
                        sprites.drawWrongMark(fb, px, py);
                    }
                },
                .question => sprites.drawDigit(
                    fb,
                    px + @divTrunc(layout.cell - sprites.digit_width, 2),
                    py + @divTrunc(layout.cell - sprites.digit_height, 2),
                    sprites.question_index,
                    widgets.text,
                ),
                .none => {},
            }
            return;
        }

        // Revealed cells are flat with a single grey rule along the top and left.
        fb.fill(r, if (cell.exploded) widgets.led_on else widgets.face);
        fb.hLine(px, py, layout.cell, widgets.shadow);
        fb.vLine(px, py, layout.cell, widgets.shadow);

        if (cell.mine) {
            sprites.drawTile(fb, px, py, &sprites.mine);
            return;
        }
        if (cell.adjacent > 0) {
            sprites.drawDigit(
                fb,
                px + @divTrunc(layout.cell - sprites.digit_width, 2) + 1,
                py + @divTrunc(layout.cell - sprites.digit_height, 2) + 1,
                cell.adjacent - 1,
                sprites.number_colors[cell.adjacent - 1],
            );
        }
    }

    fn drawDialog(self: *const App, fb: *gfx.Framebuffer) void {
        const dl = self.dialogLayout() orelse return;
        const frame = dl.frame;
        fb.fill(frame, widgets.face);
        widgets.raised(fb, frame, 2);
        fb.frame(frame, widgets.dark);

        const title: []const u8 = switch (self.dialog) {
            .custom => "Custom Field",
            .best_times => "Fastest Mine Sweepers",
            .about => "About Saper",
            .new_best => "Congratulations",
            .none => "",
        };
        _ = widgets.titleBar(fb, dl.title, title);

        const left = frame.x + 8;
        switch (self.dialog) {
            .custom => |d| {
                const labels = [3][]const u8{ "Height:", "Width:", "Mines:" };
                for (labels, 0..) |label, i| {
                    const fr = dl.fields[i];
                    font.drawText(fb, left, fr.y + 4, label, widgets.text);
                    widgets.textField(fb, fr, d.fields[i].slice(), d.focus == i);
                }
                widgets.defaultButton(fb, dl.buttons[0], "OK", self.dialogPressed(0));
                widgets.button(fb, dl.buttons[1], "Cancel", self.dialogPressed(1));
            },
            .best_times => {
                var i: usize = 0;
                while (i < 3) : (i += 1) {
                    const y = frame.y + 26 + @as(i32, @intCast(i)) * 22;
                    const entry = self.scores.entries[i];
                    var buf: [32]u8 = undefined;
                    const heading = std.fmt.bufPrint(&buf, "{s}:", .{level_names[i]}) catch level_names[i];
                    font.drawText(fb, left, y, heading, widgets.text);

                    var time_buf: [24]u8 = undefined;
                    const seconds = std.fmt.bufPrint(&time_buf, "{d} seconds", .{entry.seconds}) catch "?";
                    font.drawText(fb, left + 12, y + 11, seconds, widgets.text);

                    const name = entry.nameSlice();
                    const name_x = frame.x + frame.w - 8 - font.textWidth(name);
                    font.drawText(fb, @max(name_x, left + 90), y + 11, name, widgets.text);
                }
                widgets.button(fb, dl.buttons[0], "Reset Scores", self.dialogPressed(0));
                widgets.defaultButton(fb, dl.buttons[1], "OK", self.dialogPressed(1));
            },
            .about => {
                const lines = [_][]const u8{
                    "Saper - Minesweeper,",
                    "written in Zig with no",
                    "outside dependencies.",
                    "",
                    "Left click opens a cell,",
                    "right click flags it,",
                    "both together clear",
                    "around a number.",
                };
                for (lines, 0..) |line, i| {
                    font.drawText(fb, left, frame.y + 26 + @as(i32, @intCast(i)) * 11, line, widgets.text);
                }
                widgets.defaultButton(fb, dl.buttons[0], "OK", self.dialogPressed(0));
            },
            .new_best => |d| {
                var buf: [48]u8 = undefined;
                const line = std.fmt.bufPrint(
                    &buf,
                    "time for {s} level.",
                    .{level_names[d.level]},
                ) catch "level.";
                font.drawText(fb, left, frame.y + 28, "You have the fastest", widgets.text);
                font.drawText(fb, left, frame.y + 39, line, widgets.text);
                font.drawText(fb, left, frame.y + 52, "Please enter your name:", widgets.text);
                widgets.textField(fb, dl.fields[0], d.name.slice(), true);
                widgets.defaultButton(fb, dl.buttons[0], "OK", self.dialogPressed(0));
            },
            .none => {},
        }
    }

    fn dialogClosePressed(self: *const App) bool {
        const dl = self.dialogLayout() orelse return false;
        return dl.close.contains(self.mouse_x, self.mouse_y);
    }

    fn dialogPressed(self: *const App, index: usize) bool {
        const pressed = self.dialog_pressed orelse return false;
        if (pressed != index) return false;
        const dl = self.dialogLayout() orelse return false;
        return dl.buttons[index].contains(self.mouse_x, self.mouse_y);
    }
};


const testing = std.testing;

/// Builds an app with score persistence switched off, so no `Io` is touched.
fn testApp(seed: u64) App {
    return App.init(undefined, null, seed);
}

fn cellCenter(app: *const App, cx: i32, cy: i32) struct { x: i32, y: i32 } {
    return .{
        .x = app.metrics.field.x + cx * layout.cell + layout.cell / 2,
        .y = app.metrics.field.y + cy * layout.cell + layout.cell / 2,
    };
}

fn clickAt(app: *App, x: i32, y: i32, button: types.MouseButton) void {
    app.handle(.{ .mouse_move = .{ .x = x, .y = y } });
    app.handle(.{ .mouse_down = .{ .x = x, .y = y, .button = button } });
    app.handle(.{ .mouse_up = .{ .x = x, .y = y, .button = button } });
}

fn clickCell(app: *App, cx: i32, cy: i32, button: types.MouseButton) void {
    const p = cellCenter(app, cx, cy);
    clickAt(app, p.x, p.y, button);
}

test "a left click opens a cell" {
    var app = testApp(1);
    clickCell(&app, 4, 4, .left);
    try testing.expect(app.board.get(4, 4).revealed);
    try testing.expectEqual(game.State.playing, app.board.state);
}

test "a right click flags and updates the mine counter" {
    var app = testApp(1);
    try testing.expectEqual(@as(i32, 10), app.board.minesLeft());
    clickCell(&app, 0, 0, .right);
    try testing.expectEqual(game.Mark.flag, app.board.get(0, 0).mark);
    try testing.expectEqual(@as(i32, 9), app.board.minesLeft());
}

test "clicks outside the field do nothing" {
    var app = testApp(1);
    clickAt(&app, 2, app.metrics.height - 2, .left);
    try testing.expectEqual(game.State.ready, app.board.state);
}

test "the smiley button starts a new game" {
    var app = testApp(1);
    clickCell(&app, 4, 4, .left);
    try testing.expectEqual(game.State.playing, app.board.state);
    const face = app.metrics.face;
    clickAt(&app, face.x + 13, face.y + 13, .left);
    try testing.expectEqual(game.State.ready, app.board.state);
}

test "F2 starts a new game" {
    var app = testApp(1);
    clickCell(&app, 4, 4, .left);
    app.handle(.{ .key_down = .f2 });
    try testing.expectEqual(game.State.ready, app.board.state);
}

test "holding both buttons chords once released" {
    var app = testApp(5);

    // Hand-build a known position: one mine at (1,0) touching four cells.
    app.board.reset(.{ .width = 9, .height = 9, .mines = 1 });
    app.board.at(1, 0).mine = true;
    for ([_][2]i32{ .{ 0, 0 }, .{ 2, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 } }) |p| {
        app.board.at(p[0], p[1]).adjacent = 1;
    }
    app.board.at(0, 0).revealed = true;
    app.board.revealed_count = 1;
    app.board.state = .playing;

    clickCell(&app, 1, 0, .right);
    try testing.expectEqual(game.Mark.flag, app.board.get(1, 0).mark);

    const before = app.board.revealed_count;
    const p = cellCenter(&app, 0, 0);
    app.handle(.{ .mouse_move = .{ .x = p.x, .y = p.y } });
    app.handle(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = .left } });
    app.handle(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = .right } });
    app.handle(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = .left } });
    app.handle(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = .right } });

    try testing.expect(app.board.revealed_count > before);
    try testing.expect(app.board.get(0, 1).revealed);
    try testing.expect(app.board.get(1, 1).revealed);
    try testing.expect(app.board.state != .lost);
}

test "chording refuses to fire when the flags do not match" {
    var app = testApp(5);
    app.board.reset(.{ .width = 9, .height = 9, .mines = 1 });
    app.board.at(1, 0).mine = true;
    app.board.at(0, 0).adjacent = 1;
    app.board.at(0, 0).revealed = true;
    app.board.revealed_count = 1;
    app.board.state = .playing;

    const before = app.board.revealed_count;
    const p = cellCenter(&app, 0, 0);
    app.handle(.{ .mouse_move = .{ .x = p.x, .y = p.y } });
    app.handle(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = .left } });
    app.handle(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = .right } });
    app.handle(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = .left } });
    app.handle(.{ .mouse_up = .{ .x = p.x, .y = p.y, .button = .right } });

    try testing.expectEqual(before, app.board.revealed_count);
    try testing.expectEqual(game.State.playing, app.board.state);
}

test "switching difficulty resizes the window" {
    var app = testApp(1);
    const beginner_width = app.metrics.width;
    app.applyMenuAction(.set_expert);
    try testing.expectEqual(@as(i32, 30), app.board.width);
    try testing.expect(app.metrics.width > beginner_width);
    try testing.expectEqual(@as(i32, 30 * layout.cell + 24), app.metrics.width);
}

test "the custom dialog applies clamped values" {
    var app = testApp(1);
    app.applyMenuAction(.set_custom);
    try testing.expect(app.dialog == .custom);
    switch (app.dialog) {
        .custom => |*d| {
            d.fields[0].set("40");
            d.fields[1].set("50");
            d.fields[2].set("999");
        },
        else => unreachable,
    }
    app.handle(.{ .key_down = .enter });
    try testing.expect(app.dialog == .none);
    try testing.expectEqual(@as(i32, game.max_height), app.board.height);
    try testing.expectEqual(@as(i32, game.max_width), app.board.width);
    try testing.expectEqual(@as(i32, (game.max_width - 1) * (game.max_height - 1)), app.board.mines);
}

test "escape closes an open menu" {
    var app = testApp(1);
    app.handle(.{ .mouse_down = .{ .x = 15, .y = 9, .button = .left } });
    try testing.expect(app.open_menu != null);
    app.handle(.{ .key_down = .escape });
    try testing.expect(app.open_menu == null);
}

test "the marks menu entry toggles question marks" {
    var app = testApp(1);
    try testing.expect(app.marks_enabled);
    app.applyMenuAction(.toggle_marks);
    try testing.expect(!app.marks_enabled);
    clickCell(&app, 0, 0, .right);
    clickCell(&app, 0, 0, .right);
    try testing.expectEqual(game.Mark.none, app.board.get(0, 0).mark);
}

test "winning offers to record a best time" {
    var app = testApp(4);
    clickCell(&app, 4, 4, .left);
    var y: i32 = 0;
    outer: while (y < app.board.height) : (y += 1) {
        var x: i32 = 0;
        while (x < app.board.width) : (x += 1) {
            if (app.board.state == .won) break :outer;
            if (!app.board.get(x, y).mine) clickCell(&app, x, y, .left);
        }
    }
    try testing.expectEqual(game.State.won, app.board.state);
    try testing.expect(app.dialog == .new_best);
}

test "a still pointer does not force a redraw" {
    var app = testApp(1);
    var fb = try gfx.Framebuffer.init(testing.allocator, app.metrics.width, app.metrics.height);
    defer fb.deinit();
    app.render(&fb);
    try testing.expect(!app.needsRedraw());
    app.handle(.{ .mouse_move = .{ .x = 5, .y = app.metrics.height - 5 } });
    try testing.expect(!app.needsRedraw());
    app.handle(.{ .mouse_move = .{ .x = 6, .y = app.metrics.height - 5 } });
    try testing.expect(!app.needsRedraw());
}

test "pressing a cell marks the frame dirty" {
    var app = testApp(1);
    var fb = try gfx.Framebuffer.init(testing.allocator, app.metrics.width, app.metrics.height);
    defer fb.deinit();
    app.render(&fb);
    const p = cellCenter(&app, 2, 2);
    app.handle(.{ .mouse_down = .{ .x = p.x, .y = p.y, .button = .left } });
    try testing.expect(app.needsRedraw());
}
