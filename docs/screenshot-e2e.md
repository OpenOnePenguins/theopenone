# Screenshot delivery verification — 2026-10-10

## Reproduced failure

The camera returned a Screen Recording permission notice without opening the selector, despite the macOS switch being enabled. macOS TCC diagnostics explicitly reported a mismatch between the recorded code requirement and the current app's cdhash. The development build was signed ad hoc. Merely toggling the old permission entry did not repair it; resetting only `local.openone.app`'s ScreenCapture grant, enabling the current build, and restarting allowed `/usr/sbin/screencapture -i -x -t png …` to run.

## Changes

- Preserve the originating composer through capture and restore its window.
- Reveal Talk for toolbar capture from a non-composer panel.
- Keep the attachment when starting a new agent from an image composition.
- Add image preview, capture, and file attachment to floating conversations.
- Send image-only messages with the default request “Please review this screenshot.”
- Deliver Claude images as a PNG content block over structured stdin, following [Anthropic's streaming image input schema](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode). Codex receives the local image through `--image`.
- Surface capture errors instead of treating every status-1 exit as Escape.
- Recheck permission after the first request, expose the Settings link, and explain stale development signatures.
- Default local builds reuse a per-user certificate-backed identity in a dedicated Keychain. `OPEN_ONE_SIGNING_IDENTITY` can override it for distribution. The private key is non-extractable in the Keychain; setup files and credentials are owner-only. Certificate trust is scoped to the user-domain code-signing policy, with no TLS or system-root trust change. Signing serializes Keychain access and locks it afterward; missing saved identity material fails instead of silently rotating the key.

## Automated checks

`bash scripts/test.sh`: 353 native checks, 3 Python bridge tests, and 22 Python utility tests pass. The socket-based tests require execution outside the restricted sandbox.

`scripts/screenshot-tests.swift` verifies first-grant continuation, real error reporting, image-only staging, recipient isolation, Undo, first-message handoff, missing-file behavior, and the Store → AgentRunner → subprocess → conversation response path for both providers. The fixture process decodes Claude's stdin or opens Codex's image argument and validates the PNG signature and dimensions. These tests use generated pixels, not desktop capture or live models.

`python3 scripts/test-signing.py` compiles and signs two different native binaries. Their code hashes differ, their certificate-backed designated requirements remain identical, and the second binary passes verification against the first binary's requirement. Both also pass deep, strict signature verification. This test uses the configured local development Keychain and never launches the fixture app.

## Live provider check

`work/screenshot-e2e/live-image.swift` exercised the production `AgentRunner` against the authenticated Codex and Claude CLIs in a fresh local test project. A generated 400 × 200 PNG contains red on the left and blue on the right. Both providers returned the correct colors, with exit status 0:

- Codex: `Red, blue`
- Claude: `Red, Blue`

No private screenshot was sent in this check. The first generated fixture had an unsupported AppKit color space; it was corrected to explicit device RGB and visually inspected before this successful run. The reusable fixture uses the corrected colors.

## Desktop acceptance procedure

1. Build the app, then grant Screen Recording to that exact build and restart it.
2. Open a harmless public page. Click the toolbar camera, press Escape, and verify no attachment was added.
3. Capture a region containing only public page content. Verify the original composer returns with a readable preview.
4. Send it to a fresh managed conversation with “Describe only the attached image; do not use tools.” Verify the response describes the captured content.
5. Repeat from a floating conversation and verify Undo retains the attachment.


Multi-monitor scaling and window-mode capture require separate desktop checks. Local certificate setup is documented in [installation](installation.md).
