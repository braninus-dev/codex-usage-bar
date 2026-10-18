# Security and privacy

## Data handled by the app

Codex Usage Bar starts the Codex CLI app-server as the signed-in user and requests `account/rateLimits/read`. It does not open sessions, submit prompts, or make model requests. Authentication stays in the Codex CLI. The app does not copy credential files or print response payloads.

Idea drafts and saved ideas are plain JSON in the current macOS user's Application Support directory. The app sets directory permissions to `0700` and the data file to `0600`; the contents are not encrypted. Quota reset metadata stores only reset timestamps and a per-install salted account digest. Neither ideas nor quota snapshots are uploaded by this app.

Do not include account data, CLI logs, credentials, private ideas, or unredacted app-server responses in a bug report. Synthetic fixtures should be used for tests and issue reproductions.

## Reporting a vulnerability

For a suspected security issue, use GitHub's private **Report a vulnerability** action for the repository that distributes this package. Please do not post credentials, private quota responses, or exploitable details in a public issue. If private reporting is unavailable, open a minimal issue asking for a private contact path without including sensitive material.

This project is community maintained and is not an official OpenAI security response channel.
