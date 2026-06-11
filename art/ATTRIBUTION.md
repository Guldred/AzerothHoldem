# Art assets & licensing

All art bundled with Azeroth Hold'em is free to redistribute (public-domain / CC0).
Everything ships as **power-of-two, 32-bit uncompressed Targa (.tga)** — the only image
format WoW 3.3.5a can load (it cannot read PNG/JPG). Textures are referenced from Lua by
in-game path (`Interface\AddOns\AzerothHoldem\art\<file>.tga`); they are **not** listed in
the `.toc`.

| File         | Size (px) | What it is            | Source / license |
|--------------|-----------|-----------------------|------------------|
| `cards.tga`  | 1024×1024 | 52 card faces + back  | **Faces:** Byron Knoll *Vector Playing Cards* — **public domain**. **Back:** generated here (CC0). |
| `felt.tga`   | 512×512   | Green felt (fallback) | Generated here with ImageMagick — **CC0**. |
| `chips.tga`  | 128×128   | Chip stack (the pot)  | Generated here with ImageMagick — **CC0**. |
| `dealer.tga` | 64×64     | Dealer button         | Generated here with ImageMagick — **CC0**. |
| `table.tga`  | 1024×1024 | Stadium poker table in the TOP HALF (v 0–0.5): wood rail, felt, board inlay, stencil | Generated here with ImageMagick — **CC0**. |
| `btns.tga`   | 128×128   | Button states in 32px rows: normal / hover (additive) / pushed / disabled | Generated here with ImageMagick — **CC0**. |
| `plates.tga` | 128×128   | Seat nameplate (top half) + active-turn halo (bottom half) | Generated here with ImageMagick — **CC0**. |
| `panelbg.tga`| 256×256   | Panel cloth backdrop  | Generated here with ImageMagick — **CC0**. |

> **Square-texture rule (learned in-client):** WoW 3.3.5a rendered our non-square TGAs
> (1024×512, 128×32, 128×64) as black. Every texture must be **square** pow2; rectangular
> content lives in atlas regions addressed via `SetTexCoord`.

## Card faces — Byron Knoll "Vector Playing Cards" (public domain)

The 52 face sprites are rasterized from Byron Knoll's vector playing-card SVGs, which their
author released into the **public domain**.

- Original: Byron Knoll, *vector-playing-cards* — http://www.byronknoll.com/ /
  https://code.google.com/p/vector-playing-cards/ (public domain)
- Mirror used at build time: https://github.com/notpeter/Vector-Playing-Cards
  (`cards-svg/`), released "into the public domain or optionally licensed under the WTFPL".

No attribution is legally required for public-domain work; it is recorded here for provenance.

## Generated assets (card back, felt, chips, dealer button)

These were created from scratch for this project with ImageMagick and are released under
**CC0 1.0** (public domain dedication). See the build scripts for the exact recipes. (The
dealer button's "D" is rasterized with whatever bold system font ImageMagick resolves —
typeface *designs* aren't copyrightable in most jurisdictions and the rendered glyph output
is dedicated CC0 along with the rest of the image.)

## Build / regenerate

Both scripts require ImageMagick v7 (`magick`); the card script also needs `curl` and
`rsvg-convert`. They write the `.tga` files in this directory.

```sh
bash art/build_cards.sh      # downloads the PD SVGs, builds the 1024² card atlas
bash art/build_textures.sh   # generates felt / chips / dealer button
bash art/build_ui.sh         # generates the stadium table, buttons, plates, glow, panel cloth
```

`build_ui.sh` encodes a layout contract with `src/ui/Table.lua` (the table art maps to a
544×292 display area; the board inlay centers 28 px above the felt center where the
community cards render) — change those offsets together.

### Card atlas layout (the contract `src/ui/Widgets.lua` relies on)

A 13-column × 5-row grid packed into the **top-left** of a 1024×1024 canvas, cell **78×114**:

- **column** = `rank0 = floor(id/4)` — `0=Two … 12=Ace` (Two on the left)
- **row**    = `suit  = id % 4`      — `0=clubs, 1=diamonds, 2=hearts, 3=spades`
- the **card back** is at row 4, column 0

`Widgets.lua` (`W.ART.cell`) hard-codes `{w=78, h=114, atlas=1024}`; if you change the cell
size in `build_cards.sh`, change it there too. The id→cell mapping was verified end-to-end by
decoding the shipped `cards.tga` and confirming all 52 cells match the canonical `cardName`.

## In-client checks (cannot be verified outside WoW)

- **Button skin.** `W.button` overrides the `UIPanelButtonTemplate` textures via
  `SetNormalTexture`/`SetHighlightTexture`/`SetPushedTexture`. Confirm hover/press states
  read correctly and that very small buttons (the panel "X", the Min/Pot/All-in
  quick-fills) don't squash the gold trim unpleasantly — if they do, the skin can be
  limited to wider buttons in `W.button`.
- **Table mapping.** The stadium table art replaces the felt rectangle; community cards
  should sit inside the board inlay and seat plates ride the rail. If the inlay is offset,
  the contract values are in `art/build_ui.sh` + `Table.lua` (`544x292`, board at −28).

- **Animation / visibility.** With `W.ART`/`W.ANIM` on, the table fades in and cards
  deal/flip in (they prime to alpha 0 and rely on the shared animator frame's OnUpdate
  to become visible). Open a table once and confirm: the window fades in, community
  cards slide in left-to-right as each street turns, your hole cards turn face-up, and
  the pot chip swells when the pot grows. If anything is stuck invisible, set
  `W.ANIM.enabled = false` (instant rendering, bypasses the alpha-0 priming).
- **Orientation.** ImageMagick can emit a *bottom-up* TGA. If the cards/back render
  upside-down or with the suit rows reversed in the client, flip `W.ART.flipV = true` in
  `Widgets.lua` (it samples each cell vertically mirrored — a no-rebuild fix), or re-export
  the atlas flipped: `magick /tmp/azh_cards/atlas.png -flip -type TrueColorAlpha -depth 8 -compress none art/cards.tga`.
  The packed atlas PNG was confirmed upright before conversion, so any flip is purely the
  TGA origin bit — `flipV` corrects it.
- **Missing-art fallback.** Every visual probes its texture once via `W.artOK()` and falls
  back to its built-in/text rendering (text cards, solid felt, gold-coin pot, "D" label).
  The probe is best-effort: it auto-detects a missing file on clients whose `GetTexture()`
  nils out after a failed load, but because some 3.3.5a clients echo the path (file loading
  is deferred to first render) the probe biases to "present" for the files we ship. For a
  guaranteed, deterministic fallback regardless of client semantics, set `W.ART.enabled =
  false` (forces *all* art off); `W.ART.useCardArt = false` forces just the text cards.
