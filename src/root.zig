//! Zigma is a lightweight Zig toolkit for building configurable CLI and
//! terminal/TUI utilities.

/// Current Zigma release version.
pub const version = "1.0.0";

pub const ansi = @import("ansi.zig");
pub const args = @import("args.zig");
pub const cli = @import("cli.zig");
pub const terminal = @import("terminal.zig");
pub const text = @import("text.zig");
pub const tui = @import("tui.zig");
pub const widgets = @import("widgets.zig");

pub const App = cli.App;
pub const Command = args.Command;
pub const Context = cli.Context;
pub const Option = args.Option;
pub const Argument = args.Argument;
pub const Route = cli.Route;

pub const flag = args.flag;
pub const option = args.option;
pub const requiredOption = args.requiredOption;
pub const helpFlag = args.helpFlag;
pub const command = args.command;
pub const commandWithArgs = args.commandWithArgs;
pub const arg = args.arg;
pub const optionalArg = args.optionalArg;

pub const cmd = args.command;
pub const cmdArgs = args.commandWithArgs;
pub const opt = args.option;
pub const req = args.requiredOption;

pub const run = cli.runMain;
pub const runCommand = cli.runCommandMain;
pub const route = cli.route;
pub const routeWithAliases = cli.routeWithAliases;
