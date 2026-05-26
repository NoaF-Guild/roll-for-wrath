# API Seam Consolidation — RollFor-WotLK 3.3.5a

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Lift every version-variant Blizzard API call (`GetMasterLootCandidate`, `GetLootMethod`, `GetLootSlotInfo`, leader checks) into a single normalized adapter (`GameApi`) so business logic in `MasterLootCandidates`, `LootFacade`, and `PlayerInfo` never branches on expansion.

**Architecture:** A single concrete adapter `src/GameApi.lua` wraps the raw global table (`m.api = _G` via `getfenv()`) and exposes intention-revealing, normalized methods. It plugs into the existing DI seam: components receive `M.game_api` instead of `M.api()`. The adapter normalizes the WoW API *surface* (signatures, return shapes, presence checks); domain decisions (`is_master_looter`, `is_leader`) stay in the callers.

**Tech Stack:** Lua 5.1, WoW 3.3.5a API, existing `Interface.validate` machinery (`src/Interface.lua`), `getfenv()` global table injection (`src/modules.lua` line 11).

---

## Context: How the DI system works today

- `src/modules.lua:11`: `M.api = getfenv()` — `m.api` IS the global table `_G`.
- `main.lua:110`: `M.api = function() return m.api end` — returns `_G`.
- Components receive `M.api()` (the raw `_G` table) and call `api.SomeBlizzardFunction()`.
- `src/Interface.lua`: `interface.validate(impl, interface_table)` checks that every key in the interface exists in `impl` and is the correct type.
- Existing interface declarations:
  - `src/WowApi.lua: M.LootInterface` — raw Blizzard functions `LootFacade` needs
  - `src/LootFacade.lua: M.interface` — normalized methods `LootFacade` exposes
  - `src/AutoLoot.lua: M.interface` — normalized methods `AutoLoot` exposes

---

## Guiding principle — the boundary rule

> **The adapter normalizes the WoW API *surface*. It does not encode domain decisions.**

- **Belongs in the adapter:** "what does the client return, and in what shape." Signature differences, return-shape differences, presence/absence of symbols.
- **Stays in the caller:** "what that means for us." `is_master_looter()` composing loot method + roster lookup + name comparison is *domain logic*.

---

## Target architecture

A single `src/GameApi.lua` — module `m.GameApi` — wraps raw `_G` and exposes:

**Loot primitives** (consumed by `LootFacade`)
```
get_num_loot_items()        → number
get_loot_slot_link(slot)      → ItemLink?
get_loot_slot_info(slot)      → { texture, name, quantity, quality }?   -- collapses 4-vs-5 return
is_loot_slot_item(slot)       → boolean  -- wraps GetLootSlotType == LOOT_SLOT_ITEM
is_loot_slot_coin(slot)       → boolean  -- wraps GetLootSlotType == LOOT_SLOT_MONEY
loot_slot(slot)               → ()
get_loot_source_guid()        → string?  -- delegates to existing m.UnitGUID(api, "target")
```

**Group / loot method primitives** (consumed by `PlayerInfo`, `MasterLootCandidates`)
```
get_loot_method()             → { method, party_index?, raid_index? }   -- normalized record
get_master_loot_candidate(slot, index) → name?                          -- always 2-arg; drops slot for vanilla internally
get_raid_member(index)        → { name, rank, class }?                  -- wraps GetRaidRosterInfo
is_party_leader()             → boolean  -- UnitIsGroupLeader if present, else UnitIsPartyLeader
is_in_group()                 → boolean  -- backported IsInGroup global
is_in_raid()                  → boolean  -- backported IsInRaid global
unit_name(unit)               → string?
unit_class(unit)              → PlayerClass?
```

**Domain logic that explicitly stays in callers:**
- `PlayerInfo.is_master_looter()` — `get_loot_method()` + `get_raid_member()` + `unit_name()` compare
- `PlayerInfo.is_leader()` — `is_in_raid()` + `get_raid_member()` scan OR `is_party_leader()`
- `PlayerInfo.is_assistant()` — `is_in_raid()` + `get_raid_member()` scan

---

## Migration sequence

