# The Open One brand mark

The selected logo is a rounded penguin head with large near-black oval eyes, a bright white face, and a saturated yellow beak. The body is removed. Strong contrast was restored after review of the muted gray version, retaining the rounder contour. The canonical asset is [open-one-logo.png](../../Sources/OpenOne/Assets/open-one-logo.png), a 1254 × 1254 transparent PNG. See the [latest refinement prompt](penguin-head-contrast.md).

## Integration

- App icon: generated from the canonical PNG by `scripts/build-icons.sh` and bundled by `scripts/build.sh`.
- Menu bar: full-color 22-point image, retaining the white face and yellow beak in both appearances.
- Toolbar: the Talk control above the microphone, with its existing label and actions.
- Settings header, empty Inbox and empty Talk screen.
- Remote Inbox header and browser icon.
- README header.
- Landing-page header, footer, product mockups, source-build card, closing section, favicon, and Apple touch icon.
- Mobile pairing/conversation headers, app icon, Android adaptive/themed icons, launch screen, and web favicon.

## Keep every copy current

`Sources/OpenOne/Assets/open-one-logo.png` is the single design source. Run these from the repo root on macOS:

```sh
bash scripts/sync-brand-assets.sh
bash scripts/sync-brand-assets.sh --check
```

The first command copies the exact master to the landing page and mobile UI, and exports platform sizes using Core Graphics. It does not redraw or regenerate the mascot. The second command exits unsuccessfully if an export is missing or stale. `scripts/build-icons.sh` runs the sync automatically before macOS icon packaging; `scripts/build.sh` then bundles the updated images.

| Export | Purpose |
| --- | --- |
| `landing/assets/open-one-logo.png` | Exact canonical copy for all website logos |
| `mobile/assets/open-one-logo.png` | Exact canonical copy used by the shared mobile `BrandLogo` component |
| `mobile/assets/open-one.png` | Synchronized compatibility copy for earlier mobile consumers |
| `mobile/assets/icon.png` | 1024 px opaque white icon for iOS and legacy launchers |
| `mobile/assets/android-icon-foreground.png` | Transparent, padded 1024 px foreground to keep the complete head inside launcher masks |
| `mobile/assets/android-icon-monochrome.png` | Matching Android themed-icon alpha mask, with face cutouts so the eyes remain visible |
| `mobile/assets/splash-icon.png` | 1024 px transparent launch-screen logo |
| `*/favicon.png`, `Sources/OpenOne/Assets/open-one-favicon.png` | 64 px browser icons |
| `landing/assets/apple-touch-icon.png`, `Sources/OpenOne/Assets/open-one-touch-icon.png` | 180 px opaque Apple touch icons |

Mobile exports and the splash plugin follow the [Expo icon guide](https://docs.expo.dev/develop/user-interface/splash-screen-and-app-icon/) and [SDK 57 splash-screen configuration](https://docs.expo.dev/versions/v57.0.0/sdk/splash-screen/). Native launch screens and launcher icons require a new native mobile build to appear; Expo Go is not a release-build visual check.

Older images and briefs in this directory are design history, not production assets. Provider logos continue to identify Claude, OpenAI, and OpenCode; functional icons continue to identify their actions.

### Repository-wide verification

The landing-page and mobile masters are byte-for-byte copies of the selected logo. Verified opaque 1024 px mobile app icons, transparent Android foreground padding inside the launcher safe circle, and matching browser/touch exports. The desktop build, packaged asset comparison, and strict code-signature verification passed. Mobile TypeScript and web export passed; lint reported zero errors and one existing `react-hooks/exhaustive-deps` warning in `src/lib/store.tsx`. All 22 utility/remote tests passed, including all three branding routes and Host rejection. Native mobile launcher/splash appearance still requires a native preview build.

`BrandLogo.swift` loads the asset from the SwiftPM resource bundle or the standalone app bundle. Keep the image in original-color rendering mode, not template mode: treating its full alpha silhouette as a template would erase the face.

## UI design fit

The app uses native system typography, compact white utility glyphs, dark translucent glass, and restrained color. The penguin uses the same control surfaces, padding, hover behavior, and pressed animation as the adjacent microphone and camera. Its yellow beak remains a small identity accent; state colors remain on the status dots.

| Placement | Image box | Rationale |
| --- | --- | --- |
| Toolbar / empty Talk heading | 26 pt | The head's visible height is about 18 pt, matching the neighboring utility glyphs. The toolbar retains its existing 40 pt hit width and 32 pt row. |
| Menu bar | 22 pt | The visible head is about 19 × 15 pt, fitting the native status item. Original colors retain the facial features in both appearances. |
| Settings heading | 32 pt | Aligns the visible head with the existing 22 pt heading, without adding another line of text. |
| Empty Inbox | 48 pt | A restrained identity cue above the existing message and actions. |

No extra badge, tile, shadow, or background is added to the in-app mark. Surrounding glass comes from the existing `ToolbarCapsule`; native Reduce Motion and Reduce Transparency behavior remains in that component. Decorative marks beside text are hidden from accessibility, while the Talk control keeps its existing accessible action label.

Review follows the imagegen skill's logo-brand principles: simple scalable silhouette, balanced negative space, and no decorative flourishes. The Databricks dashboard design skill was reviewed but does not apply to this native macOS branding task.

Reproduce the visual check with `bash scripts/render-inbox.sh .build/branding-review --branding` after building. It renders the real toolbar components, light/dark menu-bar samples, empty Talk, and Settings without opening a visible window.

Reviewed output: [UI preview](ui-preview.png). Validation on 2026-10-10: app build passed; all 22 utility/remote tests passed, including PNG delivery and Host validation; packaged icon/resource lookup verified. The preview uses offscreen rendering, not a live interaction test. The macOS icon-packaging tool and localhost tests needed execution outside the sandbox.

## Generation

Head-only asset generated with the built-in image generation tool, using the approved penguin v3 on white as reference, then refined with rounder contours and [restored black-and-white contrast](penguin-head-contrast.md). Standard app-icon sizes are packaged with macOS `sips` and `iconutil`.

### Original head-only prompt

Use case: precise-object-edit.
Create the final head-only logo for The Open One from this exact approved penguin. Remove the entire small body, flippers, belly patch, and feet. Keep ONLY the existing oversized rounded penguin HEAD, large black oval eyes, white heart-shaped face, and warm yellow beak. Preserve the head's exact proportions, friendly expression, shapes and color relationships; close its bottom silhouette smoothly into the existing broad rounded chin. No neck or body remnants. Center the isolated head horizontally and vertically on a square transparent canvas. Head should occupy approximately 88 percent of canvas width; keep its existing wider-than-tall aspect ratio. Clean crisp logo edges, solid near-black head and eyes, solid white face, solid warm yellow beak. Flatten any residual texture into uniform fills, no shading or gradients. Genuinely transparent background outside the head. No white background, no app-icon square, no drop shadow, no text, no extra elements. The result must be immediately usable as a small app toolbar logo.
