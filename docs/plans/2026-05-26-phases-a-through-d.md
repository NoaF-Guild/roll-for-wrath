# RollFor-WotLK Phases A–D Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Complete consolidation, de-vanilla strip, and migrate addon comms from sica's manual chunking to AceComm-3.0 + LibSerialize + LibDeflate.

**Architecture:** Phase A fixes remaining raw API callers and cosmetic issues. Phase B migrates AutoLoot to GameApi. Phase C strips dead vanilla code paths (`m.vanilla` branches, lua50 guards, `self = this` patterns). Phase D swaps the comms stack and cleans up WinnerTracker's conflicting sync code.

**Tech Stack:** Lua 5.1 (WoW 3.3.5a), AceComm-3.0, ChatThrottleLib, LibSerialize, LibDeflate, LibStub

---

## Phase A — Finish Consolidation

### Task 1: Dedup `M.game_api` in `main.lua`

`main.lua` creates `m.GameApi.new(m.api)` twice — lines 111 and 144. Both are stateless and identical. Remove the second, reuse the first.

**Files:**
- Modify: `main.lua:111,144`

**Step 1: Make the edit**

In `main.lua`, the first creation at line ~111:
```lua
  M.game_api = m.GameApi.new( m.api )
  M.player_info = m.PlayerInfo.new( M.game_api )
```

The second at line ~144:
```lua
  M.game_api = m.GameApi.new( m.api )
  M.loot_facade = m.LootFacade.new( m.EventFrame.new( m.api ), M.game_api )
```

Delete the second `M.game_api = m.GameApi.new( m.api )` line entirely. The `M.loot_facade` line already has access to `M.game_api` from the first assignment.

**Step 2: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures

**Step 3: Commit**

```bash
git add main.lua
git commit -m "refactor: remove duplicate game_api creation in main.lua"
```

---

### Task 2: Migrate `WinnerTracker` off raw globals

`src/WinnerTracker.lua:52` calls raw `GetLootMethod()`, `GetNumRaidMembers()`, `GetNumPartyMembers()`, `UnitIsUnit()`, `UnitIsPartyLeader()`, `UnitIsRaidOfficer()`, `SendAddonMessage()`, and `CreateFrame()` on `_G`. The sync broadcast code (lines 48–88) and the sync listener (lines 133–164) both bypass the GameApi adapter.

**IMPORTANT:** The sync code uses the `"RollForSync"` prefix, which is the SAME prefix that `RollForBroadcast`/`RollForReceiver` use via AceComm. In Phase D, AceComm will `RegisterComm("RollForSync", ...)` and intercept all messages on that prefix. The raw `SendAddonMessage` / `CHAT_MSG_ADDON` listener in WinnerTracker would conflict with AceComm's message reassembly.

**Decision:** The WinnerTracker sync feature is sica's custom addition that duplicates what `RollForBroadcast`/`RollForReceiver` already do (they broadcast `RF_WIN` events). In Phase D, winner data will be synced through the AceComm stack. Therefore:

1. **Remove the sync broadcast code** from `WinnerTracker.track()` (lines ~48–88) — revert to the clean `track` function that just writes to db and notifies subscribers.
2. **Remove the sync listener frame** (lines ~133–164) — the `CreateFrame("Frame")` + `CHAT_MSG_ADDON` handler.
3. This makes WinnerTracker a pure local data structure again, with sync handled by the comms layer.

**Files:**
- Modify: `src/WinnerTracker.lua`

**Step 1: Edit WinnerTracker.lua**

Remove the `is_sync_packet` parameter from `track()`. Remove everything from `-- === NEW SYNC BROADCAST CODE ===` to the end of the track function's extra closure. Remove everything from `-- === NEW SYNC LISTENER CODE ===` to the end of that block (the `CreateFrame` + `SetScript` listener).

The clean `track` function should be:
```lua
  local function track( winner_name, item_link, roll_type, winning_roll, rolling_strategy )
    db.winners[ item_link ] = db.winners[ item_link ] or {}
    db.winners[ item_link ][ winner_name ] = {
      roll_type = roll_type,
      winning_roll = winning_roll,
      rolling_strategy = rolling_strategy
    }

    notify_winner_found( winner_name, item_link, roll_type, winning_roll, rolling_strategy )
  end
```

And the return table should directly follow `clear()` with no frame creation code between them.

**Step 2: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures

**Step 3: Commit**

