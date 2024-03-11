load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//d:toolchain.bzl", "D_TOOLCHAIN")

DInfo = provider(
    "D compile provider.",
    fields = {
        "imports": "List of import dirs to be added to the compile line.",
        "headers": "Depset of header files",
        "versions": "List of -version flags",
    },
)

COMMON_ATTRS = {
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
    "pic": attr.bool(default = False),
    "_use_interface": attr.label(
        default = Label("//d:use_interface")
    ),
    "_cc_toolchain": attr.label(
        default = Label(
            "@rules_cc//cc:current_cc_toolchain",
        ),
    ),
    '_windows_constraint': attr.label(default = '@platforms//os:windows'),
    '_macos_constraint': attr.label(default = '@platforms//os:macos'),
}

def _map_imports(content):
    # toolchain = ctx.toolchains[D_TOOLCHAIN]
    return "-I%s" % content

def _build_import(label, im):
    """Builds the import path under a specific label"""
    return paths.join(label.workspace_root, label.package, im)

def a_filetype(ctx):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]

    if ctx.target_platform_has_constraint(windows_constraint):
        return ".lib"
    else:
        return ".a"

def so_filetype(ctx):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]
    macos_constraint = ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]

    if ctx.target_platform_has_constraint(windows_constraint):
        return ".lib"
    elif ctx.target_platform_has_constraint(macos_constraint):
        return ".dylib"
    else:
        return ".so"

def exe_filetype(ctx):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]

    if ctx.target_platform_has_constraint(windows_constraint):
        return ".exe"
    else:
        return ""

def preprocess_and_compile(ctx):
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
    needs_pic_for_dynamic_libraries = cc_toolchain.needs_pic_for_dynamic_libraries(
        feature_configuration = feature_configuration,
    )

    common_args = ctx.actions.args()

    # This is similar to -D (define) in C/C++
    versions = []
    versions.extend(ctx.attr.versions)

    use_interface = ctx.attr._use_interface[BuildSettingInfo].value

    # This is similar to include paths in C/C++
    imports = []
    self_imports = []
    for im in ctx.attr.imports:
        # For generated files (e.g. interface files)
        self_imports.append(paths.join(ctx.bin_dir.path, ctx.label.package, im))

        # For already existing source files, in case interface files aren't
        # generated, or source files already contains interface files
        self_imports.append(_build_import(ctx.label, im))
    imports.extend(self_imports)

    # In D, this is also called interface files
    headers = []

    # Gather all the information necessary to build flags to pass to the
    # compiler
    for dep in ctx.attr.deps:
        if DInfo in dep:
            versions.extend(dep[DInfo].versions)
            headers.append(dep[DInfo].headers)
            imports.extend(dep[DInfo].imports)
        elif CcInfo in dep:
            pass
        else:
            fail("deps must be cc-compatible or a d_binary")

    # Build common compile flags
    common_args.add_all(imports, map_each = _map_imports)

    # Whether we need -fPIC
    # Weirdly, -fPIC is turned on by default only on DMD Linux.
    # This affects linking since Bazel differentiates between `objects` and
    # `pic_objects`. Exactly how this affects linking, I don't know. It seems
    # that only on Linux, Bazel has PIC enabled by default.
    pic = ctx.attr.pic or toolchain.default_pic or needs_pic_for_dynamic_libraries
    if pic and not toolchain.default_pic:
        common_args.add(toolchain.flags["pic"])
    print("pic: %s" % pic)
    print("ctx.attr.pic: %s" % ctx.attr.pic)
    print("toolchain.default_pic: %s" % toolchain.default_pic)
    print("cc_toolchain.needs_pic_for_dynamic_libraries: %s" % needs_pic_for_dynamic_libraries)

    # DMD doesn't completely comply with posix, namely it only allows "-x=XXX"
    # but not "-x XXX", which is what Bazel's Arg helper formats to.
    # Usually we can use `map_each`, but it must be a top-level function while
    # the version flag can change depending on the compiler. Therefore, we
    # for-loop it out manually
    for version in versions:
        common_args.add("%s=%s" % (toolchain.flags["version"], version))

    # config file for the compiler
    if toolchain.conf_file:
        common_args.add("-conf=" + toolchain.conf_file.files.to_list()[0].path)

    # Toolchain-specific default flags
    common_args.add_all(toolchain.dopts)
    # User-supplied flags to passed to the compiler
    common_args.add_all(ctx.attr.dopts)

    # List of depset of common files (druntime, phobos, configuration files)
    # that are needed for
    # every compilation action
    base_files = [toolchain.libphobos_src.files]
    if toolchain.druntime_src:
        base_files.append(toolchain.druntime_src.files)
    if toolchain.conf_file:
        base_files.append(toolchain.conf_file.files)

    # Files from thet target itself that are needed by every compilation
    data_depset = depset(ctx.files.data)
    srcs_depset = depset(ctx.files.srcs)

    # Every src's corresponding interface (.di) files
    srcis = []
    if use_interface:
        for src in ctx.files.srcs:
            if src.extension == "di":
                # fail(".di files are NOT accepted as srcs to d_binary. Consider adding them to hdrs.")
                srcis.append(src)
                continue
            elif src.extension != "d":
                fail("Only .d or .di files are accepted as srcs to d_binary, but got %s!" % src.short_path)

            srci = ctx.actions.declare_file(
                paths.replace_extension(src.basename, ".di"),
                sibling = src,
            )
            iargs = ctx.actions.args()
            iargs.add(src)
            iargs.add("-o-")
            iargs.add("%s=%s" % (toolchain.flags["header"], srci.path))

            ctx.actions.run(
                outputs = [srci],
                inputs = depset([src], transitive = [srcs_depset, data_depset] + headers + base_files),
                arguments = [common_args, iargs],
                executable = toolchain.compiler.files_to_run,
                mnemonic = "DInterface",
                progress_message = "Generating interface file for %s" % src.short_path,
            )
            srcis.append(srci)

    # Either the interface files, or the source files depending on the flag
    # @gzgz_rules_d//d:use_interface
    srcis_depset = depset(srcis) if use_interface else depset(ctx.files.srcs)

    # Every src's corresponding object (.o) files
    objs = []
    for src in ctx.files.srcs:
        srco = ctx.actions.declare_file(
            paths.replace_extension(src.basename, ".o"),
            sibling = src,
        )
        oargs = ctx.actions.args()
        oargs.add("%s=%s" % (toolchain.flags["output"], srco.path))
        oargs.add("-c")
        oargs.add(src)

        ctx.actions.run(
            outputs = [srco],
            inputs = depset([src], transitive = [srcis_depset, data_depset] + headers + base_files),
            arguments = [common_args, oargs],
            executable = toolchain.compiler.files_to_run,
            mnemonic = "DCompile",
            progress_message = "Compiling D src %{input} to object file %{output}",
        )
        objs.append(srco)

    return (srcis, objs, self_imports, versions, pic)
