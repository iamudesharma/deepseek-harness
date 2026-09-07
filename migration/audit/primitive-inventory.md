# Primitive Inventory

Audited 2026-08-21 from `packages/client/ui-primitives/src/index.ts` (authoritative export list).

Corrects the legacy tracker defect where `component.ui-primitives.Markdown` pointed at `TerminalBlock.tsx`. The actual markdown surface is `MarkdownText` / `MessageText` / `CodeBlock` / `JsonBlock` under `packages/client/ui-primitives/src/markdown/`.

## Exported primitives

### Controls & feedback
| Export | Source | Flutter counterpart |
|---|---|---|
| `Button`, `ButtonVariant` | `packages/client/ui-primitives/src/Button.tsx` | `DshButton` |
| `Input` | `packages/client/ui-primitives/src/Input.tsx` | `DshInput` |
| `Pill` | `packages/client/ui-primitives/src/Pill.tsx` | `DshPill` |
| `Menu` + entry types | `packages/client/ui-primitives/src/Menu.tsx` | `DshMenu` (popup menu) |
| `HoverCard` | `packages/client/ui-primitives/src/HoverCard.tsx` | hover overlay |
| `Modal` | `packages/client/ui-primitives/src/Modal.tsx` | dialog route |
| `Tooltip`, `TooltipSide` | `packages/client/ui-primitives/src/Tooltip.tsx` | tooltip |
| `Toast` | `packages/client/ui-primitives/src/Toast.tsx` | snackbar |
| `DisclosureRow` | `packages/client/ui-primitives/src/DisclosureRow.tsx` | expansion tile |
| `StateDot`, `StateDotState` | `packages/client/ui-primitives/src/StateDot.tsx` | status dot |
| `OnboardingSurface` | `packages/client/ui-primitives/src/OnboardingSurface.tsx` | onboarding shell |
| `RiskConfirmation` | `packages/client/ui-primitives/src/RiskConfirmation.tsx` | confirm dialog |
| `ConnectionBanner` | `packages/client/ui-primitives/src/ConnectionBanner.tsx` | connectivity banner |

### Brand
| Export | Source |
|---|---|
| `FishLogo` | `packages/client/ui-primitives/src/FishLogo.tsx` |
| `BrandWordmark` | `packages/client/ui-primitives/src/BrandWordmark.tsx` |

### Blocks (tool output)
| Export | Source |
|---|---|
| `TerminalBlock`, `DEFAULT_TERMINAL_MAX_LINES` | `packages/client/ui-primitives/src/TerminalBlock.tsx` |
| `ReadBlock`, `ReadBlockLine` | `packages/client/ui-primitives/src/ReadBlock.tsx` |
| `DiffBlock`, `DiffHunk` | `packages/client/ui-primitives/src/DiffBlock.tsx` |
| `SearchBlock` (+ path/match props) | `packages/client/ui-primitives/src/SearchBlock.tsx` |
| `WebBlock` (+ search/fetch/source props) | `packages/client/ui-primitives/src/WebBlock.tsx` |

### Markdown & JSON
| Export | Source |
|---|---|
| `MarkdownText`, `MarkdownCodeLabels`, `MarkdownFileMentions` | `packages/client/ui-primitives/src/markdown/MarkdownText.tsx` |
| `MessageText` | `packages/client/ui-primitives/src/markdown/MessageText.tsx` |
| `CodeBlock` | `packages/client/ui-primitives/src/markdown/CodeBlock.tsx` |
| `JsonBlock` | `packages/client/ui-primitives/src/markdown/JsonBlock.tsx` |
| `extractMarkdownPlainText` | `packages/client/ui-primitives/src/markdown/plain-text.ts` |
| `JsonTree`, `JsonTreeLabels` | `packages/client/ui-primitives/src/JsonTree.tsx` |

### Utilities
| Export | Source |
|---|---|
| `writeClipboard` | `packages/client/ui-primitives/src/clipboard.ts` |
| `useAnchoredMaxHeight` | `packages/client/ui-primitives/src/useAnchoredMaxHeight.ts` |
| `useAnchoredPosition` | `packages/client/ui-primitives/src/useAnchoredPosition.ts` |
| `useDismissOnOutsidePointer` | `packages/client/ui-primitives/src/useDismissOnOutsidePointer.ts` |
| icon set (`export *`) | `packages/client/ui-primitives/src/icons/index.tsx` |

### Markdown internals (not exported, consumed by renderers)
`packages/client/ui-primitives/src/markdown/{parse,render,highlight,incremental,katex,mathCompatibility,cjkFriendlyStrong}.ts(x)` — Shiki highlighting, KaTeX math, incremental streaming parse.

## Legacy mapping corrections

- `component.ui-primitives.Markdown` → source is `packages/client/ui-primitives/src/markdown/MarkdownText.tsx` (NOT TerminalBlock).
- Streaming-partial markdown: `incremental.ts` exists and must be ported for live token rendering.
- File/session mentions: `MarkdownFileMentions` type — mention rendering inside markdown.

## Sources

- `packages/client/ui-primitives/src/index.ts`
- `packages/client/ui-primitives/src/markdown/MarkdownText.tsx`
- `packages/client/ui-primitives/src/markdown/MessageText.tsx`
- `packages/client/ui-primitives/src/markdown/CodeBlock.tsx`
- `packages/client/ui-primitives/src/markdown/JsonBlock.tsx`
- `packages/client/ui-primitives/src/markdown/plain-text.ts`
- `packages/client/ui-primitives/src/markdown/incremental.ts`
- `packages/client/ui-primitives/src/TerminalBlock.tsx`
- `packages/client/ui-primitives/src/ReadBlock.tsx`
- `packages/client/ui-primitives/src/DiffBlock.tsx`
- `packages/client/ui-primitives/src/SearchBlock.tsx`
- `packages/client/ui-primitives/src/WebBlock.tsx`
- `packages/client/ui-primitives/src/JsonTree.tsx`
- `packages/client/ui-primitives/src/clipboard.ts`
- `packages/client/ui-primitives/src/icons/index.tsx`
