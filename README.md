<p align="center"><img src="Sources/OpenOne/Assets/open-one-logo.png" width="144" alt="The Open One penguin logo"></p>

# The Open One

An independent native macOS recreation of One's agent toolbar and Inbox, implemented in SwiftUI and AppKit. This repository contains original code; it does not use One's private source, binaries, credentials, or backend.

The [branding guide](docs/branding/README.md) identifies the shared penguin logo and its desktop, landing-page, and mobile exports. Run `bash scripts/sync-brand-assets.sh` after updating the canonical logo; add `--check` to verify that every exported copy is current.

## Run

Requires macOS 13+, Apple’s Swift Command Line Tools, and Python 3. Start with the [installation guide](docs/installation.md), including optional phone support and signing setup.

```sh
git clone https://github.com/OpenOnePenguins/theopenone.git
cd theopenone
bash scripts/build.sh
open "dist/Open One.app"
```

First launch opens guided setup. Choose Claude Code, Codex, or both; install or sign in to the official CLI if needed; then choose a project folder. **Verify connections** sends a short hello through each selected agent and saves the replies in Inbox. Setup finishes only after a response arrives. You can defer setup and reopen it from **Settings → Connect agents — guided setup** or the menu bar’s **Connect agents…**. Phone connection is optional after setup. See [onboarding and verification](docs/onboarding.md).

For a self-contained UI demo, with clearly marked sample conversations and no agent requests:

```sh
open "dist/Open One.app" --args --demo
```

Quit the running instance before switching between demo and live mode. The demo does not persist sample agents or consume bridge events.

## Working features

