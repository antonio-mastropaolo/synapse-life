# Synapse Life — App Store Readiness

Scope: ship the native iOS and macOS clients of Synapse Life (private-life
finance, life log, financial advisors) to the App Store. This document is
the operator checklist — read once, act on it.

## Identity

- Display name: **Synapse Life** (`CFBundleDisplayName`). The Xcode targets
  and SwiftPM package retain the internal codename `Synapse` / `SynapseLife`
  to avoid churning the build graph; users never see that string.
- Bundle IDs:
  - iOS: `tech.synapse.life.ios`
  - macOS: `tech.synapse.life.mac`
- App group (shared between targets, future widgets): `group.tech.synapse.life`
- Primary App Store category: **Finance**. Secondary: **Lifestyle**.
- URL scheme (deep links, password-manager handoff): `synapse-life://`
- Sign in with Apple is the only auth path. No email/password, no Google.

## Data the app collects

The finance surface is the data-heavy side. Be precise on the App Privacy
questionnaire; the wrong answer here gets a reviewer's attention.

- **Identifiers**: Apple user identifier from Sign in with Apple. The email
  field is requested but stored only if the user shared a real address (Apple
  may relay it). The Apple-relay address is stored verbatim.
- **Financial data**: account balances, transactions, holdings, advisor-chat
  messages. All entered or aggregated on the user's behalf and synced to the
  Synapse v2 backend. Tied to the user account; not anonymized.
- **Usage data**: minimal — request counts and error rates, no analytics SDK.
- **Diagnostics**: opt-in crash reports via the standard Apple framework. Off
  by default on the macOS build (Developer ID channel).
- **Not collected**: contacts, photos, location, microphone, camera,
  HealthKit, ad identifiers.

## What's shared with Anthropic

The advisor surface streams chat completions through the synapse-v2 backend,
which proxies to Anthropic's API. Anthropic receives the prompt text (which
may include user-authored financial questions and any context the user
chose to include), plus an opaque per-request identifier. Anthropic does
not receive the Apple user identifier or aggregated account data unless the
user pastes it into a message. This is disclosed in the privacy policy and
in the first-run Advisors screen.

## Biometric usage

Optional Face ID / Touch ID gate on app launch and before revealing balances
when "Conceal balances" is on. The justification string in `Info.plist`
reads exactly: *"Synapse Life uses Face ID to unlock your account
balances."* Do not embellish — App Review rejects fluffy strings.

## Account deletion

Required by App Store Review Guideline 5.1.1(v). Implemented as
**Settings → Account → Delete account**, which calls
`POST /api/account/delete` on synapse-v2. The server purges the user row,
all finance rows joined on `user_id`, and advisor-chat history, then
revokes the Sign in with Apple credential. Confirmation requires re-auth.

The deletion path must be reachable without filing a support ticket. Verify
this in TestFlight before submission.

## Demo account considerations for review

Sign in with Apple alone is normally enough — the reviewer can sign in with
their own Apple ID and the app boots into an empty-but-functional state.
The Advisors surface, however, needs at least one signed-in pass to show
the streaming behavior. To make this painless:

1. The synapse-v2 backend grants new accounts a small free-tier quota of
   Anthropic-proxied requests with no payment required.
2. The first-launch Finance surface seeds three example accounts and a
   handful of transactions tagged `demo=true` so the reviewer sees a
   non-empty state without us shipping a fake login.
3. App Review notes call this out explicitly (see
   `synapse-v2/docs/legal/app-store-metadata.md`).

No demo credentials are provided. Reviewers use their own Apple ID.

## Screenshot requirements

Apple requires 6.7" iPhone, 13" iPad, and macOS sets. Minimum: one set of
each. Recommended: five per device.

- iPhone 6.7" (1290×2796): Finance overview, Accounts, Transactions,
  Advisors chat, Life log.
- iPad 13" (2064×2752): same five, landscape variant for the chart-heavy
  Finance surface.
- macOS (2880×1800): Finance overview in a real window, Advisors with the
  sidebar visible, the Cockpit-Dense identity in default state.

Capture from real builds against seeded data, not Figma. Numbers should
look plausible (no `$0.00` columns, no `Lorem ipsum`).

## Milestone ordering

1. **Pre-flight**: bundle IDs registered, App Store Connect record created,
   provisioning profiles in place, `xcodegen generate` clean, signing
   identities verified by `release-macos.sh` and `release-ios.sh`.
2. **Account deletion path** end-to-end, including server side.
3. **Privacy policy and ToS** live at the public URLs referenced in App
   Store Connect (point at the synapse-v2 GitHub Pages or `/legal/*`).
4. **App Privacy questionnaire** filled in matching the data section above.
5. **Screenshots** captured from a TestFlight build.
6. **App Review notes** drafted (see metadata doc).
7. **TestFlight** internal pass, then external for at least three days.
8. **Submit** iOS first; submit macOS once iOS clears review (a rejection on
   one usually predicts the other).

Do not ship the macOS build through both the App Store and Developer ID
simultaneously on first launch — pick one channel per release.
