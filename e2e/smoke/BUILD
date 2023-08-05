"""Provides a simple way to test your rules as an external workspace.
Add a basic smoke-test target below.
"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@gzgz_rules_d//d:defs.bzl", "d_library")

d_library(
    name = "greeter",
    srcs = glob(["source/greeter/*.d"]),
    imports = ["source"],
)

d_library(
    name = "hello",
    srcs = glob(["source/hello/*.d"]),
    imports = ["source"],
    deps = [":greeter"],
)


build_test(
    name = "smoke_test",
    targets = [
        ":greeter",
        ":hello",
    ],
)