1. **Task 0: Create `GameApi` module** — single normalized adapter with all primitives.
2. **Task 1: Migrate `MasterLootCandidates`** — smallest blast radius, single variant call.
3. **Task 2: Migrate `LootFacade`** — extract its internal normalization into `GameApi`, leave thin event wrapper.
4. **Task 3: Migrate `PlayerInfo`** — most domain-blended, done last when boundary discipline is established.
5. **Task 4: Update `main.lua` DI wiring** — inject `M.game_api` into all three consumers.
6. **Task 5: Global verification** — grep for remaining `m.vanilla` in target files.

**Explicitly out of scope:**
- `AutoLoot.lua` — also branches on `m.vanilla` for `GetMasterLootCandidate`. Flagged as follow-up (Task 6).
- UI / sound expansion branches (`PlaySound` vs `SOUNDKIT` in `FrameBuilder`, `RollingPopup`).
- `lua50` / event-dispatch seam (`EventFrame`, `EventHandler`).
- `if m.vanilla then self = this end` UI guards in `GuiElements`, `OptionsGuiElements`, etc.

---

## Interface contract

`GameApi.new(api)` validates the raw `_G` table against `m.WowApi.GameApiInterface` (added in `src/WowApi.lua`).

Consumer constructors validate the injected `game_api` against `m.GameApi.interface`.

This follows the exact pattern already used by `LootFacade` (`interface.validate(api, m.WowApi.LootInterface)`) and `LootList` (`interface.validate(loot_facade, m.LootFacade.interface)`).

---

## Success criteria

- No version-variant Blizzard call appears in `MasterLootCandidates.lua`, `LootFacade.lua`, or `PlayerInfo.lua` outside `GameApi.lua`.
- `grep -r 'm\.vanilla' src/MasterLootCandidates.lua src/LootFacade.lua src/PlayerInfo.lua` returns nothing.
- A new reader can answer "what does this addon assume about the 3.3.5a client?" by reading `src/GameApi.lua`.
- Test mocks (if any) target the normalized `GameApi.interface`.

---

## Risks

- **Adapter-as-god-object.** Mitigated by the boundary rule: if a method needs domain knowledge, it doesn't belong here.
- **Private-server return-shape drift.** The adapter is precisely where `GetLootSlotInfo` and `GetLootMethod` shapes get pinned.
- **`UnitIsGroupLeader` optional presence.** Not included in `GameApiInterface` (validated as required); handled via runtime `if api.UnitIsGroupLeader then` inside the adapter.

---

### Task 0: Create GameApi module + WowApi.GameApiInterface

**Files:**
- Create: `src/GameApi.lua`
- Modify: `src/WowApi.lua`
- Modify: `RollFor-WotLK.toc` (add module load order)

**Step 1: Add `GameApiInterface` to `src/WowApi.lua`**

Append after the existing `M.LootInterface` block:

```lua
M.GameApiInterface = {
  GetNumLootItems = "function",
  GetLootSlotLink = "function",
  GetLootSlotInfo = "function",
  GetLootSlotType = "function",
  LootSlot = "function",
  UnitGUID = "function",
  UnitName = "function",
  UnitClass = "function",
  GetLootMethod = "function",
  GetMasterLootCandidate = "function",
  GetRaidRosterInfo = "function",
  UnitIsPartyLeader = "function",
  IsInRaid = "function",
  IsInGroup = "function",
}
```

Note: `UnitIsGroupLeader` is intentionally **excluded** — it does not exist in WotLK 3.3.5a. The adapter handles its optional presence at runtime.

**Step 2: Create `src/GameApi.lua`**

