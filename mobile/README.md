# Open One mobile

Our phone app connects directly to **Open One on the Mac**. It uses our own authenticated bridge and desktop session runner. No Orca application, account, pairing, or protocol is required.

The phone shows tracked conversations, recent history, outstanding choices, and a composer. Open One on the Mac preserves the provider session and worktree, resumes eligible saved Codex/Claude sessions, or uses Codex's native queue for an existing writer. Provider CLI sign-in stays on the Mac.

## Connect

Start with the [step-by-step iPhone setup and test guide](../docs/phone-setup.md). The current phone app is Safari, with direct LAN access to real conversations.

1. Build/run the updated Open One Mac app from this checkout.
2. In Open One, open **Remote access**, click **Connect phone** under **Local Wi-Fi only**.
3. Scan the QR with iPhone Camera and open Safari. Keep the Mac awake with Open One running.

LAN mode binds to a selected private IPv4 interface and uses a credentialed local HTTP link. Tailscale connections and remote hostnames are disabled. No public tunnel is started by the app. An iPhone cannot reach this Mac through `127.0.0.1`.

Connection credentials use SecureStore on native devices and sessionStorage in the browser. A connection link opened in the bundled browser app has its fragment removed from browser history. Stopping remote access on the Mac revokes the connection.

## Develop and build

Agent marks use the same artwork as the Mac app. If the desktop SVGs change, run `bash scripts/build-mobile-provider-icons.sh` from the repository root before exporting the web app.

```sh
cd mobile
npm ci
npm start
npm test
npm run typecheck
npm run lint
npx expo export --platform web --platform ios
```

Expo Go must match SDK 57. EAS profiles are in `eas.json`; native Apple builds still require Expo project configuration, a confirmed bundle identifier, Apple signing, and device validation. No TestFlight build has been uploaded.

The phone client only accepts LAN addresses; loopback remains available for local development. Browser development must use the same origin as the bridge; cross-origin bridge access is intentionally disabled. Export the web app, then run `bash scripts/build.sh` from the repository root to bundle it with the Mac app. **Preview on this Mac** then uses the same UI as the mobile app.

## Isolated preview

From the repository root, after exporting the web app:

```sh
bash scripts/run-mobile-preview.sh
```

Open http://127.0.0.1:8088 and use this **test-only** connection link:

```text
http://127.0.0.1:8088/#open-one-isolated-preview-0000000000000000
```

This preview runs the production Swift Store, Python bridge, and AgentRunner against an isolated deterministic provider fixture under `.build/mobile-preview`. It never accesses real conversation credentials or asks a live model to work. It runs for up to one hour. The public fixture credential works only for this sample server.

## Delivery behavior

Each send has a durable operation ID and an opaque recipient identity. The bridge deduplicates the same operation, checks its recipient/question, and the Mac revalidates identity before delivery. Commands expire after 30 seconds. Phone Send commits immediately when consumed on the Mac; the local Mac composer keeps its two-second Undo window. The phone performs one POST after saving the pending operation, checks small receipts every 250 ms without overlapping requests, and downloads only the selected conversation for chat refreshes.

The UI distinguishes queued, staged, submitting, delivered, rejected, and uncertain states. A staged receipt is **not** delivery. The draft clears only after the desktop/provider accepts the message. Timeouts are not retried automatically; saved pending operations are reconciled through receipts after reconnect. Ambiguous delivery requires checking the Mac before unlocking another send.

The first version shows the latest 20 visible messages (8,000 characters each), all active tracked conversations. Attachments, terminal approval keys, creating new agents, and Herdr-only control are not exposed. Saved Claude sessions still inherit the desktop runner's existing limitation: it cannot prove exclusive ownership of an unrelated live Claude process.

## Validation and limits

Run the tests, typecheck and lint commands above. The desktop integration checks are documented in [the release checklist](../docs/feature-parity.md). Fixture tests use isolated data and deterministic providers; they do not establish physical-phone or live-provider coverage. Native distribution still requires signing and device testing.
