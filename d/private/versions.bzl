"""Mirror of release info

TODO: generate this file from GitHub API"""

# The integrity hashes can be computed with
# shasum -b -a 384 [downloaded file] | awk '{ print $1 }' | xxd -r -p | base64
DMD_VERSIONS = {
    "2.105.0": {
        "x86_64-apple-darwin": "sha384-f4b79y0QL2VPyaRG9s9Bk3H7LxTt/7YC4nfj6S0pLksXvCejCfB1ZrBvml/SkH15",
        "x86_64-pc-windows-msvc": "sha384-F9AeV6aG19oRyBBiA0gGW7TB8J3Jn2jXTgZcN5hJX3oDb5fzDEbffpbA7Q9M3wKG",
        "x86_64-unknown-linux-gnu": "sha384-4Utskg4Jhemhr+XfA5NiyvXEl14q6ak4XIEpxAmAiFWbWU/kFRr0KNiPL53+o3Si",
    },
}

LDC_VERSIONS = {
    "1.30.0": {
        "x86_64-apple-darwin": "sha384-7pnStRevAiPmpZP8HWGxeYZ6Tz+jT5XDIIyq6FbU2AdNTLaEp29vQCs7eVvkOJS6",
        "aarch64-apple-darwin": "sha384-ws5UW5kYCFkSPk2f+c/tvugeR8FRu6oLUMqri1cdYSxbsVggzLxebdNb53ubRurY",
        "x86_64-pc-windows-msvc": "sha384-P39XKjOp4ZZmfdVvgjTTUf9SETbLGUVfwbnJipXsKG38e9+DiqPeoZSmnwbJuwi4",
        "x86_64-unknown-linux-gnu": "sha384-cpbmUuQekrwm3NghjuS0WH5H54r/Yscd9sEOQOIbBSL9dAGQzTeAvEJkwR5sxm85",
    }
}
