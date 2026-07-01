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
    global: ?args.Result = null,
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

    /// Return true when a global option exists.
    pub fn globalHas(self: Context, name: []const u8) bool {
        const parsed_global = self.global orelse return false;
        return parsed_global.has(name);
    }

    /// Return a global option value or default.
    pub fn globalValue(self: Context, name: []const u8) ?[]const u8 {
        const parsed_global = self.global orelse return null;
        return parsed_global.value(name);
    }

    /// Return a global string option, or `fallback` when missing.
    pub fn globalString(self: Context, name: []const u8, fallback: []const u8) []const u8 {
        const parsed_global = self.global orelse return fallback;
        return parsed_global.string(name, fallback);
    }

    /// Return a global boolean option. Flags parse as true.
    pub fn globalBoolean(self: Context, name: []const u8, fallback: bool) bool {
        const parsed_global = self.global orelse return fallback;
        return parsed_global.boolean(name, fallback);
    }

    /// Parse a global integer option, or return `fallback` when missing.
    pub fn globalInt(self: Context, comptime T: type, name: []const u8, fallback: T) !T {
        const parsed_global = self.global orelse return fallback;
        return parsed_global.int(T, name, fallback);
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
    group: []const u8 = "",
    hidden: bool = false,
    before: ?Hook = null,
    after: ?Hook = null,
};