- Guided first-run setup with installation and sign-in checks, project selection, an explicit first-response check, retry/cancel, saved progress, and optional phone setup. Authentication stays with the official CLI.
- Translucent native blur, layered glass rims, pointer-following highlights, and spring toolbar transitions. Panels fade and resize smoothly. Reduce Motion and Reduce Transparency have alternate treatments. This uses APIs available on macOS 13+, rather than macOS 26's new glass API.
- Hover over the bottom ellipsis to grow it into a vertical glass capsule with Settings, Send feedback, Notes, Remote access, and Usage. The upper controls stay fixed. Hover activation follows the visible tab and controls, excluding the surrounding transparent window. Right-click the bottom capsule for pinning, placement, and New agent.
- Autosaved working-memory notes, optionally included in managed agent requests (up to 16,000 characters). Notes are never injected into external terminal sessions.
- Persistent feedback drafts, Markdown export, copy, and a reviewable email/GitHub draft using your configured destination. Reports include app/OS versions, not conversation history.
- Provider quota bars and reset times: Codex uses its supported app-server API; Claude uses an opt-in status-line feed. Connect Claude usage preserves the current status-line command and offers a restore action. Missing or old data is identified explicitly.
- Opt-in phone Inbox on the same Wi-Fi network, with a bundled Safari interface, credentialed QR connection, link revocation, question/choice validation and delivery receipts. Phone Send commits when the Mac consumes it; the Mac composer retains its two-second Undo interval. The bridge binds only to a selected private LAN interface. See [phone setup](docs/phone-setup.md).
- Hover over a panel button briefly to open Inbox, Agents, Chat, Settings, Feedback, Notes, Remote access, or Usage. Move into the panel to use it; click outside to dismiss. The first click on a hover-opened button focuses its panel, and the next closes it. Microphone and screenshot capture require a click.
- Floating edge toolbar that launches collapsed, expands on hover or click, and retracts when the pointer leaves, even with Inbox open. More → Keep toolbar expanded explicitly pins it. Both expanded and collapsed stacks show one dot per tracked working conversation or unanswered question, plus a brief signal for an agent that just finished. Amber means working, orange needs an answer and pulsing green means just finished. The same dot changes color for 20 seconds on completion, then disappears automatically; reviewing can dismiss it earlier. Old results never add dots, including after restart. Multiple agents using the same provider have separate dots. A gray dash means no active agents. Hover reports separate working, waiting and ready counts. The separate tray button has been removed; hover the dots to open Your agents, then select a conversation or Needs review. Grab the collapsed tab, status dots, or any toolbar button directly to move it; release to snap to either screen edge. A click still activates the control. More → Move to left/right edge is also available. Placement is saved.
- Click outside the main panel to dismiss it, or click its toolbar button again. Clicks inside, menus, sheets, recording, and screen capture are protected from click-away dismissal. Drafts stay in the Store when a panel closes.
- Conversation panels follow the active macOS Space by default; More → Show panels on all Spaces restores the everywhere-visible behavior.
- Inbox defaults to Needs review: unanswered questions and results you have not marked reviewed. Running and All filters keep activity and earlier conversations accessible. Mark reviewed clears attention without archiving, stopping tracking or losing drafts; new activity brings results back. Mark finished reviewed clears the results matching the current search, while questions stay visible. Use the conversation menu to mark a result as needing review again.
- Talk shows the conversation title, provider, project/worktree and latest user request above its history. Its searchable recipient picker previews each latest request and reply, so similarly named agents are distinguishable. Inbox and popouts keep the latest request visible; message bylines identify the provider and recorded time. An older answer is never presented as a reply to a newer unanswered request.
- Larger message text, stronger contrast, visible provider/worktree labels and an explicit reply destination. App notices appear in a separate banner. The window keeps its size when chats change; narrower windows stack the list above the detail. J/K follows the Inbox's section order.
- Agent picker grouped by Git project and worktree, including sessions inside checkout subfolders. Waiting agents come first, then working agents, then recent conversations; Inbox and recipient selection use the same priority. Busy projects keep inactive chats in an expandable group. Saved Codex names and Claude conversation titles are used when available.
- **Tracked worktrees** (Inbox filter button, Agents panel or Settings) lets you keep **Only this** checkout, Add/Remove known worktrees, Add folder, or Remove all. The first manual choice freezes the worktree selection, so new worktrees stay out until added. Remove individual conversations with the row's × or Conversation actions; add them back from the same tracking screen. Choices persist and apply to Inbox, agent panel, routing, remote Inbox and completion dots. Removing tracking preserves files, history, drafts and running processes.
- Drag any panel by its title or top grip; resize Inbox from the lower-right handle.
- Independently movable conversation panels (Conversation actions → Open floating conversation).
- Two-second reply delay; Escape cancels before delivery.
- Agents that finish turn their existing dots green and pulse for 20 seconds. Historical results remain accessible in Needs review without increasing the dot count. Reduce Motion keeps these indicators steady.
- Keyboard navigation: J/K, numeric answers, E to clear completed work.
- Talk panel with visible recipient selection and text input.
- Native Markdown in Talk, Inbox, floating conversations and Herdr chat: headings, emphasis, links, nested lists, read-only task checkboxes, quotes, tables and selectable code blocks with Copy. Code retains indentation; long code and tables scroll horizontally. Image Markdown appears as linked alt text. Drafts and stored messages retain their original text.
- A visible **Recommended recipient** card above Talk's composer updates as you type, with the conversation, provider and worktree; **Why?** expands the matching reason. On-device word matching keeps short follow-ups in the current chat and asks you to choose when matches are ambiguous. **Ask AI** compares richer conversation context through a separate, tool-free Claude Code invocation. **Use this** changes the recipient; sending remains explicit.
- Automatic observation of recent local Codex and Claude transcripts, with a persistent Settings toggle.
- Continue a saved Claude or Codex conversation with Send, preserving its native session ID and history. Fork remains an explicit option for a separate session.
- Microphone dictation through Apple's Speech framework; permission is requested only after pressing the microphone. Review the transcript before sending.
- Image attachments for managed Codex sessions.
- Interactive screen-region capture with an attachment preview, native macOS permission handling and Escape cancellation.
- Start local Codex and Claude Code sessions in a project folder. Output streams into the conversation; subsequent messages resume the session created by this app.
- Local bridge for arbitrary agents to publish statuses and block for a user answer.
- Persistent Inbox, duplicate event detection, stale-answer rejection, malformed-event quarantine.
- Saved per-conversation drafts shared with floating panels; Talk keeps a separate routing draft.
- Restore archived conversations from Settings.
- CLI discovery and version diagnostics for Finder-launched apps, including Homebrew, native, nvm, fnm, Volta and asdf installations.
- Optional Herdr session connection with live terminal snapshots, targeted tasks, interruption and explicit approval keys.
- Claude/Codex transcripts join a uniquely matching live Herdr conversation by native session ID. One card retains the saved title, readable history and draft, and replies go to the existing session. Ambiguous owners or conflicting drafts remain separate.
- Double-Control opens Talk by default; disable it in Settings → Shortcuts. Two short Control taps are required: other modifiers, intervening typing/clicks, held keys and slow taps cancel the gesture. The Open One no longer binds double-Option. Menu bar access and ⌘1 / ⌘2 for Inbox / Talk remain available while The Open One is focused.

