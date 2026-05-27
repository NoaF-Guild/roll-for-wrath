package.path = "./?.lua;" .. package.path .. ";../?.lua;../libs/vanilla/LibStub/?.lua"

require( "src/wotlk/compat" )
local utils = require( "test/utils" )
local lu, eq = utils.luaunit( "assertEquals" )
local m = require( "src/modules" )
require( "src/Interface" )
require( "src/Types" )
require( "src/ItemUtils" )
require( "src/RollingLogicUtils" )
require( "src/WinnerTracker" )

RollForReceiverSpec = {}

-- Captured AceComm callback from RegisterComm
local comm_callback

-- Build mocks that let us intercept the AceComm registration and simulate messages.
local function setup()
  comm_callback = nil

  -- Mock LibStub so RollForReceiver can load its libs
  utils.mock_library( "AceComm-3.0", {
    RegisterComm = function( _, channel, callback )
      comm_callback = callback
    end,
    SendCommMessage = function() end,
  } )

  -- Identity encode/decode — payload tables pass straight through
  utils.mock_library( "LibSerialize", {
    Serialize = function( _, data ) return data end,
    Deserialize = function( _, data ) return true, data end,
  } )
  utils.mock_library( "LibDeflate", {
    CompressDeflate = function( _, data ) return data end,
    DecompressDeflate = function( _, data ) return data end,
    EncodeForWoWAddonChannel = function( _, data ) return data end,
    DecodeForWoWAddonChannel = function( _, data ) return data end,
  } )

  -- Mock the global WoW API that RollForReceiver references
  m.api = m.api or {}
  m.api.UnitName = function() return "TestPlayer" end
  m.api.GetItemInfo = function( id )
    if id == 19019 then return "Thunderfury, Blessed Blade of the Windseeker", "item:19019" end
    return nil
  end

  -- Clear the module guard and package cache so we get a fresh module each test
  m.RollForReceiver = nil
  package.loaded[ "src/RollForReceiver" ] = nil
  require( "src/RollForReceiver" )
end

local function item_link( name, id )
  return string.format( "|cff9d9d9d|Hitem:%s::::::::20:257::::::|h[%s]|h|r", id, name )
end

local function mock_rolling_popup()
  local calls = {}
  return {
    show = function( self ) table.insert( calls, "show" ) end,
    hide = function() table.insert( calls, "hide" ) end,
    refresh = function( self, data ) table.insert( calls, { "refresh", data } ) end,
    calls = calls
  }
end

local function mock_winner_tracker()
  local tracked = {}
  return {
    track = function( name, link, roll_type, roll, strategy )
      table.insert( tracked, { name = name, link = link, roll_type = roll_type, roll = roll, strategy = strategy } )
    end,
    tracked = tracked
  }
end

local function mock_awarded_loot()
  local awards = {}
  return {
    award = function( player_name, item_id, roll_data, rolling_strategy, award_item_link, player_class, sr_plus, plus_one )
      table.insert( awards, {
        player_name = player_name,
        item_id = item_id,
        roll_data = roll_data,
        rolling_strategy = rolling_strategy,
        item_link = award_item_link,
        player_class = player_class,
        sr_plus = sr_plus,
        plus_one = plus_one,
      } )
    end,
    awards = awards
  }
end

--- Simulate receiving a message from another player through AceComm.
--- The mock libs are identity transforms, so we pass the raw payload table.
local function simulate_message( payload, sender )
  assert( comm_callback, "comm_callback not captured — did setup() run?" )
  comm_callback( nil, payload, nil, sender or "OtherPlayer" )
end

-- ---------------------------------------------------------------------------
-- Tests: RF_WIN syncs to winner_tracker
-- ---------------------------------------------------------------------------

