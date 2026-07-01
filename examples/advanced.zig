const std = @import("std");
const zigma = @import("zigma");

fn hello(ctx: *zigma.cli.Context) !void {
    try ctx.success("advanced CLI command");
    try ctx.writer.print("Hello, {s}\n", .{ctx.string("name", "โลก")});
}

fn dashboard(ctx: *zigma.cli.Context) !void {
    try ctx.ui.section("Complex TUI primitives");
    try ctx.ui.rule("layout");
    var areas: [3]zigma.tui.Rect = undefined;
    _ = zigma.tui.layout(.{ .width = 60, .height = 12 }, .vertical, &.{
        .{ .fixed = 3 },
        .fill,
        .{ .fixed = 4 },
    }, &areas);

    try zigma.widgets.renderPairs(ctx.writer, &.{
        .{ .key = "top", .value = "fixed 3 rows" },
        .{ .key = "middle", .value = "fill remaining space" },
        .{ .key = "bottom", .value = "fixed 4 rows" },
    });
    try ctx.ui.line();

    try zigma.tui.renderMenu(ctx.writer, &.{
        .{ .label = "Overview", .help = "basic screen" },
        .{ .label = "Settings", .help = "forms and config" },
        .{ .label = "Deploy", .help = "workflow action" },
    }, 1, .{});
    try ctx.ui.line();

    try zigma.tui.renderForm(ctx.writer, &.{
        .{ .label = "Project", .value = "Zigma" },
        .{ .label = "Language", .value = "ไทย / English / 日本語 / العربية / emoji 🚀" },
        .{ .label = "Mode", .placeholder = "interactive" },
    });
}

pub fn main(init: std.process.Init) !void {
    try zigma.run(init, .{
        .name = "zigma-advanced",
        .description = "Advanced CLI/TUI app built with short Zigma APIs.",
        .routes = &.{
            zigma.routeWithAliases(zigma.cmd("hello", "Basic command with multilingual UTF-8 text.", &.{
                zigma.opt("name", 'n', "text", "โลก", "Name to greet."),
            }), &.{"hi"}, hello),
            zigma.routeWithAliases(zigma.cmd("dashboard", "Render more complex TUI primitives.", &.{}), &.{"dash"}, dashboard),
        },
    });
}
