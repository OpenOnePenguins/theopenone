# Command approvals

Conversations started or resumed by The Open One use a bidirectional connection to their provider. When the provider requests permission, the conversation enters **Needs you** and shows an approval card in Talk, Inbox, and floating conversations.

The card names the provider, conversation and project folder, and displays the complete command or tool input as literal text. Review it, then choose **Approve once** or **Deny**. Both choices have the usual two-second Undo interval. Approval does not create a permanent allow rule. Chat messages such as “yes” cannot approve a command.

The provider's existing sandbox and permission configuration still applies. The Open One does not add bypass flags. A command already allowed by the provider's configuration may run without a new prompt. Unsupported interaction types are rejected explicitly; a request without sufficient file-change details cannot be approved from the card.

## Existing terminal conversations

An observed transcript is not an approval connection. Approvals for an active conversation owned by another terminal still need to be answered in that terminal. Sending a queued Codex chat message does not confirm its pending command. The app shows this limitation when an observed conversation is waiting.

Connect a supported terminal through Herdr to use its explicit approval keys on the Mac. For an inactive saved Claude/Codex conversation, continuing it in The Open One starts a managed run with the approval transport. Do not start another writer for an active conversation or delete its lock files.

Phone chat shows a read-only explanation while a managed command is waiting for approval. Review the card on your Mac; phone approval controls are not implemented.

## Lifecycle and validation

Each decision is bound to a unique request in the current provider process. Changing the selected chat cannot retarget it. Undo, provider cancellation, process exit and app restart invalidate pending approval controls. Decisions are never automatically retried, and approval does not clear an unrelated message draft.

The transport uses Codex's app-server request/response protocol and [Claude's approval control protocol](https://code.claude.com/docs/en/agent-sdk/user-input). Claude tool input is returned unchanged when approved. Codex only receives an individual `accept` or `decline`; session-wide policy amendments are not sent.

```sh
bash scripts/test.sh
bash scripts/render-approvals.sh
python3 scripts/e2e/approvals.py --provider Codex
python3 scripts/e2e/approvals.py --provider Claude
```

The renderer uses offscreen native views and accessibility actions; it does not move the host pointer or type into other apps. The installed-CLI tests use temporary provider homes and local fake model endpoints. Their only command writes a disposable marker inside the test directory. They do not use real accounts or conversations. Installed-protocol verification covers Codex 0.162.1 and Claude Code 2.1.280; real-account execution remains a separate check.
