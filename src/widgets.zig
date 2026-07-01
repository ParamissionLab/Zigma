//! Writer-based terminal widgets.

const std = @import("std");
const ansi = @import("ansi.zig");
const terminal = @import("terminal.zig");
const text = @import("text.zig");

/// Terminal glyph preset for UI drawing. Use `Glyphs.ascii` when the terminal
/// cannot render UTF-8 line art correctly.
pub const Glyphs = struct {
    top_left: []const u8 = "┌",
    top_mid: []const u8 = "┬",
    top_right: []const u8 = "┐",
    mid_left: []const u8 = "├",
    mid_mid: []const u8 = "┼",
    mid_right: []const u8 = "┤",
    bottom_left: []const u8 = "└",
    bottom_mid: []const u8 = "┴",
    bottom_right: []const u8 = "┘",
    horizontal: []const u8 = "─",
    vertical: []const u8 = "│",
    progress_fill: []const u8 = "█",
    progress_empty: []const u8 = "░",
    spinner_frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },

    pub const unicode: Glyphs = .{};
    pub const ascii: Glyphs = .{
        .top_left = "+",
        .top_mid = "+",
        .top_right = "+",
        .mid_left = "+",
        .mid_mid = "+",
        .mid_right = "+",
        .bottom_left = "+",
        .bottom_mid = "+",
        .bottom_right = "+",
        .horizontal = "-",
        .vertical = "|",
        .progress_fill = "#",
        .progress_empty = "-",
        .spinner_frames = &.{ "-", "\\", "|", "/" },
    };

    /// Pick a glyph preset from terminal capabilities.
    pub fn fromCharset(charset: terminal.Charset) Glyphs {
        return switch (charset) {
            .ascii => Glyphs.ascii,
            .unicode => Glyphs.unicode,
        };
    }
};

/// Color palette for CLI/TUI widgets. Applications can replace any style.
pub const Theme = struct {
    enabled: bool = true,
    title: ansi.Style = .{ .bold = true, .fg = .bright_cyan },
    header: ansi.Style = .{ .bold = true, .fg = .bright_white },
    border: ansi.Style = .{ .fg = .bright_black },
    text: ansi.Style = .{},
    muted: ansi.Style = .{ .fg = .bright_black },
    info: ansi.Style = .{ .fg = .cyan },
    success: ansi.Style = .{ .fg = .green, .bold = true },
    warning: ansi.Style = .{ .fg = .yellow, .bold = true },
    err: ansi.Style = .{ .fg = .red, .bold = true },

    /// Return a theme with every style enabled/disabled together.
    pub fn init(enabled: bool) Theme {
        var theme: Theme = .{ .enabled = enabled };
        theme.applyEnabled();
        return theme;
    }

    /// Build table options from this theme.
    pub fn tableOptions(self: Theme, glyphs: Glyphs) TableOptions {
        return .{
            .glyphs = glyphs,
            .header_style = self.header,
            .cell_style = self.text,
            .border_style = self.border,
        };
    }

    fn applyEnabled(self: *Theme) void {
        self.title.enabled = self.enabled;
        self.header.enabled = self.enabled;
        self.border.enabled = self.enabled;
        self.text.enabled = self.enabled;
        self.muted.enabled = self.enabled;
        self.info.enabled = self.enabled;
        self.success.enabled = self.enabled;
        self.warning.enabled = self.enabled;
        self.err.enabled = self.enabled;
    }
};

