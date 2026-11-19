//! Small spec-driven command-line argument parser.

const std = @import("std");

/// Description of a supported CLI option.
pub const Option = struct {
    long: []const u8,
    short: ?u8 = null,
    value_name: ?[]const u8 = null,
    help: []const u8 = "",
    required: bool = false,
    default: ?[]const u8 = null,
};

/// Description of a positional CLI argument.
pub const Argument = struct {
    name: []const u8,
    help: []const u8 = "",
    required: bool = true,
};

/// Create a boolean flag option.
pub fn flag(long: []const u8, short: ?u8, help_text: []const u8) Option {
    return .{
        .long = long,
        .short = short,
        .help = help_text,
    };
}

/// Create an option that accepts a value and may have a default.
pub fn option(long: []const u8, short: ?u8, value_name: []const u8, default: ?[]const u8, help_text: []const u8) Option {
    return .{
        .long = long,
        .short = short,
        .value_name = value_name,
        .default = default,
        .help = help_text,
    };
}

/// Create a required option that accepts a value.
pub fn requiredOption(long: []const u8, short: ?u8, value_name: []const u8, help_text: []const u8) Option {
    return .{
        .long = long,
        .short = short,
        .value_name = value_name,
        .required = true,
        .help = help_text,
    };
}

/// Common `-h, --help` flag.
pub fn helpFlag() Option {
    return flag("help", 'h', "Show help.");
}

/// Create a required positional argument spec.
pub fn arg(name: []const u8, help_text: []const u8) Argument {
    return .{
        .name = name,
        .help = help_text,
        .required = true,
    };
}

/// Create an optional positional argument spec.
pub fn optionalArg(name: []const u8, help_text: []const u8) Argument {
    return .{
        .name = name,
        .help = help_text,
        .required = false,
    };
}

/// Description of a command or single-command application.
pub const Command = struct {
    name: []const u8,
    description: []const u8 = "",
    usage: ?[]const u8 = null,
    options: []const Option = &.{},
    arguments: []const Argument = &.{},
};

/// Create a command spec with the common fields.
pub fn command(name: []const u8, description: []const u8, options: []const Option) Command {
    return .{
        .name = name,
        .description = description,
        .options = options,
    };
}

/// Create a command spec with options and positional arguments.
pub fn commandWithArgs(name: []const u8, description: []const u8, options: []const Option, arguments: []const Argument) Command {
    return .{
        .name = name,
        .description = description,
        .options = options,
        .arguments = arguments,
    };
}

/// Parsed value for one configured option.
pub const Value = struct {
    name: []const u8,
    value: ?[]const u8 = null,
    count: usize = 0,
};

/// Result returned by `parse`. Call `deinit` when done.
pub const Result = struct {
    allocator: std.mem.Allocator,
    values: []Value,
    positionals: []const []const u8,
    /// True when `--help` or `-h` appeared and the command does not declare
    /// its own option with that name.
    help_requested: bool = false,

    /// Free owned parser result memory.
    pub fn deinit(self: Result) void {
        self.allocator.free(self.values);
        self.allocator.free(self.positionals);
    }

    /// Return true when the user asked for help, through the implicit
    /// `--help`/`-h` tokens or an explicitly declared `help` option.
    pub fn wantsHelp(self: Result) bool {
        return self.help_requested or self.has(implicit_help_long);
    }

    /// Return true when an option was present at least once.
    pub fn has(self: Result, name: []const u8) bool {
        return self.count(name) > 0;
    }

    /// Return the last parsed value for an option, or its default.
    pub fn value(self: Result, name: []const u8) ?[]const u8 {
        const entry = self.find(name) orelse return null;
        return entry.value;
    }

    /// Return the parsed value, or `fallback` when missing.
    pub fn string(self: Result, name: []const u8, fallback: []const u8) []const u8 {
        return self.value(name) orelse fallback;
    }

    /// Return a boolean option value. Flags parse as true.
    pub fn boolean(self: Result, name: []const u8, fallback: bool) bool {
        const raw = self.value(name) orelse return fallback;
        return parseBool(raw) orelse fallback;
    }

    /// Parse an integer option value, or return `fallback` when missing.
    pub fn int(self: Result, comptime T: type, name: []const u8, fallback: T) !T {
        const raw = self.value(name) orelse return fallback;
        return std.fmt.parseInt(T, raw, 10);
    }

    /// Return a positional argument by index.
    pub fn positional(self: Result, index: usize) ?[]const u8 {
        if (index >= self.positionals.len) return null;
        return self.positionals[index];
    }

    /// Return the number of times an option appeared.
    pub fn count(self: Result, name: []const u8) usize {
        const entry = self.find(name) orelse return 0;
        return entry.count;
    }

    fn find(self: Result, name: []const u8) ?Value {
        for (self.values) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }
};

