# Manual Soft-Res Add/Remove Command

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Allow the raid leader to manually add or remove a soft-res entry for a player via `/sr add PlayerName [ItemLink]` and `/sr rm PlayerName [ItemLink]`, without needing to re-import from the website.

**Architecture:** Add `add_player_item` and `remove_player_item` methods to `SoftRes.lua`, wire into the existing `/sr` slash command parser in `main.lua`, and add minimap tooltip help lines. The decorator chain (MatchedName → AwardedLoot → PresentPlayers) delegates `get()` without caching, so changes to the base `unfiltered_softres` immediately reflect downstream.

**Tech Stack:** Lua 5.1, LuaUnit test framework, existing SoftRes/ItemUtils/GroupRoster modules.

---

## Context

Currently, soft-res data can only be imported in bulk from softres.it / raidres.fly.dev. There is no way to manually add a late-comer's SR or fix a mistake without re-importing the entire dataset from the website. This is a common pain point during raids.

### Data Structure Reference

`softres_data` is a table keyed by `item_id`:
```lua
softres_data[item_id] = {
  quality = 4,
  rollers = {
    { name = "Psikutas", rolls = 1, type = "Roller" },
    { name = "Obszansen", rolls = 1, type = "Roller" },
  }
}
```

Roller entries are created by `m.Types.make_roller(name, rolls)`.

### Existing Commands
- `/sr` — Opens import GUI
- `/sr init` — Clears all SR data and opens GUI
- `/srs` — Shows all SRs
- `/src` — Checks SR status
- `/sro` — Manual name matching

### Key Files
- `src/SoftRes.lua` — Core softres module (item_id → rollers map)
- `src/Types.lua` — `make_roller(name, rolls)` factory
- `src/ItemUtils.lua` — `get_item_id(item_link)` parser
- `src/MinimapButton.lua` — Tooltip help text
- `main.lua:384` — `on_softres_command(args)` handler
- `main.lua:120` — `M.item_utils = m.ItemUtils`
- `test/SoftRes_test.lua` — Existing test file using LuaUnit

---

## Task 1: Write failing tests for `add_player_item`

**Files:**
- Modify: `test/SoftRes_test.lua`

**Step 1: Add test cases**

Append before the `os.exit` line at the bottom of `test/SoftRes_test.lua`:

```lua
function SoftResIntegrationSpec:should_add_a_player_item_manually()
  -- Given
  local soft_res = mod.new()

  -- When
  local result = soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- Then
  lu.assertEquals( result, true )
  local rollers = soft_res.get( 19019 )
  lu.assertEquals( #rollers, 1 )
  lu.assertEquals( rollers[1].name, "Psikutas" )
  lu.assertEquals( rollers[1].rolls, 1 )
  lu.assertEquals( rollers[1].type, "Roller" )
end

function SoftResIntegrationSpec:should_increment_rolls_when_adding_same_player_and_item()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- When
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- Then
  local rollers = soft_res.get( 19019 )
  lu.assertEquals( #rollers, 1 )
  lu.assertEquals( rollers[1].rolls, 2 )
end

function SoftResIntegrationSpec:should_add_multiple_players_to_same_item()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- When
  soft_res.add_player_item( "Obszczymucha", 19019, 4 )

  -- Then
  local rollers = soft_res.get( 19019 )
  lu.assertEquals( #rollers, 2 )
end

function SoftResIntegrationSpec:should_return_false_when_adding_with_nil_player()
  -- Given
  local soft_res = mod.new()

  -- When
  local result = soft_res.add_player_item( nil, 19019, 4 )

  -- Then
  lu.assertEquals( result, false )
end

function SoftResIntegrationSpec:should_return_false_when_adding_with_nil_item_id()
  -- Given
  local soft_res = mod.new()

  -- When
  local result = soft_res.add_player_item( "Psikutas", nil, 4 )

  -- Then
  lu.assertEquals( result, false )
end
```

**Step 2: Run tests to verify they fail**

```bash
cd test && lua5.1 SoftRes_test.lua -v -o text
```

