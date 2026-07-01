const std = @import("std");
const zigma = @import("zigma");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const caps = zigma.terminal.detectDefault(.{ .term = "xterm-256color" });
    const ui = zigma.widgets.Ui.init(stdout, caps);

    try ui.section("Zigma dashboard");
    try ui.status(.success, "cross-platform UI ready");
    try ui.pairs(&.{
        .{ .key = "mode", .value = "demo" },
        .{ .key = "charset", .value = if (caps.charset == .ascii) "ascii-safe glyphs" else "unicode glyphs" },
        .{ .key = "languages", .value = "ไทย / English / 日本語 / العربية" },
        .{ .key = "modules", .value = "args ansi terminal text widgets tui" },
    });
    try stdout.writeAll("\n");

    try ui.table(&.{
        .{ .title = "Module", .width = 12 },
        .{ .title = "Purpose", .width = 36 },
    }, &.{
        &.{ "args", "spec-driven CLI parsing" },
        &.{ "widgets", "tables, progress, prompts" },
        &.{ "tui", "layout boxes and key decoding" },
        &.{ "unicode", "ไทย 日本語 العربية emoji 🚀" },
    });

    try stdout.writeAll("\n");
    try zigma.tui.renderBox(stdout, 32, 5, if (caps.charset == .ascii) .ascii else .unicode);
    try stdout.flush();
}
