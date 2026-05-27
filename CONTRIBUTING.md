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
Initial wayplug scaffold
Expand gitignore
```

## ABI Versioning

The public C ABI lives in `include/wayplug.h`. Changes follow the rules
below. Get them right at PR time — a quiet break compounds across the
plugins and hosts that bind to wayplug.

### No bump required

- Adding a new opaque type, function, or callback table.
- Adding a field at the end of a versioned struct, when readers gate
  access by checking the struct's `version` field.

### Bump `WAYPLUG_ABI_VERSION`

- Removing or repurposing a field in a public struct.
- Changing a function signature or its ownership rules.
- Changing struct layout in any way that breaks size compatibility.
- Changing the meaning of an existing return value or error code.

### When you bump

- Update `WAYPLUG_ABI_VERSION` in `include/wayplug.h`.
- Update `tests/c_abi_smoke.c` to exercise the new surface.
- Note the change at the top of the affected struct or function in the
  header so downstream readers see it.

## Code Style and Architecture

See [AGENTS.md](AGENTS.md) for the working rules and the C ABI rules.
See [docs/style-guide.md](docs/style-guide.md) for Zig style, naming,
ownership, error handling, test layout, and file-size discipline.

## Documentation

See [docs/README.md](docs/README.md) for the documentation index.
