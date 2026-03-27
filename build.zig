const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zempl = b.addExecutable(.{
        .name = "zempl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(zempl);

    const runtime = b.addModule("runtime", .{
        .root_source_file = b.path("src/runtime/runtime.zig"),
    });

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(zempl);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const zempl_tests = b.addTest(.{
        .root_module = zempl.root_module,
        .use_llvm = true,
    });
    const run_zempl_tests = b.addRunArtifact(zempl_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_zempl_tests.step);

    try integrationTests(b, zempl, runtime);
}

pub fn buildTemplateModule(b: *std.Build, input_file: std.Build.LazyPath) !*std.Build.Module {
    const zempl = b.dependency("zempl", .{});
    return buildTemplateModuleIntern(b, zempl.artifact("zempl"), zempl.module("runtime"), input_file);
}

fn buildTemplateModuleIntern(b: *std.Build, zempl: *std.Build.Step.Compile, runtime: *std.Build.Module, input_file: std.Build.LazyPath) !*std.Build.Module {
    const zempl_step = b.addRunArtifact(zempl);
    zempl_step.has_side_effects = true;
    zempl_step.addFileArg(input_file);
    // _ = zempl_step.addPrefixedDepFileOutputArg("--depfile=", "templates.d");
    const template_dir = zempl_step.addOutputDirectoryArg("zempl_templates");

    const templates_module = b.createModule(.{
        .root_source_file = template_dir.path(b, "0.zig"),
    });
    templates_module.addImport("zempl_runtime", runtime);
    return templates_module;
}

fn integrationTests(b: *std.Build, zempl: *std.Build.Step.Compile, runtime: *std.Build.Module) !void {
    const integration_tests = b.addExecutable(.{
        .name = "integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration_tests.zig"),
            .target = b.graph.host,
        }),
    });

    const templates = try buildTemplateModuleIntern(b, zempl, runtime, b.path("test/templates/templates.zempl"));
    integration_tests.root_module.addImport("templates", templates);

    const integration_test_step = b.step("integration", "Run the integration tests");

    const integration_test_cmd = b.addRunArtifact(integration_tests);
    integration_test_step.dependOn(&integration_test_cmd.step);
}
