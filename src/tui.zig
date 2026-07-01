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

    var cursor_x = rect.x;
    var cursor_y = rect.y;
    for (constraints[0..count], 0..) |constraint, i| {
        const requested = switch (constraint) {
            .fixed => |value| value,
            .percent => |value| (total * value) / 100,
            .fill => fill_size,
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

    /// Write UTF-8 text starting at x,y. The cursor advances by display width.
    pub fn writeText(self: *Screen, x: usize, y: usize, value: []const u8) void {
        var cx = x;
        var iter = CodepointSlices.init(value);
        while (iter.next()) |slice| {
            if (cx >= self.width) break;
            self.put(cx, y, slice);
            cx += @max(text.width(slice), 1);
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

/// Render a simple vertical menu.
pub fn renderMenu(writer: *std.Io.Writer, items: []const MenuItem, selected: usize, options: MenuOptions) !void {
    for (items, 0..) |item, i| {
        try writer.writeAll(if (i == selected) options.selected_prefix else options.normal_prefix);
        try writer.writeAll(item.label);
        if (item.help.len > 0) try writer.print("  {s}", .{item.help});
        try writer.writeAll("\n");
    }
}

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
    try repeat(writer, border.horizontal, width - 2);
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
    try repeat(writer, border.horizontal, width - 2);
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

fn repeat(writer: *std.Io.Writer, bytes: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try writer.writeAll(bytes);
}

const CodepointSlices = struct {
    bytes: []const u8,
    index: usize = 0,

    fn init(bytes: []const u8) CodepointSlices {
        return .{ .bytes = bytes };
    }

    fn next(self: *CodepointSlices) ?[]const u8 {
        if (self.index >= self.bytes.len) return null;
        const start = self.index;
        const len = std.unicode.utf8ByteSequenceLength(self.bytes[start]) catch 1;
        self.index = @min(self.bytes.len, start + len);
        return self.bytes[start..self.index];
    }
};
