//! ANSI styling, cursor, and screen-control helpers.

const std = @import("std");

/// Standard terminal colors.
pub const Color = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

/// 24-bit terminal color.
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Composable terminal style. Set `enabled = false` to render plain text.
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    fg_256: ?u8 = null,
    bg_256: ?u8 = null,
    fg_rgb: ?Rgb = null,
    bg_rgb: ?Rgb = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reversed: bool = false,
    enabled: bool = true,

    /// Write the opening escape sequence for this style.
    pub fn writeStart(self: Style, writer: *std.Io.Writer) !void {
        if (!self.enabled or !self.hasAttributes()) return;

        var first = true;
        try writer.writeAll("\x1b[");
        if (self.bold) try writeCode(writer, &first, 1);
        if (self.dim) try writeCode(writer, &first, 2);
        if (self.italic) try writeCode(writer, &first, 3);
        if (self.underline) try writeCode(writer, &first, 4);
        if (self.reversed) try writeCode(writer, &first, 7);
        if (self.fg_rgb) |color| {
            try writeRgb(writer, &first, 38, color);
        } else if (self.fg_256) |color| {
            try write256(writer, &first, 38, color);
        } else if (self.fg) |color| {
            try writeCode(writer, &first, colorCode(30, color));
        }
        if (self.bg_rgb) |color| {
            try writeRgb(writer, &first, 48, color);
        } else if (self.bg_256) |color| {
            try write256(writer, &first, 48, color);
        } else if (self.bg) |color| {
            try writeCode(writer, &first, colorCode(40, color));
        }
        if (first) try writer.writeAll("0");
        try writer.writeAll("m");
    }

    /// Write the reset escape sequence when this style is enabled.
    pub fn writeEnd(self: Style, writer: *std.Io.Writer) !void {
        if (self.enabled and self.hasAttributes()) try writer.writeAll("\x1b[0m");
    }

    /// Render `bytes` surrounded by this style's start/end sequences.
    pub fn write(self: Style, writer: *std.Io.Writer, bytes: []const u8) !void {
        try self.writeStart(writer);
        try writer.writeAll(bytes);
        try self.writeEnd(writer);
    }

    /// Return true when this style would emit ANSI attributes.
    pub fn hasAttributes(self: Style) bool {
        return self.fg != null or
            self.bg != null or
            self.fg_256 != null or
            self.bg_256 != null or
            self.fg_rgb != null or
            self.bg_rgb != null or
            self.bold or
            self.dim or
            self.italic or
            self.underline or
            self.reversed;
    }
};

/// Convenience constructor for foreground colors.
pub fn fg(color: Color) Style {
    return .{ .fg = color };
}

/// Convenience constructor for background colors.
pub fn bg(color: Color) Style {
    return .{ .bg = color };
}

/// Convenience constructor for 24-bit foreground colors.
pub fn rgb(r: u8, g: u8, b: u8) Style {
    return .{ .fg_rgb = .{ .r = r, .g = g, .b = b } };
}

/// Write a terminal reset sequence.
pub fn reset(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[0m");
}

/// Move the cursor to a 1-based row/column.
pub fn moveTo(writer: *std.Io.Writer, row: usize, col: usize) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}

/// Move the cursor up by `n` rows.
pub fn cursorUp(writer: *std.Io.Writer, n: usize) !void {
    try writer.print("\x1b[{d}A", .{n});
}

/// Move the cursor down by `n` rows.
pub fn cursorDown(writer: *std.Io.Writer, n: usize) !void {
    try writer.print("\x1b[{d}B", .{n});
}

/// Hide the cursor.
pub fn hideCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[?25l");
}

/// Show the cursor.
pub fn showCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[?25h");
}

/// Clear the full screen and move to the home position.
pub fn clearScreen(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
}

/// Clear the current line.
pub fn clearLine(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[2K\r");
}

fn writeCode(writer: *std.Io.Writer, first: *bool, code: usize) !void {
    if (!first.*) try writer.writeAll(";");
    first.* = false;
    try writer.print("{d}", .{code});
}

fn write256(writer: *std.Io.Writer, first: *bool, slot: usize, color: u8) !void {
    if (!first.*) try writer.writeAll(";");
    first.* = false;
    try writer.print("{d};5;{d}", .{ slot, color });
}

fn writeRgb(writer: *std.Io.Writer, first: *bool, slot: usize, color: Rgb) !void {
    if (!first.*) try writer.writeAll(";");
    first.* = false;
    try writer.print("{d};2;{d};{d};{d}", .{ slot, color.r, color.g, color.b });
}

fn colorCode(base: usize, color: Color) usize {
    const value = @intFromEnum(color);
    if (value < 8) return base + value;
    return base + 60 + (value - 8);
}
