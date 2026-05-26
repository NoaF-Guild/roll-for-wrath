# Fix Test Infrastructure for WotLK Port

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Get all 33 test files passing by updating the test harness to support the WotLK-ported codebase (GameApi adapter, KeyBindings, missing modules), then identify gaps in test coverage for WotLK-specific features.

**Architecture:** The root causes are: (1) `test/utils.lua:load_real_stuff` doesn't load `GameApi` before consumers that need it, (2) `main.lua` references `m.KeyBindings` which requires `BindingsHandler` (not loaded by tests), (3) the `IntegrationTestBuilder` passes a raw mock API to `MasterLootCandidates` instead of a `GameApi`-shaped mock, (4) `GroupRoster` tests mock party-check functions incompatibly with the WotLK API signatures, (5) `load_real_stuff` loads vanilla-only modules (`RollForBroadcast`, `GargulBridge`) that depend on `AceComm`/`LibSerialize` (not available in test env). Fixes are surgical: add a `GameApi` mock, update module load order, add missing mocks, skip unavailable modules gracefully.

**Tech Stack:** Lua 5.1, luaunit test framework, existing mock infrastructure in `test/mocks/`

---

## Failure Taxonomy (33 test files)

| Category | Count | Root Cause | Files |
|----------|-------|-----------|-------|
| ✅ PASS | 13 | — | DroppedLootAnnounce_test, EventFrame_test, GroupRosterApi_test, ItemUtils_test, LootList_test, modules_test, SoftResDataTransformer_test, SoftRes_test, test_utils_test, TieRollGuiData_test, VersionBroadcast_test, SoftResGui_test (empty) |
| 💥 CRASH (`[C]: in ?`) | 11 | `main.lua:583` → `m.KeyBindings` is nil (BindingsHandler not loaded) | both_spec, DroppedLootAnnounce_integration, generic, HowToRoll, InstaRaidRoll, mainspec, NameAutoMatcher, offspec, RaidRoll, softres_rolls, tie_rolls, TradeTracker |
| 🔴 GAMEAPI nil | 8 | `MasterLootCandidates:44` or `LootFacade:43` → `m.GameApi` is nil | AutoLootSpec, InstaRaidRollSpec, LootFacade, LootListSpec, NormalRollSpec, PreviewSpec, RaidRollSpec, SoftResRollSpec |
| 🟡 GroupRoster | 1 (4 failures) | Party-member mocking doesn't match WotLK `IsInGroup` semantics | GroupRoster_test |
| ❓ SoftResAwardedLootDecorator | 1 | Crashes in `load_real_stuff` (same KeyBindings issue) | SoftResAwardedLootDecorator_test |

**All 20 failing files trace to just 3 root causes:**
1. `BindingsHandler`/`KeyBindings` not loaded → crash in `main.lua:583` (11 files)
2. `GameApi` not loaded/mocked → nil index at constructor validation (8 files)
3. `GroupRoster` party mocking doesn't set `IsInGroup` properly (1 file)

---

## Task 1: Add GameApi mock

**Files:**
- Create: `test/mocks/GameApi.lua`

This mock satisfies `m.GameApi.interface` so that `MasterLootCandidates.new()`, `LootFacade.new()`, `PlayerInfo.new()`, and `AutoLoot.new()` can validate their constructor argument.

**Step 1: Write the mock**

```lua
-- test/mocks/GameApi.lua
local M = {}

function M.new( overrides )
  overrides = overrides or {}

  local defaults = {
    get_num_loot_items = function() return 0 end,
    get_loot_slot_link = function() return nil end,
    get_loot_slot_info = function() return nil end,
    is_loot_slot_item = function() return false end,
    is_loot_slot_coin = function() return false end,
    loot_slot = function() end,
    get_loot_source_guid = function() return nil end,
    get_loot_method = function() return { method = "group" } end,
    get_master_loot_candidate = function() return nil end,
    get_raid_member = function() return nil end,
    is_party_leader = function() return false end,
    is_in_group = function() return false end,
    is_in_raid = function() return false end,
    unit_name = function() return "Psikutas" end,
    unit_class = function() return "Warrior" end,
  }

  for k, v in pairs( overrides ) do
    defaults[ k ] = v
  end

  return defaults
end

return M
```

**Step 2: Verify it satisfies the interface**