```lua
RollFor = RollFor or {}
local m = RollFor

if m.GameApi then return end

local M = {}
local interface = m.Interface

M.interface = {
  get_num_loot_items = "function",
  get_loot_slot_link = "function",
  get_loot_slot_info = "function",
  is_loot_slot_item = "function",
  is_loot_slot_coin = "function",
  loot_slot = "function",
  get_loot_source_guid = "function",
  get_loot_method = "function",
  get_master_loot_candidate = "function",
  get_raid_member = "function",
  is_party_leader = "function",
  is_in_group = "function",
  is_in_raid = "function",
  unit_name = "function",
  unit_class = "function",
}

---@class LootSlotInfo
---@field texture string
---@field name string
---@field quantity number
---@field quality number

---@class LootMethodInfo
---@field method string
---@field party_index number?
---@field raid_index number?

---@class RaidMemberInfo
---@field name string
---@field rank number
---@field class string

---@param api table  -- raw global table (_G)
function M.new( api )
  interface.validate( api, m.WowApi.GameApiInterface )

  -- Loot primitives

  local function get_num_loot_items()
    return api.GetNumLootItems()
  end

  local function get_loot_slot_link( slot )
    return api.GetLootSlotLink( slot )
  end

  local function get_loot_slot_info( slot )
    if m.vanilla or m.wotlk then
      -- Vanilla and WotLK: GetLootSlotInfo returns texture, name, quantity, quality (4 values)
      local texture, name, quantity, quality = api.GetLootSlotInfo( slot )

      return texture and {
        texture = texture,
        name = name,
        quantity = quantity,
        quality = quality,
      } or nil
    else
      -- BCC/Retail: GetLootSlotInfo returns texture, name, quantity, currencyID, quality (5 values)
      local texture, name, quantity, _, quality = api.GetLootSlotInfo( slot )

      return texture and {
        texture = texture,
        name = name,
        quantity = quantity,
        quality = quality,
      } or nil
    end
  end

  local function is_loot_slot_item( slot )
    return api.GetLootSlotType( slot ) == LOOT_SLOT_ITEM
  end

  local function is_loot_slot_coin( slot )
    return api.GetLootSlotType( slot ) == LOOT_SLOT_MONEY
  end

  local function loot_slot( slot )
    api.LootSlot( slot )
  end

  local function get_loot_source_guid()
    -- Delegates to existing version-aware wrapper in compat.lua
    return m.UnitGUID( api, "target" )
  end

  -- Group / loot method primitives

  local function get_loot_method()
    if m.vanilla then
      -- Vanilla: GetLootMethod returns (method, id)
      -- Party: id = 0-4 (0 = you)
      -- Raid: id = 1-40 (raid member index)
      local method, id = api.GetLootMethod()
      return { method = method, party_index = id, raid_index = nil }
    else
      -- WotLK 3.3.5a, BCC, Retail: GetLootMethod returns (method, partyMaster, raidMaster)
      -- Party: partyMaster = 0-4, raidMaster = nil
      -- Raid: partyMaster = nil, raidMaster = 1-40
      local method, party_id, raid_id = api.GetLootMethod()
      return { method = method, party_index = party_id, raid_index = raid_id }
    end
  end

  local function get_master_loot_candidate( slot, index )
    if m.vanilla then
      return api.GetMasterLootCandidate( index )
    else
      return api.GetMasterLootCandidate( slot, index )
    end
  end

  local function get_raid_member( index )
    local name, rank, _, _, _, class = api.GetRaidRosterInfo( index )
    return name and { name = name, rank = rank, class = class } or nil
  end

  local function is_party_leader()
    -- UnitIsGroupLeader was added in Cataclysm. If present (modern client), prefer it.
    if api.UnitIsGroupLeader then
      return api.UnitIsGroupLeader( "player" )
    end
    -- WotLK 3.3.5a fallback: UnitIsPartyLeader only works in party context.
    return api.UnitIsPartyLeader and api.UnitIsPartyLeader( "player" ) or false
  end

  local function is_in_group()
    return api.IsInGroup()
  end

  local function is_in_raid()
    return api.IsInRaid()
  end

  local function unit_name( unit )
    return api.UnitName( unit )
  end

  local function unit_class( unit )
    local _, class = api.UnitClass( unit )
    return class
  end

  return {
    get_num_loot_items = get_num_loot_items,
    get_loot_slot_link = get_loot_slot_link,
    get_loot_slot_info = get_loot_slot_info,
    is_loot_slot_item = is_loot_slot_item,
    is_loot_slot_coin = is_loot_slot_coin,
    loot_slot = loot_slot,
    get_loot_source_guid = get_loot_source_guid,
    get_loot_method = get_loot_method,
    get_master_loot_candidate = get_master_loot_candidate,
    get_raid_member = get_raid_member,
    is_party_leader = is_party_leader,
    is_in_group = is_in_group,
    is_in_raid = is_in_raid,
    unit_name = unit_name,
    unit_class = unit_class,
  }
end

m.GameApi = M
return M
```

**Step 3: Add `src/GameApi.lua` to the TOC**

