load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//d:toolchain.bzl", "D_TOOLCHAIN")
load("//d/private:d_common.bzl", "COMMON_ATTRS", "DInfo", "preprocess_and_compile", "exe_filetype")

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

    (_, objs, _, _, pic) = preprocess_and_compile(ctx)

    # Prepare variables for linking
    common_linking_contexts = [toolchain.libphobos[CcInfo].linking_context]
    if not ctx.attr.better_c and toolchain.druntime:
        common_linking_contexts.append(toolchain.druntime[CcInfo].linking_context)

    # DMD has the -fPIC flag by default. LDC doesn't state it explicitly, but it
    # seems like they have it on too...?
    compilation_outputs = cc_common.create_compilation_outputs(
        objects = None if pic else depset(objs),
        pic_objects = depset(objs) if pic else None,
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
        name = ctx.label.name + exe_filetype(ctx),
        linking_contexts = common_linking_contexts + linking_contexts,
    )

    return [DefaultInfo(files = depset([linking_output.executable]), executable = linking_output.executable)]

d_binary = rule(
    implementation = _d_binary_impl,
    attrs = COMMON_ATTRS,
    provides = [DefaultInfo],
    fragments = ["cpp"],
    toolchains = [D_TOOLCHAIN] + use_cc_toolchain(),
    executable = True,
)
