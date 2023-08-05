"""Extensions for bzlmod.

Installs a d toolchain.
Every module can define a toolchain version under the default name, "d".
The latest of those versions will be selected (the rest discarded),
and will always be registered by rules_d.

Additionally, the root module can define arbitrarily many more toolchain versions under different
names (the latest version will be picked for each name) and can register them as it sees fit,
effectively overriding the default named toolchain due to toolchain resolution precedence.
"""

load("//d/private:toolchains_repo.bzl", "COMPILERS")
load(":repositories.bzl", "d_register_toolchains")

_DEFAULT_NAME = "d"

d_toolchain = tag_class(
    attrs = {
        "name": attr.string(
            doc = """\
Base name for generated repositories, allowing more than one d toolchain to be registered.
Overriding the default is only permitted in the root module.
""",
            default = _DEFAULT_NAME,
        ),
        "version": attr.string(
            doc = "Explicit version of the compiler.",
            mandatory = True,
        ),
        "compiler": attr.string(
            doc = "Type of compiler",
            default = COMPILERS[0],
            values = COMPILERS,
        ),
    },
)

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail("""\
                Only the root module may override the default name for the d toolchain.
                This prevents conflicting registrations in the global namespace of external repos.
                """)

            name = toolchain.name
            compiler = toolchain.compiler

            if compiler not in registrations.keys():
                registrations[compiler] = {}
            if name not in registrations[compiler].keys():
                registrations[compiler][name] = []
            registrations[compiler][name].append(toolchain.version)

    for compiler, regs in registrations.items():
        for name, versions in regs.items():
            if len(versions) > 1:
                selected = sorted(versions, reverse = True)[0]

                # buildifier: disable=print
                print("NOTE: d toolchain {} has multiple versions {}, selected {}".format(name, versions, selected))
            else:
                selected = versions[0]

            d_register_toolchains(
                name = name,
                version = selected,
                compiler = compiler,
                register = False,
            )

d = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {"toolchain": d_toolchain},
)