Managed sessions use the installed `codex` or `claude` executable and its existing authentication/configuration. Command requests appear in Talk, Inbox and floating conversations with **Approve once**, **Deny**, and a two-second Undo interval. The Open One never sets permission-bypass flags or creates permanent allow rules. Active conversations owned by another terminal still require approval in that terminal (or the connected Herdr controls). Quitting The Open One terminates only processes it started. See [command approvals](docs/approvals.md).

## Continue existing sessions

New terminal conversations appear once the provider saves a transcript, normally after the first message. Opening **Agents** refreshes discovery, and its Refresh button scans on demand. Conversations updated within 24 hours stay visible alongside running work; only older inactive history collapses in busy projects. Opening an empty terminal alone does not create a tracked conversation. Discovery includes the standard Codex home, an explicitly configured `CODEX_HOME`, and Orca’s separate Codex runtime home. Continuing or forking a discovered chat uses its original home.

The app scans `~/.codex/sessions` and `~/.claude/projects` on a background queue every 15 seconds. `CODEX_HOME` and `CLAUDE_CONFIG_DIR` are respected. Up to 40 transcripts modified within 24 hours are shown. Reads are bounded to a metadata header and the latest 2 MiB; system/developer prompts, reasoning and tool-result blocks are excluded. Disable discovery or force a refresh in Settings.

An **Observed** card shows transcript-derived activity, not a verified live process state. Working records older than five minutes become **Last activity**. Send to an active Codex conversation without closing its terminal: The Open One uses the native `codex queue` command and preserves the session's original Codex home. This also works with `--no-daemon` terminals on the tested Codex 0.162.1, but those terminals poll their queue roughly every 10 seconds. For prompt pickup without that delay, launch future terminals with `codex` (shared-server mode). Selected/running/recently messaged chats refresh their known transcript files every half-second; discovering additional sessions remains a separate 15-second scan. A running agent handles the message through its queue; queue acceptance is not reported as turn completion. The two-second Undo window preserves the draft until delivery, and only a receipt for the exact thread clears it. Failures retain the draft and never automatically retry. When no Codex process owns the history, Send resumes its original session. Claude continuation still requires closing the original session. Waiting approvals, missing folders/CLIs, duplicate connected owners and changed recipients block sending. Lock files are never deleted. **Fork in Open One** creates a separate conversation from saved history in the same project folder.

## Connect live Herdr agents

In **Settings → Agent connections**, choose **Find sessions**, select a running local session, then **Connect**. The app does not connect to a session until you choose one. It remembers that choice for later launches and refreshes live metadata every eight seconds. Disconnect in Settings to stop polling it. Installing Herdr or moving existing terminal conversations into it is a separate user action.

Live Herdr cards with a matching local transcript show readable conversation history and a **Terminal** tab. Other cards show terminal output, with a timestamp and a Follow switch. Matching uses the provider and native session ID, never a title or folder. Existing popouts and drafts follow a joined card. Choose a ready agent and send a task, or use **Interrupt agent (Esc)** for a working agent. A blocked terminal automatically shows its approval/question: read the prompt and use the explicit **↑**, **↓**, **Return**, or **Escape** controls. Task submissions and approval keys have the same two-second Undo window. Image delivery through Herdr is not implemented.

Every command names the selected session and pane, and rechecks terminal/provider/native-session identity before mutations. A replacement native session is rejected when Herdr exposes its identity. There is still a small interval between checking and sending; replacements without a native session identifier cannot always be distinguished. Delivery failures are never retried automatically because a timeout does not establish whether a terminal received the input. Drafts remain available after an unconfirmed delivery.