/// CLI application specification.
pub const App = struct {
    name: []const u8,
    version: []const u8 = "",
    description: []const u8 = "",
    options: []const args.Option = &.{},
    routes: []const Route = &.{},
    before: ?Hook = null,
    after: ?Hook = null,
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

/// Create a grouped route for larger applications with categorized help.
pub fn groupedRoute(group: []const u8, cmd: args.Command, handler: Handler) Route {
    return .{
        .command = cmd,
        .handler = handler,
        .group = group,
    };
}

/// Create a hidden route that is dispatchable but omitted from app help.
pub fn hiddenRoute(cmd: args.Command, handler: Handler) Route {
    return .{
        .command = cmd,
        .handler = handler,
        .hidden = true,
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
    var split = try splitGlobalArgs(allocator, app.options, argv);
    defer split.deinit(allocator);

    const global_cmd: args.Command = .{
        .name = app.name,
        .options = app.options,
    };
    var global_diagnostic: args.Diagnostic = .{};
    const global_parsed = args.parseDetailed(allocator, global_cmd, split.global_tokens, &global_diagnostic) catch |err| {
        try global_diagnostic.write(writer);
        try writer.writeAll("\n");
        try writeHelp(writer, app);
        return err;
    };
    defer global_parsed.deinit();

    const command_argv = split.rest;
    if (command_argv.len == 0 or isHelp(command_argv[0])) {
        try writeHelp(writer, app);
        return;
    }
    if (std.mem.eql(u8, command_argv[0], "--version") or std.mem.eql(u8, command_argv[0], "-V")) {
        if (app.version.len > 0) {
            try writer.print("{s} {s}\n", .{ app.name, app.version });
        } else {
            try writer.print("{s}\n", .{app.name});
        }
        return;
    }

    const matched_route = findRoute(app.routes, command_argv[0]) orelse {
        try writer.print("unknown command: {s}\n\n", .{command_argv[0]});
        try writeHelp(writer, app);
        return error.UnknownCommand;
    };
    if (hasCommandHelp(command_argv[1..])) {
        try args.writeHelp(writer, matched_route.command);
        return;
    }

    var diagnostic: args.Diagnostic = .{};
    const parsed = args.parseDetailed(allocator, matched_route.command, command_argv[1..], &diagnostic) catch |err| {
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
        .global = global_parsed,
        .caps = caps,
        .ui = widgets.Ui.init(writer, caps),
    };
    if (context.has("help")) {
        try args.writeHelp(writer, matched_route.command);
        return;
    }
    if (app.before) |hook| try hook(&context);
    if (matched_route.before) |hook| try hook(&context);
    try matched_route.handler(&context);
    if (matched_route.after) |hook| try hook(&context);
    if (app.after) |hook| try hook(&context);
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
        .global = null,
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
    try writeRouteGroups(writer, app.routes);
    if (app.options.len > 0) {
        try writer.writeAll("\nGlobal Options:\n");
        try writeOptions(writer, app.options);
    }
    try writer.writeAll("\nGlobal:\n");
    try writer.writeAll("  -h, --help       Show help\n");
    if (app.version.len > 0) try writer.writeAll("  -V, --version    Show version\n");
}

const GlobalSplit = struct {
    global_tokens: []const []const u8,
    rest: []const []const u8,

    fn deinit(self: GlobalSplit, allocator: std.mem.Allocator) void {
        allocator.free(self.global_tokens);
    }
};

fn splitGlobalArgs(allocator: std.mem.Allocator, options: []const args.Option, argv: []const []const u8) !GlobalSplit {
    var global_tokens: std.ArrayList([]const u8) = .empty;
    errdefer global_tokens.deinit(allocator);

    var i: usize = 0;
    while (i < argv.len) {
        const span = globalTokenSpan(options, argv, i) orelse break;
        try global_tokens.appendSlice(allocator, argv[i .. i + span]);
        i += span;
    }

    return .{
        .global_tokens = try global_tokens.toOwnedSlice(allocator),
        .rest = argv[i..],
    };
}

fn globalTokenSpan(options: []const args.Option, argv: []const []const u8, index: usize) ?usize {
    if (options.len == 0 or index >= argv.len) return null;
    const token = argv[index];
    if (std.mem.eql(u8, token, "--")) return null;
    if (std.mem.startsWith(u8, token, "--") and token.len > 2) {
        const raw = token[2..];
        const eq = std.mem.indexOfScalar(u8, raw, '=');
        const name = if (eq) |at| raw[0..at] else raw;
        const spec = findLongOption(options, name) orelse return null;
        if (spec.value_name != null and eq == null and index + 1 < argv.len) return 2;
        return 1;
    }
    if (std.mem.startsWith(u8, token, "-") and token.len > 1) {
        var short_i: usize = 1;
        while (short_i < token.len) : (short_i += 1) {
            const spec = findShortOption(options, token[short_i]) orelse return null;
            if (spec.value_name != null) {
                if (short_i + 1 < token.len) return 1;
                return if (index + 1 < argv.len) 2 else 1;
            }
        }
        return 1;
    }
    return null;
}

fn findLongOption(options: []const args.Option, name: []const u8) ?args.Option {
    for (options) |option| {
        if (std.mem.eql(u8, option.long, name)) return option;
    }
    return null;
}

fn findShortOption(options: []const args.Option, short: u8) ?args.Option {
    for (options) |option| {
        if (option.short != null and option.short.? == short) return option;
    }
    return null;
}

fn writeRouteGroups(writer: *std.Io.Writer, routes: []const Route) !void {
    if (hasVisibleUngrouped(routes)) {
        try writer.writeAll("Commands:\n");
        for (routes) |entry| {
            if (!entry.hidden and entry.group.len == 0) try writeRoute(writer, entry);
        }
    }
    for (routes, 0..) |entry, i| {
        if (entry.hidden or entry.group.len == 0 or groupSeen(routes, i)) continue;
        try writer.print("{s}:\n", .{entry.group});
        for (routes) |candidate| {
            if (!candidate.hidden and std.mem.eql(u8, candidate.group, entry.group)) try writeRoute(writer, candidate);
        }
    }
}

fn hasVisibleUngrouped(routes: []const Route) bool {
    for (routes) |entry| {
        if (!entry.hidden and entry.group.len == 0) return true;
    }
    return false;
}

fn groupSeen(routes: []const Route, index: usize) bool {
    var i: usize = 0;
    while (i < index) : (i += 1) {
        if (!routes[i].hidden and std.mem.eql(u8, routes[i].group, routes[index].group)) return true;
    }
    return false;
}

fn writeRoute(writer: *std.Io.Writer, entry: Route) !void {
    try writer.print("  {s}", .{entry.command.name});
    if (entry.aliases.len > 0) {
        try writer.writeAll(" (");
        for (entry.aliases, 0..) |alias, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(alias);
        }
        try writer.writeAll(")");
    }
    if (entry.command.description.len > 0) try writer.print("\n      {s}", .{entry.command.description});
    try writer.writeAll("\n");
}

fn writeOptions(writer: *std.Io.Writer, options: []const args.Option) !void {
    for (options) |option| {
        try writer.writeAll("  ");
        if (option.short) |short| {
            try writer.print("-{c}, ", .{short});
        } else {
            try writer.writeAll("    ");
        }
        try writer.print("--{s}", .{option.long});
        if (option.value_name) |name| try writer.print(" <{s}>", .{name});
        if (option.required) try writer.writeAll(" (required)");
        if (option.default) |default| try writer.print(" [default: {s}]", .{default});
        if (option.help.len > 0) try writer.print("\n      {s}", .{option.help});
        try writer.writeAll("\n");
    }
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
