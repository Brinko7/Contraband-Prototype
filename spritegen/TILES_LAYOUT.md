# Tile Sheet Layout

Three environment-tile sheets, one per floor theme. All sheets share the **same
layout**. Cells are 16px on a 16px world grid. Sheet image size: **128 × 80 px**.

Light source: upper-left. Floors tile seamlessly with themselves and each other
(shared joint grid + tileable value-noise grain). Wall faces tile horizontally.

## Files

- `sprites/tiles_sandstone.png` — warm tan flagstone (PAL['sand'])
- `sprites/tiles_slate.png` — cool blue-grey slate (PAL['slate'])
- `sprites/tiles_obsidian.png` — dark violet obsidian, faint arcane veins (PAL['obsidian'])

## Piece rects (x, y, w, h) — identical across all three files

### Floor variants — all 16×16, tile seamlessly
| Piece          | Rect (x,y,w,h) | Purpose |
|----------------|----------------|---------|
| floor_plain_a  | 0,  0, 16, 16  | Primary floor, slightly lighter value |
| floor_plain_b  | 16, 0, 16, 16  | Secondary floor, slightly darker value (mix for variety) |
| floor_cracked  | 32, 0, 16, 16  | Branching crack; crack wraps across all 4 edges |
| floor_mossy    | 48, 0, 16, 16  | Patchy green moss collecting in joints |
| floor_inlay    | 64, 0, 16, 16  | Arcane diamond + rune inlay (glows brightest on obsidian) |
| floor_glint    | 80, 0, 16, 16  | Calm floor with a few mineral specular flecks |

### Wall pieces
| Piece       | Rect (x,y,w,h) | Purpose |
|-------------|----------------|---------|
| wall_cap    | 96,  0, 16, 16 | Flat lit TOP surface of a wall block (sits on the wall cell) |
| corner_cap  | 112, 0, 16, 16 | Wall cap variant for an exposed upper-left corner (extra rounding) |
| base_shadow | 0,  16, 16, 16 | Semi-transparent shadow strip; draw on the floor cell SOUTH of a wall face. Top rows ~150 alpha fading to 0 downward. Tiles horizontally. |
| wall_face   | 0,  32, 16, 48 | Tall hanging brick FRONT FACE. Hangs DOWNWARD from the wall cell, covering the cell to the south. Running-bond brick courses (6px tall), mortar lines, per-brick value variation, top catch-light, bottom darkening. Tiles horizontally. Obsidian variant has vertical arcane veins. |

## Assembly notes (2.5D walls)
For a wall at cell (cx, cy):
1. Draw `wall_cap` (or `corner_cap` for exposed corners) at the wall cell.
2. Draw `wall_face` (16×48) with its TOP-LEFT anchored at the wall cell's
   top-left + (0, +16): the face's first 16px overlaps nothing visible behind
   the cap-below; it hangs down to cover the next ~3 cells to the south.
   In practice the cap is at row Y and the face top aligns at row Y so the face
   reads as the front of the same block descending below the cap.
3. Optionally composite `base_shadow` over the floor cell directly south of the
   face's bottom for a grounded contact shadow.

## Regenerate
From project root: `python3 spritegen/gen_tiles.py`
Previews (6×) are written to `spritegen/previews/`:
- `sheet_<theme>.png` — full sheet
- `tile3x3_<theme>_<variant>.png` — 3×3 seamless-tiling test per floor variant
- `wallmock_<theme>.png` — assembled cap + face + floor mockup
