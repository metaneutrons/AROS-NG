# AROS-NX migration inventory

Inventory date: 30 August 2026.  This is the measured extraction ledger for
the migration described in `MIGRATION-AROS-NX.md`.

## Recovery baseline

- AROS-NG migration commit: `c35ed6ec7438cc8611ae88957e094dca5abf8972`
- AROS-NG tree: `7db5f057aa6a384b58b3ed5c1927db2a3ff4bb34`
- Current upstream AROS `master`: `6722a0ae9e03fe5d26e32703360bd2059e0864cc`
- Common ancestor: `fbea2d8b8d6beca257be82583aae1b389909ee7c`
- Local commits after the ancestor: 349
- New upstream commits after the ancestor: 128
- Verified backup: `/Volumes/Dev/Backups/AROS-NG-migration-20260830.RJWp2h`

The backup contains a verified all-refs bundle, an exact `.git` archive, a
successful independent bare restore, all 56 RC3 release assets, five Actions
log archives and a separately recoverable dirty detached worktree.  Nothing in
that worktree was modified by the migration.

## Path ownership

The 1,049 paths changed between the common ancestor and the migration commit
are assigned as follows.  These counts are an extraction guard, not an
architectural quality metric.

| Owner | Paths | Rule |
| --- | ---: | --- |
| `aros-tools` | 196 | Rust workspace, Pi support assets and agent workflow |
| `aros-toolchains` | 24 | Producer scripts, schemas, recipes and release workflows |
| AROS-NX CMake integration | 154 | CMake engine, fixtures, presets and target bridge |
| AROS-NX consumer locks | 2 | Target and immutable toolchain selection |
| CI/evidence/migration | 10 | Product CI, sync, boot/symbol tools and handoff records |
| AROS source/build tree | 663 | Runtime, MetaMake, vendored closure and source metadata |

Within the last group, 500 files are the vendored Boost SDK subset and 65 are
the vendored ACPICA header subset.  They are AROS-NX/toolchain build closure,
not independent upstream fixes.  Of the remaining files, 18 belong to the
already isolated patch candidates below and 77 require either AROS-NX build
integration or a newly isolated upstream review branch.

## Existing upstream patch candidates

`git cherry` confirms that none of these patch IDs is present in current
upstream.  A clean `git apply --check --whitespace=error-all` against current
upstream succeeds for every row marked `applies`.

| New branch name | AROS-NG source commit | Current upstream |
| --- | --- | --- |
| `pr/rom-bootloader-static-runtime` | `b42b3619a02a` | applies |
| `pr/rom-debug-sort-without-qsort` | `d78af7b3ea2f` | applies |
| `pr/rom-oop-static-runtime` | `8fd1261d843b` | applies |
| `pr/devs-ahci-posix-errno` | `688f2764e323` | applies |
| `pr/rom-aros-kickstartbase-cast` | `9e051e3f845b` | applies |
| `pr/arostcp-colorlist-extern` | `4278e55cb7f7` | applies |
| `pr/elf-loader-weak-undefined` | `8074d4f16b45` | applies |
| `pr/elf-loader-startup-entry` | `c691ba06300f` | applies after preceding ELF patch |
| `pr/exec-vlog-proto` | `c62d1489d9b9` | applies |
| `pr/kernel-early-stdbool` | `db6284437da7` | re-create minimally; old commit rewrote line endings |
| `pr/kickstart-romtag-section-order` | `1eda4028c37b` | applies |
| `pr/vmm-remove-trap-kernelbase` | `00a5dcd37574` | applies |

The old `fix/*` refs that were based on early AROS-NG integration commits must
not be pushed as upstream branches.  Only the isolated patch commits are
re-created on top of the exact new `master`.

## Additional review candidates

The following net source changes are not silently folded into an integration
commit.  Each gets an explicit review decision while constructing AROS-NX:

- SMBIOS/firmware validation (`7f307d3da8`);
- portable ARM and SysExplorer includes (`c386a080ba`);
- compiler string-pointer and symbol-set corrections (`5f41f54052`);
- C++ runtime header contracts (`6d37fc69bb`);
- self-contained bsdsocket prototypes (`22df424745`);
- the remaining runtime/source changes associated with the CMake graph.

MetaMake source inventories, generated-source declarations, vendored header
subsets, LLVM patches and CMake fixtures are classified as AROS-NX build or
toolchain closure unless a later isolated diff proves they are independently
useful upstream.

## Extraction rules

- AROS-NX starts at the current upstream commit above; no AROS-NG integration
  branch is pushed into its history.
- Upstream candidates are re-created as reviewable commits on `master`.
- AROS-NX-only changes are applied on `main` in functional groups after all
  overlapping upstream changes are reconciled; old files never overwrite new
  upstream files wholesale.
- `aros-tools` is extracted from its three owned path roots.  History rewriting
  removes only the 89 exact Claude Opus co-author trailers and path prefixes.
- `aros-toolchains` receives only producer ownership.  AROS-NX retains measured
  consumer locks; fresh releases receive fresh attestations.
- Every extraction has a file-list, tree-content and attribution audit before
  it is pushed.