```bash
git add src/WinnerTracker.lua
git commit -m "refactor: remove raw sync code from WinnerTracker

The winner sync broadcast and listener used raw SendAddonMessage
on the 'RollForSync' prefix, bypassing GameApi and conflicting
with AceComm's message handling. Winner data sync will be handled
by the AceComm-based RollForBroadcast/Receiver in Phase D."
```

---

### Task 3: Cosmetic cleanups

Three minor issues:

**3a. `is_assistant` missing `return false`**

In `src/PlayerInfo.lua`, the `is_assistant()` function returns `nil` (implicit) when the player isn't found in the raid roster. All other predicates return `false`. Add an explicit `return false` after the loop.

```lua
  local function is_assistant()
    if not game_api.is_in_raid() then return false end
    local my_name = get_name()

    for i = 1, 40 do
      local member = game_api.get_raid_member( i )

      if member and member.name == my_name then
        return member.rank > 0
      end
    end

    return false  -- <-- ADD THIS
  end
```

**3b. Remove orphaned `M.LootInterface`**

In `src/WowApi.lua`, `M.LootInterface` (lines 8-13) is no longer referenced anywhere. Delete it.

**3c. Remove duplicate `@class LootSlotInfo`**

In `src/GameApi.lua:27`, there's a `---@class LootSlotInfo` annotation that duplicates `src/LootFacade.lua:20`. Remove the one in `GameApi.lua` (LootFacade is the canonical definition).

**Files:**
- Modify: `src/PlayerInfo.lua`
- Modify: `src/WowApi.lua`
- Modify: `src/GameApi.lua`

**Step 1: Make all three edits**

**Step 2: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures

**Step 3: Commit**

```bash
git add src/PlayerInfo.lua src/WowApi.lua src/GameApi.lua
git commit -m "refactor: cosmetic cleanups (is_assistant return, orphaned LootInterface, dup annotation)"
```

---

## Phase B — AutoLoot Migration

### Task 4: Verify AutoLoot already uses GameApi

`src/AutoLoot.lua` already receives `game_api` as a constructor parameter and calls `game_api.get_master_loot_candidate(slot, i)`. The migration is **already done**. Verify by checking that AutoLoot has no remaining raw API calls for the four migrated methods.

**Files:**
- Read: `src/AutoLoot.lua`

**Step 1: Verify no raw calls remain**

```bash
grep -n 'GetLootMethod\|GetMasterLootCandidate\|GetLootSlotInfo\|GetRaidRosterInfo' src/AutoLoot.lua
```
Expected: No output (AutoLoot uses `game_api.get_master_loot_candidate` not `GetMasterLootCandidate`).

**Note:** AutoLoot still uses `api()` (the `_G` wrapper) for `UnitName`, `GetRealZoneText`, `GetLootThreshold`, `GiveMasterLoot`, `CreateFrame`, `LootSlot`. These are NOT part of the GameApi adapter scope — they're UI/world APIs that don't have version-specific behavior. This is intentional.

**Step 2: Confirm and commit skip**

No code change needed. Record in this plan that Phase B is already complete.

---

## Phase C — De-Vanilla Strip

### Task 5: Strip `m.vanilla` branches from GameApi

`src/GameApi.lua` has three `if m.vanilla then ... else ...` blocks. Since `m.vanilla` is never true on this fork, delete the vanilla arms and keep only the WotLK/else paths.

**Files:**
- Modify: `src/GameApi.lua`

**Step 1: Edit GameApi.lua**

**In `get_loot_slot_info` (~line 58):** Remove the `if m.vanilla or m.wotlk then` conditional and the BCC/Retail else-arm. Keep only the 4-value return path (which is what WotLK uses). Remove the version comment.

Before:
```lua
  local function get_loot_slot_info( slot )
    if m.vanilla or m.wotlk then
      local texture, name, quantity, quality = api.GetLootSlotInfo( slot )
      return texture and { ... } or nil
    else
      local texture, name, quantity, _, quality = api.GetLootSlotInfo( slot )
      return texture and { ... } or nil
    end
  end
```

After:
```lua
  local function get_loot_slot_info( slot )
    local texture, name, quantity, quality = api.GetLootSlotInfo( slot )

    return texture and {
      texture = texture,
      name = name,
      quantity = quantity,
      quality = quality,
    } or nil
  end
```

**In `get_loot_method` (~line 101):** Remove the `if m.vanilla then` arm. Keep the 3-return WotLK path.

