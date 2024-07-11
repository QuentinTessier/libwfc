const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    var lib = b.addStaticLibrary(.{
        .name = "wfc",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.addCSourceFile(.{ .file = .{
        .path = "./wfc.c",
    } });
    lib.addIncludePath(.{
        .path = "./",
    });

    var module = b.addModule(
        "wfc",
        .{
            .root_source_file = .{
                .path = "wfc.zig",
            },
            .target = target,
            .optimize = optimize,
        },
    );
    module.linkLibrary(lib);
}
