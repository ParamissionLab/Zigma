const std = @import("std");
const zigma = @import("zigma");
const builtin = @import("builtin");

fn testCliHandler(ctx: *zigma.cli.Context) !void {
    try ctx.writer.print("ran:{s}\n", .{ctx.value("name") orelse "none"});
}

test "package exposes stable 1.0.0 version" {
    try std.testing.expectEqualStrings("1.0.0", zigma.version);
}

test "ansi style can be disabled" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try (zigma.ansi.Style{ .fg = .red, .enabled = false }).write(&writer.writer, "plain");
    try std.testing.expectEqualStrings("plain", writer.written());
}

test "ansi supports 24-bit color" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try (zigma.ansi.Style{ .fg_rgb = .{ .r = 10, .g = 20, .b = 30 } }).write(&writer.writer, "rgb");
    try std.testing.expectEqualStrings("\x1b[38;2;10;20;30mrgb\x1b[0m", writer.written());
}

test "argument parser handles flags values defaults and positionals" {
    const command = zigma.command("demo", "", &.{
        zigma.option("name", 'n', "text", "world", ""),
        zigma.option("retries", 'r', "count", "2", ""),
        zigma.flag("verbose", 'v', ""),
    });

    const parsed = try zigma.args.parse(std.testing.allocator, command, &.{ "-vv", "--name=zig", "--retries", "3", "file.txt" });
    defer parsed.deinit();

    try std.testing.expect(parsed.has("verbose"));
    try std.testing.expect(parsed.boolean("verbose", false));
    try std.testing.expectEqual(@as(usize, 2), parsed.count("verbose"));
    try std.testing.expectEqualStrings("zig", parsed.value("name").?);
    try std.testing.expectEqualStrings("zig", parsed.string("name", "fallback"));
    try std.testing.expectEqual(@as(u8, 3), try parsed.int(u8, "retries", 0));
    try std.testing.expectEqual(@as(usize, 1), parsed.positionals.len);
    try std.testing.expectEqualStrings("file.txt", parsed.positionals[0]);
    try std.testing.expectEqualStrings("file.txt", parsed.positional(0).?);
}

test "option helpers create common command specs" {
    const command = zigma.cmd("deploy", "Deploy app.", &.{
        zigma.req("config", 'c', "path", "Config path."),
        zigma.flag("dry-run", null, "Preview changes."),
        zigma.helpFlag(),
    });

    try std.testing.expectEqualStrings("deploy", command.name);
    try std.testing.expect(command.options[0].required);
    try std.testing.expectEqual(@as(?u8, null), command.options[1].short);
    try std.testing.expectEqualStrings("help", command.options[2].long);
}

test "positional argument specs validate required values and render help" {
    const command = zigma.cmdArgs("copy", "Copy files.", &.{
        zigma.flag("force", 'f', "Overwrite existing files."),
    }, &.{
        zigma.arg("source", "Source path."),
        zigma.optionalArg("dest", "Destination path."),
    });

    var diagnostic: zigma.args.Diagnostic = .{};
    try std.testing.expectError(
        error.MissingRequiredArgument,
        zigma.args.parseDetailed(std.testing.allocator, command, &.{}, &diagnostic),
    );
    try std.testing.expectEqual(zigma.args.DiagnosticKind.missing_required_argument, diagnostic.kind);

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try zigma.args.writeHelp(&writer.writer, command);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Usage: copy [options] <source> [dest]") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Arguments:") != null);

    const parsed = try zigma.args.parse(std.testing.allocator, command, &.{"file.txt"});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("file.txt", parsed.positional(0).?);
}

test "help output includes options" {
    const command: zigma.args.Command = .{
        .name = "demo",
        .description = "A demo command.",
        .options = &.{
            .{ .long = "config", .short = 'c', .value_name = "path", .required = true, .help = "Config path." },
        },
    };

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.args.writeHelp(&writer.writer, command);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "--config <path>") != null);
}

test "argument parser writes useful diagnostics" {
    const command: zigma.args.Command = .{
        .name = "demo",
        .options = &.{
            .{ .long = "config", .short = 'c', .value_name = "path", .required = true },
        },
    };

    var diagnostic: zigma.args.Diagnostic = .{};
    try std.testing.expectError(
        error.MissingRequiredOption,
        zigma.args.parseDetailed(std.testing.allocator, command, &.{}, &diagnostic),
    );
    try std.testing.expectEqual(zigma.args.DiagnosticKind.missing_required_option, diagnostic.kind);

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try diagnostic.write(&writer.writer);
    try std.testing.expectEqualStrings("missing required option: --config\n", writer.written());
}

