# RollFor-WotLK Changelog

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

**Impact:** Messages are now automatically fragmented when they exceed the 255-byte addon message limit, throttled to avoid server kicks, and decompressed transparently. The protocol is the same `RF_START` / `RF_END` / `RF_WIN` event vocabulary, so the user-facing behavior is unchanged.

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
- `test/WinnerTracker_test.lua` — 9 scenarios covering `track`, `untrack`, `find_winners`, `start_rolling`, `clear`, persistence, overwrite behavior, and subscriber notifications.
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

### Bug Fixes

- **AzerothCore 3.3.5a compatibility:** Some private-server cores return `nil` for `UnitIsPartyLeader` or use a 1-arg `GetMasterLootCandidate`. Added runtime detection and fallback paths (`4d60d01`, `b1b0c6d`, `8929cda`).
- **Aggressively suppress Blizzard / ElvUI master-loot dropdown:** On 3.3.5a, the default UI and ElvUI both try to render their own candidate dropdowns on top of RollFor's, causing empty lists and double UI. We now hide both immediately when opening our frame (`a5d4bf4`).
- **Hide loot frame when no items to display:** Prevents an empty frame from lingering after all items are awarded (`b382667`).
- **Scoped `math.huge` mutation:** `BindingsHandler.lua` was mutating a stdlib constant during JSON encoding. Now saved and restored around the call (`Task 12` in porting fixes).
- **Removed dead `OPEN_MASTER_LOOT_LIST` event registration:** Registered but never handled; caused silent fall-through on every master-loot right-click.

---

### Repository & Quality-of-Life

- Added automated release workflow (`.github/workflows/release.yml`) that builds a zip artifact on every tag.
- Added `docs/plans/` with detailed implementation plans for every major phase:
  - `2026-05-25-api-seam-consolidation.md`
  - `2026-05-25-wotlk-porting-fixes.md`
  - `2026-05-26-fix-test-infrastructure.md`
  - `2026-05-26-phases-a-through-d.md`
  - `2026-05-26-winner-sync-tests-selftest.md`
- Texture assets (`resize-grip`, `arrows`, `titlebar`) restored after being dropped during a previous refactor.

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
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
            │                   └─► NoaF-Guild/RollFor-WotLK (this repo, 1.3.0)
            └─► Vanilla continues independently (v4.6.17 as of 2026-05-17)
```

This fork is **WotLK-only**. No upstream merge to Vanilla is intended, which makes the aggressive de-vanilla strip safe. Future work should merge vanilla bug fixes manually via the `GameApi` adapter boundary.
