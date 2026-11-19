//! Small TUI layout and screen-buffer primitives.

const std = @import("std");
const text = @import("text.zig");

/// A rectangular terminal area.
pub const Rect = struct {
    x: usize = 0,
    y: usize = 0,
    width: usize = 0,
    height: usize = 0,

    /// Return a rectangle inset by `amount` on all sides.
    pub fn inset(self: Rect, amount: usize) Rect {
        const twice = amount * 2;
        return .{
            .x = self.x + amount,
            .y = self.y + amount,
            .width = if (self.width > twice) self.width - twice else 0,
            .height = if (self.height > twice) self.height - twice else 0,
        };
    }
};

/// Split direction for layouts.
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Layout sizing rule.
pub const Constraint = union(enum) {
    fixed: usize,
    percent: u8,
    fill,
};

/// Split `rect` into many areas using fixed, percent, and fill constraints.
/// Returns the number of rectangles written to `out`.
pub fn layout(rect: Rect, direction: Direction, constraints: []const Constraint, out: []Rect) usize {
    const count = @min(constraints.len, out.len);
    if (count == 0) return 0;

    const total = if (direction == .horizontal) rect.width else rect.height;
    var used: usize = 0;
    var fill_count: usize = 0;
    for (constraints[0..count]) |constraint| {
        switch (constraint) {
            .fixed => |value| used += @min(value, total),
            .percent => |value| used += (total * value) / 100,
            .fill => fill_count += 1,
        }
    }
    const remaining = if (used < total) total - used else 0;
    const fill_size = if (fill_count == 0) 0 else remaining / fill_count;
    // Hand the division remainder out one cell at a time so fills cover the
    // whole area instead of leaving trailing cells unused.
    var fill_extra = if (fill_count == 0) 0 else remaining % fill_count;

    var cursor_x = rect.x;
    var cursor_y = rect.y;
    for (constraints[0..count], 0..) |constraint, i| {
        const requested = switch (constraint) {
            .fixed => |value| value,
            .percent => |value| (total * value) / 100,
            .fill => blk: {
                const extra: usize = if (fill_extra > 0) 1 else 0;
                fill_extra -= extra;
                break :blk fill_size + extra;
            },
        };
        const available = if (direction == .horizontal)
            rect.x + rect.width - cursor_x
        else
            rect.y + rect.height - cursor_y;
        const size = @min(requested, available);

        out[i] = switch (direction) {
            .horizontal => .{ .x = cursor_x, .y = rect.y, .width = size, .height = rect.height },
            .vertical => .{ .x = rect.x, .y = cursor_y, .width = rect.width, .height = size },
        };
        if (direction == .horizontal) {
            cursor_x += size;
        } else {
            cursor_y += size;
        }
    }
    return count;
}

/// Split a rectangle into two areas. `first_size` is clamped to the available
/// width/height.
pub fn split(rect: Rect, direction: Direction, first_size: usize) [2]Rect {
    return switch (direction) {
        .horizontal => blk: {
            const left_width = @min(first_size, rect.width);
            break :blk .{
                .{ .x = rect.x, .y = rect.y, .width = left_width, .height = rect.height },
                .{ .x = rect.x + left_width, .y = rect.y, .width = rect.width - left_width, .height = rect.height },
            };
        },
        .vertical => blk: {
            const top_height = @min(first_size, rect.height);
            break :blk .{
                .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = top_height },
                .{ .x = rect.x, .y = rect.y + top_height, .width = rect.width, .height = rect.height - top_height },
            };
        },
    };
}

/// Border drawing characters.
pub const BorderSet = struct {
    top_left: []const u8 = "┌",
    top_right: []const u8 = "┐",
    bottom_left: []const u8 = "└",
    bottom_right: []const u8 = "┘",
    horizontal: []const u8 = "─",
    vertical: []const u8 = "│",

    pub const unicode: BorderSet = .{};
    pub const ascii: BorderSet = .{
        .top_left = "+",
        .top_right = "+",
        .bottom_left = "+",
        .bottom_right = "+",
        .horizontal = "-",
        .vertical = "|",
    };
};

/// A simple retained screen buffer. Each cell stores a UTF-8 slice reference;
/// callers own the strings they put into cells.
pub const Screen = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []?[]const u8,

    /// Allocate a screen buffer.
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Screen {
        const cells = try allocator.alloc(?[]const u8, width * height);
        @memset(cells, null);
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .cells = cells,
        };
    }

    /// Free screen memory.
    pub fn deinit(self: Screen) void {
        self.allocator.free(self.cells);
    }

    /// Clear the screen to spaces.
    pub fn clear(self: *Screen) void {
        @memset(self.cells, null);
    }

    /// Put one glyph/string at x,y.
    pub fn put(self: *Screen, x: usize, y: usize, value: []const u8) void {
        if (x >= self.width or y >= self.height) return;
        self.cells[(y * self.width) + x] = value;
    }

    /// Write UTF-8 text starting at x,y. The cursor advances by display width:
    /// wide glyphs occupy two cells, combining marks (such as Thai vowel and
    /// tone marks) join the preceding cell, and control characters are skipped.
    /// Text that does not fit on the row is clipped.
    pub fn writeText(self: *Screen, x: usize, y: usize, value: []const u8) void {
        if (y >= self.height) return;
        var cx = x;
        var last: ?struct { cell: usize, start: usize } = null;
        var i: usize = 0;
        while (i < value.len) {
            const start = i;
            const decoded = text.nextCodepoint(value, i) orelse text.Decoded{ .value = replacement_char, .len = 1 };
            i += decoded.len;
            if (isControl(decoded.value)) continue;

            const cell_width = text.codepointWidth(decoded.value);
            if (cell_width == 0) {
                if (last) |prev| {
                    // Combining bytes directly follow the base glyph in `value`.
                    self.cells[prev.cell] = value[prev.start..i];
                    continue;
                }
            }
            const cells = @max(cell_width, 1);
            if (cx + cells > self.width) break;
            const cell = (y * self.width) + cx;
            self.cells[cell] = value[start..i];
            if (cells == 2) self.cells[cell + 1] = wide_continuation;
            last = .{ .cell = cell, .start = start };
            cx += cells;
        }
    }

    /// Render the full buffer.
    pub fn render(self: Screen, writer: *std.Io.Writer) !void {
        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                try writer.writeAll(self.cells[(y * self.width) + x] orelse " ");
            }
            try writer.writeAll("\n");
        }
    }
};

