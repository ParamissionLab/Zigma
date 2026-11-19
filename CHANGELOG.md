# Changelog

All notable changes to Zigma are documented here.

## Unreleased

### Fixed

- `run`/`runCommand` now flush stdout when dispatch fails, so parser diagnostics and help are no longer lost behind the error.
- `run`/`runCommand` probe the real stdout and environment: no ANSI codes in piped output, and `NO_COLOR`, `CLICOLOR_FORCE`, `TERM`, `COLORTERM` are honored.
- `--help`/`-h` are now recognized by the parser itself (`Result.wantsHelp`), so tokens after `--`, option values such as `--pattern --help`, and a positional `help` reach the handler instead of triggering help.
- Required options and arguments are not enforced when help is requested.
- Out-of-memory during parsing no longer prints a bogus `no parser error` diagnostic.
- Unknown short options report the user's token (`-vx`) instead of a bare letter.
- An empty `NO_COLOR` no longer disables color (per no-color.org).
- `renderRule` with a title now renders exactly `width` cells (it was 2 short).
- `text.writeTruncated` resets ANSI styles when it cuts styled text and treats invalid UTF-8 the same way as `text.width`.
- `tui.layout` distributes the fill remainder so fills cover the whole area.
- `tui.Screen.writeText` keeps wide glyphs two cells wide and attaches combining marks (such as Thai vowels and tone marks) to their base character, so rows stay aligned.
- Progress bar math no longer overflows for very large totals.
- Table vertical borders now use `border_style`, like horizontal borders.

### Changed

- Added `terminal.detectProcess`, `args.writeOptions`, `args.findLong`, `args.findShort`, `text.writeRepeated`, `text.nextCodepoint`, `text.codepointWidth`, and named widget constants (`default_meter_width`, `default_rule_width`, `max_table_columns`).
- Removed duplicated option lookup, help rendering, and repeat helpers between modules.

## 1.0.0 - 2026-07-01

Initial stable release.

- CLI parser with diagnostics, generated help, flags, options, defaults, required values, named positional arguments, and positional validation.
- Short public API helpers: `zigma.cmd`, `zigma.cmdArgs`, `zigma.opt`, `zigma.flag`, `zigma.req`, `zigma.arg`, `zigma.optionalArg`, and the longer explicit aliases.
- Default runners for small and large apps: `zigma.runCommand`, `zigma.run`, `cli.runCommandMain`, `cli.runMain`, `cli.runCommand`, `cli.runCommandWithCapabilities`, and `cli.runWithCapabilities`.
- App dispatcher with subcommands, aliases, grouped routes, hidden routes, app-level global options, app/route lifecycle hooks, help, and version output.
- Automatic app and command help for `--help` and `-h`, so commands do not need explicit `helpFlag()` declarations.
- Handler context with `ctx.caps`, `ctx.ui`, parsed command options, parsed global options, and shortcuts for status rendering.
- Typed accessors on `cli.Context` and `args.Result`: `string`, `boolean`, `int`, `positional`, and `count`.
- Global option accessors on `cli.Context`: `globalHas`, `globalValue`, `globalString`, `globalBoolean`, and `globalInt`.
- ANSI styling with 16-color, 256-color, and 24-bit RGB support.
- Terminal capability helpers for color, charset, fallback sizing, practical default detection, and Windows UTF-8 console setup.
- ASCII and Unicode glyph presets with Windows-safe ASCII defaults.
- UTF-8-aware text width, padding, truncation, wrapping, and alignment.
- UI facade with sections, status lines, tables, progress bars, prompts, key/value rows, horizontal rules, notes, plain text, blank lines, and convenience shortcuts.
- TUI primitives for rectangles, constraints, screen buffers, menus, forms, boxes, and key decoding.
- Examples for basic CLI, TUI rendering, and advanced CLI/TUI apps using the short API path.
- README rewritten as an installation-first usage manual for the real repository `ParamissionLab/Zigma`, including copy-pasteable single-command, subcommand, large-app, widget, terminal, parser, and TUI examples.
- CI workflow covering Linux, macOS, and Windows with Zig 0.16.0.