Expected: 5 new tests FAIL with `attempt to call a nil value` (method doesn't exist yet).

---

## Task 2: Implement `add_player_item` in SoftRes

**Files:**
- Modify: `src/SoftRes.lua`

**Step 1: Add the function**

In `src/SoftRes.lua`, after the `get_player_items` function (around line 168) and before the `return {` block (line 171), add:

```lua
  local function add_player_item( player_name, item_id, quality )
    if not player_name or not item_id then return false end

    softres_data[ item_id ] = softres_data[ item_id ] or {
      quality = quality,
      rollers = {}
    }

    -- Check if player already has this item SR'd
    for _, roller in ipairs( softres_data[ item_id ].rollers ) do
      if roller.name == player_name then
        roller.rolls = roller.rolls + 1
        return true
      end
    end

    table.insert( softres_data[ item_id ].rollers, m.Types.make_roller( player_name, 1 ) )
    return true
  end
```

**Step 2: Expose in the return table**

Add `add_player_item = add_player_item,` to the return table after `get_player_items`.

**Step 3: Run tests to verify they pass**

```bash
cd test && lua5.1 SoftRes_test.lua -v -o text
```

Expected: All tests PASS including the 5 new ones.

**Step 4: Commit**

```bash
git add src/SoftRes.lua test/SoftRes_test.lua
git commit -m "feat(softres): add add_player_item method

Allows programmatic addition of individual player SR entries.
Increments rolls if the player already has that item SR'd."
```

---

## Task 3: Write failing tests for `remove_player_item`

**Files:**
- Modify: `test/SoftRes_test.lua`

**Step 1: Add test cases**

Append before the `os.exit` line:

```lua
function SoftResIntegrationSpec:should_remove_a_player_item()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- When
  local result = soft_res.remove_player_item( "Psikutas", 19019 )

  -- Then
  lu.assertEquals( result, true )
  lu.assertEquals( #soft_res.get( 19019 ), 0 )
end

function SoftResIntegrationSpec:should_decrement_rolls_when_removing_multi_roll()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- When
  local result = soft_res.remove_player_item( "Psikutas", 19019 )

  -- Then
  lu.assertEquals( result, true )
  local rollers = soft_res.get( 19019 )
  lu.assertEquals( #rollers, 1 )
  lu.assertEquals( rollers[1].rolls, 1 )
end

function SoftResIntegrationSpec:should_return_false_when_removing_nonexistent_item()
  -- Given
  local soft_res = mod.new()

  -- When
  local result = soft_res.remove_player_item( "Psikutas", 99999 )

  -- Then
  lu.assertEquals( result, false )
end

function SoftResIntegrationSpec:should_return_false_when_removing_player_not_on_item()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )

  -- When
  local result = soft_res.remove_player_item( "Obszczymucha", 19019 )

  -- Then
  lu.assertEquals( result, false )
  lu.assertEquals( #soft_res.get( 19019 ), 1 )
end

function SoftResIntegrationSpec:should_clean_up_item_entry_when_last_roller_removed()
  -- Given
  local soft_res = mod.new()
  soft_res.add_player_item( "Psikutas", 19019, 4 )
  soft_res.remove_player_item( "Psikutas", 19019 )

  -- When
  local ids = soft_res.get_item_ids()

  -- Then
  lu.assertEquals( #ids, 0 )
end
```

**Step 2: Run tests to verify they fail**

```bash
cd test && lua5.1 SoftRes_test.lua -v -o text
```

Expected: 5 new tests FAIL with `attempt to call a nil value`.

---

## Task 4: Implement `remove_player_item` in SoftRes

**Files:**
- Modify: `src/SoftRes.lua`

**Step 1: Add the function**

After `add_player_item`, add:

```lua
  local function remove_player_item( player_name, item_id )
    if not player_name or not item_id then return false end
    if not softres_data[ item_id ] then return false end

    local rollers = softres_data[ item_id ].rollers
    for i, roller in ipairs( rollers ) do
      if roller.name == player_name then
        if roller.rolls > 1 then
          roller.rolls = roller.rolls - 1
        else
          table.remove( rollers, i )
        end

        -- Clean up empty item entries
        if #rollers == 0 then
          softres_data[ item_id ] = nil
        end

        return true
      end
    end

    return false
  end
```

**Step 2: Expose in the return table**

Add `remove_player_item = remove_player_item,` to the return table after `add_player_item`.

**Step 3: Run tests to verify they pass**

```bash
cd test && lua5.1 SoftRes_test.lua -v -o text
```

Expected: All tests PASS (16 total in this file).

**Step 4: Commit**

```bash
git add src/SoftRes.lua test/SoftRes_test.lua
git commit -m "feat(softres): add remove_player_item method

Decrements roll count or removes the player entirely. Cleans up
the item entry when no rollers remain."
```

---

## Task 5: Wire `/sr add` and `/sr rm` slash commands

**Files:**
- Modify: `main.lua` (function `on_softres_command` at line 384)

**Step 1: Rewrite `on_softres_command`**

Replace the existing function (lines 384-389):

```lua
local function on_softres_command( args )
  if args == "init" then
    clear_data()
  end
  M.softres_gui.toggle()
end
```

With:

```lua
local function on_softres_command( args )
  if args == "init" then
    clear_data()
    M.softres_gui.toggle()
    return
  end

  -- /sr add PlayerName [ItemLink]
  local add_player, add_link = string.match( args, "^add (%S+) (|.+|r)$" )
  if add_player and add_link then
    local item_id = M.item_utils.get_item_id( add_link )
    if not item_id then
      M.chat.info( "Invalid item link." )
      return
    end

    -- Resolve proper capitalization from group roster
    local group_player = M.group_roster.find_player( add_player )
    if group_player then
      add_player = group_player.name
    end

    local quality = select( 3, m.api.GetItemInfo( add_link ) ) or 0
    if M.unfiltered_softres.add_player_item( add_player, item_id, quality ) then
      M.name_matcher.auto_match()
      update_minimap_icon()
      local display = group_player and m.colorize_player_by_class( group_player.name, group_player.class ) or add_player
      M.chat.info( string.format( "Added SR: %s → %s", display, add_link ) )
    else
      M.chat.info( "Failed to add SR." )
    end
    return
  end

  -- /sr rm PlayerName [ItemLink]
  local rm_player, rm_link = string.match( args, "^rm (%S+) (|.+|r)$" )
  if rm_player and rm_link then
    local item_id = M.item_utils.get_item_id( rm_link )
    if not item_id then
      M.chat.info( "Invalid item link." )
      return
    end

    local group_player = M.group_roster.find_player( rm_player )
    if group_player then
      rm_player = group_player.name
    end

    if M.unfiltered_softres.remove_player_item( rm_player, item_id ) then
      M.name_matcher.auto_match()
      update_minimap_icon()
      local display = group_player and m.colorize_player_by_class( group_player.name, group_player.class ) or rm_player
      M.chat.info( string.format( "Removed SR: %s → %s", display, rm_link ) )
    else
      local display = group_player and m.colorize_player_by_class( group_player.name, group_player.class ) or rm_player
      M.chat.info( string.format( "%s does not have that item soft-ressed.", display ) )
    end
    return
  end

  -- /sr (no args or unrecognized) — toggle GUI
  M.softres_gui.toggle()
end
```

**Step 2: Run full test suite**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -v -o text 2>&1; done | grep -E 'success|failure|error' | tail -1
```

Expected: All tests pass (no regressions).

**Step 3: Commit**

```bash
git add main.lua
git commit -m "feat: wire /sr add and /sr rm slash commands

/sr add PlayerName [ItemLink] - adds a soft-res entry
/sr rm PlayerName [ItemLink] - removes a soft-res entry

Resolves player name capitalization from group roster. Updates
minimap icon color and name matcher after modification."
```

---

## Task 6: Add minimap tooltip help lines

**Files:**
- Modify: `src/MinimapButton.lua`

**Step 1: Add help text for new commands**

In `src/MinimapButton.lua`, find the block (around line 100):
```lua
        api().GameTooltip:AddLine( string.format( "%s - %s", hl( "/sr" ), white( "manage softres" ) ) )
```

Add these two lines immediately after it:
```lua
        api().GameTooltip:AddLine( string.format( "%s %s %s - %s", hl( "/sr add" ), grey( "<player>" ), grey( "<item>" ), white( "add SR for player" ) ) )
        api().GameTooltip:AddLine( string.format( "%s %s %s - %s", hl( "/sr rm" ), grey( "<player>" ), grey( "<item>" ), white( "remove SR for player" ) ) )
```

**Step 2: Run full test suite**

```bash
cd test && for f in *_test.lua; do lua5.1 "$f" -v -o text 2>&1; done | grep -E 'success|failure|error' | tail -1
```

Expected: All tests pass (no regressions).

**Step 3: Commit**

```bash
git add src/MinimapButton.lua
git commit -m "feat: add /sr add and /sr rm to minimap tooltip help"
```

---

## Task 7: In-game verification

**No code changes — manual validation only.**

**Step 1: Reload UI**

```
/reload
```

**Step 2: Test adding an SR**

```
/sr add Rainga [Shift+Click an item]
```

Expected: Chat prints "Added SR: Rainga → [Item Name]"

**Step 3: Verify it shows in SR list**

```
/srs
```

Expected: Shows Rainga with the item listed.

**Step 4: Test removing an SR**

```
/sr rm Rainga [Shift+Click same item]
```

Expected: Chat prints "Removed SR: Rainga → [Item Name]"

**Step 5: Verify minimap tooltip**

Hover minimap button — should show `/sr add` and `/sr rm` lines.

**Step 6: Test edge cases**

- `/sr add NonexistentPlayer [Item]` — should still add (uses raw name)
- `/sr rm Rainga [Item they don't have]` — should print "does not have that item soft-ressed"
- `/sr add Rainga [Same item twice]` — should increment rolls (2 SRs)

**Step 7: Tag release if all good**

```bash
git tag 1.3.1
git push origin master --tags
```

---

## Summary

| Task | What | Effort |
|------|------|--------|
| 1 | Write failing tests for `add_player_item` | 2 min |
| 2 | Implement `add_player_item` + pass tests | 3 min |
| 3 | Write failing tests for `remove_player_item` | 2 min |
| 4 | Implement `remove_player_item` + pass tests | 3 min |
| 5 | Wire `/sr add` and `/sr rm` in `main.lua` | 5 min |
| 6 | Add minimap tooltip help lines | 2 min |
| 7 | In-game verification | 5 min |

**Usage after implementation:**
```
/sr add Rainga [Thunderfury, Blessed Blade of the Windseeker]
/sr rm Rainga [Thunderfury, Blessed Blade of the Windseeker]
/srs  -- verify it shows up
```
