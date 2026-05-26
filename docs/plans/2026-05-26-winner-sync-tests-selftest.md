# Winner Sync, WinnerTracker Tests, and In-Game Self-Test Harness

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Re-implement persistent winner-history sync in `RollForReceiver`, add WinnerTracker unit tests, and build `/rf apicheck` + `/rf commtest` in-game self-test commands.

**Architecture:** The receiver gets `winner_tracker` as a new constructor arg and calls `track()` on `RF_WIN` messages. A new `src/SelfTest.lua` module provides the two slash commands. Tests use the existing mock infrastructure.

**Tech Stack:** Lua 5.1, AceComm-3.0, existing test/utils.lua + luaunit

---

## Task 1: Add `winner_tracker` to RollForReceiver

The `RF_WIN` handler currently inserts winners into ephemeral popup `state.winners` for display. It should ALSO persist them via `winner_tracker.track()` so non-ML clients maintain a permanent winner history.

**Files:**
- Modify: `src/RollForReceiver.lua`
- Modify: `main.lua`

**Step 1: Modify RollForReceiver to accept winner_tracker**

In `src/RollForReceiver.lua`, change the constructor signature:

```lua
-- Before:
function M.new( rolling_popup, db )

-- After:
function M.new( rolling_popup, db, winner_tracker )
```

Then in the `RF_WIN` handler, after the existing `table.insert( state.winners, ... )`, add:

```lua
    RF_WIN = function( payload )
      if not state then return end
      table.insert( state.winners, {
        name = payload.name,
        class = payload.class,
        roll_type = payload.roll_type,
        roll = payload.roll
      } )
      state.strategy_type = payload.strategy
      state.waiting_for_rolls = false

      -- Persist winner to local tracker db
      if winner_tracker and state.item_link then
        winner_tracker.track( payload.name, state.item_link, payload.roll_type, payload.roll, payload.strategy )
      end

      refresh()
    end,
```

**Step 2: Pass winner_tracker in main.lua**

Change the receiver construction:

```lua
-- Before:
  M.roll_for_receiver = m.RollForReceiver.new( M.rolling_popup, db( "roll_for_receiver" ) )

-- After:
  M.roll_for_receiver = m.RollForReceiver.new( M.rolling_popup, db( "roll_for_receiver" ), M.winner_tracker )
```

**Step 3: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | grep -E 'Ran|fail|error' | tail -5
```
Expected: 360 tests, 0 failures (existing tests don't exercise this path)

**Step 4: Commit**

```bash
git add src/RollForReceiver.lua main.lua
git commit -m "feat: persist winner data from RF_WIN messages to winner_tracker

Non-ML clients now write winner records to their local WinnerTracker db
when receiving RF_WIN broadcasts. Restores cross-client winner history
that was lost when the sica sync code was removed."
```

---

## Task 2: Write WinnerTracker unit tests

Lock the pure-local behavior contract: `track()` writes to db and notifies, `untrack()` removes, `find_winners()` queries, `start_rolling()` clears, `clear()` wipes all. 5-param signature.

**Files:**
- Create: `test/WinnerTracker_test.lua`

**Step 1: Write the test file**

```lua
package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/bcc/compat" )
local utils = require( "test/utils" )
local lu, eq = utils.luaunit( "assertEquals" )
local m = require( "src/modules" )
require( "src/Interface" )
require( "src/WinnerTracker" )

WinnerTrackerSpec = {}

local function new_tracker( db )
  db = db or {}
  return m.WinnerTracker.new( db ), db
end

