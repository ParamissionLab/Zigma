# Zigma

Zigma is a lightweight Zig toolkit for command-line apps and terminal UI output. It keeps the short path short: argv parsing, stdout setup, UTF-8 setup, terminal capabilities, UI defaults, help text, diagnostics, and flushing can all be handled by the library.

Use the high-level API first. Drop to the explicit modules only when you need custom allocation, custom writers, deterministic tests, or non-default terminal behavior.

## What You Get

- Short CLI entry points: `zigma.runCommand` and `zigma.run`.
- Built-in command specs with `zigma.cmd`, `zigma.cmdArgs`, `zigma.opt`, `zigma.flag`, `zigma.req`, `zigma.arg`, and `zigma.optionalArg`.
- Handler context with typed accessors, writer, terminal capabilities, and `ctx.ui` ready to use.
- Generated app/command help and parser diagnostics. Commands support `--help` without declaring a help option.
- ANSI colors, RGB colors, cursor helpers, terminal capability detection, and Windows UTF-8 setup.
- UI widgets: sections, statuses, key/value rows, tables, progress bars, spinners, and prompts.
- TUI primitives: rectangles, constraints, screen buffers, menus, forms, boxes, and key decoding.
- Unicode-aware text helpers for common terminal text width, padding, truncation, wrapping, and alignment.
- ASCII-safe glyph fallbacks for Windows, CI, redirected output, or terminals with broken line art.

## Requirements

- Zig `0.16.0` or newer in the 0.16 series.
- No third-party runtime dependencies.

Check your Zig version:

```sh
zig version
```

## Install

From a local checkout:

```sh
zig fetch --save=zigma path/to/Zigma
```

From a Git repository:

```sh
zig fetch --save=zigma git+https://github.com/ParamissionLab/Zigma.git
```

Then add the module to your executable in `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "mytool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const zigma = b.dependency("zigma", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigma", zigma.module("zigma"));

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run mytool");
    run_step.dependOn(&run.step);
}
```

Import it in application code:

```zig
const zigma = @import("zigma");
```

## Quick Start: Single Command

This is the recommended shape for small CLIs.

```zig
const std = @import("std");
const zigma = @import("zigma");

fn hello(ctx: *zigma.Context) !void {
    try ctx.success("ready");
    try ctx.writer.print("Hello, {s}\n", .{ctx.string("name", "world")});
}

pub fn main(init: std.process.Init) !void {
    try zigma.runCommand(init, zigma.cmd("hello", "Greet someone.", &.{
        zigma.opt("name", 'n', "text", "world", "Name to greet."),
    }), hello);
}
```

Run it:

```sh
zig build run -- --name Zigma
zig build run -- --help
```

`runCommand` handles:

- arena allocator from `std.process.Init`
- argv conversion
- stdout writer setup
- Windows UTF-8 setup
- terminal capability defaults
- parser diagnostics
- generated help
- final flush

Set `.version` on `zigma.App` only when your application wants `--version` output. Zigma's own `zigma.version` is generated from `build.zig.zon`, so package version bumps only need the package metadata updated.

## Quick Start: Subcommands

Use `zigma.run` when the app has multiple commands.

```zig
const std = @import("std");
const zigma = @import("zigma");

fn hello(ctx: *zigma.Context) !void {
    try ctx.writer.print("Hello, {s}\n", .{ctx.string("name", "world")});
}

fn dashboard(ctx: *zigma.Context) !void {
    try ctx.ui.section("Dashboard");
    try ctx.success("systems ready");
    try ctx.ui.meter(7, 10);
    try ctx.ui.line();
}

pub fn main(init: std.process.Init) !void {
    try zigma.run(init, .{
        .name = "mytool",
        .description = "Small CLI with subcommands.",
        .routes = &.{
            zigma.routeWithAliases(zigma.cmd("hello", "Greet someone.", &.{
                zigma.opt("name", 'n', "text", "world", "Name to greet."),
            }), &.{"hi"}, hello),
            zigma.route(zigma.cmd("dashboard", "Show status.", &.{}), dashboard),
        },
    });
}
```

Run it:

```sh
zig build run -- hello --name Ada
zig build run -- hi --name Ada
zig build run -- dashboard
zig build run -- --help
```

## Handler Context

Handlers receive `*zigma.Context`.

