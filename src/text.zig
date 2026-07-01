//! UTF-8-aware terminal text formatting helpers.

const std = @import("std");

/// Horizontal text alignment.
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Count display cells for common terminal text. This function is UTF-8 aware,
/// ignores ANSI CSI escape sequences, treats combining marks as zero width, and
/// treats common CJK/emoji ranges as width 2.
pub fn width(bytes: []const u8) usize {
    var total: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) {
        if (skipAnsi(bytes, &i)) continue;

        const decoded = nextCodepoint(bytes, i) orelse {
            i += 1;
            total += 1;
            continue;
        };
        i += decoded.len;
        total += codepointWidth(decoded.value);
    }
    return total;
}

/// Write `bytes`, padded to `target_width` using `alignment`.
pub fn writePadded(writer: *std.Io.Writer, bytes: []const u8, target_width: usize, alignment: Alignment) !void {
    const current = width(bytes);
    if (current >= target_width) {
        try writer.writeAll(bytes);
        return;
    }

    const padding = target_width - current;
    const left = switch (alignment) {
        .left => 0,
        .right => padding,
        .center => padding / 2,
    };
    const right = padding - left;

    try writeSpaces(writer, left);
    try writer.writeAll(bytes);
    try writeSpaces(writer, right);
}

/// Write `bytes`, truncating to `max_width` and appending an ellipsis when
/// there is not enough room.
pub fn writeTruncated(writer: *std.Io.Writer, bytes: []const u8, max_width: usize) !void {
    if (max_width == 0) return;
    if (width(bytes) <= max_width) {
        try writer.writeAll(bytes);
        return;
    }
    if (max_width == 1) {
        try writer.writeAll("…");
        return;
    }

    var used: usize = 0;
    var end: usize = 0;
    while (end < bytes.len and used + 1 < max_width) {
        if (skipAnsi(bytes, &end)) continue;
        const decoded = nextCodepoint(bytes, end) orelse break;
        const cell_width = codepointWidth(decoded.value);
        if (used + cell_width + 1 > max_width) break;
        used += cell_width;
        end += decoded.len;
    }
    try writer.writeAll(bytes[0..end]);
    try writer.writeAll("…");
}

/// Wrap words to a fixed width. Existing whitespace is collapsed between words.
pub fn writeWrapped(writer: *std.Io.Writer, bytes: []const u8, line_width: usize, indent: []const u8) !void {
    if (line_width == 0) return;

    var iter = std.mem.tokenizeAny(u8, bytes, " \t\r\n");
    var line_len: usize = 0;
    var first = true;
    while (iter.next()) |word| {
        const word_width = width(word);
        const sep: usize = if (line_len == 0) 0 else 1;
        if (!first and line_len + sep + word_width > line_width) {
            try writer.writeAll("\n");
            try writer.writeAll(indent);
            line_len = width(indent);
        } else if (sep == 1) {
            try writer.writeAll(" ");
            line_len += 1;
        }
        try writer.writeAll(word);
        line_len += word_width;
        first = false;
    }
}

/// Write `count` spaces.
pub fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try writer.writeAll(" ");
}

const Decoded = struct {
    value: u21,
    len: usize,
};

fn nextCodepoint(bytes: []const u8, index: usize) ?Decoded {
    if (index >= bytes.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(bytes[index]) catch return null;
    if (index + len > bytes.len) return null;
    const slice = bytes[index .. index + len];
    return .{
        .value = std.unicode.utf8Decode(slice) catch return null,
        .len = len,
    };
}

fn skipAnsi(bytes: []const u8, index: *usize) bool {
    var i = index.*;
    if (i + 1 >= bytes.len or bytes[i] != 0x1b or bytes[i + 1] != '[') return false;
    i += 2;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] >= 0x40 and bytes[i] <= 0x7e) {
            index.* = i + 1;
            return true;
        }
    }
    index.* = bytes.len;
    return true;
}

fn codepointWidth(cp: u21) usize {
    if (cp == 0) return 0;
    if (cp < 0x20 or (cp >= 0x7f and cp < 0xa0)) return 0;
    if (isCombining(cp)) return 0;
    if (isWide(cp)) return 2;
    return 1;
}

fn isCombining(cp: u21) bool {
    return (cp >= 0x0300 and cp <= 0x036f) or
        (cp >= 0x0483 and cp <= 0x0489) or
        (cp >= 0x0591 and cp <= 0x05bd) or
        cp == 0x05bf or
        (cp >= 0x05c1 and cp <= 0x05c2) or
        (cp >= 0x05c4 and cp <= 0x05c5) or
        cp == 0x05c7 or
        (cp >= 0x0610 and cp <= 0x061a) or
        (cp >= 0x064b and cp <= 0x065f) or
        cp == 0x0670 or
        (cp >= 0x06d6 and cp <= 0x06dc) or
        (cp >= 0x06df and cp <= 0x06e4) or
        (cp >= 0x06e7 and cp <= 0x06e8) or
        (cp >= 0x06ea and cp <= 0x06ed) or
        (cp >= 0x0711 and cp <= 0x0711) or
        (cp >= 0x0730 and cp <= 0x074a) or
        (cp >= 0x07a6 and cp <= 0x07b0) or
        (cp >= 0x07eb and cp <= 0x07f3) or
        (cp >= 0x0816 and cp <= 0x0819) or
        (cp >= 0x081b and cp <= 0x0823) or
        (cp >= 0x0825 and cp <= 0x0827) or
        (cp >= 0x0829 and cp <= 0x082d) or
        (cp >= 0x0e31 and cp <= 0x0e31) or
        (cp >= 0x0e34 and cp <= 0x0e3a) or
        (cp >= 0x0e47 and cp <= 0x0e4e) or
        (cp >= 0x200c and cp <= 0x200f) or
        (cp >= 0x20d0 and cp <= 0x20ff) or
        (cp >= 0xfe00 and cp <= 0xfe0f);
}

fn isWide(cp: u21) bool {
    return (cp >= 0x1100 and cp <= 0x115f) or
        cp == 0x2329 or
        cp == 0x232a or
        (cp >= 0x2e80 and cp <= 0xa4cf) or
        (cp >= 0xac00 and cp <= 0xd7a3) or
        (cp >= 0xf900 and cp <= 0xfaff) or
        (cp >= 0xfe10 and cp <= 0xfe19) or
        (cp >= 0xfe30 and cp <= 0xfe6f) or
        (cp >= 0xff00 and cp <= 0xff60) or
        (cp >= 0xffe0 and cp <= 0xffe6) or
        (cp >= 0x1f300 and cp <= 0x1f64f) or
        (cp >= 0x1f680 and cp <= 0x1f6ff) or
        (cp >= 0x1f700 and cp <= 0x1f77f) or
        (cp >= 0x1f780 and cp <= 0x1f7ff) or
        (cp >= 0x1f900 and cp <= 0x1f9ff) or
        (cp >= 0x20000 and cp <= 0x3fffd);
}
