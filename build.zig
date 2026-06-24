const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;
const Allocator = std.mem.Allocator;

const Target = std.Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const Options = std.Build.Step.Options;

const Dependency = struct {
    name: []const u8,
    module: *std.Build.Module,
};

const ExeConfig = struct {
    version: ?std.SemanticVersion = null, // The version of the executable
    name: []const u8, // The name for the generated executable
    build_cmd: []const u8, // The build step name ('zig build <cmd>')
    build_description: []const u8, // The description for the build step ('zig build -l')
    run_cmd: []const u8, // The run step name ('zig build <cmd>')
    run_description: []const u8, //  The description for the run step ('zig build -l')
    root_path: []const u8, // The zig file containing main()
};

const BuildOpts = struct {
    optimize: OptimizeMode,
    target: ?Target = null,
    dependencies: ?[]Dependency = null,
    options: *Options,
    use_llvm: bool = false,
    no_bin: bool = false,
};

pub fn build(b: *std.Build) !void {
    const target: Target = b.standardTargetOptions(.{});
    const optimize: OptimizeMode = b.standardOptimizeOption(.{});

    const no_bin = b.option(bool, "no-bin", "Just check compilation (don't emit binaries)") orelse false;
    _ = no_bin; // autofix

    // Export the jaymark module to downstream consumers
    const jaymark = b.addModule("jaymark", .{
        .root_source_file = b.path("src/jaymark.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Generate documentation for jaymark and its dependencies by building a library.
    // Note that the main page of the generated documentation will be the root_source_file
    // of the library target.
    const lib = b.addLibrary(.{
        .name = "jaymark",
        .root_module = jaymark,
        .linkage = .static,
    });

    const lib_step = b.step("lib", "Build jaymark as a shared library (and also build HTML docs)");
    lib_step.dependOn(&lib.step);

    // Generate and install documentation using the library target
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    install_docs.step.dependOn(lib_step);
    const docs_step = b.step("docs", "Copy documentation artifacts to prefix path");
    docs_step.dependOn(&install_docs.step);

    ////////////////////////////////////////////////////////////////////////////
    // Add unit tests
    ////////////////////////////////////////////////////////////////////////////

    const test_exe = b.addTest(.{
        .root_module = jaymark,
        .test_runner = .{ .path = b.path("tools/test_runner.zig"), .mode = .simple },
    });
    const run_step = b.addRunArtifact(test_exe);
    run_step.has_side_effects = true; // Force the test to always be run on command
    const step = b.step("test", "Run all unit tests");
    step.dependOn(&run_step.step);
}
