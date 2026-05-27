# Contributing

## Build and Test

```sh
zig build
zig build test
```

Format Zig files before submitting:

```sh
zig fmt src build.zig
```

Do not run Zig builds or tests in parallel. They share `.zig-cache` and
`zig-out`; concurrent invocations produce confusing or stale results.

## Commit Style

Subject: imperative, present tense, under 70 characters. Body explains the
why and wraps at 72 columns. Skip the body when the subject says enough.

Existing commits set the tone:

```
Initial wayembed scaffold
Expand gitignore
```

## ABI Versioning

The public C ABI lives in `include/wayembed.h`. Changes follow the rules
below. Get them right at PR time — a quiet break compounds across the
plugins and hosts that bind to wayembed.

### No bump required

- Adding a new opaque type, function, or callback table.
- Adding a field at the end of a versioned struct, when readers gate
  access by checking the struct's `version` field.

Example: adding an optional callback to the end of
`wayembed_host_interface` does not require a bump when
`src/c_api.zig` copies the field only if the caller's `size` reaches that
field. Older callers leave the callback null and keep the same behavior.

### Bump `WAYEMBED_ABI_VERSION`

- Removing or repurposing a field in a public struct.
- Changing a function signature or its ownership rules.
- Changing struct layout in any way that breaks size compatibility.
- Changing the meaning of an existing return value or error code.

Example: changing `wayembed_embed_resize` from client-scoped resize to a
new handle-scoped resize would require a bump, because existing callers
would pass the wrong object and the ownership contract would change.

### When you bump

- Update `WAYEMBED_ABI_VERSION` in `include/wayembed.h`.
- Update `tests/c_abi_smoke.c` to exercise the new surface.
- Note the change at the top of the affected struct or function in the
  header so downstream readers see it.

## Code Style and Architecture

See [AGENTS.md](AGENTS.md) for the working rules and the C ABI rules.
See [docs/style-guide.md](docs/style-guide.md) for Zig style, naming,
ownership, error handling, test layout, and file-size discipline.

## Documentation

See [docs/README.md](docs/README.md) for the documentation index.
