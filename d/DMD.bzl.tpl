load("@gzgz_rules_d//d:toolchain.bzl", "d_toolchain")
# load("@bazel_skylib//rules:native_binary.bzl", "native_binary")

package(default_visibility = ["//visibility:public"])

cc_import(
    name = "libphobos2",
    shared_library = select({
        "@bazel_tools//src/conditions:linux_x86_64": "linux/lib64/libphobos2.so",
        "//conditions:default": None,
    }),
    static_library = select({
        "@bazel_tools//src/conditions:darwin": "osx/lib/libphobos2.a",
        "@bazel_tools//src/conditions:linux_x86_64": "linux/lib64/libphobos2.a",
        "@bazel_tools//src/conditions:windows_x64": "windows/lib64/phobos64.lib",
    }),
)

filegroup(
    name = "phobos_src",
    srcs = glob(["src/phobos/**/*.d"]),
)

filegroup(
    name = "druntime_src",
    srcs = glob([
        "src/druntime/import/*.*",
        "src/druntime/import/**/*.d",
    ]),
)

# native_binary(
#     name = "dmd",
#     out = "dmd_copy.exe",
#     src = "linux/bin64/dmd",
# )

d_toolchain(
    name = "d_toolchain",
    compiler = select({
        "@bazel_tools//src/conditions:darwin": "osx/bin/dmd",
        "@bazel_tools//src/conditions:linux_x86_64": "linux/bin64/dmd",
        "@bazel_tools//src/conditions:windows_x64": "windows/bin64/dmd.exe",
    }),
    druntime_src = "//:druntime_src",
    libphobos = "//:libphobos2",
    libphobos_src = "//:phobos_src",
    conf_file = "linux/bin64/dmd.conf",
	flags = {
        "version": "-version",
        "header": "-Hf",
		"output": "-of",
	},
)