/// Parser failures. Use `Diagnostic` when user-facing messages need more
/// context.
pub const Error = error{
    UnknownOption,
    MissingValue,
    MissingRequiredOption,
    MissingRequiredArgument,
    OutOfMemory,
};

/// Parse command-line tokens. Pass `argv[1..]` if your slice includes the
/// executable name.
pub fn parse(allocator: std.mem.Allocator, cmd: Command, argv: []const []const u8) Error!Result {
    return parseDetailed(allocator, cmd, argv, null);
}

/// Detailed parser diagnostic kind.
pub const DiagnosticKind = enum {
    none,
    unknown_option,
    missing_value,
    missing_required_option,
    missing_required_argument,
};

/// Optional user-facing context for parser failures.
pub const Diagnostic = struct {
    kind: DiagnosticKind = .none,
    token: ?[]const u8 = null,
    option: ?[]const u8 = null,
    argument: ?[]const u8 = null,

    /// Write a concise parser error message.
    pub fn write(self: Diagnostic, writer: *std.Io.Writer) !void {
        switch (self.kind) {
            .none => try writer.writeAll("no parser error\n"),
            .unknown_option => try writer.print("unknown option: {s}\n", .{self.token orelse ""}),
            .missing_value => try writer.print("missing value for option: {s}\n", .{self.option orelse self.token orelse ""}),
            .missing_required_option => try writer.print("missing required option: --{s}\n", .{self.option orelse ""}),
            .missing_required_argument => try writer.print("missing required argument: {s}\n", .{self.argument orelse ""}),
        }
    }
};

/// Parse command-line tokens and populate `diagnostic` when a parser error
/// occurs. This is the production-friendly variant for CLIs that need clear
/// user-facing error messages.
///
/// `--help` and `-h` are recognized implicitly when the command does not
/// declare options with those names; see `Result.wantsHelp`. Required options
/// and arguments are not enforced when help is requested.
pub fn parseDetailed(
    allocator: std.mem.Allocator,
    cmd: Command,
    argv: []const []const u8,
    diagnostic: ?*Diagnostic,
) Error!Result {
    if (diagnostic) |diag| diag.* = .{};

    var values = try allocator.alloc(Value, cmd.options.len);
    errdefer allocator.free(values);
    for (cmd.options, 0..) |opt, i| {
        values[i] = .{
            .name = opt.long,
            .value = opt.default,
            .count = 0,
        };
    }

    var positionals: std.ArrayList([]const u8) = .empty;
    defer positionals.deinit(allocator);

    var help_requested = false;
    var positional_only = false;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const token = argv[i];
        if (positional_only) {
            try positionals.append(allocator, token);
            continue;
        }
        if (std.mem.eql(u8, token, "--")) {
            positional_only = true;
            continue;
        }
        if (std.mem.startsWith(u8, token, "--") and token.len > 2) {
            const raw = token[2..];
            const eq = std.mem.indexOfScalar(u8, raw, '=');
            const name = if (eq) |at| raw[0..at] else raw;
            const spec_index = findLong(cmd.options, name) orelse {
                if (eq == null and std.mem.eql(u8, name, implicit_help_long)) {
                    help_requested = true;
                    continue;
                }
                setDiagnostic(diagnostic, .unknown_option, token, name);
                return error.UnknownOption;
            };
            const spec = cmd.options[spec_index];
            if (spec.value_name != null) {
                values[spec_index].value = if (eq) |at| raw[at + 1 ..] else try takeNext(argv, &i, token, spec, diagnostic);
            } else {
                if (eq != null) {
                    setDiagnostic(diagnostic, .unknown_option, token, name);
                    return error.UnknownOption;
                }
                values[spec_index].value = flag_true;
            }
            values[spec_index].count += 1;
            continue;
        }
        if (std.mem.startsWith(u8, token, "-") and token.len > 1) {
            var short_i: usize = 1;
            while (short_i < token.len) : (short_i += 1) {
                const short = token[short_i];
                const spec_index = findShort(cmd.options, short) orelse {
                    if (short == implicit_help_short) {
                        help_requested = true;
                        continue;
                    }
                    setDiagnostic(diagnostic, .unknown_option, token, token[short_i .. short_i + 1]);
                    return error.UnknownOption;
                };
                const spec = cmd.options[spec_index];
                values[spec_index].count += 1;
                if (spec.value_name != null) {
                    // The rest of the bundle (`-nvalue`) or the next token is the value.
                    values[spec_index].value = if (short_i + 1 < token.len) token[short_i + 1 ..] else try takeNext(argv, &i, token, spec, diagnostic);
                    break;
                }
                values[spec_index].value = flag_true;
            }
            continue;
        }
        try positionals.append(allocator, token);
    }

    if (!help_requested) try validateRequired(cmd, values, positionals.items, diagnostic);

    return .{
        .allocator = allocator,
        .values = values,
        .positionals = try positionals.toOwnedSlice(allocator),
        .help_requested = help_requested,
    };
}