```zig
fn handler(ctx: *zigma.Context) !void {
    if (ctx.has("verbose")) {
        try ctx.ui.status(.info, "verbose mode");
    }

    const name = ctx.string("name", "world");
    try ctx.writer.print("Hello, {s}\n", .{name});

    if (ctx.caps.charset == .ascii) {
        try ctx.ui.status(.warning, "using ASCII-safe glyphs");
    }
}
```

Important fields:

| Field | Purpose |
| --- | --- |
| `ctx.allocator` | Allocator from the runner. |
| `ctx.writer` | Output writer. |
| `ctx.parsed` | Full parsed argument result. |
| `ctx.global` | Parsed app-level options for multi-command apps. |
| `ctx.caps` | Terminal capabilities: ANSI, color mode, charset, size. |
| `ctx.ui` | Ready-to-use `widgets.Ui` configured from `ctx.caps`. |

Important methods:

| Method | Purpose |
| --- | --- |
| `ctx.has("flag")` | True when a flag or option was present. |
| `ctx.value("name")` | Last parsed option value or default. |
| `ctx.string("name", "fallback")` | String value with fallback. |
| `ctx.boolean("force", false)` | Boolean value. Flags parse as true. |
| `try ctx.int(u16, "port", 8080)` | Integer value with fallback. |
| `ctx.positional(0)` | Positional argument by index. |
| `ctx.count("verbose")` | Number of times an option appeared. |
| `ctx.globalString("env", "dev")` | Global string option with fallback. |
| `ctx.globalBoolean("json", false)` | Global boolean option. |
| `try ctx.globalInt(u16, "port", 8080)` | Global integer option with fallback. |
| `ctx.status(.success, "done")` | Shortcut for `ctx.ui.status`. |
| `ctx.success("done")` | Shortcut success line. |
| `ctx.info(...)`, `ctx.warning(...)`, `ctx.err(...)` | Common status shortcuts. |

## Options

```zig
zigma.flag("verbose", 'v', "Show more details.")
zigma.opt("name", 'n', "text", "world", "Name to use.")
zigma.req("config", 'c', "path", "Config file.")
```

The equivalent explicit form is still supported:

```zig
.{ .long = "name", .short = 'n', .value_name = "text", .default = "world", .help = "Name to use." }
```

Parser behavior:

- Flags can be repeated, including short groups like `-vvv`.
- Options accept `--name value`, `--name=value`, or `-nvalue`.
- `--` ends option parsing and treats the rest as positionals.
- Defaults are returned by `ctx.value` and `args.Result.value`.
- Required options produce a diagnostic and generated help.
- `--help` and `-h` work automatically for apps and commands.
- `zigma.helpFlag()` still exists for projects that want an explicit help option in their specs.

## Positional Arguments

Use `zigma.cmdArgs` when a command has named positional arguments. Zigma validates required arguments and includes them in generated usage/help.

```zig
const copy = zigma.cmdArgs("copy", "Copy a file.", &.{
    zigma.flag("force", 'f', "Overwrite destination."),
}, &.{
    zigma.arg("source", "Source path."),
    zigma.optionalArg("dest", "Destination path."),
});

fn runCopy(ctx: *zigma.Context) !void {
    const source = ctx.positional(0).?;
    const dest = ctx.positional(1) orelse ".";
    try ctx.writer.print("{s} -> {s}\n", .{ source, dest });
}
```

Generated usage:

```text
Usage: copy [options] <source> [dest]
```

## Scaling To Large Apps

Small tools can stay tiny with `zigma.runCommand`. Larger apps can use the same primitives with app-level options, lifecycle hooks, command groups, aliases, and hidden internal routes.

```zig
fn before(ctx: *zigma.Context) !void {
    if (ctx.globalBoolean("verbose", false)) {
        try ctx.info("verbose mode");
    }
}

fn deploy(ctx: *zigma.Context) !void {
    const env = ctx.globalString("env", "dev");
    const target = ctx.positional(0) orelse "default";
    try ctx.writer.print("deploy {s} to {s}\n", .{ target, env });
}

pub fn main(init: std.process.Init) !void {
    try zigma.run(init, .{
        .name = "ops",
        .description = "Operations toolkit.",
        .options = &.{
            zigma.opt("env", 'e', "name", "dev", "Environment."),
            zigma.flag("verbose", 'v', "Show detailed output."),
        },
        .before = before,
        .routes = &.{
            zigma.groupedRoute("Deploy", zigma.cmdArgs("deploy", "Deploy a target.", &.{}, &.{
                zigma.optionalArg("target", "Target name."),
            }), deploy),
            zigma.hiddenRoute(zigma.cmd("internal-cache", "Maintenance task.", &.{}), deploy),
        },
    });
}
```