Before:
```lua
  local function get_loot_method()
    if m.vanilla then
      local method, id = api.GetLootMethod()
      return { method = method, party_index = id, raid_index = nil }
    else
      local method, party_id, raid_id = api.GetLootMethod()
      return { method = method, party_index = party_id, raid_index = raid_id }
    end
  end
```

After:
```lua
  local function get_loot_method()
    local method, party_id, raid_id = api.GetLootMethod()
    return { method = method, party_index = party_id, raid_index = raid_id }
  end
```

**In `get_master_loot_candidate` (~line 117):** Remove the vanilla `api.GetMasterLootCandidate(index)` arm. Keep the WotLK `api.GetMasterLootCandidate(slot, index)` path.

Before:
```lua
  local function get_master_loot_candidate( slot, index )
    if m.vanilla then
      return api.GetMasterLootCandidate( index )
    else
      return api.GetMasterLootCandidate( slot, index )
    end
  end
```

After:
```lua
  local function get_master_loot_candidate( slot, index )
    return api.GetMasterLootCandidate( slot, index )
  end
```

**Step 2: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures (GameApi_test.lua tests the WotLK paths)

**Step 3: Commit**

```bash
git add src/GameApi.lua
git commit -m "refactor: strip vanilla code paths from GameApi (WotLK-only fork)"
```

---

### Task 6: Strip `m.vanilla` branches from UI modules

These are all `if m.vanilla then self = this end` guards (for Lua 5.0 compat) and vanilla-specific UI differences. Since `m.vanilla` is never true, all these branches are dead code.

**Files (11 files):**
- `src/OptionsGuiElements.lua` — 1 `self = this` guard
- `src/GuiElements.lua` — 3 `self = this` guards, 2 template checks, 2 height checks
- `src/MinimapButton.lua` — 8 `self = this` guards + 1 `OnClick` guard
- `src/MasterLootCandidateSelectionFrame.lua` — 3 `self = this` guards + 2 conditional blocks
- `src/ModernLootFrameSkin.lua` — 1 `self = this` guard + 2 conditional blocks
- `src/OgLootFrameSkin.lua` — 3 `self = this` guards + 3 conditional blocks
- `src/FrameBuilder.lua` — 2 `m.vanilla or m.wotlk` checks + 1 `.n = 0` guard
- `src/RollingPopup.lua` — 1 `m.vanilla or m.wotlk` check

**Step 1: Strip all `if m.vanilla then self = this end` lines**

These are all single-line guards. Delete the entire line in each case. The `self` parameter is already provided by WotLK's Lua 5.1 method call syntax.

**Step 2: Strip remaining `m.vanilla` conditionals**

For `if m.vanilla or m.wotlk then ... end` blocks where both vanilla AND wotlk take the same path: remove the conditional, keep the body.

For `if m.vanilla then ... else ... end` blocks: remove the vanilla arm, keep the else body, remove the if/else/end wrapper.

Specific cases:

- `GuiElements.lua:275-276`: `m.vanilla and "StaticPopupButtonTemplate" or "UIPanelButtonTemplate"` → just `"UIPanelButtonTemplate"`
- `GuiElements.lua:288-289`: Same pattern → `"UIPanelButtonTemplate"` and height `21`
- `OgLootFrameSkin.lua:117`: `m.vanilla and "LootButton" or "Button"` → just `"Button"`
- `FrameBuilder.lua:377`: `if m.vanilla then lines.n = 0 end` → delete line
- `FrameBuilder.lua:250,266`: `if m.vanilla or m.wotlk then` — this is TRUE on our fork, so keep the body, remove the conditional

**Step 3: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures

**Step 4: Commit**

```bash
git add src/OptionsGuiElements.lua src/GuiElements.lua src/MinimapButton.lua \
  src/MasterLootCandidateSelectionFrame.lua src/ModernLootFrameSkin.lua \
  src/OgLootFrameSkin.lua src/FrameBuilder.lua src/RollingPopup.lua
git commit -m "refactor: strip dead vanilla UI guards (self=this, template checks, .n=0)"
```

---

### Task 7: Strip `m.vanilla` branches from logic modules

**Files (10 files):**
- `src/Config.lua` — 3 vanilla/bcc checks
- `src/EventHandler.lua` — 3 vanilla checks + lua50 detection
- `src/EventFrame.lua` — lua50 detection block
- `src/InstaRaidRollRollingLogic.lua` — `.n = 0` + lua50 type guard
- `src/RaidRollRollingLogic.lua` — `.n = 0` + lua50 type guard
- `src/LootAutoProcess.lua` — `.n = 0`
- `src/SoftResRollGuiData.lua` — `.n = 0`
- `src/TieRollGuiData.lua` — `.n = 0`
- `src/RollTracker.lua` — `.n = 0`
- `src/RollResultAnnouncer.lua` — lua50 type guard
- `src/SoftResLootListDecorator.lua` — lua50 type guard
- `src/SoftRes.lua` — bcc/wotlk check
- `src/SoftResGui.lua` — vanilla check
- `src/LootController.lua` — bcc/wotlk check

