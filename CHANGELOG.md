# Changelog

All notable changes to Zigma are documented here.

## Unreleased

- Added shorter public API helpers: `zigma.command`, `zigma.option`, `zigma.flag`, `zigma.requiredOption`, and `zigma.helpFlag`.
- Added default runners: `cli.runCommandMain`, `cli.runMain`, `cli.runCommand`, `cli.runCommandWithCapabilities`, and `cli.runWithCapabilities`.
- Added `cli.Context.caps`, `cli.Context.ui`, and `cli.Context.status` so handlers can render UI without repeated setup.
- Added `terminal.detectDefault`, `widgets.Ui.auto`, and `widgets.Ui.plain`.
- Added root-level aliases: `zigma.run`, `zigma.runCommand`, `zigma.route`, `zigma.routeWithAliases`, `zigma.cmd`, `zigma.opt`, and `zigma.req`.
- Added automatic command help for `--help` and `-h`, so commands no longer need explicit `helpFlag()` declarations.
- Added typed accessors: `ctx.string`, `ctx.boolean`, `ctx.int`, `ctx.positional`, `ctx.count`, plus matching `args.Result` methods.
- Added positional argument specs with `zigma.arg`, `zigma.optionalArg`, `zigma.commandWithArgs`, and `zigma.cmdArgs`; generated help now includes named arguments and missing required argument diagnostics.
- Added UI shortcuts: `ui.info`, `ui.success`, `ui.warning`, `ui.err`, `ui.text`, `ui.note`, `ui.line`, `ui.kv`, `ui.meter`, and `ui.rule`.
- Reworked examples to use the short API path.
- Rewrote README as an installation-first usage manual with copy-pasteable single-command, subcommand, widget, terminal, parser, and TUI examples.

## 1.0.0 - 2026-07-01

Initial stable release.

- CLI parser with diagnostics, generated help, flags, options, defaults, required values, and positionals.
- `cli.App` dispatcher with subcommands, aliases, hooks, help, and version output.
- ANSI styling with 16-color, 256-color, and 24-bit RGB support.
- Terminal capability helpers for color, charset, and fallback sizing.
- Windows UTF-8 console setup helper for multilingual output.
- ASCII and Unicode glyph presets with Windows-safe ASCII defaults.
- UTF-8-aware text width, padding, truncation, wrapping, and alignment.
- UI facade with sections, status lines, tables, progress bars, prompts, and key/value rows.
- TUI primitives for rectangles, constraints, screen buffers, menus, forms, boxes, and key decoding.
- Examples for basic CLI, TUI rendering, and advanced CLI/TUI apps.
- CI workflow covering Linux, macOS, and Windows with Zig 0.16.0.