/// High-level, small UI facade. It keeps call sites short while still allowing
/// full customization through `theme` and `glyphs`.
pub const Ui = struct {
    writer: *std.Io.Writer,
    theme: Theme = .{},
    glyphs: Glyphs = Glyphs.unicode,

    /// Create a UI from detected terminal capabilities.
    pub fn init(writer: *std.Io.Writer, caps: terminal.Capabilities) Ui {
        return .{
            .writer = writer,
            .theme = Theme.init(caps.ansi),
            .glyphs = Glyphs.fromCharset(caps.charset),
        };
    }

    /// Create a UI using Zigma's practical terminal defaults.
    pub fn auto(writer: *std.Io.Writer) Ui {
        return Ui.init(writer, terminal.detectDefault(.{}));
    }

    /// Create a plain ASCII UI for logs, tests, redirected output, or CI.
    pub fn plain(writer: *std.Io.Writer) Ui {
        return Ui.init(writer, .{
            .ansi = false,
            .charset = .ascii,
        });
    }

    /// Render a styled section heading.
    pub fn section(self: Ui, title: []const u8) !void {
        try (Section{ .title = title, .style = self.theme.title }).render(self.writer);
    }

    /// Render a status line.
    pub fn status(self: Ui, kind: Status, message: []const u8) !void {
        try renderStatusThemed(self.writer, kind, message, self.theme);
    }

    /// Render an info status line.
    pub fn info(self: Ui, message: []const u8) !void {
        try self.status(.info, message);
    }

    /// Render a success status line.
    pub fn success(self: Ui, message: []const u8) !void {
        try self.status(.success, message);
    }

    /// Render a warning status line.
    pub fn warning(self: Ui, message: []const u8) !void {
        try self.status(.warning, message);
    }

    /// Render an error status line.
    pub fn err(self: Ui, message: []const u8) !void {
        try self.status(.err, message);
    }

    /// Render a plain line of text.
    pub fn text(self: Ui, message: []const u8) !void {
        try self.theme.text.write(self.writer, message);
        try self.writer.writeAll("\n");
    }

    /// Render muted text.
    pub fn note(self: Ui, message: []const u8) !void {
        try self.theme.muted.write(self.writer, message);
        try self.writer.writeAll("\n");
    }

    /// Write a blank line.
    pub fn line(self: Ui) !void {
        try self.writer.writeAll("\n");
    }

    /// Render one key/value row.
    pub fn kv(self: Ui, key: []const u8, value: []const u8) !void {
        const row = [_]Pair{.{ .key = key, .value = value }};
        try self.pairs(&row);
    }

    /// Render key/value rows.
    pub fn pairs(self: Ui, values: []const Pair) !void {
        try renderPairs(self.writer, values);
    }

    /// Render a themed table.
    pub fn table(self: Ui, columns: []const Column, rows: []const []const []const u8) !void {
        try renderTable(self.writer, columns, rows, self.theme.tableOptions(self.glyphs));
    }

    /// Render a themed progress bar.
    pub fn progress(self: Ui, current: usize, total: usize, width: usize) !void {
        try renderProgress(self.writer, current, total, .{
            .width = width,
            .glyphs = self.glyphs,
            .style = self.theme.success,
        });
    }

    /// Render a compact progress bar using the default width.
    pub fn meter(self: Ui, current: usize, total: usize) !void {
        try self.progress(current, total, 24);
    }

    /// Render a horizontal rule with an optional title.
    pub fn rule(self: Ui, title: []const u8) !void {
        try renderRule(self.writer, title, self.glyphs, self.theme.muted, 48);
    }

    /// Render a prompt.
    pub fn prompt(self: Ui, label: []const u8, placeholder: ?[]const u8) !void {
        try (Prompt{ .label = label, .placeholder = placeholder, .style = self.theme.header }).render(self.writer);
    }
};

/// Common status kinds for CLI diagnostics.
pub const Status = enum {
    info,
    success,
    warning,
    err,
};

/// Render a compact status line such as `[ok] generated file`.
pub fn renderStatus(writer: *std.Io.Writer, status: Status, message: []const u8, enable_color: bool) !void {
    try renderStatusThemed(writer, status, message, Theme.init(enable_color));
}

/// Render a compact status line using a custom theme.
pub fn renderStatusThemed(writer: *std.Io.Writer, status: Status, message: []const u8, theme: Theme) !void {
    const label, const style = switch (status) {
        .info => .{ "info", theme.info },
        .success => .{ "ok", theme.success },
        .warning => .{ "warn", theme.warning },
        .err => .{ "error", theme.err },
    };
    try writer.writeAll("[");
    try style.write(writer, label);
    try writer.print("] {s}\n", .{message});
}

/// Render a horizontal rule.
pub fn renderRule(writer: *std.Io.Writer, title: []const u8, glyphs: Glyphs, style: ansi.Style, width: usize) !void {
    const safe_width = @max(width, 4);
    try style.writeStart(writer);
    if (title.len == 0) {
        try writeRepeated(writer, glyphs.horizontal, safe_width);
    } else {
        try writeRepeated(writer, glyphs.horizontal, 2);
        try writer.print(" {s} ", .{title});
        const used = text.width(title) + 6;
        if (used < safe_width) try writeRepeated(writer, glyphs.horizontal, safe_width - used);
    }
    try style.writeEnd(writer);
    try writer.writeAll("\n");
}

/// A section heading.
pub const Section = struct {
    title: []const u8,
    style: ansi.Style = .{ .bold = true },

    /// Render the section heading.
    pub fn render(self: Section, writer: *std.Io.Writer) !void {
        try self.style.write(writer, self.title);
        try writer.writeAll("\n");
    }
};

/// Key/value row.
pub const Pair = struct {
    key: []const u8,
    value: []const u8,
};

/// Render aligned key/value pairs.
pub fn renderPairs(writer: *std.Io.Writer, pairs: []const Pair) !void {
    var key_width: usize = 0;
    for (pairs) |pair| key_width = @max(key_width, text.width(pair.key));
    for (pairs) |pair| {
        try text.writePadded(writer, pair.key, key_width, .left);
        try writer.writeAll("  ");
        try writer.writeAll(pair.value);
        try writer.writeAll("\n");
    }
}

/// Table column description.
pub const Column = struct {
    title: []const u8,
    width: ?usize = null,
    alignment: text.Alignment = .left,
};

/// Table rendering options.
pub const TableOptions = struct {
    border: bool = true,
    glyphs: Glyphs = Glyphs.unicode,
    header_style: ansi.Style = .{ .bold = true },
    cell_style: ansi.Style = .{},
    border_style: ansi.Style = .{},
};