**Step 1: Handle `lua50` detection in EventFrame and EventHandler**

`src/EventFrame.lua:8`: `local lua50 = table.setn and true or false` — on Lua 5.1, `table.setn` is nil, so `lua50 = false`. All the `lua50 and X or Y` ternaries resolve to `Y`. Replace each with just the `Y` value and remove the `lua50` variable.

The pattern in EventFrame (lines 38-48):
```lua
    local event = lua50 and event or _event      → local event = _event
    local arg1 = lua50 and arg1 or _arg1          → local arg1 = _arg1
    -- etc for arg2, arg3, arg4, arg5
```

Same pattern in `EventHandler.lua` (lines 9, 15, 17).

**Step 2: Handle `.n = 0` guards**

All `if m.vanilla then X.n = 0 end` lines — delete them. Lua 5.1 doesn't use `.n` for table length.

Files: `InstaRaidRollRollingLogic.lua`, `RaidRollRollingLogic.lua`, `LootAutoProcess.lua`, `SoftResRollGuiData.lua`, `TieRollGuiData.lua`, `RollTracker.lua`, `FrameBuilder.lua`

**Step 3: Handle lua50 type guards**

Pattern: `if type(X) == "table" then ... end` with comment `-- Fucking lua50 and its n.`

These guard against Lua 5.0's `.n` field appearing in `ipairs` iteration. On Lua 5.1, this never happens. Remove the type guard, keep the body.

Files: `InstaRaidRollRollingLogic.lua:52`, `RaidRollRollingLogic.lua:97`, `RollResultAnnouncer.lua:128`, `SoftResLootListDecorator.lua:65`

**Step 4: Handle Config and EventHandler vanilla checks**

- `Config.lua:141`: `if m.bcc or m.wotlk then return end` — this is TRUE, so keep the `return`. Simplify to just `return` (unconditional) since this function is never reached on WotLK. Or better: the function `tmog_rolling_enabled()` should just return `false` unconditionally.
- `Config.lua:318`: `if m.vanilla then` — FALSE on WotLK. Delete the vanilla arm, keep the else.
- `Config.lua:480`: Version mismatch check — simplify for WotLK only.
- `EventHandler.lua:74`: `local message = m.vanilla and arg1 or arg2` → `local message = arg2`
- `EventHandler.lua:114-120`: `if not m.vanilla then ... end` — TRUE on WotLK, keep body; `if m.vanilla then ... end` — FALSE, delete.
- `SoftRes.lua:47`: `if m.bcc or m.wotlk then` — TRUE, keep body, remove conditional.
- `SoftResGui.lua:195`: `elseif m.vanilla then` — FALSE, delete arm.
- `LootController.lua:243`: `if (m.bcc or m.wotlk) and ...` — simplify to just the inner condition.

**Step 5: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures

**Step 6: Commit**

```bash
git add src/Config.lua src/EventHandler.lua src/EventFrame.lua \
  src/InstaRaidRollRollingLogic.lua src/RaidRollRollingLogic.lua \
  src/LootAutoProcess.lua src/SoftResRollGuiData.lua src/TieRollGuiData.lua \
  src/RollTracker.lua src/RollResultAnnouncer.lua src/SoftResLootListDecorator.lua \
  src/SoftRes.lua src/SoftResGui.lua src/LootController.lua
git commit -m "refactor: strip dead vanilla logic paths (lua50, .n=0, version flags)"
```

---

### Task 8: Remove `getfenv` and dead code

**Files:**
- `src/WinnersPopup.lua:10` — `local _G = getfenv( 0 )` (not needed on Lua 5.1; `_G` is a global)
- `src/WinnersPopupGui.lua:25` — same
- `src/ChatApi.lua:6` — same

**Step 1: In each file, replace `local _G = getfenv( 0 )` with `local _G = _G`**

This is cleaner and works on all Lua 5.x. The `getfenv` call does work on 5.1 (it returns `_G`), but it's unnecessary and confusing.

