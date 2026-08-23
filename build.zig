const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{ .name = "saper", .root_module = mod });

    switch (target.result.os.tag) {
        .macos => {
            mod.link_libc = true;
            // Cross-compiling to a different macOS architecture needs the SDK
            // spelled out: zig build --sysroot "$(xcrun --show-sdk-path)" ...
            if (b.sysroot) |sysroot| {
                mod.addSystemFrameworkPath(.{
                    .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }),
                });
            }
            mod.linkFramework("Cocoa", .{});
            mod.linkFramework("QuartzCore", .{});
            mod.linkFramework("CoreGraphics", .{});
        },
        .windows => {
            mod.link_libc = true;
            exe.subsystem = .Windows;
            mod.addWin32ResourceFile(.{ .file = b.path("assets/icon.rc") });
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("gdi32", .{});
        },
        else => {
            mod.link_libc = true;
            mod.linkSystemLibrary("X11", .{});
        },
    }

    b.installArtifact(exe);

    if (target.result.os.tag == .macos) addMacBundle(b, exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Build and run Saper");
    run_step.dependOn(&run.step);

    const shots = b.addExecutable(.{
        .name = "devshots",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/devshots.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const shots_run = b.addRunArtifact(shots);
    if (b.args) |args| shots_run.addArgs(args);
    const shots_step = b.step("shots", "Render sample screens to BMP files");
    shots_step.dependOn(&shots_run.step);

    const icon = b.addExecutable(.{
        .name = "icongen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/icongen.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const icon_run = b.addRunArtifact(icon);
    icon_run.addArg("assets");
    const icon_step = b.step("icon", "Regenerate the icon PNGs in assets/");
    icon_step.dependOn(&icon_run.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run the unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

/// Wraps the executable in a minimal Saper.app so macOS treats it as a real
/// application: proper dock name, menu bar, and Retina-aware presentation.
fn addMacBundle(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const info_plist =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>CFBundleName</key><string>Saper</string>
        \\    <key>CFBundleDisplayName</key><string>Saper</string>
        \\    <key>CFBundleIdentifier</key><string>dev.zig.saper</string>
        \\    <key>CFBundleExecutable</key><string>saper</string>
        \\    <key>CFBundleIconFile</key><string>Saper</string>
        \\    <key>CFBundleIconName</key><string>Saper</string>
        \\    <key>CFBundlePackageType</key><string>APPL</string>
        \\    <key>CFBundleVersion</key><string>1.0</string>
        \\    <key>CFBundleShortVersionString</key><string>1.0</string>
        \\    <key>LSMinimumSystemVersion</key><string>10.13</string>
        \\    <key>NSHighResolutionCapable</key><true/>
        \\</dict>
        \\</plist>
        \\
    ;

    const files = b.addWriteFiles();
    const plist_path = files.add("Info.plist", info_plist);
    const pkginfo_path = files.add("PkgInfo", "APPL????");

    const bundle_step = b.step("bundle", "Build Saper.app for macOS");
    bundle_step.dependOn(&b.addInstallFileWithDir(plist_path, .prefix, "Saper.app/Contents/Info.plist").step);
    bundle_step.dependOn(&b.addInstallFileWithDir(pkginfo_path, .prefix, "Saper.app/Contents/PkgInfo").step);
    bundle_step.dependOn(&b.addInstallFileWithDir(
        b.path("assets/Saper.icns"),
        .prefix,
        "Saper.app/Contents/Resources/Saper.icns",
    ).step);

    // The layered macOS 26 icon, when Xcode was around to compile it.
    if (b.build_root.handle.access(b.graph.io, "assets/Assets.car", .{})) |_| {
        bundle_step.dependOn(&b.addInstallFileWithDir(
            b.path("assets/Assets.car"),
            .prefix,
            "Saper.app/Contents/Resources/Assets.car",
        ).step);
    } else |_| {}
    bundle_step.dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "Saper.app/Contents/MacOS" } },
    }).step);
}
