const std = @import("std");
const fs = std.fs;
const Builder = std.build.Builder;
const sep_str = std.fs.path.sep_str;
const Cpu = std.Target.Cpu;
const Pkg = std.build.Pkg;
const deps = @import("./deps.zig");

const SITE_DIR = "www";
const PLATFORM = std.build.Pkg{
    .name = "platform",
    .path = .{ .path = "./platform/platform.zig" },
    .dependencies = &[_]Pkg{deps.pkgs.math.pkg.?, deps.pkgs.zigimg.pkg.?, deps.pkgs.bare.pkg.?},
};
const UTIL = std.build.Pkg{
    .name = "util",
    .path = .{ .path = "./util/util.zig" },
    .dependencies = &[_]Pkg{deps.pkgs.math.pkg.?, deps.pkgs.zigimg.pkg.?, deps.pkgs.bare.pkg.?},
};
const CORE = std.build.Pkg{
    .name = "core",
    .path = .{ .path = "./core/core.zig" },
    .dependencies = &[_]Pkg{UTIL, deps.pkgs.math.pkg.?, deps.pkgs.zigimg.pkg.?, deps.pkgs.bare.pkg.?},
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");

    const options = b.addOptions();
    options.addOption(bool, "enable_tracy", tracy != null);

    const tests = b.addTest("src/main.zig");
    tests.addOptions("enable_tracy", options);
    if (tracy) |tracy_path| {
        const client_cpp = std.fs.path.join(b.allocator, &[_][]const u8{ tracy_path, "TracyClient.cpp" }) catch unreachable;
        tests.addIncludeDir(tracy_path);
        tests.addCSourceFile(client_cpp, &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "--rtlib=compiler-rt" });
        tests.linkSystemLibraryName("c++");
        tests.linkLibC();
    }

    const native = b.addExecutable("mclone", "src/main.zig");
    deps.addAllTo(native);
    native.addPackage(UTIL);
    native.addPackage(CORE);
    native.addPackage(PLATFORM);
    native.linkSystemLibrary("SDL2");
    native.linkLibC();
    native.setTarget(target);
    native.setBuildMode(mode);
    native.install();
    b.step("native", "Build native binary").dependOn(&native.step);

    // Server
    const server = b.addExecutable("mclone-server", "server/server.zig");
    deps.addAllTo(server);
    server.addPackage(UTIL);
    server.addPackage(CORE);
    server.setTarget(target);
    server.setBuildMode(mode);
    server.install();
    server.addOptions("enable_tracy", options);
    if (tracy) |tracy_path| {
        const client_cpp = std.fs.path.join(b.allocator, &[_][]const u8{ tracy_path, "TracyClient.cpp" }) catch unreachable;
        server.addIncludeDir(tracy_path);
        server.addCSourceFile(client_cpp, &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "--rtlib=compiler-rt" });
        server.linkSystemLibraryName("c++");
        server.linkLibC();
    }
    b.step("server", "Build server binary").dependOn(&server.step);
    b.step("server-run", "Run the native server binary").dependOn(&server.run().step);

    const test_server = b.addTest("server/server.zig");
    const test_core = b.addTest("core/core.zig");
    test_core.addPackage(UTIL);

    b.step("run", "Run the native binary").dependOn(&native.run().step);

    // const wasm = b.addStaticLibrary("mclone-web", "src/main.zig");
    // deps.addAllTo(wasm);
    // wasm.addPackage(CORE);
    // wasm.addPackage(UTIL);
    // wasm.addPackage(PLATFORM);
    // wasm.step.dependOn(&b.addExecutable("webgl_generate", "platform/web/tool_webgl_generate.zig").run().step);
    // const wasmOutDir = b.fmt("{s}" ++ sep_str ++ SITE_DIR, .{b.install_prefix});
    // wasm.setOutputDir(wasmOutDir);
    // wasm.setBuildMode(b.standardReleaseOptions());
    // wasm.setTarget(.{
    //     .cpu_arch = .wasm32,
    //     .os_tag = .freestanding,
    // });

    // const htmlInstall = b.addInstallFile(.{.path = "./index.html"}, SITE_DIR ++ sep_str ++ "index.html");
    // const cssInstall = b.addInstallFile(.{.path = "./index.css"}, SITE_DIR ++ sep_str ++ "index.css");
    // const webglJsInstall = b.addInstallFile(.{.path = "platform/web/webgl.js"}, SITE_DIR ++ sep_str ++ "webgl.js");
    // const mainJsInstall = b.addInstallFile(.{.path = "platform/web/main.js"}, SITE_DIR ++ sep_str ++ "main.js");

    // wasm.step.dependOn(&htmlInstall.step);
    // wasm.step.dependOn(&cssInstall.step);
    // wasm.step.dependOn(&webglJsInstall.step);
    // wasm.step.dependOn(&mainJsInstall.step);

    // b.step("wasm", "Build WASM binary").dependOn(&wasm.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
    test_step.dependOn(&test_server.step);
    test_step.dependOn(&test_core.step);

    const all = b.step("all", "Build all binaries");
    all.dependOn(&native.step);
    all.dependOn(&server.step);
    // all.dependOn(&wasm.step);
    all.dependOn(&tests.step);
}
