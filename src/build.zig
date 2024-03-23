const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "ztui",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // Create as a module for use
    const ztui_mod = b.createModule(.{ .root_source_file = .{
        .path = "./src/root.zig",
    } });
    _ = ztui_mod;

    // Build Example for Demonstration and Testing
    const exe = b.addExecutable(.{
        .name = "ztui-example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();

    const build_example = b.addRunArtifact(exe);
    build_example.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        build_example.addArgs(args);
    }

    const run_step = b.step("example", "run example");
    run_step.dependOn(&build_example.step);

    // Build Example for Demonstration and Testing
    const echo = b.addExecutable(.{
        .name = "echo-events",
        .root_source_file = .{ .path = "src/echo-events.zig" },
        .target = target,
        .optimize = optimize,
    });
    echo.linkLibC();

    const build_echo = b.step("echo", "build echo example");
    build_echo.dependOn(&echo.step);
    b.installArtifact(echo);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = .{ .path = "./test/kkp_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("int-tests", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);
}
