# Capabilities and release checks

The Open One is an independent implementation. Full feature parity with One is not established. Automated fixture coverage, native UI checks, and live-device tests provide different evidence.

| Area | Included | Remaining limits |
| --- | --- | --- |
| Desktop interface | Collapsing edge toolbar, hover panels, activity dots, provider marks, searchable Inbox, floating chats and native Markdown | Spaces, multiple monitors and accessibility preferences need device checks |
| Agent organization | Project/worktree grouping, explicit tracking selection, persistent review state, recent Claude/Codex transcript discovery | Empty terminals have no transcript to discover; other providers need the bridge |
| Sending | Managed Claude/Codex sessions, native resume/fork, durable Codex queue, preserved drafts, two-second Mac Undo | Active Claude continuation requires closing its original terminal; uncertain delivery is never automatically retried |
| Command approvals | Approve once / Deny for managed Claude/Codex runs, exact-request fencing, Undo, cancellation and native cards; explicit keys for connected Herdr terminals | Observed external terminals require confirmation in their owning process; phone approvals are unsupported. See [approval checks](approvals.md). |
| Questions | Local event bridge with explicit choices, request identity validation and stale-answer protection | Bridge questions are separate from provider command permissions |
| Recipients | Visible context, on-device recommendations, explicit optional tool-free Claude routing | AI routing requires the user's Claude account and does not send automatically |
| Onboarding | Provider installation/auth checks, project selection, explicit first-response verification, cancel/retry and saved progress | Fixture success does not verify real account billing or clean-machine installation |
| Screenshots and speech | Native region capture, preview, Codex/Claude image delivery and Apple Speech dictation | Hardware permissions, denial/recovery and multiple displays need live checks |
| Phone | Bundled Safari app, same-LAN QR connection, tracked histories, replies, receipts and revocation | Mac must stay awake; no public relay, native signed iOS release, push notifications, attachments or approval controls |
| Utilities | Notes, feedback drafts, Codex usage, opt-in Claude status-line usage and configurable shortcuts | Provider-specific feeds require setup |
| Distribution | Reproducible local build and persistent development signing | No notarized installer or auto-update feed |

## Automated checks

From the repository root on macOS:

```sh
bash scripts/test.sh
bash scripts/test-onboarding.sh
bash scripts/test-utility-service.sh
python3 scripts/e2e/packaged-app.py
```

Build the app before running the packaged-app check. The main suite covers persistence, discovery, worktrees, delivery, Undo, stale questions, writer conflicts, queue receipts, Markdown, screenshots, utilities and the local/HTTP bridges. Onboarding runs the real SwiftUI/model/Store/runner path with isolated fixture CLIs; see [onboarding verification](onboarding.md).

For the phone client:

```sh
cd mobile
npm ci
npm test
npm run typecheck
npm run lint
npx expo export --platform web
```

The [mobile preview](../mobile/README.md#isolated-preview) runs the production desktop Store and bridge with a deterministic provider. It does not send requests to live agents.

## Desktop and live release checks

`bash scripts/test-native-ui.sh` sends real pointer and keyboard events. Run it only in a dedicated desktop session with the required Accessibility access; its historic assertions may need updating as the interface changes. Offscreen renders do not prove pointer/keyboard interaction works.

Before distributing a release, check first-run setup on a clean Mac, provider sign-in and real responses, supported continuation paths, a real command permission prompt, capture permissions, dictation, app restart with unsent drafts, and physical-phone reconnect/reply. Verify signing, package contents and the minimum supported operating system separately. Use disposable projects and conversations for tests that contact providers.
