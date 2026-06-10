const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_linux = target.result.os.tag == .linux;

    const lib_mod = b.addModule("limbo", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib_mod.addIncludePath(b.path("third_party/limbo/sqlite3/include"));
    lib_mod.addLibraryPath(b.path("third_party/limbo/target/release"));
    lib_mod.linkSystemLibrary("turso_sqlite3", .{});
    if (target.result.os.tag != .windows) {
        lib_mod.linkSystemLibrary("pthread", .{});
        lib_mod.linkSystemLibrary("dl", .{});
        lib_mod.linkSystemLibrary("m", .{});
        if (target.result.os.tag == .macos) {
            lib_mod.linkFramework("CoreFoundation", .{});
        } else if (target.result.os.tag == .linux) {
            lib_mod.linkSystemLibrary("unwind", .{});
        }
    }

    const lib = b.addLibrary(.{
        .name = "limbo",
        .linkage = .static,
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    if (is_linux) {
        lib_tests.use_llvm = true;
        lib_tests.use_lld = true;
    }
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
}
