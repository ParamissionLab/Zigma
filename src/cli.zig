//! Higher-level CLI application helpers: subcommands, built-in help/version,
//! and small handler contexts.

const std = @import("std");
const args = @import("args.zig");
const terminal = @import("terminal.zig");
const widgets = @import("widgets.zig");

/// CLI context passed to command handlers.
pub const Context = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    app: *const App,
    route: *const Route,
    parsed: args.Result,
    caps: terminal.Capabilities,
    ui: widgets.Ui,

    /// Return true when a parsed option exists.
    pub fn has(self: Context, name: []const u8) bool {
        return self.parsed.has(name);
    }

    /// Return the parsed option value or default.
    pub fn value(self: Context, name: []const u8) ?[]const u8 {
        return self.parsed.value(name);
    }

    /// Return the parsed option value, or `fallback` when missing.
    pub fn string(self: Context, name: []const u8, fallback: []const u8) []const u8 {
        return self.parsed.string(name, fallback);
    }

    /// Return a boolean option value. Flags parse as true.
    pub fn boolean(self: Context, name: []const u8, fallback: bool) bool {
        return self.parsed.boolean(name, fallback);
    }

    /// Parse an integer option value, or return `fallback` when missing.
    pub fn int(self: Context, comptime T: type, name: []const u8, fallback: T) !T {
        return self.parsed.int(T, name, fallback);
    }

    /// Return a positional argument by index.
    pub fn positional(self: Context, index: usize) ?[]const u8 {
        return self.parsed.positional(index);
    }

    /// Return the number of times an option appeared.
    pub fn count(self: Context, name: []const u8) usize {
        return self.parsed.count(name);
    }

    /// Render a status line with the context UI.
    pub fn status(self: Context, kind: widgets.Status, message: []const u8) !void {
        try self.ui.status(kind, message);
    }

    /// Render an info status line.
    pub fn info(self: Context, message: []const u8) !void {
        try self.ui.info(message);
    }

    /// Render a success status line.
    pub fn success(self: Context, message: []const u8) !void {
        try self.ui.success(message);
    }

    /// Render a warning status line.
    pub fn warning(self: Context, message: []const u8) !void {
        try self.ui.warning(message);
    }

    /// Render an error status line.
    pub fn err(self: Context, message: []const u8) !void {
        try self.ui.err(message);
    }
};

/// Command handler signature.
pub const Handler = *const fn (*Context) anyerror!void;

/// Optional hook called before or after a command handler.
pub const Hook = *const fn (*Context) anyerror!void;

/// A runnable CLI route.
pub const Route = struct {
    command: args.Command,
    handler: Handler,
    aliases: []const []const u8 = &.{},
    before: ?Hook = null,
    after: ?Hook = null,
};

/// CLI application specification.
pub const App = struct {
    name: []const u8,
    version: []const u8 = "0.0.0",
    description: []const u8 = "",
    routes: []const Route = &.{},
};

/// Create a route from a command spec and handler.
pub fn route(cmd: args.Command, handler: Handler) Route {
    return .{
        .command = cmd,
        .handler = handler,
    };
}

/// Create a route with aliases from a command spec and handler.
pub fn routeWithAliases(cmd: args.Command, aliases: []const []const u8, handler: Handler) Route {
    return .{
        .command = cmd,
        .handler = handler,
        .aliases = aliases,
    };
}

/// CLI dispatcher errors.
pub const Error = error{
    UnknownCommand,
};

/// Run an app from argv tokens. Pass `argv[1..]` when the executable name is
/// included in the original argv slice.
pub fn run(allocator: std.mem.Allocator, writer: *std.Io.Writer, app: App, argv: []const []const u8) anyerror!void {
    const caps = terminal.detectDefault(.{});
    try runWithCapabilities(allocator, writer, app, argv, caps);
}

/// Run an app using caller-supplied terminal capabilities.
pub fn runWithCapabilities(allocator: std.mem.Allocator, writer: *std.Io.Writer, app: App, argv: []const []const u8, caps: terminal.Capabilities) anyerror!void {
    if (argv.len == 0 or isHelp(argv[0])) {
        try writeHelp(writer, app);
        return;
    }
    if (std.mem.eql(u8, argv[0], "--version") or std.mem.eql(u8, argv[0], "-V")) {
        try writer.print("{s} {s}\n", .{ app.name, app.version });
        return;
    }

    const matched_route = findRoute(app.routes, argv[0]) orelse {
        try writer.print("unknown command: {s}\n\n", .{argv[0]});
        try writeHelp(writer, app);
        return error.UnknownCommand;
    };
    if (hasCommandHelp(argv[1..])) {
        try args.writeHelp(writer, matched_route.command);
        return;
    }

    var diagnostic: args.Diagnostic = .{};
    const parsed = args.parseDetailed(allocator, matched_route.command, argv[1..], &diagnostic) catch |err| {
        try diagnostic.write(writer);
        try writer.writeAll("\n");
        try args.writeHelp(writer, matched_route.command);
        return err;
    };
    defer parsed.deinit();

    var context: Context = .{
        .allocator = allocator,
        .writer = writer,
        .app = &app,
        .route = matched_route,
        .parsed = parsed,
        .caps = caps,
        .ui = widgets.Ui.init(writer, caps),
    };
    if (context.has("help")) {
        try args.writeHelp(writer, matched_route.command);
        return;
    }
    if (matched_route.before) |hook| try hook(&context);
    try matched_route.handler(&context);
    if (matched_route.after) |hook| try hook(&context);
}