The adapter follows the public [Herdr CLI](https://herdr.dev/docs/cli-reference/) and is covered by fixture-process integration tests. A live Herdr session has not yet been exercised in this environment.

Talk's immediate recommendations stay on device. AI routing is invoked only by **Ask AI**, directly on the recommendation card. It uses your Claude Code sign-in and sends the draft plus candidate names, project/worktree names, task titles, state, the selected conversation ID, the latest request (up to 800 characters), the latest message (up to 600), and six recent user/assistant messages (up to 400 each) with speaker and timestamp. The classifier has built-in tools and MCP tools disabled, runs in a dedicated directory and does not persist a session. It cannot send a task itself. Draft edits, changing recipients or leaving Talk cancel the pending suggestion; unknown recipients and malformed responses are rejected.

The camera menu offers **Capture screen region** and **Attach image file** in Talk and floating conversations. Capturing hides The Open One’s windows, uses the native region selector (Space selects a window), then restores the originating composer and previews the image. Escape preserves the existing draft. You can send an image with or without text to a managed Codex or Claude session; it also follows the first message into a new agent. Captures stay in the app’s local `captures` directory until you explicitly send them.

macOS Screen Recording permission is required. Capture errors offer a link to the permission settings. Quit and reopen The Open One after granting access. Local builds now reuse a per-user development certificate in a dedicated Keychain, so rebuilding preserves the app's identity. On a new Mac, complete the one-time setup with `python3 scripts/sign-app.py --trust-local-certificate 'dist/Open One.app'` after the first build creates the bundle. This trusts the certificate only for code signing in the user domain. Moving from an older ad hoc build requires refreshing its existing Screen Recording entry once. Keep `~/Library/Application Support/Open One/signing` across worktrees and clean builds; it contains private signing material and must not be committed or shared. Distribution builds should set `OPEN_ONE_SIGNING_IDENTITY` to their Apple-issued identity. Explicit `OPEN_ONE_SIGNING_IDENTITY=-` opts into ad hoc signing and loses permission continuity.

## Connect an agent

The CLI lives at `scripts/one`, and is also bundled in the app's `Contents/Resources/one`. Invoke with Python or make it executable and add its directory to your PATH.

```sh
python3 scripts/one register --agent build-1 --provider Codex
python3 scripts/one working --agent build-1 --text 'Building the pricing page'
python3 scripts/one ask --agent build-1 \
  --question 'Which layout?' --option 'Three tiers' --option 'One plan'
python3 scripts/one done --agent build-1 --text 'The pricing page is ready.'
```

`ask` prints the actual answer to stdout, and progress to stderr. `--json` includes the zero-based choice index, request ID and agent ID. Timeout exits 2 without supplying an answer; Ctrl-C exits 130. `--timeout` is in seconds and defaults to 3600.

Only one outstanding question per agent ID is supported. Use separate agent IDs for independent conversations. An external agent receives replies only while it has an open `ask`; arbitrary terminal injection is not implemented.

Data lives in `~/Library/Application Support/Open One/`. Set `OPEN_ONE_HOME` for an isolated test installation. The app and bridge must use the same directory. Event files are published by atomic rename; directories are owner-only. The bridge opens no network listener.

## Validation

See the [feature parity and release checklist](docs/feature-parity.md) for verified coverage and remaining gaps. Full feature parity is not yet achieved.

Additional packaged-app and desktop checks (macOS Accessibility access required for desktop input):

```sh
bash scripts/test-utility-service.sh
python3 scripts/e2e/packaged-app.py
bash scripts/test-native-ui.sh
```

The desktop runner uses disposable demo data and stops if the pointer leaves its targets. Leave mouse and keyboard idle during this run. Reports are saved under `.build/e2e/`.

```sh
bash scripts/test.sh
bash scripts/test-onboarding.sh
```

The native integration checks cover persistence, event replay, delayed delivery, undo, stale questions, and malformed input. Python tests exercise the real CLI subprocess and response protocol. `swift test` additionally runs the package's XCTest suite on a healthy SwiftPM installation.

## Fidelity and remaining scope

This is a functional local implementation, **not full parity** with the shipping One service. The toolbar and conversation treatment are based on the installed app and its public launch video. Version 0.4 replaces the combined sidebar layout with separate Inbox cards, Chat, and agent-picker surfaces based on direct inspection of One 0.3.14. Toolbar proportions, typography, neutral message blocks, page markers, and pill controls follow that reference. Conversation actions can open an independent floating conversation. Toolbar dots represent tracked working or waiting conversations and briefly signal completion; historical results do not add activity dots.

Not implemented: direct control or migration of terminals outside Herdr, generated recaps/next steps, One account/billing, a native iPhone app, push notifications, One-compatible device-key pairing or hosted relay, automatic remote agent installation, auto-update, and notarized distribution. Phone access uses a private connection link over local HTTP on the same trusted LAN. Titles use saved provider titles with observed request text as fallback. Voice still requires permission-granted hardware tests. Native region capture, preview, and real Claude image delivery have been verified on this Mac; real Codex image transport was separately checked with a generated color fixture. Live model execution requires the user's own CLI authentication. Managed Codex and Claude conversations and a context-preserving Codex resume were verified through the app UI; the automated suite uses fixture executables.

See the [local protocol](docs/protocol.md) for integration details and the [release checklist](docs/feature-parity.md) for remaining limitations.
