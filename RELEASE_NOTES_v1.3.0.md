# v1.3.0 — Dial rewrite, Clean/Eco fix, card HACS-ready

This is a major release. The Lovelace card got a complete visual rewrite inspired by
the ESPHome/LVGL MirAIe reference, several protocol fields were corrected, and the
card is now structured for HACS publishing.

> **Heads-up**: the `acec` switch was mislabeled as "Eco Mode" in earlier versions.
> It is actually the **Clean** button in the MirAIe app. Migration notes below.

## 🎨 Lovelace card — full rewrite

- **New dial**: 80-tick ring (300° sweep, 60° gap at the bottom), mode-color halo
  with 5-stop radial gradient + pulsing breathing animation, cool/warm arc that
  splits at the room-temp position ("cool zone" → "warmer than room" zone), bright
  white room-temp needle with glow, small white-on-color draggable handle.
- **Drag-to-set**: grab the handle and drag along the ring; the handle follows
  smoothly. A single `set_temperature` service call fires on release, and the
  handle stays pinned for ~2 s to mask MQTT round-trip lag.
- **Responsive**: the whole dial scales via container-query units (cqw), keeping
  text, spacing, handle, halo and snowflakes in proportion. Works down to 180 px.
- **Pill row**: compact status pills — Energy / V-Swing / H-Swing / Converti8 /
  Features — each with its own popup. Converti8 pill tints warm-orange when
  engaged (non-Off). V/H-Swing pills show mini vent-direction glyphs inline.
- **Mode bar**: Off / Cool / Auto + `⋯` overflow for Heat / Fan / Dry. Active
  label is dark text on bright mode color for WCAG-AA contrast.
- **Boost badge**: pulsing rocket chip appears above the mode label when Powerful
  mode is on.
- **Snowflake particles**: 7 physics-independent flakes (each with 3 un-synced
  animations — fall / sway / spin) drift inside the dial during Cool mode.
- **Card header**: AC name on the left; status dot + last-seen + WiFi RSSI bars
  on the right. RSSI reads from the dedicated `sensor.kpr_<id>_rssi` entity.
- **Auto-derived entities**: the card can infer all 13 companion entity IDs from
  the climate entity's slug — a working card now needs only two YAML lines.
- **Graceful unavailable state**: clean "Offline" screen with wifi-off icon,
  gradient dial dimmed, controls hidden.
- **Version banner**: `KPR-MIRAIE-CARD v1.3.0` logs to console on load — easy
  to verify the browser loaded the right build after deploy.

## 🔧 Protocol corrections

- **`acec` = Clean, not Eco** (and `acem` = Eco). The MirAIe app's **Clean** and
  **Eco mode** buttons map to **different** MQTT fields. The integration now
  exposes both:
  - `switch.kpr_<id>_acec` — **Clean Mode** (was mislabeled as "Eco Mode")
  - `switch.kpr_<id>_acem` — **Eco Mode** (new, true Eco)
- **Converti8 supports 9 levels**, not 3: Off / 40 / 50 / 60 / 70 / 80 / 90 /
  FC (100) / HC (110). The select options were extended to match.

## 🚀 HACS-ready

- New `card/hacs.json` declaring the card as an HACS plugin (filename, name,
  render_readme).
- Card `package.json` version bumped to **1.3.0**.
- Integration `manifest.json` version bumped to **1.3.0**.
- Debug & narration logs removed from the bridge so log output stays clean in
  production.
- Dead CSS and unused helpers pruned.
- Lint + type + build all pass (`ruff`, `py_compile`, `rollup`).

## 🪛 Bridge improvements

- Unknown-field logger: any new MirAIe status field (not in the 21 known fields)
  is logged once so future protocol additions are easy to discover.
- `acem` added to the known field set.

## 📘 Docs

- New `card/README.md` with install steps, minimum YAML example, full YAML
  reference, screenshots for every mode and every popup, and the
  Clean vs Eco compatibility note.
- `CLAUDE.md` updated with the card component, protocol corrections, and CSS/SVG
  gotchas learned while building the card.
- Root `README.md` adds Contributors section with thanks to
  [Home Automation India](https://discord.gg/KfAjVkAG).

## Migration — `acec` "Eco" → Clean

If you have automations or dashboards referencing `switch.kpr_<id>_acec` as
"Eco Mode":

1. The **entity ID is unchanged** (history preserved). Automations still work —
   they just now toggle what the MirAIe app calls "Clean" (which is what that
   MQTT field actually did all along).
2. For **true Eco mode**, use the new `switch.kpr_<id>_acem` entity after
   restarting Home Assistant.
3. The custom card's `eco_entity` / `clean_entity` config keys now point at the
   correct underlying switches by default — if your YAML had
   `eco_entity: switch.kpr_<id>_acec`, move that value to `clean_entity` and
   either let `eco_entity` auto-derive or set it to `switch.kpr_<id>_acem`.

## Install / upgrade

**HACS (recommended)**:
1. Integration: custom repo, category **Integration** — update
2. Card: custom repo, category **Plugin** — install

**Manual**:
1. Copy `custom_components/kpr_miraie_mqtt/` to `/config/custom_components/`
2. Copy `card/dist/kpr-miraie-card.js` to `/config/www/`
3. Add as Lovelace resource (Type: JavaScript Module)
4. Hard-refresh browser

See `README.md` and `card/README.md` for full instructions.

## Thanks

A special thank-you to the
**[Home Automation India Discord](https://discord.gg/KfAjVkAG)** — testing,
real-world device diversity, and late-night debugging sessions from this
community made this project possible.
