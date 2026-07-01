const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const package_options = b.addOptions();
    package_options.addOption([]const u8, "version", packageVersion(b));

    const zigma = b.addModule("zigma", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigma_build_options", .module = package_options.createModule() },
        },
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma },
            },
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    const check_step = b.step("check", "Run release verification: tests and examples");
    check_step.dependOn(&run_tests.step);

    const basic = b.addExecutable(.{
        .name = "zigma-basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma },
            },
        }),
    });
    b.installArtifact(basic);

    const basic_run = b.addRunArtifact(basic);
    if (b.args) |args| basic_run.addArgs(args);
    const basic_step = b.step("example-basic", "Run the basic CLI example");
    basic_step.dependOn(&basic_run.step);
    const basic_check = b.addRunArtifact(basic);
    basic_check.addArgs(&.{ "--name", "Zigma", "--loud" });
    check_step.dependOn(&basic_check.step);

    const tui = b.addExecutable(.{
        .name = "zigma-tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma },
            },
        }),
    });
    b.installArtifact(tui);

    const tui_run = b.addRunArtifact(tui);
    const tui_step = b.step("example-tui", "Run the TUI rendering example");
    tui_step.dependOn(&tui_run.step);
    const tui_check = b.addRunArtifact(tui);
    check_step.dependOn(&tui_check.step);

    const advanced = b.addExecutable(.{
        .name = "zigma-advanced",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/advanced.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma },
            },
        }),
    });
    b.installArtifact(advanced);

    const advanced_run = b.addRunArtifact(advanced);
    if (b.args) |args| advanced_run.addArgs(args);
    const advanced_step = b.step("example-advanced", "Run the advanced CLI/TUI app example");
    advanced_step.dependOn(&advanced_run.step);
    const advanced_help_check = b.addRunArtifact(advanced);
    advanced_help_check.addArg("--help");
    check_step.dependOn(&advanced_help_check.step);
    const advanced_hello_check = b.addRunArtifact(advanced);
    advanced_hello_check.addArgs(&.{ "hello", "--name", "Codex" });
    check_step.dependOn(&advanced_hello_check.step);
    const advanced_dashboard_check = b.addRunArtifact(advanced);
    advanced_dashboard_check.addArg("dashboard");
    check_step.dependOn(&advanced_dashboard_check.step);
}

fn packageVersion(b: *std.Build) []const u8 {
    const source = b.build_root.handle.readFileAllocOptions(
        b.graph.io,
        "build.zig.zon",
        b.allocator,
        .limited(64 * 1024),
        .of(u8),
        0,
    ) catch return "0.0.0";
    defer b.allocator.free(source);

    const key = ".version";
    const key_index = std.mem.indexOf(u8, source, key) orelse return "0.0.0";
    const after_key = source[key_index + key.len ..];
    const equals_index = std.mem.indexOfScalar(u8, after_key, '=') orelse return "0.0.0";
    const after_equals = std.mem.trimStart(u8, after_key[equals_index + 1 ..], " \t\r\n");
    if (after_equals.len == 0 or after_equals[0] != '"') return "0.0.0";
    const rest = after_equals[1..];
    const end_index = std.mem.indexOfScalar(u8, rest, '"') orelse return "0.0.0";
    return b.dupe(rest[0..end_index]);
}
