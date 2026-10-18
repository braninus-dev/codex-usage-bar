# Contributing

Thanks for helping improve Codex Usage Bar. Keep the app small, local, and conservative about quota state.

## Before opening a change

- Explain the user-visible behavior and the failure mode the change addresses.
- Keep quota interpretation in `Sources/UsageCore/QuotaReducer.swift`; never infer availability from a timer or one quota window.
- Use synthetic fixtures for state and storage behavior. Do not commit live account responses, account identifiers, idea text, credentials, or local build artifacts.
- Keep the app read-only with respect to Codex sessions. It may read rate limits, but should not create a conversation or execute a saved idea.
- Preserve the privacy disclosure in the README when changing idea storage or networking.

## Build and verify

On macOS 13 or later with Swift 5.9+:

```sh
./scripts/verify.sh
./build.sh
```

The executable check target uses the production core code and synthetic data. Add a regression check for every new quota or reset boundary. For UI work, generate the relevant light and dark previews and inspect the actual AppKit view hierarchy. When possible, also check VoiceOver, Reduce Motion, another supported macOS release, and both processor architectures.

Keep commits focused on this package. The surrounding AgentDesk checkout may contain unrelated work; do not stage or reformat it as part of a Codex Usage Bar change.