```bash
cd test && lua -e '
  package.path = "./?.lua;../?.lua;" .. package.path
  require("src/modules")
  require("src/Interface")
  require("src/WowApi")
  require("src/GameApi")
  local mock = require("mocks/GameApi").new()
  RollFor.Interface.validate(mock, RollFor.GameApi.interface)
  print("GameApi mock validates OK")
'
```
Expected: `GameApi mock validates OK`

**Step 3: Commit**

```bash
git add test/mocks/GameApi.lua
git commit -m "test: add GameApi mock for test infrastructure"
```

---

## Task 2: Update `test/utils.lua` load order — add GameApi, BindingsHandler, and handle missing modules

**Files:**
- Modify: `test/utils.lua`

The `load_real_stuff` function loads modules in order and then loads `main.lua`. Three problems:
1. `GameApi` is never loaded, but `LootFacade`, `MasterLootCandidates`, `PlayerInfo`, and `AutoLoot` now require it
2. `BindingsHandler` is never loaded, but `main.lua:583` calls `m.KeyBindings.new()`
3. `RollForBroadcast`, `RollForReceiver`, `GargulBridge` require AceComm/LibSerialize (not available in tests) — they need pcall wrapping or skipping
4. Several WotLK modules are missing: `Client`, `ClientBroadcast`, `ConfirmPopup`, `OptionsPopup`, `OptionsGuiElements`, `WinnersPopup`, `WinnersPopupGui`, `SrListener`, `RollingLogic`

**Step 1: Add GameApi load before its first consumer (LootFacade)**

In `load_real_stuff`, add after `r( "src/WowApi" )`:
```lua
  r( "src/GameApi" )
```

**Step 2: Add BindingsHandler load before main.lua**

Before `r( "main" )`, add:
```lua
  r( "src/BindingsHandler" )
```

**Step 3: Add missing WotLK modules before main.lua**

Before `r( "main" )`, add all modules that `main.lua` expects:
```lua
  r( "src/ConfirmPopup" )
  r( "src/OptionsGuiElements" )
  r( "src/OptionsPopup" )
  r( "src/WinnersPopup" )
  r( "src/WinnersPopupGui" )
  r( "src/SrListener" )
  r( "src/Client" )
  r( "src/ClientBroadcast" )
  r( "src/BindingsHandler" )
```

**Step 4: Wrap vanilla-only modules that need AceComm in pcall**

Replace:
```lua
  r( "src/RollForBroadcast" )
  r( "src/RollForReceiver" )
  r( "src/GargulBridge" )
```

With:
```lua
  pcall( r, "src/RollForBroadcast" )
  pcall( r, "src/RollForReceiver" )
  pcall( r, "src/GargulBridge" )
```

**Step 5: Add `GameApi` to `mock_api` — initialize it from mock globals**

After the existing mocks in `M.mock_api()`, add:
```lua
  -- Initialize GameApi from mocked globals
  RollFor.GameApi = require( "src/GameApi" )
```

Wait — `GameApi.new()` validates against `WowApi.GameApiInterface`, which requires real globals (`GetNumLootItems`, etc.) to exist. The test mock_api already mocks these. So we need to ensure `GameApi` is constructed AFTER `mock_api()` sets up the globals.

Actually, `load_real_stuff` does `r("src/GameApi")` which only loads the module definition — it doesn't call `GameApi.new()`. The actual `GameApi.new(m.api)` call happens in `main.lua:111`. At that point, `m.api = getfenv()` which IS `_G` (with all the mocked globals from `mock_api`). So this should work without additional mocking.

The only issue is: `GameApi.new()` calls `interface.validate(api, m.WowApi.GameApiInterface)` which checks that functions like `LootSlot`, `UnitGUID`, `GetLootMethod` etc. exist in `_G`. We need to add any missing mocks.

**Step 6: Add missing mock globals needed by GameApi validation**

In `mock_api()`, add any globals that `WowApi.GameApiInterface` requires but aren't mocked yet:
```lua
  M.mock( "LootSlot", function() end )
  M.mock( "UnitGUID", function() return nil end )
  M.mock( "GetLootMethod", function() return "group", nil, nil end )
  M.mock( "GetMasterLootCandidate", function() return nil end )
  M.mock( "GetRaidRosterInfo", function() return nil end )
  M.mock( "UnitIsPartyLeader", false )
  M.mock( "UnitIsConnected", false )
  M.mock( "LOOT_SLOT_ITEM", 1 )
  M.mock( "LOOT_SLOT_MONEY", 2 )
```

