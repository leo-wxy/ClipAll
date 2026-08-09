# Local Build, Installation, And Release Contract

## 1. Scope / Trigger

This contract applies when changing app version metadata, local signing, bundle
assembly, `/Applications` installation, or GitHub Actions release behavior.

## 2. Signatures

```text
Scripts/check-version.sh
Scripts/build-local-app.sh
Scripts/install-local-app.sh
CLIPALL_ADHOC=1 Scripts/build-local-app.sh
git tag v<contents-of-VERSION>
```

`Scripts/install-local-app.sh` is the only local run/install entry. It builds an
intermediate bundle, verifies it, atomically replaces `/Applications/ClipAll.app`,
and launches that path.

## 3. Contracts

- `VERSION` is a three-part numeric SemVer.
- `CFBundleShortVersionString`, `CFBundleVersion`, host plugin compatibility
  defaults, and the bundled example minimum host version equal `VERSION`.
- `build-local-app.sh` assembles `.build/ClipAll.app`; it never launches it.
- `install-local-app.sh` only targets `/Applications/ClipAll.app`, refuses a
  symbolic-link destination, stages in `/Applications`, and backs up the prior
  bundle before replacement.
- Local builds use `ClipAll Local Development`. `CLIPALL_ADHOC=1` is CI-only.
- A `vX.Y.Z` tag must exactly equal `v$(<VERSION)` before creating a prerelease.

## 4. Validation And Error Matrix

| Condition | Required behavior |
|---|---|
| Version metadata differs | `check-version.sh` exits non-zero |
| Local signing identity missing | build exits before replacing Applications |
| Source or staged signature invalid | install exits and leaves current App intact |
| Applications process will not quit | install aborts before replacement |
| Move of staged App fails | restore the backup when possible |
| Tag differs from VERSION | release job exits before packaging |
| CI artifact | mark arm64, ad-hoc, prerelease, and not notarized |

## 5. Good / Base / Bad Cases

- Good: run `install-local-app.sh`, keep one `/Applications` process, and preserve
  a stable local signing identity across rebuilds.
- Base: CI uses `CLIPALL_ADHOC=1` and never treats the artifact as notarized.
- Bad: run `.build/ClipAll.app` beside the Applications copy; this duplicates the
  menu-bar item and gives macOS a different TCC identity.
- Bad: replace `/Applications/ClipAll.app` before bundle signature verification.

## 6. Tests Required

- `Scripts/check-version.sh`: assert all version-owned files agree.
- `zsh -n Scripts/*.sh`: assert shell syntax.
- `Scripts/verify-all.sh`: assert domain, overlay, provider, runner, fixture, and
  lifecycle checks.
- `swift build --target ClipAll`: assert the app module compiles.
- CI with full Xcode runs `swift test`; CLT-only environments may not provide
  `XCTest` and must report that limitation rather than hiding it.
- After installation, verify nested runner and App signatures, confirm exactly one
  Applications process, and visually check the Applications copy.

## 7. Wrong Vs Correct

### Wrong

```sh
open .build/ClipAll.app
```

### Correct

```sh
./Scripts/install-local-app.sh
```

The intermediate bundle may be recreated at any time, but it is never a user-facing
execution path.
