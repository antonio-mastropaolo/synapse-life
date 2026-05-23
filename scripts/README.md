# Release scripts

This directory holds the scripts that produce shippable Synapse builds
for macOS (Developer ID + notarisation) and iOS (TestFlight upload).
The scripts themselves are short and self-contained; the heavy lifting
is the one-time credential setup the user does on their laptop. None
of those credentials live in the repo.

## Files

- `make-icons.swift` — re-renders the Cockpit-amber app icon at every
  required size and writes the PNGs into both asset catalogs. Re-run
  whenever the icon design changes. Renderer lives in
  `packages/SynapseKit/Sources/Tools/IconRenderer.swift`.

- `release-macos.sh` — archives + exports + notarises + staples the
  macOS app. End result: a `SynapseMac.app` under `build/macOS-export/`
  that double-clicks cleanly on a fresh Mac.

- `release-ios.sh` — archives + exports + uploads the iOS app to App
  Store Connect (TestFlight). End result: a build visible in App Store
  Connect for the user to push to internal testers.

## One-time setup (user laptop only — not the agent)

### macOS notarisation

You need an Apple ID, a Developer ID Application certificate (installed
in Keychain via Xcode > Settings > Accounts), and an app-specific
password generated at https://appleid.apple.com/.

Store the credential profile once:

```
xcrun notarytool store-credentials synapse-notarytool \
    --apple-id "<your-apple-id>" \
    --team-id "<YOUR_TEAM_ID>" \
    --password "<app-specific-password>"
```

After that the macOS release script runs as a single command:

```
./scripts/release-macos.sh
```

### iOS TestFlight upload

Generate an App Store Connect API key at https://appstoreconnect.apple.com/
> Users and Access > Keys. Download the `.p8` once (it can't be
re-downloaded), then place it at:

```
~/private_keys/AuthKey_<KEY_ID>.p8
```

Export the matching env vars:

```
export ASC_API_KEY_ID="<10-char Key ID>"
export ASC_API_ISSUER="<UUID Issuer ID>"
```

Then run:

```
./scripts/release-ios.sh
```

## What to .gitignore

Make sure the following never get committed:

```
*.p8
*.cer
*.p12
~/private_keys/
~/.appstoreconnect/
build/
```

`build/` is the scripts' output directory; the others hold the actual
signing material. If you ever see a `.p8` show up in `git status`,
stop and rotate the key.

## CI tagged-release behaviour

`.github/workflows/ci.yml` defines a `release` job that fires on tags
matching `v*.*.*`. The job runs both scripts above *only if* the
repo's GitHub Actions secrets are populated:

- `MACOS_SIGNING_PROFILE` — base64 of the notarytool keychain item
  (the user is expected to wire this through their own preferred
  secret-management flow; the CI job will skip with a clear log line
  if it's not set).
- `ASC_API_KEY_ID`, `ASC_API_ISSUER`, `ASC_API_KEY_BASE64` — the same
  fields as above, with the `.p8` body inlined base64 so it can be
  reconstituted on a runner.

The CI job *never fails* when secrets are missing; it logs a "skipped"
line and exits successfully. That keeps the scaffolding live before
the user wires their account in.