function WinnerTrackerSpec.should_track_a_winner()
  -- Given
  local tracker, db = new_tracker()

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- Then
  local winners = tracker.find_winners( "[Thunderfury]" )
  eq( #winners, 1 )
  eq( winners[1].winner_name, "Psikutas" )
  eq( winners[1].roll_type, "MainSpec" )
  eq( winners[1].winning_roll, 95 )
  eq( winners[1].rolling_strategy, "NormalRoll" )
end

function WinnerTrackerSpec.should_track_multiple_winners_for_same_item()
  -- Given
  local tracker = new_tracker()

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )
  tracker.track( "Obszansen", "[Thunderfury]", "OffSpec", 42, "NormalRoll" )

  -- Then
  local winners = tracker.find_winners( "[Thunderfury]" )
  eq( #winners, 2 )
end

function WinnerTrackerSpec.should_untrack_a_winner()
  -- Given
  local tracker = new_tracker()
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- When
  tracker.untrack( "Psikutas", "[Thunderfury]" )

  -- Then
  local winners = tracker.find_winners( "[Thunderfury]" )
  eq( #winners, 0 )
end

function WinnerTrackerSpec.should_return_empty_for_unknown_item()
  -- Given
  local tracker = new_tracker()

  -- When
  local winners = tracker.find_winners( "[Unknown Item]" )

  -- Then
  eq( #winners, 0 )
end

function WinnerTrackerSpec.should_notify_subscribers_on_track()
  -- Given
  local tracker = new_tracker()
  local notified_name, notified_link, notified_roll
  tracker.subscribe_for_winner_found( function( name, link, roll )
    notified_name = name
    notified_link = link
    notified_roll = roll
  end )

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- Then
  eq( notified_name, "Psikutas" )
  eq( notified_link, "[Thunderfury]" )
  eq( notified_roll, 95 )
end

function WinnerTrackerSpec.should_start_rolling_clears_item_winners()
  -- Given
  local tracker = new_tracker()
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- When
  tracker.start_rolling( "[Thunderfury]" )

  -- Then
  local winners = tracker.find_winners( "[Thunderfury]" )
  eq( #winners, 0 )
end

function WinnerTrackerSpec.should_notify_subscribers_on_start_rolling()
  -- Given
  local tracker = new_tracker()
  local notified = false
  tracker.subscribe_for_rolling_started( function() notified = true end )

  -- When
  tracker.start_rolling( "[Thunderfury]" )

  -- Then
  eq( notified, true )
end

function WinnerTrackerSpec.should_clear_all_winners()
  -- Given
  local tracker = new_tracker()
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )
  tracker.track( "Obszansen", "[Ashkandi]", "OffSpec", 50, "NormalRoll" )

  -- When
  tracker.clear()

  -- Then
  eq( #tracker.find_winners( "[Thunderfury]" ), 0 )
  eq( #tracker.find_winners( "[Ashkandi]" ), 0 )
end

function WinnerTrackerSpec.should_persist_to_db()
  -- Given
  local db = {}
  local tracker = m.WinnerTracker.new( db )

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- Then
  eq( db.winners["[Thunderfury]"]["Psikutas"].roll_type, "MainSpec" )
  eq( db.winners["[Thunderfury]"]["Psikutas"].winning_roll, 95 )
end

function WinnerTrackerSpec.should_overwrite_existing_winner()
  -- Given
  local tracker = new_tracker()
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 50, "NormalRoll" )

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "SoftResRoll" )

  -- Then
  local winners = tracker.find_winners( "[Thunderfury]" )
  eq( #winners, 1 )
  eq( winners[1].winning_roll, 95 )
  eq( winners[1].rolling_strategy, "SoftResRoll" )
end

os.exit( lu.LuaUnit.run() )
```

**Step 2: Run tests**

```bash
cd test && lua5.1 WinnerTracker_test.lua -v -T Spec -m should -o text
```
Expected: 9 tests pass, 0 failures.

**Step 3: Commit**

```bash
git add test/WinnerTracker_test.lua
git commit -m "test: add WinnerTracker unit tests (9 scenarios)

Locks the 5-param track() contract: writes to db, notifies subscribers,
overwrite behavior, untrack, start_rolling clears, find_winners queries."
```

---

## Task 3: Create the in-game self-test module (`/rf apicheck`)

A new module that registers a `/rf apicheck` subcommand. When invoked, it calls each GameApi primitive and prints PASS/FAIL per assertion. Loot-slot checks only fire if a loot window is open.

**Files:**
- Create: `src/SelfTest.lua`
- Modify: `RollFor-WotLK.toc` (add before `main.lua`)
- Modify: `main.lua` (wire the slash subcommand)

**Step 1: Create src/SelfTest.lua**

```lua
RollFor = RollFor or {}
local m = RollFor

if m.SelfTest then return end

local M = {}

local function ok( label, cond )
  local color = cond and "|cff44ff44" or "|cffff4444"
  local tag = cond and "PASS" or "FAIL"
  print( color .. tag .. "|r " .. label )
  return cond
end

---@param game_api GameApi
---@param player_info PlayerInfo
function M.new( game_api, player_info )
  local pass_count = 0
  local fail_count = 0

  local function check( label, cond )
    if ok( label, cond ) then
      pass_count = pass_count + 1
    else
      fail_count = fail_count + 1
    end
  end

  local function apicheck()
    pass_count = 0
    fail_count = 0

    print( "|cff80b8ff--- RollFor API Self-Test ---|r" )

    -- §1.3: Lua build assumptions
    check( "table.setn is nil (lua50=false)", table.setn == nil )
    check( "table.getn exists", table.getn ~= nil )

    -- §2.4: Library presence
    local lib_stub = LibStub
    check( "LibStub present", lib_stub ~= nil )
    if lib_stub then
      check( "AceComm-3.0 loaded", lib_stub( "AceComm-3.0", true ) ~= nil )
      check( "LibSerialize loaded", lib_stub( "LibSerialize", true ) ~= nil )
      check( "LibDeflate loaded", lib_stub( "LibDeflate", true ) ~= nil )
    end

    -- GameApi primitives
    check( "unit_name(player) is string", type( game_api.unit_name( "player" ) ) == "string" )
    check( "unit_class(player) is string", type( game_api.unit_class( "player" ) ) == "string" )
    check( "is_in_group() is boolean", type( game_api.is_in_group() ) == "boolean" )
    check( "is_in_raid() is boolean", type( game_api.is_in_raid() ) == "boolean" )
    check( "is_party_leader() is boolean", type( game_api.is_party_leader() ) == "boolean" )

    -- §1.5: get_loot_method record shape
    local loot = game_api.get_loot_method()
    check( "get_loot_method() returns table", type( loot ) == "table" )
    check( "get_loot_method().method is string", type( loot.method ) == "string" )
    print( string.format( "   loot_method: method=%s party_index=%s raid_index=%s",
      tostring( loot.method ), tostring( loot.party_index ), tostring( loot.raid_index ) ) )

    -- PlayerInfo
    check( "player_info.get_name() is string", type( player_info.get_name() ) == "string" )
    check( "player_info.get_class() is string", type( player_info.get_class() ) == "string" )
    check( "player_info.is_master_looter() is boolean", type( player_info.is_master_looter() ) == "boolean" )
    check( "player_info.is_leader() is boolean", type( player_info.is_leader() ) == "boolean" )

    -- §1.4: Loot slot shape (only if loot window open)
    local num_items = game_api.get_num_loot_items()
    if num_items > 0 then
      local info = game_api.get_loot_slot_info( 1 )
      check( "get_loot_slot_info(1) returns table", type( info ) == "table" )
      if info then
        check( "loot_slot_info.texture is string", type( info.texture ) == "string" )
        check( "loot_slot_info.name is string", type( info.name ) == "string" )
        check( "loot_slot_info.quantity is number", type( info.quantity ) == "number" )
        check( "loot_slot_info.quality is number", type( info.quality ) == "number" )
        print( string.format( "   slot1: texture=%s name=%s qty=%d quality=%d",
          tostring( info.texture ), tostring( info.name ), info.quantity or 0, info.quality or -1 ) )
      end
    else
      print( "   (open a loot window and re-run for loot-slot shape checks)" )
    end

    -- Summary
    print( string.format( "|cff80b8ff--- Results: %d passed, %d failed ---|r", pass_count, fail_count ) )
  end

  return {
    apicheck = apicheck
  }
end

m.SelfTest = M
return M
```

**Step 2: Create the comms test module (`/rf commtest`)**

Add a `commtest` function to the same module. It broadcasts a `RF_PING` message over AceComm and the receiver prints confirmation when received.

Extend `src/SelfTest.lua` — add to the return table:

```lua
  local function commtest()
    local lib_stub = LibStub
    local ace_comm = lib_stub and lib_stub( "AceComm-3.0", true )
    local lib_serialize = lib_stub and lib_stub( "LibSerialize", true )
    local lib_deflate = lib_stub and lib_stub( "LibDeflate", true )

    if not ace_comm or not lib_serialize or not lib_deflate then
      print( "|cffff4444FAIL|r Required libs not loaded." )
      return
    end

    local channel = m.api.IsInRaid() and "RAID" or m.api.IsInGroup() and "PARTY" or nil

    if not channel then
      print( "|cffff4444FAIL|r Not in a group. Join a party or raid to test comms." )
      return
    end

    local payload = { type = "RF_PING", sender = m.api.UnitName( "player" ), timestamp = time() }
    local serialized = lib_serialize:Serialize( payload )
    local compressed = lib_deflate:CompressDeflate( serialized, { level = 5 } )
    local encoded = lib_deflate:EncodeForWoWAddonChannel( compressed )

    ace_comm:SendCommMessage( "RollForSync", encoded, channel, nil, "ALERT" )
    print( string.format( "|cff44ff44SENT|r RF_PING to %s channel. Other clients should confirm receipt.", channel ) )
  end

  return {
    apicheck = apicheck,
    commtest = commtest
  }
```

And in `src/RollForReceiver.lua`, add an `RF_PING` handler to the handlers table:

```lua
    RF_PING = function( payload )
      print( string.format( "|cff44ff44COMMS OK|r Received RF_PING from %s (ts=%s)",
        tostring( payload.sender ), tostring( payload.timestamp ) ) )
    end,
```

**Step 3: Add to TOC**

In `RollFor-WotLK.toc`, add `src\SelfTest.lua` before `main.lua`:

```
src\RollForBroadcast.lua
src\RollForReceiver.lua
src\SelfTest.lua

main.lua
```

**Step 4: Wire in main.lua**

In `create_components()`, after the receiver creation:

```lua
  M.roll_for_receiver = m.RollForReceiver.new( M.rolling_popup, db( "roll_for_receiver" ), M.winner_tracker )
  M.self_test = m.SelfTest.new( M.game_api, M.player_info )
```

In the `/rf` slash command handler (the `on_roll_command` function), add before the `args_parser.parse` line:

```lua
    if args == "apicheck" then
      M.self_test.apicheck()
      return
    end

    if args == "commtest" then
      M.self_test.commtest()
      return
    end
```

**Step 5: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | grep -E 'Ran|fail|error' | tail -5
```
Expected: 369+ tests, 0 failures

**Step 6: Commit**

```bash
git add src/SelfTest.lua src/RollForReceiver.lua RollFor-WotLK.toc main.lua
git commit -m "feat: add /rf apicheck and /rf commtest in-game self-test commands

/rf apicheck — validates GameApi return shapes, library presence, Lua build
assumptions, and loot-slot structure against the live 3.3.5a client.

/rf commtest — broadcasts an RF_PING over the AceComm stack and confirms
round-trip receipt on other clients. Validates the comms layer works
without disturbing real loot flow."
```

---

## Task 4: Delete dead Client/ClientBroadcast files

These are no longer loaded by the TOC and no longer referenced anywhere.

**Files:**
- Delete: `src/Client.lua`
- Delete: `src/ClientBroadcast.lua`

**Step 1: Remove files**

```bash
git rm src/Client.lua src/ClientBroadcast.lua
```

**Step 2: Verify no references remain**

```bash
grep -rn 'Client\b\|ClientBroadcast' src/ main.lua | grep -v 'AceComm\|-- '
```
Expected: no hits (or only comments/dead references).

**Step 3: Run tests**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | grep -E 'Ran|fail|error' | tail -5
```

**Step 4: Commit**

```bash
git commit -m "chore: remove dead Client/ClientBroadcast files

No longer loaded by TOC or referenced anywhere. Replaced by
AceComm-based RollForBroadcast/Receiver in v1.3.0."
```

---

## Task 5: Final verification and push

**Step 1: Run full test suite**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -T Spec -m should -o text 2>&1; done | tail -5
```
Expected: 369+ tests, 0 failures.

**Step 2: Push**

```bash
git push origin master
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Wire winner_tracker into RollForReceiver's RF_WIN handler | RollForReceiver.lua, main.lua |
| 2 | WinnerTracker unit tests (9 scenarios) | test/WinnerTracker_test.lua |
| 3 | In-game self-test: `/rf apicheck` + `/rf commtest` + RF_PING handler | src/SelfTest.lua, RollForReceiver.lua, TOC, main.lua |
| 4 | Delete dead files | src/Client.lua, src/ClientBroadcast.lua |
| 5 | Verify and push | — |
