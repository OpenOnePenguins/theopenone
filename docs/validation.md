# Validation of the initial source snapshot

Validated on macOS on 2026-10-10 for The Open One 0.7.16 (41):

| Check | Result |
| --- | --- |
| Native regression suite | 528 checks passed |
| Local event bridge | 3 tests passed |
| Utilities and HTTP bridge | 32 tests passed |
| Provider approval transport | 9 tests passed |
| Guided onboarding | 42 checks passed |
| Native approval buttons | 12 offscreen accessibility action checks passed across Talk, Inbox and floating windows for both providers |
| Installed Codex 0.162.1 | Approve and deny passed against an isolated local model and temporary project |
| Installed Claude Code 2.1.280 | Approve and deny passed against an isolated local model and temporary project |
| Packaged macOS app | 13 isolation, bridge, restart and recovery checks passed |
| Desktop build and signature | Build and strict signature verification passed |
| Phone protocol | 15 tests passed |
| Phone TypeScript, lint and production web export | Passed |
| Publication checks | Local Markdown links resolve; generated files, local session records, connection QR screenshots and credentials excluded |

The provider checks use installed CLIs with deterministic local HTTP model fixtures. They do not validate live account billing or every provider permission type. Offscreen UI checks do not simulate physical mouse input. Physical-phone, microphone, multiple-monitor and clean-machine installation checks remain separate release gates.

Reproduction commands and limitations are in [the release checklist](feature-parity.md), [onboarding](onboarding.md) and [command approvals](approvals.md).
