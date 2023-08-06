"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//d/private:toolchains_repo.bzl", "COMPILERS", "PLATFORMS", "PLATFORM_TO_FILE", "toolchains_repo")
load("//d/private:versions.bzl", "TOOL_VERSIONS")

def http_archive(name, **kwargs):
    maybe(_http_archive, name = name, **kwargs)

# WARNING: any changes in this function may be BREAKING CHANGES for users
# because we'll fetch a dependency which may be different from one that
# they were previously fetching later in their WORKSPACE setup, and now
# ours took precedence. Such breakages are challenging for users, so any
# changes in this function should be marked as BREAKING in the commit message
# and released only in semver majors.
# This is all fixed by bzlmod, so we just tolerate it for now.
def rules_d_dependencies():
    # The minimal version of bazel_skylib we require
    http_archive(
        name = "bazel_skylib",
        sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        ],
    )
    http_archive(
        name = "rules_cc",
        urls = ["https://github.com/bazelbuild/rules_cc/releases/download/0.0.5/rules_cc-0.0.5.tar.gz"],
        sha256 = "2004c71f3e0a88080b2bd3b6d3b73b4c597116db9c9a36676d0ffad39b849214",
        strip_prefix = "rules_cc-0.0.5",
    )
    http_archive(
        name = "platforms",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/platforms/releases/download/0.0.5/platforms-0.0.5.tar.gz",
            "https://github.com/bazelbuild/platforms/releases/download/0.0.5/platforms-0.0.5.tar.gz",
        ],
        sha256 = "379113459b0feaf6bfbb584a91874c065078aa673222846ac765f86661c27407",
    )

########
# Remaining content of the file is only used to support toolchains.
########
_DOC = "Fetch external tools needed for d toolchain"
_ATTRS = {
    "version": attr.string(mandatory = True),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
    "compiler": attr.string(mandatory = True, values = COMPILERS),
}

def _d_repo_impl(repository_ctx):
    compiler = repository_ctx.attr.compiler
    version = repository_ctx.attr.version
    platform = repository_ctx.attr.platform

    base_url = ""
    if compiler == "dmd":
        base_url = "https://downloads.dlang.org/releases/2.x/{0}/dmd.{0}.{1}"
    elif compiler == "ldc":
        base_url = "https://github.com/ldc-developers/ldc/releases/download/v{0}/ldc2-{0}-{1}"

    url = base_url.format(
        version,
        PLATFORM_TO_FILE[compiler][platform],
    )
    repository_ctx.download_and_extract(
        url = url,
        stripPrefix = "dmd2",
        # integrity = TOOL_VERSIONS[version][platform],
    )

    # Base BUILD file for this repository
    if compiler == "dmd":
        repository_ctx.template("BUILD.bazel", Label("//d:DMD.bzl.tpl"))
    else:
        repository_ctx.template("BUILD.bazel", Label("//d:LDC.bzl.tpl"))

d_repositories = repository_rule(
    _d_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

# Wrapper macro around everything above, this is the primary API
def d_register_toolchains(name, compiler, version, register = True, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "d_linux_amd64" -
      this repository is lazily fetched when node is needed for that platform.
    - TODO: create a convenience repository for the host platform like "d_host"
    - create a repository exposing toolchains for each platform like "d_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.
    Args:
        name: base name for all created repos, like "d1_14"
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        compiler: the type of compiler to register (dmd or ldc)
        version: the version of the compiler to register
        **kwargs: passed to each d_repositories call
    """
    for platform in PLATFORMS.keys():
        if compiler == "dmd" and platform == "aarch64-apple-darwin":
            continue

        d_repositories(
            name = name + "_" + compiler + "_" + platform,
            compiler = compiler,
            version = version,
            platform = platform,
            **kwargs
        )

    toolchains_repo_name = "%s_%s_toolchains" % (name, compiler)
    toolchains_repo(
        name = toolchains_repo_name,
        compiler = compiler,
        user_repository_name = name,
    )

    if register:
        native.register_toolchains("@%s//:all" % toolchains_repo_name)
