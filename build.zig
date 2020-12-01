const std = @import("std");
const fs = std.fs;
const Builder = std.build.Builder;
const sep_str = std.fs.path.sep_str;
const Cpu = std.Target.Cpu;
const Pkg = std.build.Pkg;

const SITE_DIR = "www";
const MATH = std.build.Pkg{
    .name = "math",
    .path = "./zigmath/math.zig",
};
const PLATFORM = std.build.Pkg{
    .name = "platform",
    .path = "./platform/platform.zig",
    .dependencies = &[_]Pkg{ MATH },
};
const UTIL = std.build.Pkg{
    .name = "util",
    .path = "./util/util.zig",
    .dependencies = &[_]Pkg{ MATH },
};
const CORE = std.build.Pkg{
    .name = "core",
    .path = "./core/core.zig",
    .dependencies = &[_]Pkg{ UTIL, MATH },
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/main.zig");

    const native = b.addExecutable("mclone", "src/main.zig");
    native.addPackage(UTIL);
    native.addPackage(CORE);
    native.addPackage(MATH);
    native.addPackage(PLATFORM);
    native.addPackagePath("zigimg", "zigimg/zigimg.zig");
    native.linkSystemLibrary("SDL2");
    native.linkSystemLibrary("epoxy");
    native.linkLibC();
    native.setTarget(target);
    native.setBuildMode(mode);
    native.install();
    b.step("native", "Build native binary").dependOn(&native.step);

    // Server
    const server = b.addExecutable("mclone-server", "server/server.zig");
    server.addPackage(CORE);
    server.addPackage(MATH);
    server.setTarget(target);
    server.setBuildMode(mode);
    server.install();
    b.step("server", "Build server binary").dependOn(&server.step);

    const test_server = b.addTest("server/server.zig");
    const test_core = b.addTest("core/core.zig");
    test_core.addPackage(UTIL);

    b.step("run", "Run the native binary").dependOn(&native.run().step);

    const wasm = b.addStaticLibrary("mclone-web", "src/main.zig");
    wasm.addPackage(CORE);
    wasm.addPackage(UTIL);
    wasm.addPackage(MATH);
    wasm.addPackage(PLATFORM);
    wasm.step.dependOn(&b.addExecutable("webgl_generate", "platform/web/tool_webgl_generate.zig").run().step);
    const wasmOutDir = b.fmt("{}" ++ sep_str ++ SITE_DIR, .{b.install_prefix});
    wasm.setOutputDir(wasmOutDir);
    wasm.setBuildMode(b.standardReleaseOptions());
    wasm.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const htmlInstall = b.addInstallFile("./index.html", SITE_DIR ++ sep_str ++ "index.html");
    const cssInstall = b.addInstallFile("./index.css", SITE_DIR ++ sep_str ++ "index.css");
    const webglJsInstall = b.addInstallFile("platform/web/webgl.js", SITE_DIR ++ sep_str ++ "webgl.js");
    const mainJsInstall = b.addInstallFile("platform/web/main.js", SITE_DIR ++ sep_str ++ "main.js");

    wasm.step.dependOn(&htmlInstall.step);
    wasm.step.dependOn(&cssInstall.step);
    wasm.step.dependOn(&webglJsInstall.step);
    wasm.step.dependOn(&mainJsInstall.step);

    b.step("wasm", "Build WASM binary").dependOn(&wasm.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
    test_step.dependOn(&test_server.step);
    test_step.dependOn(&test_core.step);

    const all = b.step("all", "Build all binaries");
    all.dependOn(&native.step);
    all.dependOn(&server.step);
    all.dependOn(&wasm.step);
    all.dependOn(&tests.step);
}
