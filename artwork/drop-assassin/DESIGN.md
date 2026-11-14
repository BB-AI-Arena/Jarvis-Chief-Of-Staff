# Drop Assassin

Prepared for Brandon. A proposal. This repository had no Drop Assassin brief, script, or artwork when this was made.

## Direction

**Void Drop.** Recommended.

The room is already dark. A lime slit opens, point-down, and the figure is on the ground. One knee. Visor locked. No second pass.

Obsidian suit, acid-lime fall, magenta lock. Same night as Jarvis, a different animal: Jarvis wears porcelain and cyan. This one wears void and a single slit.

### Alternates, not built

1. **Porcelain Ghost.** A white helmet in the Jarvis family, one falling red tick instead of cyan eyes. Quieter, and it disappears beside Jarvis.
2. **Signal only.** The mark and a monospace lock-line, no figure. Smaller, and it has no one to remember.

## The mark

A lime needle through a magenta bar. The needle is the fall. The bar is the visor, locked.

- `mark.svg` — lime `#D6FF3F`, magenta `#FF2D7B`
- `mark-mono.svg` — `currentColor`, one ink
- `icon.svg` and `icon-1024.png` — the mark centered on void. Corners are square on purpose. The platform masks the icon. Do not bake a squircle into the file.

The bar is straight. On the helmet plates the slit bends because the glass is curved. Same gesture, two drawings.

The suit carries a small lime chevron on the chest. That is costume. It is not a second logo.

The mark still reads at 32px. Under 24px the needle tightens toward a plus. Use the wordmark at that size.

This mark does not use a hood, a cape, a hidden blade, an eagle, or a creed. Those belong to other games.

## Colour

| Name | Hex | Use |
| :--- | :--- | :--- |
| Void | `#07080C` | Ground |
| Armor | `#14161E` | Panels, the seam between a plate and a type block |
| Strike | `#D6FF3F` | The fall, the name DROP, the visor slit |
| Lock | `#FF2D7B` | The bar, temple and joint lights |
| Porcelain | `#F4F1EA` | ASSASSIN, and any sentence that has to be read |
| Steel | `#8B95A8` | Meta only. Never the name. |

Contrast below was calculated from these hex values in this session, using WCAG relative luminance. It is not a certified audit.

| Pair | Ratio | Rule |
| :--- | :--- | :--- |
| Strike on void | 17.38:1 | Yes |
| Porcelain on void | 17.75:1 | Yes |
| Steel on void | 6.64:1 | Yes, for meta |
| Lock on void | 5.64:1 | Yes, including small text |
| Lock on armor | 5.08:1 | Yes, including small text |
| Strike on porcelain | 1.02:1 | Never |
| Lock on porcelain | 3.15:1 | Large shapes only. Not text. |
| Void on strike | 17.38:1 | Yes, if type ever sits on lime |
| Void on lock | 5.64:1 | Yes |

On a light ground, the droplet is void and both words are void. Magenta stays in the bar, large. See `wordmark-on-light.svg`.

## Type

- **Name.** Inter Bold. DROP is tight, about −0.045em, in Strike. ASSASSIN sits under it, smaller, tracked about +0.22 to +0.26em, in Porcelain.
- **Lock-lines.** JetBrains Mono. The tagline, the hex, the timings.

`wordmark.svg`, `lockup.svg`, and `lockup-stack.svg` are outlined. They do not need the fonts installed.

## Voice

Cold. Short. Present tense. Never cute, never a mission statement.

- “One drop. No second pass.”
- “Land it once.”
- “The room goes quiet. Then it’s done.”

## Motion

No bounce. A drop lands. It does not giggle.

- **Fall.** 280ms, `cubic-bezier(0.2, 0.8, 0.2, 1)`, about 28px. The needle arrives.
- **Lock.** 90ms, starting at 220ms. The bar snaps from Strike to Lock and holds.
- **Idle.** The helmet slit breathes, opacity 0.72 to 1, over 2.4s. On lock, the slit takes the same 90ms snap to magenta.
- **Reduced motion.** Show the settled frame. No fall, no snap. The preview page does this when the system asks for it.

## Plates

Generated this session, then reviewed. These are the native sizes. They are not print masters.

| File | Pixels | What it is |
| :--- | :--- | :--- |
| `character-bust.jpg` | 864×1152 | Helmet reference. Temple discs, lime slit, chest chevron. |
| `character-wide.jpg` | 1280×720 | Crouch on the right, empty void on the left. |
| `character-landing.jpg` | 864×1152 | The action plate. One knee, one hand planted. |
| `character-helmet.jpg` | 1024×1024 | Square helmet. |
| `poster-wide.png` | 1280×720 | Wide plate with the stacked lockup. |
| `poster-portrait.png` | 1720×1440 | Lockup panel beside the landing plate. |
| `style-guide.png` | 1600×2311 | The board above, on one sheet. |

Helmet reference is the bust, the wide plate, and the square helmet: round temple discs, one horizontal lime slit. On the landing plate the temple lights rendered as vertical streaks, and the joints carry rings. Keep the discs. Do not average the two.

Close crops of the landing plate and the wide plate showed gloved hands with a thumb and four fingers, and no extra limb. That is a visual review of those crops, not a measurement.

## See it

Open `preview.html` in a browser. It loads the files next to it. No server, no build.

The files live in `artwork/drop-assassin/` and not in `Resources/`. `scripts/build.sh` copies all of `Resources/` into the app, and this proposal is not part of the app.

## Not verified

- Not opened in the macOS app. This session did not build or run Jarvis.
- Not printed.
- Not shown to anyone else.
- The contrast figures are calculations from the hex values, not a screen-reader or device pass.
- The landing plate’s temple lights do not match the helmet reference. Called out above. Left as the action plate.
