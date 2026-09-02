# Project Context

This repository is for an `EdgeTX` Lua widget running on `RadioMaster TX16 MK3`.

Do not assume `ETHOS` APIs, storage behavior, UI controls, or widget conventions here.

## Platform Rules

- Target platform: `EdgeTX`
- Main runtime file: `main.lua`
- Widget configuration helper: `config.lua`
- Widget install path on SD: `/WIDGETS/DBK_TX16KMK3/`
- Model images are loaded from `/IMAGES`, and only from the image configured for the model in EdgeTX (`model.getInfo().bitmap`); there is no lookup derived from the model name
- Audio assets are loaded from `/WIDGETS/DBK_TX16KMK3/audio`

## Configuration Rules

- Widget settings are declared in the `options` table in `main.lua`
- The radio firmware manages persistence for widget options
- This script does not manually save widget option values to a custom config file
- The displayed pilot name is read from `/WIDGETS/DBK_TX16KMK3_config.json`
- `battery_alert_pct` and `battery_alert_interval` are also read from `/WIDGETS/DBK_TX16KMK3_config.json`
- Script-created files under `/logs` are for flight logs, counters, and derived telemetry data only

## Implementation Guardrails

- Before changing UI or option types, verify the change matches `EdgeTX` widget option behavior
- Before discussing persistence, separate `widget options` from `script log files`
- Before proposing API changes, confirm the function exists in this repository's current `EdgeTX` usage pattern
- If a behavior looks like an `ETHOS` feature, treat that as a red flag and re-check the code first

## Current Known Example

- `BatAlertPct` remains a widget option, but its default value comes from `battery_alert_pct` in the JSON config
- Pilot name defaults to `Rotorflight` when `DBK_TX16KMK3_config.json` is missing, empty, or lacks `pilot_name`
- Battery alert defaults are `25` percent and `10` seconds when the JSON config lacks those keys
- Log files are written under `/WIDGETS/DBK_TX16KMK3/logs`
