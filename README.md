# limbo-zig

Zig wrapper for Turso Limbo's `turso_sqlite3` C-compatible library.

This package exposes the `limbo` Zig module and links the matching prebuilt `turso_sqlite3` static library for these release targets:

- `x86_64-linux-gnu`
- `x86_64-macos`
- `aarch64-macos`
- `x86_64-windows-msvc`

Limbo stores rows and bytes. It exposes `Text` and `Blob`; it does not define Zinc tables, package behavior, Circuitry semantics, or execution policy.

Use the `limbo-zig-<version>.tar.gz` source asset from a GitHub release as the Zig package URL. The normal GitHub source archive does not contain the prebuilt libraries.

When developing this repository with `third_party/limbo` checked out, `zig build` builds `turso_sqlite3` with Cargo for the requested target instead of using the release prebuilts.
