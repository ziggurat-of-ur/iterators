const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("iterators", "src/iterators.zig");
    lib.setBuildMode(mode);
    lib.install();

    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable("rangespeed", "src/rangespeed.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.setOutputDir(".");
    exe.single_threaded = true;
    exe.install();

    var tests = b.addTest("src/iterators.zig");
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