function RollForReceiverSpec:should_track_winner_on_rf_win()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local db = {}
  m.RollForReceiver.new( popup, db, wt )

  local link = item_link( "Thunderfury", 19019 )

  -- First send RF_ITEM to establish state
  simulate_message( { type = "RF_ITEM", link = link, count = 1 } )
  -- Then RF_WIN
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 } )

  eq( #wt.tracked, 1 )
  eq( wt.tracked[1].name, "Psikutas" )
  eq( wt.tracked[1].roll_type, "MainSpec" )
  eq( wt.tracked[1].roll, 95 )
  eq( wt.tracked[1].strategy, "NormalRoll" )
end

-- ---------------------------------------------------------------------------
-- Tests: RF_WIN does NOT currently sync to awarded_loot (the bug)
-- This test documents the current broken behavior so it fails when we fix it.
-- ---------------------------------------------------------------------------

function RollForReceiverSpec:should_sync_winner_to_awarded_loot_on_rf_win()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  -- Currently RollForReceiver.new() only takes (rolling_popup, db, winner_tracker).
  -- After the fix it will also accept awarded_loot.
  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 1 } )
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 } )

  -- After fix: awarded_loot.award() should have been called
  eq( #al.awards, 1 )
  eq( al.awards[1].player_name, "Psikutas" )
  eq( al.awards[1].item_id, 19019 )
  eq( al.awards[1].item_link, link )
  eq( al.awards[1].player_class, "Warrior" )
  eq( al.awards[1].rolling_strategy, "NormalRoll" )
  eq( al.awards[1].roll_data.roll_type, "MainSpec" )
  eq( al.awards[1].roll_data.roll, 95 )
end

function RollForReceiverSpec:should_sync_multiple_winners_to_awarded_loot()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 2 } )
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 } )
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Obszansen", class = "Mage", roll_type = "OffSpec", roll = 42 } )

  eq( #al.awards, 2 )
  eq( al.awards[1].player_name, "Psikutas" )
  eq( al.awards[2].player_name, "Obszansen" )
  eq( al.awards[2].player_class, "Mage" )
  eq( al.awards[2].roll_data.roll_type, "OffSpec" )
end

function RollForReceiverSpec:should_not_sync_to_awarded_loot_without_state()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  -- RF_WIN without a prior RF_ITEM and no link in payload — should be a no-op
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 } )

  eq( #al.awards, 0 )
  eq( #wt.tracked, 0 )
end

function RollForReceiverSpec:should_sync_direct_award_without_prior_rf_item()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  -- RF_WIN with link in payload but no prior RF_ITEM (direct award / auto-loot)
  simulate_message( { type = "RF_WIN", strategy = nil, name = "Psikutas", class = "Warrior", roll_type = nil, roll = nil, link = link, item_id = 19019 } )

  eq( #al.awards, 1 )
  eq( al.awards[1].player_name, "Psikutas" )
  eq( al.awards[1].item_id, 19019 )
  eq( al.awards[1].item_link, link )
  eq( #wt.tracked, 1 )
end

function RollForReceiverSpec:should_not_award_when_awarded_loot_not_provided()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local db = {}

  -- No awarded_loot passed — should still work for winner_tracker only
  m.RollForReceiver.new( popup, db, wt )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 1 } )
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 } )

  -- winner_tracker still works
  eq( #wt.tracked, 1 )
end

function RollForReceiverSpec:should_ignore_messages_from_self()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 1 }, "TestPlayer" )
  simulate_message( { type = "RF_WIN", strategy = "NormalRoll", name = "Psikutas", class = "Warrior", roll_type = "MainSpec", roll = 95 }, "TestPlayer" )

  eq( #al.awards, 0 )
  eq( #wt.tracked, 0 )
end

function RollForReceiverSpec:should_sync_softres_win_to_awarded_loot()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 1 } )
  simulate_message( { type = "RF_WIN", strategy = "SoftResRoll", name = "Rainga", class = "Druid", roll_type = "SoftRes", roll = 78 } )

  eq( #al.awards, 1 )
  eq( al.awards[1].player_name, "Rainga" )
  eq( al.awards[1].rolling_strategy, "SoftResRoll" )
  eq( al.awards[1].roll_data.roll_type, "SoftRes" )
end

function RollForReceiverSpec:should_sync_raid_roll_win_to_awarded_loot()
  setup()
  local popup = mock_rolling_popup()
  local wt = mock_winner_tracker()
  local al = mock_awarded_loot()
  local db = {}

  m.RollForReceiver.new( popup, db, wt, al )

  local link = item_link( "Thunderfury", 19019 )

  simulate_message( { type = "RF_ITEM", link = link, count = 1 } )
  simulate_message( { type = "RF_WIN", strategy = "RaidRoll", name = "Lucky", class = "Rogue", roll_type = "MainSpec", roll = 7 } )

  eq( #al.awards, 1 )
  eq( al.awards[1].rolling_strategy, "RaidRoll" )
end

lu.LuaUnit.run()
