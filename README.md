[![Release](https://badgen.net/github/checks/darkhorseprojects/limbo-zig/main/release.yml?label=Release&icon=github)](https://github.com/darkhorseprojects/limbo-zig/actions/workflows/release.yml)
[![License](https://badgen.net/github/license/darkhorseprojects/limbo-zig?label=License&color=black&icon=github)](LICENSE)

# limbo-zig

`limbo-zig` is a Zig wrapper around Turso Limbo's `turso_sqlite3` C-compatible library.

It gives Zig projects a small storage layer for rows and bytes. The wrapper exposes text and blob values while leaving higher-level schemas and application behavior to the caller.

## What is included

The package exposes the `limbo` Zig module and links the matching prebuilt `turso_sqlite3` static library for these targets:

- `x86_64-linux-gnu`
- `x86_64-macos`
- `aarch64-macos`
- `x86_64-windows-msvc`

## Using release assets

Use the `limbo-zig-<version>.tar.gz` asset from a GitHub release as the package URL. The normal GitHub source archive does not include the prebuilt libraries.

## Development

When `third_party/limbo` is checked out, `zig build` builds `turso_sqlite3` with Cargo for the requested target instead of using the release prebuilts.

```bash
zig build
zig build test
```

## Read more

- [Turso Limbo](https://github.com/tursodatabase/limbo)

