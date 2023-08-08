load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//d:toolchain.bzl", "D_TOOLCHAIN")
load("//d/private:d_common.bzl", "COMMON_ATTRS", "DInfo", "a_filetype", "preprocess_and_compile")

def _d_library_impl(ctx):
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

    (headers, objs, imports, versions, _) = preprocess_and_compile(ctx)

    # Prepare variables for linking
    output_lib = ctx.actions.declare_file("lib" + ctx.label.name + a_filetype(ctx))
    common_cc_infos = [toolchain.libphobos[CcInfo]]
    common_linker_inputs = [toolchain.libphobos[CcInfo].linking_context.linker_inputs]
    if not ctx.attr.better_c and toolchain.druntime:
        common_cc_infos.append(toolchain.druntime[CcInfo])
        common_linker_inputs.append(toolchain.druntime[CcInfo].linking_context.linker_inputs)

    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset([
            cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain,
                static_library = output_lib,
            ),
        ]),
        user_link_flags = ctx.attr.linkopts,
    )
    compilation_context = cc_common.create_compilation_context()
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linker_input], transitive = common_linker_inputs),
    )

    # Build linker flags
    archiver_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
    )
    archiver_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output_file = output_lib.path,
        is_using_linker = False,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        variables = archiver_variables,
    )
    link_args = ctx.actions.args()
    link_args.add_all(command_line)
    link_args.add_all(objs)

    # Link!
    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        variables = archiver_variables,
    )
    ctx.actions.run(
        executable = archiver_path,
        arguments = [link_args],
        env = env,
        inputs = depset(
            direct = objs,
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [output_lib],
        mnemonic = "DLink",
        progress_message = "Linking D objects to static library %{output}",
    )

    # Gather providers
    default_info = DefaultInfo(files = depset([output_lib]))
    d_info = DInfo(
        imports = imports,
        headers = depset(headers),
        versions = versions,
    )
    cc_info = cc_common.merge_cc_infos(
        cc_infos = [CcInfo(compilation_context = compilation_context, linking_context = linking_context)] + [dep[CcInfo] for dep in ctx.attr.deps] + common_cc_infos,
    )
    return [default_info, d_info, cc_info]

d_library = rule(
    implementation = _d_library_impl,
    attrs = COMMON_ATTRS,
    provides = [DInfo, CcInfo],
    fragments = ["cpp"],
    toolchains = [D_TOOLCHAIN] + use_cc_toolchain(),
)
