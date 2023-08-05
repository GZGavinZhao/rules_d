"""Provides a simple way to test your rules as an external workspace.
Add a basic smoke-test target below.
"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")

build_test(
    name = "greeter",
    targets = [
        "//source:greeter",
    ],
)

build_test(
    name = "hello",
    targets = [
        "//source:hello",
    ],
)

build_test(
    name = "app",
    targets = ["//app:app"],
)
