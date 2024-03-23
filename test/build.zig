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

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = .{ .path = "kkp_tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    const ztui_dep = b.dependency("ztui", .{});
    integration_tests.root_module.addImport("ztui", ztui_dep.module("ztui"));
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_test_step = b.step("int-tests", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);
}