**Step 7: Run all tests**

```bash
./test.sh 2>&1 | tail -5
# Or run all independently:
find test/ -name '*_test.lua' | sort | while read f; do
  dir=$(dirname "$f"); file=$(basename "$f")
  result=$(cd "$dir" && lua "$file" -v -T Spec -m should -o text 2>&1 | tail -1)
  echo "$file: $result"
done
```

**Step 8: Commit**

```bash
git add test/utils.lua
git commit -m "test: update load_real_stuff for WotLK modules and GameApi"
```

---

## Task 3: Fix IntegrationTestBuilder to provide GameApi mock

**Files:**
- Modify: `test/IntegrationTestBuilder.lua`

The builder constructs `MasterLootCandidates.new(ml_candidates_api, ...)` where `ml_candidates_api` is a raw mock with `GetMasterLootCandidate` function. But `MasterLootCandidates.new()` now expects a `GameApi`-shaped object and validates against `m.GameApi.interface`.

**Step 1: Replace MasterLootCandidatesApi with GameApi mock in builder**

In the `build()` function (~line 209-211), replace:
```lua
    local ml_candidates_api = deps[ "MasterLootCandidatesApi" ] or require( "mocks/MasterLootCandidatesApi" ).new( group_roster, raw_loot_list )
    local ml_candidates = require( "src/MasterLootCandidates" ).new( ml_candidates_api, group_roster, raw_loot_list )
```

With:
```lua
    local GameApiMock = require( "mocks/GameApi" )
    local ml_game_api = deps[ "GameApi" ] or GameApiMock.new( {
      get_master_loot_candidate = function( slot, index )
        if raw_loot_list and not raw_loot_list.is_looting() then return end
        local players = group_roster and group_roster.get_all_players_in_my_group() or {}
        for i, player in ipairs( players ) do
          if i == index then return player.name end
        end
      end
    } )
    local ml_candidates = require( "src/MasterLootCandidates" ).new( ml_game_api, group_roster, raw_loot_list )
```

**Step 2: Update LootFacade mock injection**

Check if `LootFacade.new()` is called with a real `game_api` or the mock. If the mock `LootFacade` is used (line 196), it should already bypass `GameApi` validation. Verify:
```bash
grep -n 'LootFacade' test/IntegrationTestBuilder.lua
```

The mock LootFacade (`test/mocks/LootFacade.lua`) is typically used, which doesn't call `GameApi.new()`. So this is fine.

**Step 3: Update AutoLoot mock if needed**

The `AutoLoot` mock at line 284 calls `require("src/AutoLoot")` directly:
```lua
    local auto_loot = require( "mocks/AutoLoot" ).new( loot_list, u.modules().api, db( "auto_loot" ), config, player_info )
```

But the real `AutoLoot.new()` now takes `game_api` as its 6th arg. The mock wraps the real module — so we need to pass a GameApi mock. Update to:
```lua
    local auto_loot = require( "mocks/AutoLoot" ).new( loot_list, u.modules().api, db( "auto_loot" ), config, player_info, ml_game_api )
```

And update `test/mocks/AutoLoot.lua` to accept and pass through the game_api parameter:
```lua
function M.new( loot_list, api, db, config, player_info, game_api )
  local real_auto_loot = RealAutoLoot.new( loot_list, function() return api end, db, config, player_info, game_api )
```

**Step 4: Run integration tests**

```bash
cd test && lua AutoLootSpec_test.lua -v -T Spec -m should -o text 2>&1 | tail -5
cd test && lua NormalRollSpec_test.lua -v -T Spec -m should -o text 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add test/IntegrationTestBuilder.lua test/mocks/AutoLoot.lua
git commit -m "test: update IntegrationTestBuilder for GameApi adapter"
```

---

## Task 4: Fix GroupRoster_test party mocking

**Files:**
- Modify: `test/GroupRoster_test.lua`

4 failures: party-member tests expect `IsInGroup` to return `true` when party members are mocked, but the mock setup only sets up `UnitName`/`UnitClass` for party slots — it doesn't mock `IsInGroup` to return `true`.

