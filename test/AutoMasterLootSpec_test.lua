package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/wotlk/compat" )
local u = require( "test/utils" )
local lu = u.luaunit()

u.mock_api()

-- Ensure shared utility functions (target_name, target_dead, is_master_loot, table_contains_value) are loaded.
u.modules()

require( "src/BossList" )

local AutoMasterLoot = require( "src/AutoMasterLoot" )
local PlayerInfo = require( "mocks/PlayerInfo" )

local m = RollFor
local loot_method_calls = {}

---@param target_name string
---@param zone string
---@param is_dead boolean
---@param is_master_loot boolean
local function setup_context( target_name, zone, is_dead, is_master_loot )
  loot_method_calls = {}

  u.mock( "GetRealZoneText", zone )
  u.mock( "UnitName", function( unit )
    return unit == "target" and target_name or "Psikutas"
  end )
  u.mock( "UnitIsDead", function( unit )
    return is_dead and unit == "target"
  end )
  u.mock( "IsInGroup", true )
  u.mock( "GetLootMethod", function()
    return is_master_loot and "master" or "group", nil, nil
  end )
  u.mock( "SetLootMethod", function( method, player )
    table.insert( loot_method_calls, { method = method, player = player } )
  end )
end

---@param auto_master_loot boolean
---@param leader boolean
local function create_auto_master_loot( auto_master_loot, leader )
  local config = u.mock_config( { auto_master_loot = auto_master_loot } ).new()
  local player_info = PlayerInfo.new( "Psikutas", "Warrior", false, leader )

  return AutoMasterLoot.new( config, m.BossList.zones, player_info )
end

AutoMasterLootSpec = {}

function AutoMasterLootSpec:should_switch_to_master_loot_on_obsidian_sanctum_boss()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Sartharion", "The Obsidian Sanctum", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 1 )
  lu.assertEquals( loot_method_calls[ 1 ].method, "master" )
  lu.assertEquals( loot_method_calls[ 1 ].player, "Psikutas" )
end

function AutoMasterLootSpec:should_switch_to_master_loot_on_vault_of_archavon_boss()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Archavon the Stone Watcher", "Vault of Archavon", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 1 )
  lu.assertEquals( loot_method_calls[ 1 ].method, "master" )
  lu.assertEquals( loot_method_calls[ 1 ].player, "Psikutas" )
end

function AutoMasterLootSpec:should_not_switch_when_targeting_a_non_boss()
  local aml = create_auto_master_loot( true, true )
  setup_context( "A Feral Wolf", "The Obsidian Sanctum", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_not_switch_when_not_in_a_supported_zone()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Sartharion", "Elwynn Forest", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_not_switch_when_already_master_loot()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Sartharion", "The Obsidian Sanctum", false, true )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_not_switch_when_not_leader()
  local aml = create_auto_master_loot( true, false )
  setup_context( "Sartharion", "The Obsidian Sanctum", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_not_switch_when_target_is_dead()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Sartharion", "The Obsidian Sanctum", true, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_not_switch_when_auto_master_loot_is_disabled()
  local aml = create_auto_master_loot( false, true )
  setup_context( "Sartharion", "The Obsidian Sanctum", false, false )

  aml.on_player_target_changed( "player" )

  lu.assertEquals( #loot_method_calls, 0 )
end

function AutoMasterLootSpec:should_ignore_auto_target_changed_events()
  local aml = create_auto_master_loot( true, true )
  setup_context( "Sartharion", "The Obsidian Sanctum", false, false )

  aml.on_player_target_changed( "0.5" )

  lu.assertEquals( #loot_method_calls, 0 )
end

os.exit( lu.LuaUnit.run() )