Run it:

```sh
zig build run -- --env prod --verbose deploy api
zig build run -- --help
zig build run -- deploy --help
```

Large-app support includes:

- App-level `options` parsed before the command.
- `ctx.globalString`, `ctx.globalBoolean`, and `ctx.globalInt` for shared config.
- `before` and `after` hooks at both app and route level.
- `groupedRoute` for categorized help output.
- `hiddenRoute` for internal commands that still dispatch but do not appear in help.

## UI Widgets

Use `ctx.ui` inside CLI handlers:

```zig
try ctx.ui.section("Deploy");
try ctx.ui.rule("build");
try ctx.success("built");
try ctx.ui.kv("target", "linux-x86_64");
try ctx.ui.kv("mode", "ReleaseSafe");
try ctx.ui.meter(3, 5);
try ctx.ui.line();
```

Tables:

```zig
try ctx.ui.table(&.{
    .{ .title = "Name", .width = 12 },
    .{ .title = "Status", .width = 10 },
}, &.{
    &.{ "api", "ready" },
    &.{ "worker", "queued" },
});
```

Create a UI outside the CLI runner:

```zig
const ui = zigma.widgets.Ui.auto(stdout);
try ui.status(.success, "done");
```

Use plain output for tests, logs, or CI:

```zig
const ui = zigma.widgets.Ui.plain(writer);
```

## Terminal Defaults

The high-level runners use `zigma.terminal.detectDefault(.{})`.

Defaults:

- `is_tty = true`
- ANSI enabled unless disabled through supplied options
- UTF-8 setup attempted on Windows
- Unicode glyphs after successful UTF-8 setup
- ASCII-safe glyphs when the platform or setup requires fallback
- terminal size falls back to `80x24`

Manual detection:

```zig
const caps = zigma.terminal.detectDefault(.{
    .term = "xterm-256color",
    .colorterm = "truecolor",
});
const ui = zigma.widgets.Ui.init(stdout, caps);
```

Fully explicit detection for tests or custom apps:

```zig
const caps = zigma.terminal.detect(.{
    .is_tty = false,
    .charset = .ascii,
    .size = .{ .cols = 100, .rows = 30 },
});
```

## Explicit Parser API

Use this when you do not want Zigma to own the app runner.

```zig
const command = zigma.command("copy", "Copy a file.", &.{
    zigma.requiredOption("from", null, "path", "Source path."),
    zigma.requiredOption("to", null, "path", "Destination path."),
});

var diagnostic: zigma.args.Diagnostic = .{};
const parsed = zigma.args.parseDetailed(allocator, command, argv[1..], &diagnostic) catch |err| {
    try diagnostic.write(stderr);
    try zigma.args.writeHelp(stderr, command);
    return err;
};
defer parsed.deinit();
```

## Explicit Writer API

All renderers accept `*std.Io.Writer`, so they work with stdout, files, buffers, and tests.

```zig
var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
defer writer.deinit();

try zigma.widgets.renderProgress(&writer.writer, 5, 10, .{
    .width = 12,
    .glyphs = zigma.widgets.Glyphs.ascii,
});
```

## Styling

```zig
try (zigma.ansi.Style{
    .fg = .cyan,
    .bold = true,
    .enabled = ctx.caps.ansi,
}).write(ctx.writer, "Hello");
```

RGB color:

```zig
try zigma.ansi.rgb(120, 180, 255).write(ctx.writer, "custom color");
```

Disable ANSI without changing rendering code:

```zig
const plain = zigma.ansi.Style{ .fg = .red, .bold = true, .enabled = false };
```

## Text Helpers

```zig
try zigma.text.writePadded(writer, "zig", 8, .right);
try zigma.text.writeTruncated(writer, "ภาษาไทย", 5);
const width = zigma.text.width("日本語");
```

Zigma handles common UTF-8 terminal width cases including CJK wide characters, Thai combining marks, Arabic/Hebrew marks, ANSI escape sequences, and common emoji ranges. It does not ship a large Unicode database.

## TUI Primitives

Zigma is not a full curses replacement. It provides composable primitives.

