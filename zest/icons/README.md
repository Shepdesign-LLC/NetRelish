# Zest ecosystem icons

Four app icons in the NetRelish material language: the squircle, steel hardware, and a glossy citrus material — a different fruit per tool, with grated-zest flecks as the family signature.

| Icon | Fruit | Hardware | Meaning |
|---|---|---|---|
| Zest (studio) | Lemon | Dial | The instrument you set everything else by; the brightest fruit |
| ZestMail | Orange | Envelope | The classic; warmth going out |
| Zest MD | Lime | Page | Closest to the parent green; the reading surface |
| ZestImage | Grapefruit | Frame | The showy one; the picture is the fruit |

## Folders
- `svg/` — full icons, 100×100 viewBox, layered groups `layer-background`, `layer-hardware`, `layer-fruit`, `layer-highlight`
- `layers/<icon>/` — one SVG per layer, for Apple Icon Composer (import each as a layer; give `fruit` the most lift and specular, `background` none)
- `png/` — 1024 · 512 · 256 · 128 · 64 · 32
- `mono/` — single-color glyphs (the flat Segment, rotated per tool) for tinted / monochrome icon modes and favicons
- `fruits.json` — each fruit's peel, flesh, pith, juice, background, glow, and the UI accent pair (`accent`, `accentInk`) derived from it. Where a tool draws indicators on light user content (ZestMail's canvas), `accentInd` is the darker accent that clears WCAG 3:1 there — pair it with a light halo on unknown surfaces.
- `dock-light.png`, `dock-dark.png` — the family in a dock beside the NetRelish mark

## Rules
- Never recolor a fruit or swap fruits between tools. The fruit is the tool.
- Steel is shared with NetRelish exactly (#CBD2DA→#848D99, #59626D→#39404A). Don't warm or cool it.
- The flecks are the signature. Keep 4–6, small, near the fruit, never on the hardware's glossy face.
- One drip minimum, three maximum.