test "cli app dispatches subcommands aliases and parsed options" {
    const app: zigma.cli.App = .{
        .name = "demo",
        .version = "1.2.3",
        .routes = &.{
            zigma.routeWithAliases(zigma.command("hello", "", &.{
                zigma.option("name", 'n', "text", "world", ""),
            }), &.{"hi"}, testCliHandler),
        },
    };

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.cli.run(std.testing.allocator, &writer.writer, app, &.{ "hi", "--name", "Zig" });
    try std.testing.expectEqualStrings("ran:Zig\n", writer.written());
}

test "cli app shows command help without explicit help option" {
    const app: zigma.cli.App = .{
        .name = "demo",
        .routes = &.{
            zigma.route(zigma.command("hello", "Greet.", &.{
                zigma.option("name", 'n', "text", "world", ""),
            }), testCliHandler),
        },
    };

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.cli.runWithCapabilities(std.testing.allocator, &writer.writer, app, &.{ "hello", "--help" }, .{ .ansi = false, .charset = .ascii });
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Usage: hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "--name <text>") != null);
}

test "single command runner supplies parsed values and ui" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.cli.runCommandWithCapabilities(
        std.testing.allocator,
        &writer.writer,
        zigma.command("hello", "", &.{
            zigma.option("name", 'n', "text", "world", ""),
        }),
        testCliHandler,
        &.{ "--name", "short" },
        .{ .ansi = false, .charset = .ascii },
    );
    try std.testing.expectEqualStrings("ran:short\n", writer.written());
}

test "single command shows help without explicit help option" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.cli.runCommandWithCapabilities(
        std.testing.allocator,
        &writer.writer,
        zigma.command("hello", "Greet.", &.{
            zigma.option("name", 'n', "text", "world", ""),
        }),
        testCliHandler,
        &.{"--help"},
        .{ .ansi = false, .charset = .ascii },
    );
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Usage: hello") != null);
}

test "text padding and truncation are predictable" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.text.writePadded(&writer.writer, "zig", 5, .right);
    try writer.writer.writeAll("|");
    try zigma.text.writeTruncated(&writer.writer, "abcdef", 4);

    try std.testing.expectEqualStrings("  zig|abc…", writer.written());
}

test "text width is utf8-aware for multilingual UI" {
    try std.testing.expectEqual(@as(usize, 4), zigma.text.width("ภาษา"));
    try std.testing.expectEqual(@as(usize, 4), zigma.text.width("日本"));
    try std.testing.expectEqual(@as(usize, 2), zigma.text.width("🚀"));

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try zigma.text.writeTruncated(&writer.writer, "ภาษาไทย", 5);
    try std.testing.expectEqualStrings("ภาษา…", writer.written());
}

test "terminal color detection respects NO_COLOR and force" {
    try std.testing.expect(!zigma.terminal.shouldUseColor("1", null, true));
    try std.testing.expect(zigma.terminal.shouldUseColor("1", "1", false));

    const caps = zigma.terminal.detect(.{
        .is_tty = true,
        .term = "xterm-256color",
        .colorterm = "truecolor",
    });
    try std.testing.expect(caps.ansi);
    try std.testing.expectEqual(zigma.terminal.ColorMode.truecolor, caps.color);
}

test "terminal default charset is safe on windows" {
    const expected: zigma.terminal.Charset = if (builtin.os.tag == .windows) .ascii else .unicode;
    try std.testing.expectEqual(expected, zigma.terminal.defaultCharset());
}

test "terminal charset switches to unicode after utf8 setup succeeds" {
    try std.testing.expectEqual(zigma.terminal.Charset.unicode, zigma.terminal.charsetAfterUtf8Setup(.enabled));
    try std.testing.expectEqual(zigma.terminal.defaultCharset(), zigma.terminal.charsetAfterUtf8Setup(.failed));
}

test "glyph presets support unicode and ascii terminals" {
    try std.testing.expectEqualStrings("┌", zigma.widgets.Glyphs.unicode.top_left);
    try std.testing.expectEqualStrings("+", zigma.widgets.Glyphs.ascii.top_left);
    try std.testing.expectEqualStrings("+", zigma.widgets.Glyphs.fromCharset(.ascii).top_left);
}