/// Run a single-command CLI from argv tokens. This is the shortest path for
/// small tools that do not need subcommands.
pub fn runCommand(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    cmd: args.Command,
    handler: Handler,
    argv: []const []const u8,
) anyerror!void {
    const caps = terminal.detectDefault(.{});
    try runCommandWithCapabilities(allocator, writer, cmd, handler, argv, caps);
}

/// Run a single-command CLI with caller-supplied terminal capabilities.
pub fn runCommandWithCapabilities(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    cmd: args.Command,
    handler: Handler,
    argv: []const []const u8,
    caps: terminal.Capabilities,
) anyerror!void {
    if (hasCommandHelp(argv)) {
        try args.writeHelp(writer, cmd);
        return;
    }

    var diagnostic: args.Diagnostic = .{};
    const parsed = args.parseDetailed(allocator, cmd, argv, &diagnostic) catch |err| {
        try diagnostic.write(writer);
        try writer.writeAll("\n");
        try args.writeHelp(writer, cmd);
        return err;
    };
    defer parsed.deinit();

    const app: App = .{
        .name = cmd.name,
        .routes = &.{},
    };
    const active_route: Route = .{
        .command = cmd,
        .handler = handler,
    };
    var context: Context = .{
        .allocator = allocator,
        .writer = writer,
        .app = &app,
        .route = &active_route,
        .parsed = parsed,
        .caps = caps,
        .ui = widgets.Ui.init(writer, caps),
    };
    if (context.has("help")) {
        try args.writeHelp(writer, cmd);
        return;
    }
    try handler(&context);
}

/// Run an app from `std.process.Init` with default allocator, argv, stdout,
/// UTF-8 setup, UI capabilities, and final flush.
pub fn runMain(init: std.process.Init, app: App) anyerror!void {
    const allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try run(allocator, stdout, app, argv[1..]);
    try stdout.flush();
}

/// Run a single-command CLI from `std.process.Init` with default allocator,
/// argv, stdout, UTF-8 setup, UI capabilities, and final flush.
pub fn runCommandMain(init: std.process.Init, cmd: args.Command, handler: Handler) anyerror!void {
    const allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try runCommand(allocator, stdout, cmd, handler, argv[1..]);
    try stdout.flush();
}

/// Write application-level help.
pub fn writeHelp(writer: *std.Io.Writer, app: App) !void {
    try writer.print("{s}", .{app.name});
    if (app.version.len > 0) try writer.print(" {s}", .{app.version});
    try writer.writeAll("\n");
    if (app.description.len > 0) try writer.print("{s}\n\n", .{app.description});
    try writer.print("Usage: {s} <command> [options]\n\n", .{app.name});
    try writer.writeAll("Commands:\n");
    for (app.routes) |entry| {
        try writer.print("  {s}", .{entry.command.name});
        if (entry.command.description.len > 0) try writer.print("\n      {s}", .{entry.command.description});
        try writer.writeAll("\n");
    }
    try writer.writeAll("\nGlobal:\n");
    try writer.writeAll("  -h, --help       Show help\n");
    try writer.writeAll("  -V, --version    Show version\n");
}

fn findRoute(routes: []const Route, name: []const u8) ?*const Route {
    for (routes) |*entry| {
        if (std.mem.eql(u8, entry.command.name, name)) return entry;
        for (entry.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return entry;
        }
    }
    return null;
}

fn isHelp(token: []const u8) bool {
    return std.mem.eql(u8, token, "help") or
        std.mem.eql(u8, token, "--help") or
        std.mem.eql(u8, token, "-h");
}

fn hasCommandHelp(argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    if (std.mem.eql(u8, argv[0], "help")) return true;
    for (argv) |token| {
        if (std.mem.eql(u8, token, "--help") or std.mem.eql(u8, token, "-h")) return true;
    }
    return false;
}
