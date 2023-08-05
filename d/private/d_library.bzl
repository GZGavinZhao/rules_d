load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
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

def _map_imports(content):
    # toolchain = ctx.toolchains[D_TOOLCHAIN]
    return "-I%s" % content

def _build_import(label, im):
    """Builds the import path under a specific label"""
    return paths.join(label.workspace_root, label.package, im)

def _a_filetype(ctx):
    return ".a"
    if ctx.target_platform_has_constraint("@platforms//os:windows"):
        return ".lib"
    else:
        return ".a"

def _so_filetype(ctx):
    return ".so"
    if ctx.target_platform_has_constraint("@platforms//os:windows"):
        return ".lib"
    elif ctx.target_platform_has_constraint("@platforms//os:macos"):
        return ".dylib"
    else:
        return ".so"

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

    common_args = ctx.actions.args()

    # This is similar to -D (define) in C/C++
    versions = []
    versions.extend(ctx.attr.versions)

    # This is similar to include paths in C/C++
    imports = []
    self_imports = []
    for im in ctx.attr.imports:
        # For generated files (interface files)
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
            fail("deps must be cc-compatible or a d_library")

    # Build common compile flags
    common_args.add_all(imports, map_each = _map_imports)

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
    self_files = [depset(ctx.files.srcs), depset(ctx.files.data)]

    # Every src's corresponding interface (.di) files
    srcis = []
    for src in ctx.files.srcs:
        if src.extension == "di":
            # fail(".di files are NOT accepted as srcs to d_library. Consider adding them to hdrs.")
            srcis.append(src)
            continue
        elif src.extension != "d":
            fail("Only .d or .di files are accepted as srcs to d_library, but got %s!" % src.short_path)

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
            inputs = depset([src], transitive = headers + self_files + base_files),
            arguments = [common_args, iargs],
            executable = toolchain.compiler.files_to_run,
            mnemonic = "DInterface",
            progress_message = "Generating interface file for %s" % src.short_path,
        )
        srcis.append(srci)

    # Add the interface files. May reduce compilation times.
    self_files.append(depset(srcis))

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
            inputs = depset([src], transitive = headers + self_files + base_files),
            arguments = [common_args, oargs],
            executable = toolchain.compiler.files_to_run,
            mnemonic = "DCompile",
            progress_message = "Compiling D src %{input} to object file %{output}",
        )
        objs.append(srco)

    # Prepare variables for linking
    output_lib = ctx.actions.declare_file("lib" + ctx.label.name + _a_filetype(ctx))
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
        imports = self_imports,
        headers = depset(srcis),
        versions = versions,
    )
    cc_info = cc_common.merge_cc_infos(
        cc_infos = [CcInfo(compilation_context = compilation_context, linking_context = linking_context)] + [dep[CcInfo] for dep in ctx.attr.deps] + common_cc_infos,
    )
    return [default_info, d_info, cc_info]

d_library = rule(
    implementation = _d_library_impl,
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
    provides = [DInfo, CcInfo],
    fragments = ["cpp"],
    toolchains = [D_TOOLCHAIN] + use_cc_toolchain(),
)