Insert after `src/WowApi.lua` and before `src/LootFacade.lua` in `RollFor-WotLK.toc`:

```
src/GameApi.lua
```

Load order must be: `modules.lua` → `Interface.lua` → `WowApi.lua` → **GameApi.lua** → `LootFacade.lua` / `MasterLootCandidates.lua` / `PlayerInfo.lua`.

**Step 4: Verify module loads without error**

```bash
grep -n "GameApi" RollFor-WotLK.toc
# Expected: one line showing src/GameApi.lua

cd RollFor-WotLK && lua -e "RollFor = {}; dofile('src/modules.lua'); dofile('src/Interface.lua'); dofile('src/WowApi.lua'); dofile('src/GameApi.lua'); print('OK')"
# Expected: OK (no errors)
```

**Step 5: Commit**

```bash
git add src/GameApi.lua src/WowApi.lua RollFor-WotLK.toc
git commit -m "feat(api): add GameApi normalized adapter with WowApi.GameApiInterface"
```

---

### Task 1: Migrate MasterLootCandidates to GameApi

**Files:**
- Modify: `src/MasterLootCandidates.lua`
- Modify: `main.lua` (DI wiring — inject `game_api` instead of `api`)

**Step 1: Change constructor signature and validation**

Replace:
```lua
---@param api MasterLootCandidatesApi
---@param group_roster GroupRoster
---@param loot_list LootList
function M.new( api, group_roster, loot_list )
```

With:
```lua
---@param game_api GameApi
---@param group_roster GroupRoster
---@param loot_list LootList
function M.new( game_api, group_roster, loot_list )
  interface.validate( game_api, m.GameApi.interface )
```

**Step 2: Replace `api.GetMasterLootCandidate` calls with `game_api.get_master_loot_candidate`**

In `get(slot)` function:

Replace:
```lua
      if m.vanilla then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )
```

With:
```lua
        local name = game_api.get_master_loot_candidate( slot, i )
```

And remove the `else` branch:
```lua
      else
        local name = api.GetMasterLootCandidate( slot, i )
      end
```

So the loop becomes:
```lua
    for i = 1, 40 do
      local name = game_api.get_master_loot_candidate( slot, i )
```

In `get_index(slot, player_name)` function:

Replace:
```lua
      if m.vanilla then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )
```

With:
```lua
      local name = game_api.get_master_loot_candidate( slot, i )
```

And remove the `else` branch.

**Step 3: Remove all `m.vanilla` branching from this file**

After Step 2, the file should have zero `m.vanilla` references.

**Step 4: Update DI in `main.lua`**

Replace:
```lua
  M.master_loot_candidates = m.MasterLootCandidates.new( M.api(), M.group_roster, M.raw_loot_list )
```

With:
```lua
  M.game_api = m.GameApi.new( m.api )
  M.master_loot_candidates = m.MasterLootCandidates.new( M.game_api, M.group_roster, M.raw_loot_list )
```

Note: `M.game_api` is created once and reused for all consumers.

**Step 5: Verify no `m.vanilla` remains**

```bash
grep -n "m\.vanilla" src/MasterLootCandidates.lua
# Expected: no output (exit code 1)
```

**Step 6: Smoke-test in-game**

Be in a raid with master loot (you as ML). Loot a boss. Verify the master loot candidate list populates.

**Step 7: Commit**

```bash
git add src/MasterLootCandidates.lua main.lua
git commit -m "refactor: migrate MasterLootCandidates to GameApi adapter"
```

---

### Task 2: Migrate LootFacade — extract normalization into GameApi

**Files:**
- Modify: `src/LootFacade.lua`
- Modify: `main.lua` (inject `game_api` instead of `api`)

**Step 1: Change constructor signature**

Replace:
```lua
function M.new( event_frame, api )
  interface.validate( api, m.WowApi.LootInterface )
```

With:
```lua
function M.new( event_frame, game_api )
  interface.validate( game_api, m.GameApi.interface )
```

**Step 2: Replace internal normalization with GameApi calls**

`get_item_count()`:
```lua
  local function get_item_count()
    return game_api.get_num_loot_items()
  end
```

`get_source_guid()`:
```lua
  local function get_source_guid()
    return game_api.get_loot_source_guid()
  end
```

