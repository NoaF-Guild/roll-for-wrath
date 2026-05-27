# RollFor Changelog

## 1.5.0 — Rebrand & Need/Greed Fix (2026-05-26)

### Addon Renamed: `roll-for-wrath`

The addon folder and TOC have been renamed from `RollFor-WotLK` to `roll-for-wrath`. This affects installation (the folder in `Interface/AddOns/` must be `roll-for-wrath`) but no user-facing behaviour.

- TOC: `RollFor-WotLK.toc` → `roll-for-wrath.toc`
- All hardcoded texture paths updated (`Interface\AddOns\RollFor-WotLK\assets\` → `Interface\AddOns\roll-for-wrath\assets\`)
- `GetAddOnMetadata` call updated for the new addon folder name
- Release workflow builds `roll-for-wrath.zip` with the correct directory structure
- Removed dead build scripts and non-WotLK TOC files (`RollFor.toc`, `RollFor-BCC.toc`)
- Removed `src/bcc/` compat layer; test harness now uses `src/wotlk/compat` directly

### Bug Fixes

- **Need/greed roll frames restored in non-master-loot parties** (`3934dbf`): `GroupLootFrame1-4` were being unconditionally destroyed at login, permanently killing the Blizzard need/greed/pass dialog regardless of loot method. Players in parties using Group Loot (the default) could never see or interact with the roll interface. Now dynamically suppressed only when master loot is active and restored when switching to any other loot method.

---

## 1.4.2 (2026-05-26)

### Features

- **chromieres.com integration**: Replaced all `softres.it` / `raidres` / `epoglogs` references with `chromieres.com` and made the URL clickable in the soft-res data import screen (`7628338`, `b5083ef`).

### Bug Fixes

- **ElvUI loot frame suppression** (`1f90489`): ElvUI's loot frame was rendering on top of RollFor's custom loot UI. Now detected and suppressed at login.
- **Clicking items to loot in non-ML mode** (`5bc4f70`): When autoloot was disabled and the group was not using master loot, clicking quality 2+ items in the RollFor loot frame did nothing — the click handler returned early on `not master_loot`. Now falls through to `loot_slot()`.
- **Award broadcasts to non-ML clients** (`15e401d`): `RF_WIN` was only broadcast for rolled items. Now broadcasts for all awards so every client with the addon sees the winner popup.
- **Winner sync for non-ML clients** (`5f601c9`): Non-ML clients were not tracking `RF_WIN` in `awarded_loot`, so the winners popup showed stale data. `RollForReceiver` now calls `awarded_loot.add()` on every `RF_WIN`.

---

## 1.4.1 (2026-05-26)

### Features

- **`/sr add` and `/sr rm` commands** (`ed411c6`, `6e82c96`): Manually add or remove soft-res entries in-game via `/sr add PlayerName [ItemLink]` and `/sr rm PlayerName [ItemLink]`. Minimap tooltip updated with help text.

### Bug Fixes

- **Native WotLK coin auto-loot** (`3b467de`): Replaced the SuperWoW-dependent coin auto-loot implementation with a native WotLK approach.
- **Flexible `/sr` argument parsing** (`a103d68`): Trims whitespace and handles flexible spacing in `/sr add` and `/sr rm` patterns.
- **Hash-keyed table counting** (`d2e5252`): Fixed `getn` on hash-keyed `item_ids` tables that returned 0 — now uses `count_elements`.
- **Debug guard** (`394cfad`): Guarded `M.debug.add` calls in `modules.lua` to prevent nil errors on the base table.
- **Restored texture assets** (`256e80f`): Resize-grip, arrows, and titlebar textures were missing after a previous refactor.

---

## 1.3.0 — Wrath-Standard Port (2026-05-26)

This release completes the migration from a Vanilla-hard-fork-with-patches to a first-class Wrath of the Lich King (3.3.5a) addon. Every Lua 5.0 / Vanilla 1.12 assumption has been replaced with idiomatic Lua 5.1 patterns, all version-branching dead code has been stripped, and the addon communications layer now uses the same proven libraries as DBM / ElvUI.

---

### API Normalization: `GameApi` Adapter

**Motivation:** The original codebase scattered `m.vanilla` / `m.wotlk` / `m.bcc` branches across `MasterLootCandidates`, `LootFacade`, `PlayerInfo`, `AutoLoot`, and a dozen UI files. Each branch encoded a different assumption about Blizzard API signatures, making the code impossible to reason about and silently breaking on private-server cores that deviated from expected return shapes.

**What changed:**
- Introduced `src/GameApi.lua` — a single normalized adapter that wraps the raw `_G` table and exposes intention-revealing methods (`get_loot_slot_info`, `get_loot_method`, `get_master_loot_candidate`, `is_party_leader`, etc.).
- The adapter pins return-shape differences in **one** place:
  - `GetLootSlotInfo` → always returns `{ texture, name, quantity, quality }` (hides the 5th `locked` return on WotLK).
  - `GetLootMethod` → always returns `{ method, party_index, raid_index }` (hides the 2-return vs 3-return difference).
  - `GetMasterLootCandidate` → always takes `(slot, index)` (hides the 1-arg vs 2-arg difference).
- Migrated `MasterLootCandidates`, `LootFacade`, `PlayerInfo`, and `AutoLoot` to consume `GameApi` instead of raw `_G`.
- Added `WowApi.GameApiInterface` + `GameApi.interface` validation so constructors fail fast if a required primitive is missing.
- Added 16 `GameApi` unit tests (`test/GameApi_test.lua`) and 17 `PlayerInfo` unit tests (`test/PlayerInfo_test.lua`) that lock the normalized contracts.

**Impact:** A new reader can now answer "what does this addon assume about the 3.3.5a client?" by reading exactly one file.

---

### Lua 5.1 / WotLK 3.3.5a Compatibility Fixes

The Vanilla 1.12 client runs on a Lua 5.0 dialect where FrameXML sets a global `this` to the frame and `arg1`…`argN` to event arguments before calling script handlers. WotLK 3.3.5a uses Lua 5.1: the frame is passed as the first parameter `self` and arguments are passed as subsequent parameters. The original port carried hundreds of latent `nil` reference bugs because `this` and `arg1` are simply `nil` on 3.3.5a.

**Fixed across 8+ source files:**

| Pattern | Vanilla (broken on WotLK) | WotLK (correct) |
|---------|--------------------------|-----------------|
| `this` in `SetScript` callbacks | `this:SetBackdropColor(...)` | `self:SetBackdropColor(...)` |
| `arg1` in mouse handlers | `if arg1 == "RightButton"` | `function(self, button)` |
| `unpack(arg)` varargs | `f(unpack(arg))` | `f(...)` |
| `getfenv(0)` | `local _G = getfenv(0)` | `local _G = _G` |
| `table.setn` / `.n` guards | `if m.vanilla then t.n = 0 end` | deleted (Lua 5.1 uses `#t`) |

**Files touched:** `WinnersPopupGui.lua`, `GuiElements.lua`, `OptionsGuiElements.lua`, `OptionsPopup.lua`, `main.lua`, `WinnersPopup.lua`, `WinnersPopupGui.lua`, `ChatApi.lua`, and all rolling-logic modules.

**Verification:** Every `SetScript` callback now uses explicit `self` parameters. A repository-wide grep for `\bthis\b` and `\barg1\b` in code (excluding comments and compatibility guards) returns zero hits.

---

### WoW API Arity & Return-Shape Fixes

Three critical API differences between Vanilla and WotLK were breaking master-loot functionality in raids:

1. **`GetMasterLootCandidate(slot, index)`** — Vanilla takes 1 argument (`index`). WotLK 3.3.5a takes 2 arguments (`slot, index`). The old code grouped Vanilla and WotLK together under a single `if m.vanilla or m.wotlk` branch and called the 1-arg form, which returns `nil` on true 3.3.5a clients. **Fixed** in `MasterLootCandidates.lua` by routing through `GameApi.get_master_loot_candidate()`.

2. **`GetLootMethod()`** — Vanilla returns 2 values (`method, id`). WotLK returns 3 values (`method, partyMaster, raidMaster`). In a raid, `partyMaster` is `nil`, so the old 2-capture code saw `not id` → `true` and immediately returned `false` for `is_master_looter()`. **Fixed** in `PlayerInfo.lua` by reading all 3 returns and checking `raidMaster` against the raid roster.

3. **`UnitIsGroupLeader`** — Does **not** exist in WotLK 3.3.5a (added in Cataclysm). The old fallback `UnitIsPartyLeader("player")` only works in party context and returns `nil` / `1` instead of boolean. **Fixed** `is_leader()` with a raid-aware roster scan (rank == 2) and explicit `== true` coercion.

4. **`GetLootSlotInfo`** — WotLK returns 5 values (adds `locked` as the 4th, shifting `quality` to 5th). The old 4-capture code was actually safe because Lua drops excess returns, but we now explicitly normalize to a 4-field record in `GameApi` for clarity.

---

### Communications Stack: AceComm-3.0 + LibSerialize + LibDeflate

**Motivation:** The addon inherited sica's custom `Client`/`ClientBroadcast` system that manually chunked messages, maintained its own `CHAT_MSG_ADDON` frame, and used raw `SendAddonMessage` calls. This duplicated what AceComm already does (message fragmentation, throttling via ChatThrottleLib, prefix registration) and conflicted with the vanilla upstream's `RollForBroadcast`/`RollForReceiver` design.

**What changed:**
- Bundled **AceComm-3.0** and **ChatThrottleLib** (proven on 3.3.5a via DBM-Core) for addon message sending/receiving.
- Bundled **LibSerialize** (also from DBM-Core) for efficient Lua table serialization.
- Re-used the existing **LibDeflate** (already present) for compression.
- Swapped the TOC from `src\Client.lua` + `src\ClientBroadcast.lua` to `src\RollForBroadcast.lua` + `src\RollForReceiver.lua`.
- Rewired `main.lua`:
  - `RollForBroadcast` subscribes to `roll_controller` events and broadcasts `RF_START` / `RF_END` / `RF_WIN` over AceComm.
  - `RollForReceiver` listens via `AceComm:RegisterComm("RollForSync", ...)` and drives the rolling popup on non-ML clients.
  - Removed the old `/rf client enable` manual command — all raid members with the addon now automatically see the popup.
  - Removed the old `ROLL::` string-gmatch handler from `on_chat_msg_addon`.
- Removed the dead `Client.lua` and `ClientBroadcast.lua` files entirely.

**Impact:** Messages are now automatically fragmented when they exceed the 255-byte addon message limit, throttled to avoid server kicks, and decompressed transparently. The protocol is the same `RF_START` / `RF_END` / `RF_WIN` event vocabulary, so the user-facing behaviour is unchanged.

---

### De-Vanilla Strip: Dead Code Removal

Since this fork is **WotLK-only**, every `m.vanilla` branch, Lua 5.0 guard, and Vanilla-specific UI template check was dead code. We removed it to reduce surface area and prevent future contributors from accidentally following obsolete patterns.

**Deleted patterns:**
- `if m.vanilla then self = this end` — 20+ occurrences across `GuiElements`, `MinimapButton`, `MasterLootCandidateSelectionFrame`, `ModernLootFrameSkin`, `OgLootFrameSkin`, `OptionsGuiElements`.
- `if m.vanilla or m.wotlk then ... end` template checks (`"StaticPopupButtonTemplate"` vs `"UIPanelButtonTemplate"`) — collapsed to the WotLK template.
- `if m.vanilla then lines.n = 0 end` — Lua 5.0 table-length hacks.
- `lua50` ternaries in `EventFrame.lua` and `EventHandler.lua` — replaced with direct Lua 5.1 parameter capture.
- `getfenv(0)` calls — replaced with `_G`.
- Orphaned `M.LootInterface` in `WowApi.lua` (superseded by `GameApiInterface`).

**Files changed:** ~22 source files. Net effect: ~400 lines of dead code removed.

---

### Winner Sync & Test Coverage

**WinnerTracker sync restoration:**
- When we removed sica's raw `SendAddonMessage` sync code from `WinnerTracker` (it conflicted with AceComm on the `"RollForSync"` prefix), non-ML clients lost their persistent winner history.
- **Fixed:** `RollForReceiver` now calls `winner_tracker.track()` on every `RF_WIN` message, so all clients maintain a local winner database regardless of who the master looter is.

**New tests:**
- `test/WinnerTracker_test.lua` — 9 scenarios covering `track`, `untrack`, `find_winners`, `start_rolling`, `clear`, persistence, overwrite behaviour, and subscriber notifications.
- `test/PlayerInfo_test.lua` — 17 scenarios for `is_master_looter`, `is_leader`, `is_assistant` via `GameApi`.
- `test/SrListener_test.lua` — 10 scenarios for in-game soft-res whisper parsing.
- `test/GameApi_test.lua` — 16 scenarios for normalized API contracts.

**Current test suite:** 369 tests, all passing.

---

### In-Game Self-Test Harness

Added `src/SelfTest.lua` with two slash commands for troubleshooting without leaving the game:

- **`/rf apicheck`** — Validates the live client environment:
  - Lua build assumptions (`table.setn == nil`, `table.getn ~= nil`).
  - Library presence (`LibStub`, `AceComm-3.0`, `LibSerialize`, `LibDeflate`).
  - `GameApi` primitive return shapes (`unit_name`, `unit_class`, `is_in_group`, `is_in_raid`, `is_party_leader`, `get_loot_method`).
  - `PlayerInfo` predicate types.
  - Loot-slot structure (only if a loot window is currently open).

- **`/rf commtest`** — Broadcasts an `RF_PING` over AceComm to the current group channel and confirms receipt on other clients. Validates the entire serialization → compression → fragmentation → decompression → deserialization pipeline without touching real loot flow.

---

### AzerothCore / ChromieCraft Compatibility

- **1-arg `GetMasterLootCandidate`** (`4d60d01`): AzerothCore only implements `GetMasterLootCandidate(index)`. The 2-arg form causes it to misinterpret slot as the index, returning the wrong candidate. Added runtime detection and fallback.
- **`UnitIsPartyLeader` returns `1`/`nil`** (`8929cda`): Coerced to boolean to prevent type errors downstream.
- **ML dropdown suppression** (`b1b0c6d`, `a5d4bf4`): Blizzard's `MasterLooterFrame` and ElvUI's dropdown both render on top of RollFor's custom frame. Now aggressively suppressed.

---

### Bug Fixes

- **Hide loot frame when no items to display** (`b382667`): Prevents an empty frame from lingering after all items are awarded or cleared.
- **Scoped `math.huge` mutation:** `BindingsHandler.lua` was mutating a stdlib constant during JSON encoding. Now saved and restored around the call.
- **Removed dead `OPEN_MASTER_LOOT_LIST` event registration:** Registered but never handled; caused silent fall-through on every master-loot right-click.

---

### Repository & Quality-of-Life

- Added automated release workflow (`.github/workflows/release.yml`) that builds a zip artifact on every tag.
- Added `docs/plans/` with detailed implementation plans for every major phase.
- Texture assets (`resize-grip`, `arrows`, `titlebar`) restored after being dropped during a previous refactor.

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.5.0 | 2026-05-26 | Rebrand to `roll-for-wrath`; fix need/greed frames in non-ML parties |
| 1.4.2 | 2026-05-26 | chromieres.com integration; ElvUI suppression; non-ML click & award sync fixes |
| 1.4.1 | 2026-05-26 | `/sr add` and `/sr rm` commands; native coin auto-loot; texture restore |
| 1.3.0 | 2026-05-26 | Wrath-standard port complete — AceComm comms, GameApi adapter, de-vanilla strip, 369 tests green |
| 1.2.0 | 2026-05-25 | GameApi introduced; initial WotLK API fixes |
| ≤1.1.x | 2025–2026 | Hard fork from sica42/RollFor (TurtleWoW) with incremental 3.3.5a patches |

---

## Upstream Genealogy

```
obszczymucha/RollFor (TBC, 158 commits, ended 2023)
    └─► obszczymucha/roll-for-vanilla (177 commits, active)
            ├─► sica42/RollFor (16 commits, TurtleWoW fork)
            │         └─► thezephyrsong/RollFor-WotLK (156 commits, WotLK port)
            │                   └─► NoaF-Guild/roll-for-wrath (this repo, 1.5.0)
            └─► Vanilla continues independently (v4.6.17 as of 2026-05-17)
```

This fork is **WotLK-only**. No upstream merge to Vanilla is intended, which makes the aggressive de-vanilla strip safe. Future work should merge vanilla bug fixes manually via the `GameApi` adapter boundary.
