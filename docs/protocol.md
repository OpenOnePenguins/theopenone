# Local event protocol

Root: `OPEN_ONE_HOME`, or `~/Library/Application Support/Open One`.

Write one UTF-8 JSON document to a temporary file under `events`, then atomically rename to `<sortable-time>-<uuid>.json`. Maximum document size: 1 MiB. The app polls every 500 ms. Unknown kinds, invalid questions and undecodable JSON move to `rejected`. A processed-event journal deduplicates the latest 10,000 events. Persistence happens before event deletion.

```json
{
  "id": "unique-event-id",
  "agentID": "stable-agent-id",
  "kind": "question",
  "name": "codex-1",
  "provider": "Codex",
  "directory": "/path/to/project",
  "text": "Which layout?",
  "choices": ["Three tiers", "One plan"],
  "requestID": "unique-question-id"
}
```

Kinds: `register`, `working`, `question`, `message`, `done`, `offline`. `id`, `agentID`, `kind` are required. Questions also require nonempty `text` and `requestID`. `working`, `done` and `offline` invalidate previous question choices. Each agent has one outstanding request; a newer question supersedes the previous one.

After explicit submission and the undo interval, the app writes `replies/<base64url(requestID), unpadded>.json` atomically:

```json
{
  "agentID": "stable-agent-id",
  "requestID": "unique-question-id",
  "text": "One plan",
  "choiceIndex": 1
}
```

`choiceIndex` is absent for free text. The consumer verifies both IDs, consumes the response, and deletes that reply file. No reply means no decision. Timeout and cancellation must not be interpreted as agreement.

The app rechecks the outstanding request immediately before delivery. If the agent started work or replaced the question during the undo interval, the reply is rejected for user review.

This is local IPC for the current OS user, not a network authentication boundary. Do not expose this directory through a public file server. Optional remote access uses the separate authenticated adapter described below.

## Optional remote adapter (0.5)

The local IPC directory remains private to the current OS user. The optional remote bridge publishes a bounded projection through an authenticated loopback HTTP service; it never serves this directory directly. It accepts remote agent events and validated reply commands, which the app drains into the same local delivery flow. See [remote access](remote-access.md) for encrypted transport, token handling, limits, and setup.
