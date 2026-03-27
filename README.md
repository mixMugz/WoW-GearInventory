# WoW-GearInventory
Information about your alts' gear

## Item Level Coloring

Each item's ilvl in the gear list is colored by comparing it to the character's average item level (avgIlvl):

| Color | Condition                                    |
|-------|----------------------------------------------|
| Green | `item.ilvl >= avgIlvl` — at or above average |
| Red   | `item.ilvl < avgIlvl` — below average        |
| Gray  | Data not yet loaded (scanning in progress)   |

**Example:** avgIlvl = 244 → items at 246/250 are green, items at 240/237/243 are red.

> TODO: revisit coloring logic