```zig
var areas: [3]zigma.tui.Rect = undefined;
_ = zigma.tui.layout(.{ .width = 100, .height = 30 }, .vertical, &.{
    .{ .fixed = 3 },
    .fill,
    .{ .fixed = 5 },
}, &areas);

try zigma.tui.renderMenu(ctx.writer, &.{
    .{ .label = "Overview" },
    .{ .label = "Settings", .help = "selected" },
}, 1, .{});

try zigma.tui.renderForm(ctx.writer, &.{
    .{ .label = "Project", .value = "Zigma" },
    .{ .label = "Mode", .placeholder = "interactive" },
});
```

## API Map

| API | Use |
| --- | --- |
| `zigma.cli.runCommandMain(init, command, handler)` | Shortest single-command CLI. |
| `zigma.cli.runMain(init, app)` | Multi-command app runner. |
| `zigma.runCommand(init, command, handler)` | Root alias for single-command CLI. |
| `zigma.run(init, app)` | Root alias for multi-command app. |
| `zigma.cli.runCommand(...)` | Single command with caller-provided allocator/writer/argv. |
| `zigma.cli.run(...)` | Multi-command app with caller-provided allocator/writer/argv. |
| `zigma.cli.runCommandWithCapabilities(...)` | Deterministic single-command runner for tests/custom terminal state. |
| `zigma.cli.runWithCapabilities(...)` | Deterministic app runner for tests/custom terminal state. |
| `zigma.command(...)` | Build an `args.Command`. |
| `zigma.cmd(...)` | Short alias for `zigma.command`. |
| `zigma.commandWithArgs(...)` | Build a command with positional argument specs. |
| `zigma.cmdArgs(...)` | Short alias for `zigma.commandWithArgs`. |
| `zigma.flag(...)` | Build a boolean flag option. |
| `zigma.option(...)` | Build a value option with optional default. |
| `zigma.opt(...)` | Short alias for `zigma.option`. |
| `zigma.requiredOption(...)` | Build a required value option. |
| `zigma.req(...)` | Short alias for `zigma.requiredOption`. |
| `zigma.arg(...)` | Build a required positional argument spec. |
| `zigma.optionalArg(...)` | Build an optional positional argument spec. |
| `zigma.helpFlag()` | Build `-h, --help`. |
| `zigma.route(...)` | Root alias for a route. |
| `zigma.routeWithAliases(...)` | Root alias for a route with aliases. |
| `zigma.groupedRoute(...)` | Route grouped under a help heading. |
| `zigma.hiddenRoute(...)` | Dispatchable route omitted from app help. |
| `zigma.widgets.Ui.auto(writer)` | UI with default terminal setup. |
| `zigma.widgets.Ui.plain(writer)` | Plain ASCII UI. |
| `zigma.terminal.detectDefault(.{})` | Practical terminal defaults. |
| `zigma.terminal.detect(.{})` | Fully explicit terminal detection. |

## Module Reference

| Module | Purpose |
| --- | --- |
| `zigma.args` | Command specs, option specs, parsing, diagnostics, generated help. |
| `zigma.cli` | App runners, subcommands, aliases, hooks, context. |
| `zigma.ansi` | ANSI styles, colors, RGB, cursor movement, screen clearing. |
| `zigma.terminal` | Terminal capabilities, color mode, UTF-8 setup, charset fallback. |
| `zigma.text` | UTF-8-aware display width, padding, truncation, wrapping, alignment. |
| `zigma.widgets` | UI facade, themes, glyphs, tables, progress bars, statuses, prompts. |
| `zigma.tui` | Rectangles, constraints, screen buffers, menus, forms, boxes, key decoding. |

## Examples In This Repo

```sh
zig build example-basic -- --name Zigma --loud
zig build example-tui
zig build example-advanced -- hello --name Codex
zig build example-advanced -- dashboard
```

Example files:

- `examples/basic.zig`: shortest single-command CLI.
- `examples/advanced.zig`: subcommands, aliases, context UI, multilingual output.
- `examples/tui.zig`: direct widget and TUI rendering.

## Development

```sh
zig build check
zig build test
zig fmt --check build.zig src examples tests
```

`zig build check` runs tests and compiles/runs the bundled examples.

## Design Rules

- High-level APIs should be short enough for real app code.
- Explicit APIs must remain available for tests and advanced use.
- No hidden allocation in low-level modules.
- Renderers accept writers instead of using global stdout.
- Unicode and ASCII paths are both supported.
- Standard library only.

## License

Apache-2.0. See [LICENSE](LICENSE).
