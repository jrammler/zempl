const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zempl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .use_llvm = true,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    try integrationTests(b, exe);
}

pub fn buildTemplateModule(b: *std.Build, input_file: std.Build.LazyPath) !*std.Build.Module {
    const zempl = b.dependency("zempl", .{});
    return buildTemplateModuleIntern(b, zempl.artifact("zempl"), input_file);
}

fn buildTemplateModuleIntern(b: *std.Build, zempl_module: *std.Build.Step.Compile, input_file: std.Build.LazyPath) !*std.Build.Module {
    const zempl_step = b.addRunArtifact(zempl_module);
    zempl_step.has_side_effects = true;
    zempl_step.addFileArg(input_file);
    // _ = zempl_step.addPrefixedDepFileOutputArg("--depfile=", "templates.d");
    const template_dir = zempl_step.addOutputDirectoryArg("zempl_templates");

    const templates_module = b.createModule(.{
        .root_source_file = template_dir.path(b, "0.zig"),
    });
    templates_module.addAnonymousImport("zempl_runtime", .{
        .root_source_file = b.path("runtime/runtime.zig"),
    });
    return templates_module;
}

fn integrationTests(b: *std.Build, zempl_module: *std.Build.Step.Compile) !void {
    const integration_tests = b.addExecutable(.{
        .name = "integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration_tests.zig"),
            .target = b.graph.host,
        }),
    });

    const templates = try buildTemplateModuleIntern(b, zempl_module, b.path("test/templates/templates.zempl"));
    integration_tests.root_module.addImport("templates", templates);

    const integration_test_step = b.step("integration", "Run the integration tests");

    const integration_test_cmd = b.addRunArtifact(integration_tests);
    integration_test_step.dependOn(&integration_test_cmd.step);
}
