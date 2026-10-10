# The Open One landing page

Local, buildless HTML/CSS/JavaScript. Start the preview from the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory landing
```

Open http://127.0.0.1:4173. The page stays local; nothing is published.

The visual direction is inspired by getone.one, with The Open One’s branding, a benefit-led headline, and explicit open-source positioning. The hero background is CSS artwork. DM Sans loads from Google Fonts, with system fallbacks. The GitHub button links to [https://github.com/OpenOnePenguins/theopenone](https://github.com/OpenOnePenguins/theopenone). The main build CTA leads to the local build commands and installation guide; a notarized release download is not included.

## Actual application UI

The product walkthrough uses PNG renders of the real `MainView` and `ToolbarView` SwiftUI components, not HTML imitations. Frames cover the collapsed/expanded toolbar, an Inbox question, the pending reply with Undo, a working conversation, and the completed result. Native source and demo fixtures supply the fonts, colors, spacing, icons, and two-pane layout.

Regenerate the native frames from the repository root:

```sh
bash work/landing-native/render.sh
```

The renderer uses a disposable demo Store and offscreen NSHostingViews. It does not open visible app windows, read user conversations, or contact agents. A build-local copy of Views.swift initializes the toolbar’s existing pinned state from an environment variable so both collapsed and expanded states can be captured. Application source is unchanged. The original PNG frames are in `assets/native/`.

The opening shows a fictional pricing-page draft with only the collapsed The Open One side button visible. The final chapter reveals its completed three-tier layout after reviewing the agent’s result. The sample has a peach palette, oversized mixed serif/sans typography, original inline SVG sculpture, and a dark featured Studio plan. There is no terminal window or terminal menu bar in any demo scene. Scrolling to the second chapter reveals the toolbar, opens Inbox, and answers an agent. The next chapters switch from Claude’s pricing-page conversation to Codex’s checkout work, then review finished work. The native app scene stays sticky beside the corresponding copy (above it on mobile). Scrolling back to a chapter replays its short interaction; rapid scrolling cancels the previous sequence. There are no playback controls. Mobile crops the native frames around the active conversation and screen edge, and zooms out for the sample pricing page. The phone feature describes the optional mobile Inbox and its same-Wi-Fi setup.

This is a presentation of the native app with a demonstration cursor, not a live app or editable web clone. System reduced-motion settings show a static frame for each chapter. Animations pause offscreen and in hidden tabs. The full-size UI link opens the original native screen.

## Verification

Native renderer compiled and produced all nine frames. JavaScript syntax and local asset/anchor checks passed. Browser review covers scroll chapter changes, native screen rendering, switching between agents, completion, and mobile layout without horizontal overflow. The setup command copy action and FAQs remain available.
