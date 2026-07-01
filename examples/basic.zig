const std = @import("std");
const zigma = @import("zigma");

fn hello(ctx: *zigma.Context) !void {
    try ctx.success("basic CLI ready");
    try (zigma.ansi.Style{ .fg = .cyan, .bold = true, .enabled = ctx.caps.ansi }).write(ctx.writer, "Hello");
    if (ctx.boolean("loud", false)) {
        try ctx.writer.print(", {s}!\n", .{ctx.string("name", "Zig")});
    } else {
        try ctx.writer.print(", {s}.\n", .{ctx.string("name", "Zig")});
    }
    try ctx.ui.meter(7, 10);
    try ctx.ui.line();
}

pub fn main(init: std.process.Init) !void {
    try zigma.runCommand(init, zigma.cmd("zigma-basic", "Example configurable CLI built with Zigma.", &.{
        zigma.opt("name", 'n', "text", "Zig", "Name to greet."),
        zigma.flag("loud", 'l', "Use uppercase enthusiasm."),
    }), hello);
}