`get_link(slot)`:
```lua
  local function get_link( slot )
    return game_api.get_loot_slot_link( slot )
  end
```

`get_info(slot)` — remove the entire `if m.vanilla or m.wotlk` block:
```lua
  local function get_info( slot )
    return game_api.get_loot_slot_info( slot )
  end
```

`is_item(slot)`:
```lua
  local function is_item( slot )
    return game_api.is_loot_slot_item( slot )
  end
```

`is_coin(slot)`:
```lua
  local function is_coin( slot )
    return game_api.is_loot_slot_coin( slot )
  end
```

`loot_slot(slot)`:
```lua
  local function loot_slot( slot )
    game_api.loot_slot( slot )
  end
```

**Step 3: Remove all `m.vanilla` / `m.wotlk` branching from this file**

After Step 2, there should be no expansion checks.

**Step 4: Update DI in `main.lua`**

Replace:
```lua
  M.loot_facade = m.LootFacade.new( m.EventFrame.new( m.api ), m.api )
```

With:
```lua
  M.loot_facade = m.LootFacade.new( m.EventFrame.new( m.api ), M.game_api )
```

Note: `EventFrame` still receives raw `m.api` — the event-dispatch seam is out of scope for this phase.

**Step 5: Verify no expansion branching remains**

```bash
grep -n "m\.vanilla\|m\.wotlk\|m\.bcc" src/LootFacade.lua
# Expected: no output (exit code 1)
```

**Step 6: Smoke-test in-game**

Loot any mob. No Lua errors. The addon's loot detection should work identically.

**Step 7: Commit**

```bash
git add src/LootFacade.lua main.lua
git commit -m "refactor: migrate LootFacade normalization into GameApi adapter"
```

---

### Task 3: Migrate PlayerInfo — domain logic stays, primitives move

**Files:**
- Modify: `src/PlayerInfo.lua`
- Modify: `main.lua` (inject `game_api` instead of `api`)

**Step 1: Change constructor signature and validation**

Replace:
```lua
---@param api table
function M.new( api )
```

With:
```lua
---@param game_api GameApi
function M.new( game_api )
  interface.validate( game_api, m.GameApi.interface )
```

**Step 2: Replace `api.*` calls with `game_api.*` primitives**

`get_name()`:
```lua
  local function get_name()
    return game_api.unit_name( "player" )
  end
```

`get_class()`:
```lua
  local function get_class()
    return game_api.unit_class( "player" )
  end
```

**Step 3: Rewrite `is_master_looter()` using GameApi primitives**

Replace the entire function:
```lua
  local function is_master_looter()
    if not game_api.is_in_group() then return false end

    local loot = game_api.get_loot_method()
    if loot.method ~= "master" then return false end

    -- Party context: party_index == 0 means we are the ML
    if loot.party_index and loot.party_index == 0 then
      return true
    end

    -- Raid context: raid_index is our raid roster index; compare name
    if loot.raid_index then
      local member = game_api.get_raid_member( loot.raid_index )
      return member and member.name == get_name()
    end

    return false
  end
```

Note: This completely removes the `m.vanilla` / `m.wotlk` branching. The normalized `get_loot_method()` record makes the logic transparent.

**Step 4: Rewrite `is_leader()` using GameApi primitives**

Replace:
```lua
  local function is_leader()
    -- UnitIsGroupLeader was added in Cataclysm. In WotLK 3.3.5a, UnitIsPartyLeader
    -- only works in party context. For raids, check raid roster rank.
    if api.UnitIsGroupLeader then
      return api.UnitIsGroupLeader( "player" )
    end

    if api.IsInRaid() then
      local my_name = get_name()
      for i = 1, 40 do
        local name, rank = api.GetRaidRosterInfo( i )
        if name and name == my_name then
          return rank == 2
        end
      end
    end

    return api.UnitIsPartyLeader and api.UnitIsPartyLeader( "player" ) or false
  end
```

With:
```lua
  local function is_leader()
    if not game_api.is_in_group() then return false end

    -- Raid leader: scan roster for rank == 2
    if game_api.is_in_raid() then
      local my_name = get_name()
      for i = 1, 40 do
        local member = game_api.get_raid_member( i )
        if member and member.name == my_name then
          return member.rank == 2
        end
      end
      return false
    end

    -- Party leader
    return game_api.is_party_leader()
  end
```

