const std = @import("std");
const builtin = @import("builtin");

fn getRustTarget(target: std.Target) ?[]const u8 {
    const arch = target.cpu.arch;
    const os = target.os.tag;
    const abi = target.abi;

    if (os == .linux) {
        if (arch == .x86_64) {
            if (abi == .musl) return "x86_64-unknown-linux-musl";
            return "x86_64-unknown-linux-gnu";
        } else if (arch == .aarch64) {
            if (abi == .musl) return "aarch64-unknown-linux-musl";
            return "aarch64-unknown-linux-gnu";
        }
    } else if (os == .macos) {
        if (arch == .x86_64) return "x86_64-apple-darwin";
        if (arch == .aarch64) return "aarch64-apple-darwin";
    } else if (os == .windows) {
        if (arch == .x86_64) return "x86_64-pc-windows-msvc";
        if (arch == .aarch64) return "aarch64-pc-windows-msvc";
    }
    return null;
}

fn getPrebuiltDirName(target: std.Target) ?[]const u8 {
    const arch = target.cpu.arch;
    const os = target.os.tag;
    const abi = target.abi;

    if (os == .linux and abi == .gnu) {
        return switch (arch) {
            .x86_64 => "x86_64-linux-gnu",
            else => null,
        };
    }
    if (os == .macos) {
        return switch (arch) {
            .x86_64 => "x86_64-macos",
            .aarch64 => "aarch64-macos",
            else => null,
        };
    }
    if (os == .windows and abi == .msvc) {
        return switch (arch) {
            .x86_64 => "x86_64-windows-msvc",
            else => null,
        };
    }
    return null;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Accept sysroot as a build option to support child dependency propagation
    const sysroot_opt = b.option([]const u8, "sysroot", "Path to macOS/Windows SDK");
    if (sysroot_opt) |sysroot| {
        b.sysroot = sysroot;
    }

    // Automatically detect and set sysroot on macOS hosts for macOS targets if not specified
    if (target.result.os.tag == .macos and b.sysroot == null) {
        if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk| {
            b.sysroot = sdk;
        }
    }

    const lib_mod = b.addModule("limbo", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Use the locally vendored sqlite3.h
    lib_mod.addIncludePath(b.path("include"));

    const lib_file = if (target.result.os.tag == .windows) "turso_sqlite3.lib" else "libturso_sqlite3.a";

    // Detect if third_party/limbo/Cargo.toml is present
    const has_cargo_toml = if (b.build_root.handle.access(b.graph.io, "third_party/limbo/Cargo.toml", .{})) |_| true else |_| false;

    if (has_cargo_toml) {
        const is_native = target.result.cpu.arch == builtin.cpu.arch and target.result.os.tag == builtin.os.tag;
        const rust_target = if (is_native) null else getRustTarget(target.result) orelse @panic("limbo-zig cannot build turso_sqlite3 for this target");

        const cargo_cmd = b.addSystemCommand(&.{ "cargo", "build", "--release", "-p", "turso_sqlite3" });
        cargo_cmd.setCwd(b.path("third_party/limbo"));
        if (rust_target) |triple| {
            cargo_cmd.addArgs(&.{ "--target", triple });
        }

        const wf = b.addWriteFiles();
        wf.step.dependOn(&cargo_cmd.step);

        const target_dir = if (is_native)
            "target/release"
        else
            b.fmt("target/{s}/release", .{rust_target orelse ""});

        const lib_path = b.fmt("third_party/limbo/{s}/{s}", .{ target_dir, lib_file });
        const output_lib = wf.addCopyFile(b.path(lib_path), lib_file);
        lib_mod.addObjectFile(output_lib);
    } else {
        // Release source packages contain prebuilt libraries instead of the
        // Limbo Rust checkout. Keep the target mapping explicit so unsupported
        // triples fail before linking against the wrong C ABI.
        const prebuilt_dir = getPrebuiltDirName(target.result) orelse @panic("limbo-zig has no prebuilt library for this target");
        const prebuilt_path = b.fmt("lib/{s}/{s}", .{ prebuilt_dir, lib_file });
        lib_mod.addObjectFile(b.path(prebuilt_path));
    }

    if (target.result.os.tag != .windows) {
        lib_mod.linkSystemLibrary("pthread", .{});
        lib_mod.linkSystemLibrary("dl", .{});
        lib_mod.linkSystemLibrary("m", .{});
        if (target.result.os.tag == .macos) {
            lib_mod.linkFramework("CoreFoundation", .{});
            if (b.sysroot) |sysroot| {
                lib_mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sysroot}) });
            }
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
    if (target.result.os.tag == .linux) {
        lib_tests.use_llvm = true;
        lib_tests.use_lld = true;
    } else if (target.result.os.tag == .windows) {
        lib_tests.bundle_compiler_rt = false;
    }
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
}
