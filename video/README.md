# The Open One launch film

A 39-second launch film for The Open One, modeled on the structure of One's launch film and rebuilt with original visuals. It is rendered in [Remotion](https://www.remotion.dev/) at 60 fps.

```sh
npm install
npm run studio      # live preview
npm run render      # out/open-one-launch.mp4  (1920×1080, ~40 s)
```

Audio is from ElevenLabs: the score comes from Music and the UI sounds from Sound Effects. `scripts/elevenlabs.sh score|sfx|footage` regenerates it with `ELEVENLABS_API_KEY`. Music takes are not deterministic, so if you replace `public/score.mp3`, re-measure its beat grid and update `src/timeline.ts`.

## Reference: One's launch on X (researched 2026-10-10)

Note: `theone.one` is unrelated (an iframe to an S3 bucket). The product is One by kyzo (@ky__zo), at getone.one.

| Post | Date | Video | Reach |
| --- | --- | --- | --- |
| [Soft launch](https://x.com/ky__zo/status/2097838259762340028): "introducing One — a toolbar i made for myself to talk with my agents" | 2026-09-10 | 53 s silent raw screen recording on a white desktop, real use (voice → routed to an agent, screenshot capture, agent windows) | 3.5K views, 72 likes |
| [Launch](https://x.com/ky__zo/status/2107549434280284460): "meet One, the new way for talking with your agents" + 3 bullets (inbox, voice, iPhone) | 2026-10-06 | 31.5 s, 4K60, motion-designed, music only (no voiceover) | 642K views, 2.8K likes, 4.0K bookmarks, 234 replies |

The polished cut performed about 180 times better than the raw demo. Replies praised the UX and the sound: "my ears liked that video", "bro is a ux genius".

The launch film's structure, which this film follows beat for beat:

1. **0–2.5 s.** Four 0.5 s cinematic stock shots, one agent wordmark each (Claude Code, Codex, OpenCode, Grok).
2. **2.5–4.5 s.** White grid. Agent chips and `you@mac:~$ claude` snippets, with blue dots flying to the screen edge.
3. **4.5–6 s.** "Every agent. One inbox."
4. **6–7 s.** Edge toolbar with "Agent needs you" and the mascot.
5. **7–11 s.** "Answer in a keystroke." A tilted 3D question card, keycaps (⌥⌥, 1, K, 2, space, ↵), and "Answer sent · esc to undo".
6. **11–14 s.** "Press to talk." A pill composer types a request, then "Sent to @codex-9 · remote vps".
7. **14–17 s.** "See every agent. On your Mac and your VPS."
8. **17–20 s.** Dark scene: "Something's still waiting." An iPhone notification leads to "Take it with you anywhere."
9. **20–23 s.** Empty Inbox: "Nothing needs you. Suspiciously quiet."
10. **23–31 s.** Mascot crossfades into golden-hour footage. Logo, "Never keep an agent waiting.", and the URL.

Its style: SF Pro Display, heavy and tightly tracked; off-white paper backgrounds; dark glass UI; one accent color; a hard cut on every beat; music driving everything.

## The Open One's version

The structure and pacing are the same, but the content and claims belong to The Open One, limited to features the README documents:

| Time | Scene | Notes |
| --- | --- | --- |
| 0–2.1 s | A penguin wading into the surf on a sunset beach: **Claude Code** | Score bar hit 1 |
| 2.1–4.1 s | A penguin at a Mediterranean infinity pool: **Codex** | Hit 2 |
| 4.1–6.1 s | A line of penguins down a whitewashed Greek street: penguin logo + **Introducing The Open One** | Hit 3 |
| 6.1–9.6 s | Grid, chips, `one ask` bridge: "Every agent." then **"One inbox."** on the drop (8.07 s) | Beak-yellow dots replace One's blue |
| 9.6–12.6 s | "Know the moment an agent needs you." The edge tab expands into the real toolbar (activity dots · penguin chat, mic, screenshot · more) with its status label "2 working · 1 need an answer" | |
| 12.6–18.6 s | "Just type your answer." Space focuses the reply, type, ↵ sends ("Sending to Settings page… Undo esc"); K moves to the next card, E clears it | Keys match `App.swift`: K next, J previous, E review/archive |
| 18.6–23.6 s | "Chat with any agent." ⌃⌃ opens the chat; while typing, The Open One suggests "To codex-api"; ↵ sends with the 2-second undo | Recipient is reviewed before sending (`Views.swift`) |
| 23.6–28.1 s | "See every agent. Grouped by project and worktree." Includes a remote agent | |
| 28.1–32.5 s | Dark: "Away from your Mac?" A typed reply on the Remote Inbox, "Waiting for your Mac…" | Opt-in, on the same Wi-Fi network |
| 32.5–34.5 s | **"Open source."** Free and open source · Local by default · Uses the CLIs you already have | Unlike One, which is subscription or lifetime |
| 34.5–39 s | Penguin pop, then a penguin in a Provence lavender field: **The Open One**, "The open-source inbox for your coding agents." | On the score's final chord |

Every cut is placed on the score's measured beat grid (librosa: 117.5 BPM detected, fitted period 0.4995 s, first beat at 0.074 s); see `src/timeline.ts`. The UI is vector-recreated from the app's own colors (`Sources/OpenOne/Views.swift`), logo, and provider marks.

### Footage

The running joke: penguins somewhere warm, shot deadpan and cinematic. Each background in `public/footage/` (`beach`, `pool`, `village`, `lavender`) started as a 2752×1536 Nano Banana Pro still from Higgsfield (`<name>.jpg`). Each still was then animated into a 1080p Veo 3.1 clip (`<name>.mp4`: 8 s beach and lavender clips, 4 s pool and village clips) through ElevenLabs Image & Video, using the still as the start frame. The film plays the `.mp4` when one exists, otherwise it animates the `.jpg`, and otherwise it falls back to the procedural polar scenes in `src/Shader.tsx`.

## Suggested post

> meet The Open One — the open-source inbox for your coding agents
>
> • every Claude Code and Codex agent (or your own, via the bridge) in one inbox
> • type your answer, or double-tap Control to chat
> • reply from your phone
>
> native macOS. local by default. free.

Repository: [https://github.com/OpenOnePenguins/theopenone](https://github.com/OpenOnePenguins/theopenone). Installation and onboarding instructions are included there.
