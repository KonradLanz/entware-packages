# Discussion: Optimize local builds for prebuilt-binary packages

> **Status:** Proposal — seeking feedback from Entware maintainers  
> **Scope:** Local developer workflow / CI build time  
> **Related packages:** `gh`, `docker-cli`, and any package with an empty `Build/Compile` stanza

---

## Background

While adding [`gh` (GitHub CLI)](https://cli.github.com) as an Entware package, a significant inefficiency became apparent in the local development workflow:

The `gh` package — like several others in the tree — distributes **prebuilt, architecture-specific release binaries** from upstream. Its `Makefile` has an intentionally empty `Build/Compile` stanza:

```makefile
define Build/Compile
endef
```

This means no C/C++ compilation occurs. The Entware build system only needs to:
1. Download the upstream tarball
2. Extract the binary
3. Repackage it as an `.ipk`

Yet the standard local build workflow (`make package/gh/compile`) requires:
- A full Docker image (~4 GB)
- A complete cross-compilation toolchain build (~40–60 minutes on first run)
- Host tools rebuilt from source (`cmake`, `ninja`, `meson`, `autoconf`, ...)

All of this for a package that never invokes the cross-compiler.

---

## Proposal

### 1. Detect prebuilt packages automatically

A package can be classified as **prebuilt** if its `Build/Compile` stanza is empty (no commands, only whitespace/comments). This is already an established pattern in the tree.

A simple shell or `make` detection:

```sh
# Shell: detect empty Build/Compile
awk '
  /^define Build\/Compile/ { in_block=1; next }
  /^endef/ && in_block     { print (has_cmd ? "source" : "prebuilt"); exit }
  in_block && /^\t/        { has_cmd=1 }
' package/utils/gh/Makefile
```

Or a Makefile convention — an explicit variable maintainers can set:

```makefile
PKG_BUILD_TYPE:=prebuilt  # signals: no toolchain required
```

### 2. Provide a lightweight build path for prebuilt packages

For packages where `PKG_BUILD_TYPE=prebuilt`, the local build script (and optionally CI) could:

- **Skip** `make tools/install` and `make toolchain/install`
- **Skip** the Docker image entirely for local `.ipk` assembly
- Build the `.ipk` directly using standard POSIX tools (`ar`, `tar`) available on any host

This reduces the local iteration cycle from **~60 minutes** to **~10 seconds**.

### 3. Docker image presence check

For packages that do require Docker, the build script should detect whether the image already exists locally before attempting to pull or rebuild it:

```sh
if docker image inspect entware-builder >/dev/null 2>&1; then
    echo "Image present, skipping build."
else
    docker build ...
fi
```

This avoids redundant multi-gigabyte pulls in iterative development.

---

## Affected packages (non-exhaustive)

Packages in the current tree with empty or near-empty `Build/Compile` stanzas that could benefit from this optimization:

| Package | Upstream distribution | Est. binary size |
|---|---|---|
| `gh` | GitHub Releases (Go binary) | ~45 MB |
| `docker-cli` | Docker releases (Go binary) | ~70 MB |
| Various Go tools | GitHub Releases | varies |

---

## Questions for maintainers

1. **Is `PKG_BUILD_TYPE=prebuilt` an acceptable Makefile convention**, or would a different mechanism (e.g., checking for empty `Build/Compile` automatically) be preferred?

2. **Should the lightweight `.ipk` assembly path be part of a helper script** in the repository root (e.g., `scripts/build-prebuilt.sh`), or integrated into the existing Docker-based workflow as a fast path?

3. **Is there interest in publishing a maintained Docker image** (e.g., on `ghcr.io`) that is rebuilt automatically when the upstream Entware toolchain changes? This would eliminate the ~60-minute first-time toolchain build for all developers.

4. **CI implications:** For prebuilt packages, CI could potentially skip the full toolchain stage and only verify that the `.ipk` assembles correctly and the binary passes `file`/`ldd` checks for the target architecture.

---

## Reference implementation

A working proof-of-concept that implements all of the above is available in:

- [`utils/gh/setup-build.sh`](../utils/gh/setup-build.sh) on branch `add-gh-cli`

The script:
- Auto-detects `PKG_TYPE` by parsing `Build/Compile`
- Takes the direct `.ipk` path for prebuilt packages (no Docker)
- Falls back to the full Docker path for source packages
- Checks for an existing Docker image before building
- Caches the toolchain between runs

Feedback and alternative approaches very welcome.

---

*Filed by [@KonradLanz](https://github.com/KonradLanz) — May 2026*