/// Render a simple table. `rows` must contain one slice per row; missing cells
/// render empty and extra cells are ignored.
pub fn renderTable(
    writer: *std.Io.Writer,
    columns: []const Column,
    rows: []const []const []const u8,
    options: TableOptions,
) !void {
    if (columns.len == 0) return;

    var widths_buffer: [32]usize = undefined;
    if (columns.len > widths_buffer.len) return error.NoSpaceLeft;
    const widths = widths_buffer[0..columns.len];

    for (columns, 0..) |column, i| {
        widths[i] = column.width orelse text.width(column.title);
    }
    for (rows) |row| {
        for (columns, 0..) |_, i| {
            if (i < row.len) widths[i] = @max(widths[i], text.width(row[i]));
        }
    }

    var header_buffer: [32][]const u8 = undefined;
    const headers = header_buffer[0..columns.len];
    for (columns, 0..) |column, i| headers[i] = column.title;

    if (options.border) try renderBorder(writer, widths, options.glyphs.top_left, options.glyphs.top_mid, options.glyphs.top_right, options.glyphs, options.border_style);
    try renderRow(writer, columns, widths, headers, options, options.header_style);
    if (options.border) try renderBorder(writer, widths, options.glyphs.mid_left, options.glyphs.mid_mid, options.glyphs.mid_right, options.glyphs, options.border_style);
    for (rows) |row| try renderRow(writer, columns, widths, row, options, options.cell_style);
    if (options.border) try renderBorder(writer, widths, options.glyphs.bottom_left, options.glyphs.bottom_mid, options.glyphs.bottom_right, options.glyphs, options.border_style);
}

/// Progress bar rendering options.
pub const ProgressOptions = struct {
    width: usize = 24,
    fill: []const u8 = "█",
    empty: []const u8 = "░",
    glyphs: ?Glyphs = null,
    style: ansi.Style = .{},
    show_percent: bool = true,
};

/// Render a single-line progress bar for `current / total`.
pub fn renderProgress(writer: *std.Io.Writer, current: usize, total: usize, options: ProgressOptions) !void {
    const safe_total = if (total == 0) 1 else total;
    const capped = @min(current, safe_total);
    const filled = (capped * options.width) / safe_total;
    const fill = if (options.glyphs) |glyphs| glyphs.progress_fill else options.fill;
    const empty = if (options.glyphs) |glyphs| glyphs.progress_empty else options.empty;

    try writer.writeAll("[");
    try options.style.writeStart(writer);
    var i: usize = 0;
    while (i < options.width) : (i += 1) {
        try writer.writeAll(if (i < filled) fill else empty);
    }
    try options.style.writeEnd(writer);
    try writer.writeAll("]");
    if (options.show_percent) {
        try writer.print(" {d}%", .{(capped * 100) / safe_total});
    }
}

/// Spinner frame set.
pub const Spinner = struct {
    frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },

    pub const unicode: Spinner = .{ .frames = Glyphs.unicode.spinner_frames };
    pub const ascii: Spinner = .{ .frames = Glyphs.ascii.spinner_frames };

    /// Return a frame for a zero-based tick.
    pub fn frame(self: Spinner, tick: usize) []const u8 {
        if (self.frames.len == 0) return "";
        return self.frames[tick % self.frames.len];
    }
};

/// Prompt rendering options.
pub const Prompt = struct {
    label: []const u8,
    placeholder: ?[]const u8 = null,
    style: ansi.Style = .{ .bold = true },

    /// Render a prompt label. Input reading is intentionally left to callers so
    /// tests and applications can choose their own streams.
    pub fn render(self: Prompt, writer: *std.Io.Writer) !void {
        try self.style.write(writer, self.label);
        if (self.placeholder) |placeholder| try writer.print(" ({s})", .{placeholder});
        try writer.writeAll(": ");
    }
};

fn renderBorder(writer: *std.Io.Writer, widths: []const usize, left: []const u8, mid: []const u8, right: []const u8, glyphs: Glyphs, style: ansi.Style) !void {
    try style.writeStart(writer);
    try writer.writeAll(left);
    for (widths, 0..) |cell_width, i| {
        var n: usize = 0;
        while (n < cell_width + 2) : (n += 1) try writer.writeAll(glyphs.horizontal);
        try writer.writeAll(if (i + 1 == widths.len) right else mid);
    }
    try style.writeEnd(writer);
    try writer.writeAll("\n");
}

fn writeRepeated(writer: *std.Io.Writer, bytes: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try writer.writeAll(bytes);
}

fn renderRow(writer: *std.Io.Writer, columns: []const Column, widths: []const usize, row: []const []const u8, options: TableOptions, style: ansi.Style) !void {
    if (options.border) try writer.writeAll(options.glyphs.vertical);
    for (columns, 0..) |column, i| {
        try writer.writeAll(" ");
        try style.writeStart(writer);
        if (i < row.len) {
            try text.writePadded(writer, row[i], widths[i], column.alignment);
        } else {
            try text.writeSpaces(writer, widths[i]);
        }
        try style.writeEnd(writer);
        try writer.writeAll(" ");
        if (options.border) {
            try writer.writeAll(options.glyphs.vertical);
        } else if (i + 1 < columns.len) {
            try writer.writeAll(" ");
        }
    }
    try writer.writeAll("\n");
}
