"""This module implements the language-specific toolchain rule.
"""

D_TOOLCHAIN = "//d:toolchain_type"

def _d_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        name = ctx.label.name,
        compiler = ctx.attr.compiler,
        linkopts = ctx.attr.linkopts,
        libphobos = ctx.attr.libphobos,
        libphobos_src = ctx.attr.libphobos_src,
        druntime = ctx.attr.druntime,
        druntime_src = ctx.attr.druntime_src,
        conf_file = ctx.attr.conf_file,
        default_pic = ctx.attr.default_pic,
        flags = ctx.attr.flags,
    )
    return [toolchain_info]

d_toolchain = rule(
    _d_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "linkopts": attr.string_list(),
        "libphobos": attr.label(),
        "libphobos_src": attr.label(),
        "druntime": attr.label(),
        "druntime_src": attr.label(),
        "conf_file": attr.label(
            allow_single_file = True,
        ),
        "default_pic": attr.bool(
            mandatory = True,
        ),
        "flags": attr.string_dict(
            mandatory = True,
        ),
    },
)