/// Menu item.
pub const MenuItem = struct {
    label: []const u8,
    help: []const u8 = "",
};

/// Menu rendering options.
pub const MenuOptions = struct {
    selected_prefix: []const u8 = "> ",
    normal_prefix: []const u8 = "  ",
};

/// Render a simple vertical menu. Help text starts in one column: labels are
/// padded to the widest label, and prefixes to the wider prefix.
pub fn renderMenu(writer: *std.Io.Writer, items: []const MenuItem, selected: usize, options: MenuOptions) !void {
    const prefix_width = @max(text.width(options.selected_prefix), text.width(options.normal_prefix));
    var label_width: usize = 0;
    for (items) |item| {
        if (item.help.len > 0) label_width = @max(label_width, text.width(item.label));
    }

    for (items, 0..) |item, i| {
        const prefix = if (i == selected) options.selected_prefix else options.normal_prefix;
        try text.writePadded(writer, prefix, prefix_width, .left);
        if (item.help.len > 0) {
            try text.writePadded(writer, item.label, label_width, .left);
            try writer.print("{s}{s}", .{ menu_help_gap, item.help });
        } else {
            // No help: skip padding so the line has no trailing spaces.
            try writer.writeAll(item.label);
        }
        try writer.writeAll("\n");
    }
}

const menu_help_gap = "  ";

/// Basic form field.
pub const Field = struct {
    label: []const u8,
    value: []const u8 = "",
    placeholder: []const u8 = "",
};

/// Render a static form summary.
pub fn renderForm(writer: *std.Io.Writer, fields: []const Field) !void {
    var label_width: usize = 0;
    for (fields) |field| label_width = @max(label_width, text.width(field.label));
    for (fields) |field| {
        try text.writePadded(writer, field.label, label_width, .left);
        try writer.writeAll(": ");
        if (field.value.len > 0) {
            try writer.writeAll(field.value);
        } else {
            try writer.writeAll(field.placeholder);
        }
        try writer.writeAll("\n");
    }
}

/// Draw a bordered rectangle at the current writer position.
pub fn renderBox(writer: *std.Io.Writer, width: usize, height: usize, border: BorderSet) !void {
    if (width < 2 or height < 2) return;

    try writer.writeAll(border.top_left);
    try text.writeRepeated(writer, border.horizontal, width - 2);
    try writer.writeAll(border.top_right);
    try writer.writeAll("\n");

    var row: usize = 0;
    while (row < height - 2) : (row += 1) {
        try writer.writeAll(border.vertical);
        try text.writeSpaces(writer, width - 2);
        try writer.writeAll(border.vertical);
        try writer.writeAll("\n");
    }

    try writer.writeAll(border.bottom_left);
    try text.writeRepeated(writer, border.horizontal, width - 2);
    try writer.writeAll(border.bottom_right);
    try writer.writeAll("\n");
}

/// Decoded key input for simple terminal interactions.
pub const Key = union(enum) {
    char: u8,
    enter,
    escape,
    backspace,
    tab,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    unknown: []const u8,
};

/// Decode a small set of common key byte sequences.
pub fn decodeKey(bytes: []const u8) Key {
    if (bytes.len == 0) return .{ .unknown = bytes };
    if (std.mem.eql(u8, bytes, "\r") or std.mem.eql(u8, bytes, "\n")) return .enter;
    if (std.mem.eql(u8, bytes, "\t")) return .tab;
    if (std.mem.eql(u8, bytes, "\x1b")) return .escape;
    if (std.mem.eql(u8, bytes, "\x7f") or std.mem.eql(u8, bytes, "\x08")) return .backspace;
    if (std.mem.eql(u8, bytes, "\x1b[A")) return .arrow_up;
    if (std.mem.eql(u8, bytes, "\x1b[B")) return .arrow_down;
    if (std.mem.eql(u8, bytes, "\x1b[C")) return .arrow_right;
    if (std.mem.eql(u8, bytes, "\x1b[D")) return .arrow_left;
    if (bytes.len == 1 and bytes[0] >= 0x20 and bytes[0] < 0x7f) return .{ .char = bytes[0] };
    return .{ .unknown = bytes };
}

/// Marks the right half of a wide glyph; renders as nothing because the glyph
/// in the left cell already covers both columns.
const wide_continuation = "";
const replacement_char: u21 = 0xfffd;

fn isControl(cp: u21) bool {
    return cp < 0x20 or (cp >= 0x7f and cp < 0xa0);
}