**Step 5: Rewrite `is_assistant()` using GameApi primitives**

Replace:
```lua
  local function is_assistant()
    if not api.IsInRaid() then return false end
    local my_name = get_name()

    for i = 1, 40 do
      local name, rank = api.GetRaidRosterInfo( i )
      if name and name == my_name then
        return rank == 1
      end
    end

    return false
  end
```

With:
```lua
  local function is_assistant()
    if not game_api.is_in_raid() then return false end
    local my_name = get_name()

    for i = 1, 40 do
      local member = game_api.get_raid_member( i )
      if member and member.name == my_name then
        return member.rank == 1
      end
    end

    return false
  end
```

**Step 6: Remove all `m.vanilla` / `m.wotlk` / `m.bcc` branching from this file**

After Steps 3-5, there should be no expansion checks.

**Step 7: Update DI in `main.lua`**

Replace:
```lua
  M.player_info = m.PlayerInfo.new( M.api() )
```

With:
```lua
  M.player_info = m.PlayerInfo.new( M.game_api )
```

Also update `GroupRoster` if it takes `player_info` and calls through it (verify it doesn't need raw api):
```lua
  M.group_roster = m.GroupRoster.new( M.game_api, M.player_info )
```

Wait — check if `GroupRoster` uses raw API directly. Let me verify...

Actually, looking at main.lua line 112:
```lua
  M.group_roster = m.GroupRoster.new( M.api(), M.player_info )
```

We need to check if `GroupRoster` also branches on `m.vanilla` or uses raw APIs that should go through GameApi. Let me check...

**Hold — verify GroupRoster before changing it:**

```bash
grep -n "m\.vanilla\|m\.wotlk\|m\.bcc\|api\." src/GroupRoster.lua
```

If `GroupRoster` only uses `api.UnitName`, `api.UnitClass`, `api.GetRaidRosterInfo`, etc., it might also need migration. But the user's design doesn't mention it. If it has no `m.vanilla` branching, it can stay as-is or we can migrate it too.

For now, **keep `GroupRoster` on raw `M.api()`** unless it has variant branching. Only change `PlayerInfo` and `GroupRoster`'s `player_info` dependency.

So main.lua changes for Task 3:
```lua
  M.player_info = m.PlayerInfo.new( M.game_api )
  -- GroupRoster can stay on raw api if it has no variant calls
  M.group_roster = m.GroupRoster.new( M.api(), M.player_info )
```

Actually wait — if `GroupRoster` uses `api.GetRaidRosterInfo`, that could be variant. Let me check if the user wants GroupRoster included. The user's design says:

> `MasterLootCandidates`, `PlayerInfo`, and `LootFacade` each branch on `m.vanilla`

So only these three. I'll leave `GroupRoster` alone unless it has `m.vanilla`.

**Step 8: Verify no expansion branching remains**

```bash
grep -n "m\.vanilla\|m\.wotlk\|m\.bcc" src/PlayerInfo.lua
# Expected: no output (exit code 1)
```

**Step 9: Smoke-test in-game**

```
/run local pi = RollFor and RollFor.player_info; if pi then print("ML:",pi.is_master_looter()); print("Leader:",pi.is_leader()); print("Assist:",pi.is_assistant()) else print("not loaded") end
```

Test in three contexts:
1. Solo (not in group) — all should return `false`
2. Party, you as leader — `is_leader()` should return `true`
3. Raid, you as leader/ML — `is_leader()` and `is_master_looter()` should return `true`

**Step 10: Commit**

```bash
git add src/PlayerInfo.lua main.lua
git commit -m "refactor: migrate PlayerInfo to GameApi adapter, keep domain logic in caller"
```

---

### Task 4: Verify all other consumers of `M.api()` still work

**Files:**
- Verify: `main.lua` (remaining `M.api()` consumers)

After Tasks 1-3, `main.lua` still passes raw `M.api()` to several modules:
- `M.group_roster = m.GroupRoster.new( M.api(), M.player_info )`
- `M.tooltip_reader = m.TooltipReader.new( M.api() )`
- `M.name_matcher = m.NameManualMatcher.new( db(...), M.api, ... )`
- `M.auto_loot = m.AutoLoot.new( ..., M.api, ... )`
- `M.softres_gui = m.SoftResGui.new( M.api, ... )`
- `M.minimap_button = m.MinimapButton.new( M.api, ... )`
- `M.master_loot_warning = m.MasterLootWarning.new( M.api, ... )`

These are out of scope for this phase, but verify they still load correctly.

```bash
grep -n "M\.api" main.lua | grep -v "M\.api = function\|M\.game_api\|m\.api"
# Should show remaining consumers that were NOT changed
```

Smoke-test: log in, type `/rfo`, verify no Lua errors.

```bash
git add main.lua
git commit -m "chore: update main.lua DI wiring for GameApi migration"
```

---

### Task 5: Global verification — no `m.vanilla` in target files

**Step 1: Run the success-criteria grep**

```bash
grep -r "m\.vanilla\|m\.wotlk\|m\.bcc" \
  src/MasterLootCandidates.lua \
  src/LootFacade.lua \
  src/PlayerInfo.lua
# Expected: no output (exit code 1)
```

**Step 2: Verify `GameApi` contains all variant branching**

```bash
grep -n "m\.vanilla\|m\.wotlk\|m\.bcc" src/GameApi.lua
# Expected: matches in get_loot_slot_info, get_loot_method, get_master_loot_candidate
```

**Step 3: Verify consumers only call GameApi methods**

```bash
grep -n "api\.\|game_api\." src/MasterLootCandidates.lua
# Expected: only "game_api." references, no "api." (raw _G) references

grep -n "api\.\|game_api\." src/LootFacade.lua
# Expected: only "game_api." references (except event_frame which is separate)

grep -n "api\.\|game_api\." src/PlayerInfo.lua
# Expected: only "game_api." references
```

**Step 4: Verify `main.lua` has `M.game_api`**

```bash
grep -n "game_api" main.lua
# Expected: M.game_api = ... and injection into the three consumers
```

**Step 5: Commit verification results (optional — can be part of final commit)**

No code changes — this is a verification checkpoint.

---

### Task 6: Follow-up — AutoLoot also branches on `m.vanilla`

**Note:** `src/AutoLoot.lua` also contains `if m.vanilla then` branching for `GetMasterLootCandidate`. It is NOT included in this phase per the design boundary, but it should be migrated in the follow-up de-vanilla strip or a subsequent phase.

```bash
grep -n "m\.vanilla" src/AutoLoot.lua
# Shows: lines 42-43 and lines adjacent to GetMasterLootCandidate calls
```

When migrating, follow the same pattern:
1. Change constructor to receive `game_api`
2. Replace `api.GetMasterLootCandidate` with `game_api.get_master_loot_candidate`
3. Remove `m.vanilla` branching
4. Update DI in `main.lua`

---

## In-Game Testing Instructions

After all commits applied:

### Basic load test
1. Copy addon to WoW `Interface/AddOns/`
2. Log in — no Lua errors on load

### LootFacade smoke test (Task 2)
3. Kill any mob, loot it — no errors, loot list populates correctly

### MasterLootCandidates smoke test (Task 1)
4. Be in a raid with master loot (you as ML). Kill boss, open loot.
5. Master loot candidate list should populate with raid member names.

### PlayerInfo smoke test (Task 3)
6. Run in chat (solo): `/run local pi=RollFor.player_info; print(pi.is_master_looter(),pi.is_leader(),pi.is_assistant())`
   Expected: `false false false`
7. Form a party, make yourself leader: `/run print(RollFor.player_info.is_leader())`
   Expected: `true`
8. Disband party, join a raid, make yourself leader and ML: `/run print(RollFor.player_info.is_leader(),RollFor.player_info.is_master_looter())`
   Expected: `true true`

### Regression test
9. `/rfo` opens options without errors
10. `/sr import <test data>` works without errors
11. `/rf [ItemLink]` starts rolling without errors

---

## Post-Implementation Notes

- The `GameApi` module is the single source of truth for "what does this addon assume about the 3.3.5a client?"
- The de-vanilla strip (next phase) now only needs to delete vanilla arms from `src/GameApi.lua` and drop the `if m.vanilla then self = this end` UI guards — the consumers are already clean.
- `AutoLoot.lua` is the remaining file with API-level `m.vanilla` branching. Migrate it in the next phase.