**Step 2: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```

**Step 3: Commit**

```bash
git add src/WinnersPopup.lua src/WinnersPopupGui.lua src/ChatApi.lua
git commit -m "refactor: replace getfenv(0) with _G reference"
```

---

## Phase D — Comms Migration (AceComm + LibSerialize)

### Task 9: Bundle AceComm-3.0 and LibSerialize libraries

Copy the proven, version-stable libraries from DBM-Core (the most actively maintained 3.3.5a addon on the client).

**Files:**
- Create: `libs/wotlk/AceComm-3.0/AceComm-3.0.lua` (copy from DBM-Core)
- Create: `libs/wotlk/AceComm-3.0/AceComm-3.0.xml` (copy from DBM-Core)
- Create: `libs/wotlk/AceComm-3.0/ChatThrottleLib.lua` (copy from DBM-Core)
- Create: `libs/wotlk/LibSerialize/LibSerialize.lua` (copy from DBM-Core)

**Step 1: Copy library files**

```bash
cp -r /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/DBM-Core/Libs/Ace3/AceComm-3.0 \
  libs/wotlk/AceComm-3.0

cp -r /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/DBM-Core/Libs/LibSerialize \
  libs/wotlk/LibSerialize
```

**Step 2: Update `libs/wotlk/Libs.xml`**

Add the two new library includes. AceComm must come after CallbackHandler (which it depends on) and LibSerialize has no ordering requirements.

New `libs/wotlk/Libs.xml`:
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.blizzard.com/wow/ui/
..\FrameXML\UI.xsd">
	<Include file="CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
	<Include file="AceTimer-3.0\AceTimer-3.0.xml"/>
	<Include file="AceComm-3.0\AceComm-3.0.xml"/>
	<Script file="LibSerialize\LibSerialize.lua"/>
	<Include file="LibDeflate\lib.xml"/>
</Ui>
```

**Note:** AceComm-3.0.xml loads ChatThrottleLib.lua internally. LibSerialize is a single .lua file (no XML wrapper). LibStub is loaded first by the TOC directly (`libs\wotlk\LibStub\LibStub.lua`), so it's available before Libs.xml runs.

**Step 3: Verify library loading works**

Check that LibStub can find the new libraries:
```bash
grep -c 'LibStub:NewLibrary' libs/wotlk/AceComm-3.0/AceComm-3.0.lua
grep -c 'LibStub:NewLibrary' libs/wotlk/LibSerialize/LibSerialize.lua
```
Expected: Both return 1 (each registers itself with LibStub).

**Step 4: Commit**

```bash
git add libs/wotlk/AceComm-3.0/ libs/wotlk/LibSerialize/ libs/wotlk/Libs.xml
git commit -m "feat: bundle AceComm-3.0, ChatThrottleLib, and LibSerialize for WotLK

Copied from DBM-Core (proven stable on 3.3.5a). AceComm handles
message fragmentation and ChatThrottleLib prevents server kicks.
LibSerialize provides efficient Lua table serialization."
```

---

### Task 10: Swap TOC from Client/ClientBroadcast to RollForBroadcast/Receiver

**Files:**
- Modify: `RollFor-WotLK.toc`

**Step 1: Edit the TOC**

Replace:
```
src\Client.lua
src\ClientBroadcast.lua
```

With:
```
src\RollForBroadcast.lua
src\RollForReceiver.lua
```

**Important:** `RollForBroadcast.lua` and `RollForReceiver.lua` already exist in `src/` — they were carried over from the vanilla merge. They're just not loaded by the WotLK TOC currently.

**Step 2: Commit**

```bash
git add RollFor-WotLK.toc
git commit -m "feat: swap TOC to load AceComm-based RollForBroadcast/Receiver

Replaces sica's manual-chunking Client/ClientBroadcast with the
AceComm-3.0 + LibSerialize + LibDeflate based broadcast/receiver."
```

---

### Task 11: Rewire `main.lua` comms wiring

**Files:**
- Modify: `main.lua`

**Step 1: Replace client_broadcast/client construction**

In `create_components()`, replace:
```lua
  M.client_broadcast = m.ClientBroadcast.new( M.roll_controller, M.softres, M.config )
  M.client = m.Client.new( M.ace_timer, M.player_info, M.rolling_popup, M.config )
```

With:
```lua
  M.roll_for_broadcast = m.RollForBroadcast.new( M.roll_controller, M.config )
  M.roll_for_receiver = m.RollForReceiver.new( M.rolling_popup, db( "roll_for_receiver" ) )
```

