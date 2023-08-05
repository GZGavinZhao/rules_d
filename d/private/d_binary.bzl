load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//d:toolchain.bzl", "D_TOOLCHAIN")
load("//d/private:d_common.bzl", "DInfo", "preprocess_and_compile")

def _d_binary_impl(ctx):
    # D toolchain
    toolchain = ctx.toolchains[D_TOOLCHAIN]

    # CC toolchain (for linking)
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    (_, objs, _, _) = preprocess_and_compile(ctx)

    # # Prepare variables for linking
    # output = ctx.actions.declare_file(ctx.label.name)
    # common_cc_infos = [toolchain.libphobos[CcInfo]]
    # common_linker_inputs = [toolchain.libphobos[CcInfo].linking_context.linker_inputs]
    # if not ctx.attr.better_c and toolchain.druntime:
    #     common_cc_infos.append(toolchain.druntime[CcInfo])
    #     common_linker_inputs.append(toolchain.druntime[CcInfo].linking_context.linker_inputs)

    # linker_input = cc_common.create_linker_input(
    #     owner = ctx.label,
    #     libraries = depset([
    #         cc_common.create_library_to_link(
    #             actions = ctx.actions,
    #             feature_configuration = feature_configuration,
    #             cc_toolchain = cc_toolchain,
    #             static_library = output,
    #         ),
    #     ]),
    #     user_link_flags = ctx.attr.linkopts + toolchain.linkopts,
    # )
    # compilation_context = cc_common.create_compilation_context()
    # linking_context = cc_common.create_linking_context(
    #     linker_inputs = depset([linker_input], transitive = common_linker_inputs),
    # )

    # # Build linker flags
    # linker_path = cc_common.get_tool_for_action(
    #     feature_configuration = feature_configuration,
    #     action_name = ACTION_NAMES.cpp_link_executable,
    # )
    # linker_variables = cc_common.create_link_variables(
    #     feature_configuration = feature_configuration,
    #     cc_toolchain = cc_toolchain,
    #     output_file = output.path,
    #     is_using_linker = True,
    # )
    # command_line = cc_common.get_memory_inefficient_command_line(
    #     feature_configuration = feature_configuration,
    #     action_name = ACTION_NAMES.cpp_link_executable,
    #     variables = linker_variables,
    # )
    # link_args = ctx.actions.args()
    # link_args.add_all(command_line)
    # link_args.add_all(objs)

    # # Link!
    # env = cc_common.get_environment_variables(
    #     feature_configuration = feature_configuration,
    #     action_name = ACTION_NAMES.cpp_link_executable,
    #     variables = linker_variables,
    # )
    # ctx.actions.run(
    #     executable = linker_path,
    #     arguments = [link_args],
    #     env = env,
    #     inputs = depset(
    #         direct = objs,
    #         transitive = [cc_toolchain.all_files],
    #     ),
    #     outputs = [output],
    #     mnemonic = "DLink",
    #     progress_message = "Linking D objects to executable %{output}",
    # )

    # Prepare variables for linking
    common_linking_contexts = [toolchain.libphobos[CcInfo].linking_context]
    if not ctx.attr.better_c and toolchain.druntime:
        common_linking_contexts.append(toolchain.druntime[CcInfo].linking_context)

    # DMD has the -fPIC flag by default. LDC doesn't state it explicitly, but it
    # seems like they have it on too...?
    compilation_outputs = cc_common.create_compilation_outputs(
        objects = depset(objs),
        pic_objects = depset(objs),
    )
    linking_contexts = []
    for dep in ctx.attr.deps:
        linking_contexts.append(dep[CcInfo].linking_context)

    # Link executable
    linking_output = cc_common.link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        user_link_flags = ctx.attr.linkopts + toolchain.linkopts,
        name = ctx.label.name,
        linking_contexts = common_linking_contexts + linking_contexts,
    )

    return [DefaultInfo(files = depset([linking_output.executable]), executable = linking_output.executable)]

d_binary = rule(
    implementation = _d_binary_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_empty = False,
            allow_files = [".d", ".di"],
        ),
        "deps": attr.label_list(
            providers = [CcInfo, DInfo],
        ),
        "data": attr.label_list(),
        "dopts": attr.string_list(),
        "linkopts": attr.string_list(),
        "imports": attr.string_list(),
        "versions": attr.string_list(),
        "better_c": attr.bool(default = False),
        "_cc_toolchain": attr.label(
            default = Label(
                "@rules_cc//cc:current_cc_toolchain",
            ),
        ),
    },
    provides = [DefaultInfo],
    fragments = ["cpp"],
    toolchains = [D_TOOLCHAIN] + use_cc_toolchain(),
    executable = True,
)