Also, `class` comes back as `"UNKNOWN"` instead of `"Warrior"` — the WotLK `GroupRoster.lua` calls `api.UnitClass()` which returns two values `(localized, ENGLISH)` and the test mock only returns one value.

**Step 1: Fix party mocks to set IsInGroup = true**

Find the party helper functions and ensure they mock `IsInGroup`:
```lua
mock( "IsInGroup", true )
```

**Step 2: Fix UnitClass mock to return two values**

The mock should return `("Warrior", "WARRIOR")` — localized name and uppercase English token. Update `UnitClass` mocks:
```lua
mock( "UnitClass", smart_table( { [ "player" ] = packed_value( { "Warrior", "WARRIOR" } ) } ) )
```

**Step 3: Run GroupRoster tests**

```bash
cd test && lua GroupRoster_test.lua -v -T Spec -m should -o text 2>&1
```
Expected: 14/14 pass

**Step 4: Commit**

```bash
git add test/GroupRoster_test.lua
git commit -m "test: fix GroupRoster party mocking for WotLK API"
```

---

## Task 5: Run full suite and fix remaining issues

**Step 1: Run all tests**

```bash
find test/ -name '*_test.lua' | sort | while read f; do
  dir=$(dirname "$f"); file=$(basename "$f")
  result=$(cd "$dir" && lua "$file" -v -T Spec -m should -o text 2>&1 | tail -1)
  echo "$file: $result"
done
```

**Step 2: Fix any remaining failures**

Likely remaining issues:
- `main.lua` may reference modules not yet loaded in test context (e.g., `OptionsPopup`, `WinnersPopup`)
- Mock `FrameBuilder` may need updates for new popup constructors
- Some tests may need `LOOT_SLOT_ITEM` / `LOOT_SLOT_MONEY` globals defined

For each failure: check the stack trace, identify the nil reference, add the mock or module load.

**Step 3: Commit when green**

```bash
git add -A
git commit -m "test: fix remaining test failures for WotLK port"
```

---

## Task 6: Audit test coverage for WotLK-specific features

**No code changes — analysis only.**

After all tests pass, audit what IS and ISN'T tested:

### Currently tested (from vanilla):
- Rolling logic (normal, softres, raid roll, insta raid roll, tie rolls, both-spec, offspec, mainspec)
- Loot facade events
- DroppedLoot announcement
- GroupRoster party/raid membership
- ItemUtils parsing
- SoftRes data transformation
- NameAutoMatcher
- EventFrame
- LootList
- VersionBroadcast
- AutoLoot spec

### NOT tested (WotLK-specific, needs future work):
- **GameApi adapter** — normalization logic for GetLootSlotInfo (4 vs 5 returns), GetLootMethod (2 vs 3 returns), GetMasterLootCandidate (1 vs 2 args), is_party_leader fallback
- **PlayerInfo via GameApi** — is_master_looter, is_leader, is_assistant with GameApi primitives
- **SrListener** — in-game whisper SR handling
- **WotLK compat layer** — GetLootSlotType polyfill, PlaySound shim
- **Client/ClientBroadcast** — addon communication
- **OptionsPopup/WinnersPopup/ConfirmPopup** — GUI components
- **BindingsHandler** — key binding management

### Recommended test additions (priority order):
1. `GameApi_test.lua` — test normalization for each version branch
2. `PlayerInfo_test.lua` — test is_master_looter/is_leader with GameApi mock for party/raid/solo
3. `SrListener_test.lua` — test whisper parsing
4. `MasterLootCandidates_test.lua` — test candidate resolution via GameApi

**Step 1: Document findings**

Create `docs/plans/2026-05-26-test-coverage-gaps.md` with the audit results.

**Step 2: Commit**

```bash
git add docs/plans/2026-05-26-test-coverage-gaps.md
git commit -m "docs: audit test coverage gaps for WotLK features"
```

---

## Estimated Time

| Task | Time |
|------|------|
| Task 1: GameApi mock | 5 min |
| Task 2: utils.lua load order | 15 min |
| Task 3: IntegrationTestBuilder | 15 min |
| Task 4: GroupRoster_test fix | 10 min |
| Task 5: Fix remaining failures | 20 min |
| Task 6: Coverage audit | 10 min |
| **Total** | **~75 min** |
