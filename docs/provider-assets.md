# Provider marks

These marks identify connected agent providers, separately from The Open One's own identity. Hovering the toolbar's status dots opens the Agents panel, where each row shows a separate status dot followed by its provider logo. Both the expanded toolbar and compact edge tab show activity dots. Conversation headers retain overlaid status badges, and Usage also shows provider marks. The source vector paths are unchanged.

- Claude and OpenAI: SVGs from [Simple Icons v14.0.0](https://github.com/simple-icons/simple-icons/tree/14.0.0/icons), distributed under [CC0-1.0](https://github.com/simple-icons/simple-icons/blob/14.0.0/LICENSE.md). Source files: `claude.svg` and `openai.svg`. Claude uses terracotta; OpenAI uses white on the dark interface.
- OpenCode: [provider SVG from the OpenCode project](https://github.com/anomalyco/opencode/blob/dev/packages/ui/src/assets/icons/provider/opencode.svg), retrieved 2026-10-07. Project [MIT license](https://github.com/anomalyco/opencode/blob/dev/LICENSE).
- Pi currently uses a typographic π rather than a bundled brand asset. Unknown providers retain a terminal symbol.

Brand marks remain the property of their respective owners. See [OpenAI's brand guidelines](https://openai.com/brand/). This app does not imply provider endorsement.

Native AppKit loads the bundled SVG representations directly, retaining resolution-independent rendering. Both the standalone app builder and Swift Package target include these resources. Asset files are cached once per process.
