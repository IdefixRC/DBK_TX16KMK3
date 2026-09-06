# Worklog

## 2026-09-06 — Performance pass and widget settings rework (v1.0.8)

Released as [v1.0.8](https://github.com/IdefixRC/DBK_TX16KMK3/releases/tag/v1.0.8).

### What we did

Five commits, kept separate so each is independently revertable:

| Commit | Change |
|---|---|
| `c86a043` | Gauge colour bands drawn with `lcd.drawAnnulus` instead of six stacked `lcd.drawArc` calls |
| `003468a` | Hot `lcd`/`math`/`string` calls aliased as locals; 13 global functions made local |
| `899f3db` | Per-frame allocations cut; `value_min_max`/`field_id` flattened into five arrays |
| `3553ad2` | Widget options given user-facing names |
| `895a934` | Options reordered; defaults fallback and stale-file detection; VERSION → v1.0.8 |

### Measured results

| | Before | After |
|---|---|---|
| LCD primitive calls per frame | 467 | 345 |
| `drawArc` per frame | 148 | 0 |
| Garbage per frame, idle | 431 B | 128 B |
| Garbage per frame, in flight | 566 B | 326 B |
| `getValue` calls per frame | 19 | 19 (unchanged) |

The temperature gauge was 43% of the frame on its own, and the seven-segment digits
another 39%. The gauge was the win; the digit rectangles are irreducible without
changing how it looks.

### Decisions and why

**Refresh rate left alone.** The 10 FPS gate at `main.lua:1174` is Vagner's from v1.0.6
and stays. Telemetry is still sampled every frame, min/max tracked every frame, and
nothing drawn is cached on a value. The optimisation buys headroom, not a slower screen.

**Three of the original suggestions were withdrawn after checking them.**
- Dropping the dead duplicate `crsf_field[16]` ("Tmcu") would have shifted indices 17 and
  18, which are referenced by literal number. Bank number would have silently read the
  ARMD sensor. Not worth one `getValue` per frame.
- Resolving `"Arming Disable"` at `create()` would have broken late sensor discovery.
  CRSF sensors appear as telemetry arrives, so the per-frame string lookup is
  load-bearing for the normal case of powering the model after the radio.
- Digit segment bitmasks needed `bit32`, which EdgeTX's Lua 5.2 does not reliably ship.

**Option names.** `SquareColor` named neither a square nor the thing it coloured.
`Arm Switch` was considered and rejected in favour of `Log Switch`: the widget reads
armed state from the `ARM` telemetry sensor, so naming a setting after arming invited
pilots to assign their arm switch to something that only pauses the flight log.

**Option order** puts what changes between flights first and the switch assignment last.
This forces a one-time settings reset for upgraders — accepted deliberately, warned about
in the release notes.

### Platform facts worth remembering

- **EdgeTX stores widget option values by position, not by name.** Renaming an option is
  free; reordering means a saved model file no longer lines up. The order *is* the
  storage key.
- **A Lua widget cannot write its own options.** The table passed to `create`/`update` is
  a snapshot and is never read back, so the settings screen cannot be repaired from the
  script. Only saving the settings, or deleting and re-adding the widget, fixes the menu.
- **A colour option of `0` is black**, which draws every label and value invisible against
  the background. This is what "all values empty" looked like on the radio after the
  reorder. A type guard is not enough — `0` is a perfectly good number.
- `lcd.drawAnnulus` and `lcd.drawArc` share the same angle convention (0 = north,
  clockwise), so one can replace a stack of the other.

### How it was verified

No radio in the loop, so a stub EdgeTX environment was built on `lupa` (pip-installable
Lua for Python). It loads `main.lua` with a fake `lcd`, `getValue`, `model`, `io` and so
on, runs scripted flights, and records every draw call, audio cue, haptic, LED write and
file write.

The core check was diffing that trace between the old and new script: **34,687 non-arc
draw calls, byte-identical in order and arguments**, plus 272 identical side effects,
across a scenario covering arm/disarm, all nine governor states, bank changes, disable
flags, the low-battery threshold and the hold switch.

It caught two real bugs before they reached the radio: a stale model file handing
`getSwitchValue` a string (crash on first frame), and the black-text problem above. Worth
rebuilding if this work is picked up again — it is the only way to regression-test this
widget without a flash cycle. It was not committed; see open items.

### What the Log Switch actually does

Investigated in detail because the name never described it. While the assigned switch is
engaged, the widget stops updating the per-flight min/max that go into the flight log,
and the padlock turns red. **Nothing on the display freezes** — the only visible
difference across 120 frames is the padlock bitmap.

Its purpose is keeping readings that are not real out of the log. Four frames of lost
telemetry is enough to write a zero into minimum pack voltage, both temperatures, both
RSSI figures and link quality for the whole flight. Held briefly it protects the record;
held for a whole flight the min/max collapse to the arm-instant values.

Present since the original V1 (Bei Ke) and undocumented there. V1 had a log viewer page,
since removed, where these numbers were read back on the radio — which is why the feature
looks pointless now: its payoff moved off-device.

### Open items

- **`power_max` (`main.lua:1481`) is not gated by `Log Switch`**, so maximum power keeps
  climbing while the switch is held. It is the one logged column the switch does not
  protect.
- **`current_flight_max_current` (`main.lua:1590`) is not gated either**, and it *is* on
  screen as the peak-current ring around the current gauge. So the single visible maximum
  is the one the hold does not touch.

  Both predate this work and look like oversights rather than intent. Left alone
  deliberately — fixing them changes behaviour. Candidates for v1.0.9.

- **Latent bug, pre-existing, not fixed:** `get_widget_colors` only refills its cache when
  an option differs from the cached value, so if both colour options ever arrived `nil`
  the cache would never populate and `refresh` would throw. Now unreachable in practice
  because the resolver guarantees numbers, but the cache logic itself is still fragile.

- ~~The test harness was not committed.~~ Done: it lives in `tools/`, with its own
  README. `tools/` is gitignored, so it stays on this machine and out of the SD card
  package. It has no off-machine backup as a result.

- **No `CLAUDE.md` in this repo yet.** The workspace-level one at `D:\02_GitHub\CLAUDE.md`
  covers it, but a per-repo file describing the widget and its constraints does not exist.
