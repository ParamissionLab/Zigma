//! Terminal capability helpers with explicit fallbacks.

const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

/// Supported color capability levels.
pub const ColorMode = enum {
    none,
    ansi16,
    ansi256,
    truecolor,
};

/// Glyph set safety level for terminal UI.
pub const Charset = enum {
    ascii,
    unicode,
};

/// Result of attempting process-level UTF-8 console setup.
pub const Utf8Setup = enum {
    /// UTF-8 output was enabled for this process.
    enabled,
    /// This platform does not require process-level UTF-8 console setup.
    unsupported,
    /// Setup failed; keep conservative fallback behavior.
    failed,
};

/// Terminal dimensions in character cells.
pub const Size = struct {
    cols: usize = 80,
    rows: usize = 24,
};

/// Effective terminal capabilities used by renderers.
pub const Capabilities = struct {
    is_tty: bool = false,
    ansi: bool = false,
    color: ColorMode = .none,
    charset: Charset = defaultCharset(),
    size: Size = .{},
};

/// Configuration for capability detection. Supplying values explicitly keeps
/// tests deterministic and lets applications override platform behavior.
pub const DetectOptions = struct {
    is_tty: bool = false,
    no_color: ?[]const u8 = null,
    clicolor_force: ?[]const u8 = null,
    term: ?[]const u8 = null,
    colorterm: ?[]const u8 = null,
    charset: ?Charset = null,
    size: ?Size = null,
};

/// Practical defaults for small CLI apps. This opts into TTY-style color and
/// tries UTF-8 setup once so call sites do not need to repeat boilerplate.
pub const DefaultOptions = struct {
    is_tty: bool = true,
    no_color: ?[]const u8 = null,
    clicolor_force: ?[]const u8 = null,
    term: ?[]const u8 = null,
    colorterm: ?[]const u8 = null,
    charset: ?Charset = null,
    size: ?Size = null,
    enable_utf8: bool = true,
};

/// Derive terminal capabilities from explicit inputs and common environment
/// conventions. Platform-specific TTY probing can be layered on by callers.
pub fn detect(options: DetectOptions) Capabilities {
    const forced = options.clicolor_force != null and !std.mem.eql(u8, options.clicolor_force.?, "0");
    const disabled = options.no_color != null or isDumb(options.term);
    const ansi_enabled = forced or (options.is_tty and !disabled);

    return .{
        .is_tty = options.is_tty,
        .ansi = ansi_enabled,
        .color = if (!ansi_enabled) .none else detectColorMode(options.term, options.colorterm),
        .charset = options.charset orelse defaultCharset(),
        .size = options.size orelse .{},
    };
}

/// Detect capabilities with Zigma's default setup. Use `detect` directly when
/// tests or applications need every input to be explicit.
pub fn detectDefault(options: DefaultOptions) Capabilities {
    const utf8 = if (options.enable_utf8) enableUtf8() else Utf8Setup.failed;
    return detect(.{
        .is_tty = options.is_tty,
        .no_color = options.no_color,
        .clicolor_force = options.clicolor_force,
        .term = options.term,
        .colorterm = options.colorterm,
        .charset = options.charset orelse charsetAfterUtf8Setup(utf8),
        .size = options.size,
    });
}

/// Cross-platform-safe default. Windows consoles and VS Code/PowerShell
/// sessions commonly inherit a non-UTF-8 code page, so default to ASCII there
/// unless the application explicitly opts into Unicode. Unix-like terminals
/// default to Unicode.
pub fn defaultCharset() Charset {
    return if (builtin.os.tag == .windows) .ascii else .unicode;
}

/// Try to configure the current process console for UTF-8.
///
/// On Windows this calls `SetConsoleOutputCP(65001)` and `SetConsoleCP(65001)`.
/// On Unix-like systems this is a no-op because terminals consume UTF-8 byte
/// streams directly.
pub fn enableUtf8() Utf8Setup {
    if (builtin.os.tag != .windows) return .unsupported;

    const output_ok = WindowsApi.SetConsoleOutputCP(WindowsApi.utf8_code_page).toBool();
    _ = WindowsApi.SetConsoleCP(WindowsApi.utf8_code_page);
    return if (output_ok) .enabled else .failed;
}

/// Pick a charset after calling `enableUtf8`.
pub fn charsetAfterUtf8Setup(setup: Utf8Setup) Charset {
    return switch (setup) {
        .enabled => .unicode,
        .unsupported => defaultCharset(),
        .failed => defaultCharset(),
    };
}

/// Return true when a `NO_COLOR` style input should disable styling.
pub fn shouldUseColor(no_color: ?[]const u8, clicolor_force: ?[]const u8, is_tty: bool) bool {
    if (clicolor_force) |value| {
        if (!std.mem.eql(u8, value, "0")) return true;
    }
    if (no_color != null) return false;
    return is_tty;
}

fn detectColorMode(term: ?[]const u8, colorterm: ?[]const u8) ColorMode {
    if (colorterm) |value| {
        if (std.mem.indexOf(u8, value, "truecolor") != null or std.mem.indexOf(u8, value, "24bit") != null) {
            return .truecolor;
        }
    }
    if (term) |value| {
        if (std.mem.indexOf(u8, value, "256color") != null) return .ansi256;
    }
    return .ansi16;
}

fn isDumb(term: ?[]const u8) bool {
    return term != null and std.mem.eql(u8, term.?, "dumb");
}

const WindowsApi = if (builtin.os.tag == .windows) struct {
    const utf8_code_page: windows.UINT = 65001;

    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: windows.UINT) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn SetConsoleCP(wCodePageID: windows.UINT) callconv(.winapi) windows.BOOL;
} else struct {};