/// Write generated help text for a command.
pub fn writeHelp(writer: *std.Io.Writer, cmd: Command) !void {
    try writer.print("{s}\n", .{cmd.name});
    if (cmd.description.len > 0) try writer.print("{s}\n\n", .{cmd.description});

    if (cmd.usage) |usage| {
        try writer.print("Usage: {s}\n", .{usage});
    } else {
        try writer.print("Usage: {s}", .{cmd.name});
        if (cmd.options.len > 0) try writer.writeAll(" [options]");
        if (cmd.arguments.len == 0) {
            try writer.writeAll(" [--] [args...]");
        } else {
            for (cmd.arguments) |argument| {
                if (argument.required) {
                    try writer.print(" <{s}>", .{argument.name});
                } else {
                    try writer.print(" [{s}]", .{argument.name});
                }
            }
        }
        try writer.writeAll("\n");
    }

    if (cmd.arguments.len > 0) {
        try writer.writeAll("\nArguments:\n");
        for (cmd.arguments) |argument| {
            try writer.print("  {s}", .{argument.name});
            if (!argument.required) try writer.writeAll(" (optional)");
            if (argument.help.len > 0) try writer.print("\n      {s}", .{argument.help});
            try writer.writeAll("\n");
        }
    }

    if (cmd.options.len == 0) return;

    try writer.writeAll("\nOptions:\n");
    try writeOptions(writer, cmd.options);
}

/// Write one help row per option. Shared by command help and app help.
pub fn writeOptions(writer: *std.Io.Writer, options: []const Option) !void {
    for (options) |opt| {
        try writer.writeAll("  ");
        if (opt.short) |short| {
            try writer.print("-{c}, ", .{short});
        } else {
            try writer.writeAll("    ");
        }
        try writer.print("--{s}", .{opt.long});
        if (opt.value_name) |name| try writer.print(" <{s}>", .{name});
        if (opt.required) try writer.writeAll(" (required)");
        if (opt.default) |default| try writer.print(" [default: {s}]", .{default});
        if (opt.help.len > 0) try writer.print("\n      {s}", .{opt.help});
        try writer.writeAll("\n");
    }
}

/// Return the index of the option whose long name is `name`.
pub fn findLong(options: []const Option, name: []const u8) ?usize {
    for (options, 0..) |opt, i| {
        if (std.mem.eql(u8, opt.long, name)) return i;
    }
    return null;
}

/// Return the index of the option whose short name is `short`.
pub fn findShort(options: []const Option, short: u8) ?usize {
    for (options, 0..) |opt, i| {
        if (opt.short == short) return i;
    }
    return null;
}

const implicit_help_long = "help";
const implicit_help_short = 'h';
const flag_true = "true";

fn parseBool(raw: []const u8) ?bool {
    const truthy = [_][]const u8{ "true", "1", "yes", "on" };
    const falsy = [_][]const u8{ "false", "0", "no", "off" };
    for (truthy) |word| {
        if (std.ascii.eqlIgnoreCase(raw, word)) return true;
    }
    for (falsy) |word| {
        if (std.ascii.eqlIgnoreCase(raw, word)) return false;
    }
    return null;
}

fn takeNext(argv: []const []const u8, index: *usize, token: []const u8, spec: Option, diagnostic: ?*Diagnostic) Error![]const u8 {
    index.* += 1;
    if (index.* >= argv.len) {
        setDiagnostic(diagnostic, .missing_value, token, spec.long);
        return error.MissingValue;
    }
    return argv[index.*];
}

fn validateRequired(cmd: Command, values: []const Value, positionals: []const []const u8, diagnostic: ?*Diagnostic) Error!void {
    for (cmd.options, values) |opt, entry| {
        if (opt.required and entry.count == 0 and opt.default == null) {
            setDiagnostic(diagnostic, .missing_required_option, null, opt.long);
            return error.MissingRequiredOption;
        }
    }
    var required_arguments: usize = 0;
    for (cmd.arguments) |argument| {
        if (!argument.required) continue;
        if (positionals.len <= required_arguments) {
            setArgumentDiagnostic(diagnostic, argument.name);
            return error.MissingRequiredArgument;
        }
        required_arguments += 1;
    }
}

fn setDiagnostic(diagnostic: ?*Diagnostic, kind: DiagnosticKind, token: ?[]const u8, opt: ?[]const u8) void {
    if (diagnostic) |diag| {
        diag.* = .{
            .kind = kind,
            .token = token,
            .option = opt,
        };
    }
}

fn setArgumentDiagnostic(diagnostic: ?*Diagnostic, argument: []const u8) void {
    if (diagnostic) |diag| {
        diag.* = .{
            .kind = .missing_required_argument,
            .argument = argument,
        };
    }
}
