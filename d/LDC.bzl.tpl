load("@gzgz_rules_d//d:toolchain.bzl", "d_toolchain")
# load("@bazel_skylib//rules:native_binary.bzl", "native_binary")

package(default_visibility = ["//visibility:public"])

cc_import(
    name = "libphobos2",
    shared_library = select({
        "@bazel_tools//src/conditions:linux_x86_64": "lib/libphobos2-ldc-shared.so",
        "@bazel_tools//src/conditions:darwin": "lib/libphobos2-ldc-shared.dylib",
        "@bazel_tools//src/conditions:windows_x64": None,
    }),
    static_library = select({
        "@bazel_tools//src/conditions:linux_x86_64": "lib/libphobos2-ldc.a",
        "@bazel_tools//src/conditions:darwin": "lib/libphobos2-ldc.a",
        "@bazel_tools//src/conditions:windows_x64": "lib/phobos2-ldc.lib",
    }),
)

cc_import(
    name = "druntime",
    shared_library = select({
        "@bazel_tools//src/conditions:linux_x86_64": "lib/libdruntime-ldc-shared.so",
        "@bazel_tools//src/conditions:darwin": "lib/libdruntime-ldc-shared.dylib",
        "@bazel_tools//src/conditions:windows_x64": None,
    }),
    static_library = select({
        "@bazel_tools//src/conditions:linux_x86_64": "lib/libdruntime-ldc.a",
        "@bazel_tools//src/conditions:darwin": "lib/libdruntime-ldc.a",
        "@bazel_tools//src/conditions:windows_x64": "lib/druntime-ldc.lib",
    })
)

filegroup(
    name = "phobos_src",
    srcs = glob([
        "import/std/*.d",
        "import/std/**/*.d",
    ]),
)

filegroup(
    name = "druntime_src",
    srcs = glob([
        "import/core/*.d",
        "import/core/**/*.d",
        "import/etc/**/*.d",
        "import/ldc/*.d",
    ]),
)

# We purposefully don't use `native_binary` to avoid potential troubles on
# Windows regarding runfiles.
# native_binary(
#     name = "dmd",
#     out = "dmd_copy.exe",
#     src = "linux/bin64/dmd",
# )

d_toolchain(
    name = "d_toolchain",
    compiler = select({
        "@bazel_tools//src/conditions:darwin": "bin/ldc2",
        "@bazel_tools//src/conditions:linux_x86_64": "bin/ldc2",
        "@bazel_tools//src/conditions:windows_x64": "windows/bin64/dmd.exe",
    }),
    druntime = "//:druntime",
    druntime_src = "//:druntime_src",
    libphobos = "//:libphobos2",
    libphobos_src = "//:phobos_src",
	conf_file = "etc/ldc2.conf",
	default_pic = False,
	flags = {
        "version": "--d-version",
        "header": "--Hf",
		"output": "--of",
        "pic": "--relocation-model=pic",
	},
)