test "widgets render progress and spinner frames" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.widgets.renderProgress(&writer.writer, 5, 10, .{ .width = 4, .fill = "#", .empty = "-" });
    try std.testing.expectEqualStrings("[##--] 50%", writer.written());
    try std.testing.expectEqualStrings("⠹", (zigma.widgets.Spinner{}).frame(2));
}

test "progress can use ascii-safe glyphs" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.widgets.renderProgress(&writer.writer, 3, 4, .{ .width = 4, .glyphs = zigma.widgets.Glyphs.ascii });
    try std.testing.expectEqualStrings("[###-] 75%", writer.written());
}

test "status renderer supports plain output" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.widgets.renderStatus(&writer.writer, .success, "done", false);
    try std.testing.expectEqualStrings("[ok] done\n", writer.written());
}

test "table renderer does not cast headers unsafely" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try zigma.widgets.renderTable(&writer.writer, &.{
        .{ .title = "Name" },
        .{ .title = "Value", .alignment = .right },
    }, &.{
        &.{ "zig", "16" },
    }, .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Name") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "zig") != null);
}

test "ui facade uses terminal charset and plain color settings" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const ui = zigma.widgets.Ui.init(&writer.writer, .{
        .ansi = false,
        .charset = .ascii,
    });
    try ui.status(.success, "done");
    try ui.progress(1, 2, 4);

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "[ok] done") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "[##--] 50%") != null);
}

test "ui facade can be created with plain defaults" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const ui = zigma.widgets.Ui.plain(&writer.writer);
    try ui.status(.success, "done");

    try std.testing.expectEqualStrings("[ok] done\n", writer.written());
}

test "ui facade has short convenience renderers" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const ui = zigma.widgets.Ui.plain(&writer.writer);
    try ui.success("done");
    try ui.kv("mode", "test");
    try ui.rule("next");
    try ui.meter(1, 2);
    try ui.line();

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "[ok] done") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "mode  test") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "-- next --") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "[############------------] 50%") != null);
}

test "ascii ui does not emit unicode line art or block glyphs" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const ui = zigma.widgets.Ui.init(&writer.writer, .{
        .ansi = false,
        .charset = .ascii,
    });
    try ui.table(&.{
        .{ .title = "A" },
        .{ .title = "B" },
    }, &.{
        &.{ "1", "2" },
    });
    try writer.writer.writeAll("\n");
    try ui.progress(1, 2, 4);

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "+---+---+") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "[##--] 50%") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "┌") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "█") == null);
}

test "unicode ui emits unicode glyphs when requested" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const ui = zigma.widgets.Ui.init(&writer.writer, .{
        .ansi = false,
        .charset = .unicode,
    });
    try ui.table(&.{
        .{ .title = "A" },
        .{ .title = "B" },
    }, &.{
        &.{ "ไทย", "日本" },
    });
    try writer.writer.writeAll("\n");
    try ui.progress(1, 2, 4);

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "┌") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "█") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "ไทย") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "日本") != null);
}

test "tui split and key decoding work" {
    const parts = zigma.tui.split(.{ .width = 10, .height = 5 }, .horizontal, 4);
    try std.testing.expectEqual(@as(usize, 4), parts[0].width);
    try std.testing.expectEqual(@as(usize, 6), parts[1].width);
    try std.testing.expectEqual(zigma.tui.Key.arrow_up, zigma.tui.decodeKey("\x1b[A"));
}

test "tui layout screen menu and form support advanced flows" {
    var areas: [3]zigma.tui.Rect = undefined;
    const count = zigma.tui.layout(.{ .width = 100, .height = 20 }, .horizontal, &.{
        .{ .fixed = 20 },
        .{ .percent = 30 },
        .fill,
    }, &areas);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(usize, 20), areas[0].width);
    try std.testing.expectEqual(@as(usize, 30), areas[1].width);
    try std.testing.expectEqual(@as(usize, 50), areas[2].width);

    var screen = try zigma.tui.Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    screen.writeText(0, 0, "ไทย");
    screen.writeText(0, 1, "日本");

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try screen.render(&writer.writer);
    try zigma.tui.renderMenu(&writer.writer, &.{ .{ .label = "One" }, .{ .label = "Two", .help = "selected" } }, 1, .{});
    try zigma.tui.renderForm(&writer.writer, &.{.{ .label = "Name", .value = "Zigma" }});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "ไทย") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "> Two") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "Name: Zigma") != null);
}
