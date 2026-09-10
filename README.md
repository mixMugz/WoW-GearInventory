# WoW-GearInventory

Information about your alts' gear.

A World of Warcraft addon that remembers what every character on the account has
equipped — per specialization — and answers two questions without logging anybody in:
what is each alt wearing, and would this item you are holding be an upgrade for any
of them.

Targets Retail (Interface 120100). Author: mixMugz.

## Installing

The addon itself is the **`GearInventory/`** subfolder of this repository. Copy that
folder — not the repository folder around it — into:

```text
World of Warcraft\_retail_\Interface\AddOns\
```

WoW requires an addon's folder to carry the same name as its `.toc` file. A folder named
`WoW-GearInventory` holding a `GearInventory.toc` will not load, and the client will not
say why.

## Repository layout

| Path | What |
| ---- | ---- |
| `GearInventory/` | The addon, exactly as the game loads it |
| `GearInventory/Addons/` | Core, database, events, main window, tooltip recommendations |
| `GearInventory/Options/` | Settings panels registered into Blizzard's own options |
| `GearInventory/Locales/` | Locale strings |
| `GearInventory/Libs/` | LibStub, LibDataBroker, LibDBIcon, CallbackHandler |
| `GearInventory/Textures/` | Addon art |
| `RELEASE_NOTES.md` | What changed, per build |
| `*.psd`, `*.png` | Art sources — never copied into the game |

## Item Level Coloring

Each item's ilvl in the gear list is colored by comparing it to the character's average item level (avgIlvl):

| Color | Condition                                    |
|-------|----------------------------------------------|
| Green | `item.ilvl >= avgIlvl` — at or above average |
| Red   | `item.ilvl < avgIlvl` — below average        |
| Gray  | Data not yet loaded (scanning in progress)   |

**Example:** avgIlvl = 244 → items at 246/250 are green, items at 240/237/243 are red.

> TODO: revisit coloring logic

## Upgrade recommendations

Hovering an item that can still change hands adds an `Upgrades` section to its tooltip,
listing every saved character it would improve and by how much. Two rules are worth
knowing, because both hide things on purpose:

- **Bind-on-pickup gear is never listed.** It cannot reach another character, so naming
  who it would suit is noise. Account-bound gear always is.
- **An item on the same upgrade track as the one worn is not offered**, however far ahead
  it is on item level. Both pieces share a ceiling, so the difference is only how many
  ranks each has been given — that is a bill in upgrade currency, not an upgrade.

A blue arrow with a track name marks a piece whose track outranks what the character
wears there. It sits alongside the item level difference rather than replacing it: a
better track means the lead will keep growing.
