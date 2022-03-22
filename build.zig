const std = @import("std");
const glfw = @import("libs/mach-glfw/build.zig");

const pkgs = struct {
    const common = std.build.Pkg{
        .name = "common",
        .path = .{ .path = "src/common/index.zig" },
        .dependencies = &[_]std.build.Pkg{ std.build.Pkg{
            .name = "zgl",
            .path = .{ .path = "libs/zgl/zgl.zig" },
            .dependencies = &[_]std.build.Pkg{},
        }, std.build.Pkg{
            .name = "zlm",
            .path = .{ .path = "libs/zlm/zlm.zig" },
            .dependencies = &[_]std.build.Pkg{},
        } },
    };
};

pub fn buildExe(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    exe.addPackage(pkgs.common);

    // GLFW
    // Reference: https://github.com/hexops/mach-glfw
    exe.addPackagePath("glfw", "libs/mach-glfw/src/main.zig");
    glfw.link(b, exe, .{});

    // ZGL
    exe.addPackagePath("zgl", "libs/zgl/zgl.zig");
    exe.linkSystemLibrary("epoxy");

    // ZLM
    exe.addPackagePath("zlm", "libs/zlm/zlm.zig");

    exe.addCSourceFile("c/stb_image.c", &[_][]const u8{"-O2"});
    exe.addIncludePath("c");

    exe.linkSystemLibrary("c");
    exe.install();
}

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    {
        const exe = b.addExecutable("ulum_spiral", "src/demos/ulum_spiral.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        buildExe(b, exe);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("ulum_spiral", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const exe = b.addExecutable("particles", "src/demos/particles.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        buildExe(b, exe);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("particles", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // const exe_tests = b.addTest("src/main.zig");
    // exe_tests.setTarget(target);
    // exe_tests.setBuildMode(mode);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
