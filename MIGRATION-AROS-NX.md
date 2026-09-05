# AROS-NX repository migration plan

Status: initial-release closure in progress as of 5 September 2026. The measured
extraction ledger is in `MIGRATION-INVENTORY.md`. Baseline is AROS-NG commit
`c35ed6ec7438cc8611ae88957e094dca5abf8972` and the published prerelease
`toolchain-v1-20260829-rc3`. AROS-NG remains preserved as the recoverable
historical source; active development has moved to the split repositories.

The repository split is now live: AROS-NX `main` contains the reviewed OS patch
series, `aros-tools` contains the attribution-clean Rust workspace and release
publisher, and `aros-toolchains` contains the standalone producer. Its own
`toolchain-v1-20260831-rc3` prerelease is published; the AROS-NX consumer lock
enables its measured four-host/three-profile matrix. Source integration PRs
#25 and #28 remain open. The first tools release is not published: Release
Please PR #38 proposes 0.1.1 after the untagged 0.1.0 candidate was superseded.
Fabian approved central APT publication through `metaneutrons/apt-archive`;
aros-tools PR #39 implements that boundary and is still in qualification.
This file records target policy; measured run and commit identities, pending
credential handoff and explicit hardware evidence gaps are in `HANDOFF.md`.

## Target repositories

### `metaneutrons/AROS-NX`

A fresh fork of upstream AROS containing only the operating-system tree and
the smallest necessary consumer configuration.

- `master` is an exact, force-push-free mirror of upstream `master`.
- `main` is the continuously integrated AROS-NX line: upstream plus reviewed
  AROS-NX patches.
- `pr/<subsystem>-<topic>` branches start from `master` and contain one
  upstreamable patch series.
- `feature/*`, `fix/*` and `docs/*` branches start from `main` for AROS-NX work.
- Ephemeral `sync/upstream-<12sha>` branches carry automated sync proposals.
- Daily and manual sync jobs fast-forward `master`, open a PR from the sync
  branch to `main`, run the complete matrix, and merge only when green.
  Conflicts, upstream rewrites and test regressions fail closed; no branch is
  silently rebased or force-pushed.

The repository contains `aros-tools.lock.toml` and
`aros-toolchains.lock.toml`.  They are explicit consumer locks with immutable
URLs, hashes and sizes, not producer metadata or hidden dependency pins.

### `metaneutrons/aros-tools`

The complete Rust workspace for `aros`, `aros-collect` and supporting tools.
It must work equally well with pristine upstream AROS and AROS-NX.

- Upstream mode is first-class: no assumed checkout name, location or AROS-NX
  patch.  GNU Make remains supported; the CMake/transpiler path is optional.
- Versioned built-in profiles provide good defaults, while checked-in project
  overrides and explicit CLI arguments remain possible.
- Toolchain selection is explicit and locked; updates never happen silently.
- Logs, caches and generated files stay outside the source tree by default.
- The extraction removes the 89 exact Claude Opus `Co-Authored-By` trailers
  while preserving code and all other authorship.  A full history and source
  scan must prove that no Claude/Anthropic attribution remains.

Documentation uses Astro Starlight at
`https://aros.metaneutrons.cc/aros-tools/`. English
is canonical and covers installation, pristine-upstream and AROS-NX workflows,
configuration, generated CLI reference, toolchains, diagnostics/error codes,
logging, security, reproducibility and release operations.  Documentation is
versioned with releases.

Releases provide native archives for Linux x86-64/ARM64 and macOS x86-64/ARM64,
plus:

- attested `.deb` packages for amd64 and arm64, consumed and published by the
  centrally signed `metaneutrons/apt-archive` service;
- a four-host Homebrew formula in `metaneutrons/homebrew-tap`;
- an AUR `aros-tools-bin` package with exact hashes, never `SKIP`.

One verified build feeds all packaging.  Draft releases are promoted only
after archive, package, SBOM, provenance, signature and installation checks.

### `metaneutrons/aros-toolchains`

This repository owns deterministic producer workflows, build recipes, source
locks, schemas and verification.  GitHub Releases remain the canonical home
of immutable toolchain archives; Cloudflare R2 is not a second toolchain SSOT.

- Produce and compare two copies for every four-host/three-profile entry.
- Test compatibility against explicit reviewed upstream and AROS-NX commit
  identities. A published release never silently follows a moving branch.
- Publish indexes, checksums, manifests, SBOMs and fresh provenance/attestation.
- Document direct installation for users who do not use `aros-tools`.
- Never retarget an existing tag or transplant an old attestation.

## Public distribution surfaces

- GitHub Releases: `aros-tools` host archives and all toolchain archives.
- `https://aros.metaneutrons.cc/`: beta landing page.
- `https://aros.metaneutrons.cc/aros-tools/`: source-verified Starlight docs.
- `https://deb.metaneutrons.cc/aros-tools`: central APT project prefix,
  suite `rolling`, component `main`, architectures amd64/arm64. The domain
  keyring is `https://deb.metaneutrons.cc/metaneutrons-archive-keyring.pgp`.
- `metaneutrons/apt-archive` exclusively owns signing, metadata, retention,
  refresh and storage publication. Tools CI only supplies attested packages,
  requests the central workflow with a separate repository-restricted App,
  and verifies the public signed result without credentials.
- Toolchain and installation-image presentation may be added later; no
  unqualified image channel or second toolchain artifact source is implied.
- Hosting administration and local credential configuration do not belong in
  the public user documentation. Do not modify Fabian's local skill/config.

## Migration sequence

1. Create and restore-test a full Git bundle, download RC3 release assets and
   relevant Actions logs, record hashes, and freeze destructive cleanup.
2. Inventory every AROS-NG patch and classify it as upstreamable, AROS-NX-only,
   tools, toolchain, generated, or obsolete.
3. Create the three repositories and branch protections.  Seed AROS-NX from a
   fresh upstream fork, then apply OS patches as reviewable commits/branches.
4. Extract `aros-tools` through a temporary clone, rewrite only the specified
   attribution trailers, and prove the resulting workspace tree is identical.
5. Add the upstream-first UX, Starlight documentation and four-host packaging;
   release and installation tests must use the public artifacts.
6. Move the deterministic producer into `aros-toolchains` and qualify a fresh
   release with fresh attestations.
7. Point AROS-NX consumer locks at the new releases and run the full upstream
   and AROS-NX build/product matrices.
8. Scan code, history, workflows and documentation for old repository URLs and
   migration-only compatibility paths; remove only those proven obsolete.
9. Archive AROS-NG first.  Delete it only after restore verification and a new,
   explicit confirmation from Fabian.  Existing tags and releases are never
   rewritten during the migration.

## Completion criteria

- AROS-NX starts from a demonstrably exact upstream state and has a complete
  patch ledger plus independently reviewable upstream branches.
- Automated upstream synchronization is fail-closed and both permanent
  branches are protected.
- `aros-tools` has no Claude/Anthropic attribution, supports pristine upstream
  and AROS-NX, and installs successfully through all promised channels.
- Toolchains pass 24 builds, 12 byte-identical comparisons, all compatibility
  lanes, relocation, inventory, checksum, SBOM and attestation verification.
- Every consumer lock contains only measured published values; all final URLs
  and clean-room fetches pass.
- Backups restore successfully and no required reference points at AROS-NG.
- AROS-NG deletion has separate, explicit approval after all preceding gates.