**Note:** `RollForBroadcast.new` subscribes to `roll_controller` events internally (same as `ClientBroadcast` did). `RollForReceiver.new` registers its own AceComm listener internally (replaces the `on_message` dispatch).

**Step 2: Remove old client enable command**

In `on_roll_command`, remove or comment:
```lua
    if string.find( args, "^client enable" ) and M.player_info.is_master_looter() then
      M.client_broadcast.enable_roll_popup()
      return
    end
```

The AceComm-based system doesn't need a manual enable — all raid members with the addon automatically see the rolling popup via `RollForReceiver`.

**Step 3: Remove old ROLL:: message handler**

In `on_chat_msg_addon`, remove the last line:
```lua
  for data in string.gmatch( message, "ROLL::(.*)" ) do M.client.on_message( data, sender ) return end
```

AceComm handles its own `CHAT_MSG_ADDON` dispatch via `RegisterComm`. The remaining `VERSION::` handlers still use raw `SendAddonMessage` on the `"RollFor"` prefix — they stay as-is (VersionBroadcast is independent of the loot comms).

**Step 4: Keep the RegisterAddonMessagePrefix for VersionBroadcast**

The existing line stays — it's still needed for the `VERSION::` protocol:
```lua
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix("RollFor")
  elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("RollFor") end
```

**Step 5: Wire receiver's `show` into slash command**

Currently `/rf` with no rolling in progress tries `rolling_popup`. The receiver has a `show()` method that re-opens a dismissed popup. Add to the top of the `/rf` handler:
```lua
  -- Re-open dismissed receiver popup if available
  if M.roll_for_receiver and M.roll_for_receiver.show() then return end
```

**Step 6: Wire receiver's `on_item_info_received`**

In `EventHandler.lua`, the `GET_ITEM_INFO_RECEIVED` event exists. Wire:
```lua
  -- In the event handler for GET_ITEM_INFO_RECEIVED (if it exists):
  if M.roll_for_receiver then M.roll_for_receiver.on_item_info_received( item_id ) end
```

Check `src/EventHandler.lua` for where `GET_ITEM_INFO_RECEIVED` is handled and add the receiver call.

**Step 7: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -3
```
Expected: 360 tests, 0 failures (integration tests don't exercise the comms layer directly)

**Step 8: Commit**

```bash
git add main.lua src/EventHandler.lua
git commit -m "feat: rewire main.lua to use AceComm-based broadcast/receiver

- RollForBroadcast subscribes to roll_controller events (replaces ClientBroadcast)
- RollForReceiver listens via AceComm RegisterComm (replaces Client.on_message)
- Removed /rf client enable command (auto-display for all raid members)
- Removed ROLL:: message handler from on_chat_msg_addon
- VersionBroadcast VERSION:: protocol unchanged (still raw SendAddonMessage)"
```

---

### Task 12: Tag and release

**Step 1: Bump version**

In `RollFor-WotLK.toc`, change `## Version:` to `1.3.0`.

**Step 2: Commit and tag**

```bash
git add RollFor-WotLK.toc
git commit -m "chore: bump version to 1.3.0"
git tag -a 1.3.0 -m "v1.3.0 - AceComm comms migration & de-vanilla strip

- Migrated addon comms from manual chunking to AceComm-3.0 + LibSerialize + LibDeflate
- Stripped all dead vanilla code paths (m.vanilla, lua50, self=this guards)
- Cleaned up WinnerTracker sync code (now handled by RollForBroadcast)
- Removed duplicate game_api creation
- Fixed is_assistant nil return
- Breaking: clients on v1.2.x and v1.3.0 cannot communicate (different protocol)"
git push origin master --tags
```

**Step 3: Verify CI**

Watch for both the test workflow and release workflow to pass:
```bash
gh run list -R NoaF-Guild/roll-for-wrath --limit 3
```

---

## Summary

| Phase | Tasks | Files Changed | Risk |
|-------|-------|---------------|------|
| A (Consolidation) | 1-3 | 4 files | Low — mechanical |
| B (AutoLoot) | 4 | 0 files (already done) | None |
| C (De-Vanilla) | 5-8 | ~22 files | Medium — many files but all dead-code removal |
| D (Comms) | 9-12 | 5 files + 2 lib dirs | Medium — protocol change, needs live testing |

**Total estimated effort:** ~2 hours automated, 0 backward compatibility needed.
**Highest risk item:** Phase D live validation — the comms migration works correctly in code but should be tested on a real 3.3.5a server with 2+ clients before a raid.
