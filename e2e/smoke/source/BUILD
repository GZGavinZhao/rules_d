load("@gzgz_rules_d//d:defs.bzl", "d_library")

package(default_visibility = ["//visibility:public"])

d_library(
    name = "greeter",
    srcs = glob(["greeter/*.d"]),
    imports = ["."],
)

d_library(
    name = "hello",
    srcs = glob(["hello/*.d"]),
    imports = ["."],
    deps = [":greeter"],
)
