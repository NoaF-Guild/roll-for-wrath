package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/bcc/compat" )
local utils = require( "test/utils" )
local lu, eq = utils.luaunit( "assertEquals" )
local m = require( "src/modules" )
require( "src/Interface" )
require( "src/WowApi" )
require( "src/GameApi" )

-- WotLK code paths
m.wotlk = true
m.vanilla = nil

-- WoW constants
LOOT_SLOT_ITEM = 1
LOOT_SLOT_MONEY = 2

--- Build a mock raw-API table satisfying m.WowApi.GameApiInterface.
--- Every required method defaults to a noop; pass overrides to customize.
local function mock_raw_api( overrides )
  overrides = overrides or {}

  local defaults = {
    GetNumLootItems      = function() return 0 end,
    GetLootSlotLink      = function() return nil end,
    GetLootSlotInfo      = function() return nil end,
    GetLootSlotType      = function() return 0 end,
    LootSlot             = function() end,
    UnitGUID             = function() return "0x0000" end,
    UnitName             = function() return "Psikutas" end,
    UnitClass            = function() return "Warrior", "WARRIOR" end,
    GetLootMethod        = function() return "group", 0, nil end,
    GetMasterLootCandidate = function() return nil end,
    GetRaidRosterInfo    = function() return nil end,
    UnitIsPartyLeader    = function() return false end,
    IsInRaid             = function() return false end,
    IsInGroup            = function() return false end,
  }

  for k, v in pairs( overrides ) do
    defaults[ k ] = v
  end

  return defaults
end

-- ---------------------------------------------------------------------------
-- get_loot_method
-- ---------------------------------------------------------------------------

GetLootMethodSpec = {}

function GetLootMethodSpec.should_return_master_loot_in_party_when_we_are_ml()
  -- Given
  local api = mock_raw_api( {
    GetLootMethod = function() return "master", 0, nil end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_method()

  -- Then
  eq( result.method, "master" )
  eq( result.party_index, 0 )
  eq( result.raid_index, nil )
end

function GetLootMethodSpec.should_return_master_loot_in_party_when_someone_else_is_ml()
  -- Given
  local api = mock_raw_api( {
    GetLootMethod = function() return "master", 2, nil end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_method()

  -- Then
  eq( result.method, "master" )
  eq( result.party_index, 2 )
  eq( result.raid_index, nil )
end

function GetLootMethodSpec.should_return_master_loot_in_raid()
  -- Given
  local api = mock_raw_api( {
    GetLootMethod = function() return "master", nil, 5 end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_method()

  -- Then
  eq( result.method, "master" )
  eq( result.party_index, nil )
  eq( result.raid_index, 5 )
end

function GetLootMethodSpec.should_return_group_loot()
  -- Given
  local api = mock_raw_api( {
    GetLootMethod = function() return "group", 0, nil end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_method()

  -- Then
  eq( result.method, "group" )
  eq( result.party_index, 0 )
  eq( result.raid_index, nil )
end

-- ---------------------------------------------------------------------------
-- get_loot_slot_info
-- ---------------------------------------------------------------------------

GetLootSlotInfoSpec = {}

function GetLootSlotInfoSpec.should_return_structured_table_for_valid_slot()
  -- Given
  local api = mock_raw_api( {
    GetLootSlotInfo = function( slot )
      if slot == 1 then
        return "Interface\\Icons\\INV_Misc_Gem_01", "Ruby", 3, 4
      end
    end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_slot_info( 1 )

  -- Then
  eq( result.texture, "Interface\\Icons\\INV_Misc_Gem_01" )
  eq( result.name, "Ruby" )
  eq( result.quantity, 3 )
  eq( result.quality, 4 )
end

function GetLootSlotInfoSpec.should_return_nil_when_texture_is_nil()
  -- Given
  local api = mock_raw_api( {
    GetLootSlotInfo = function() return nil end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_loot_slot_info( 99 )

  -- Then
  eq( result, nil )
end

-- ---------------------------------------------------------------------------
-- is_loot_slot_item / is_loot_slot_coin
-- ---------------------------------------------------------------------------

LootSlotTypeSpec = {}

function LootSlotTypeSpec.should_return_true_for_item_slots()
  -- Given
  local api = mock_raw_api( {
    GetLootSlotType = function() return LOOT_SLOT_ITEM end,
  } )
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_loot_slot_item( 1 ), true )
  eq( ga.is_loot_slot_coin( 1 ), false )
end

function LootSlotTypeSpec.should_return_true_for_coin_slots()
  -- Given
  local api = mock_raw_api( {
    GetLootSlotType = function() return LOOT_SLOT_MONEY end,
  } )
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_loot_slot_item( 1 ), false )
  eq( ga.is_loot_slot_coin( 1 ), true )
end

function LootSlotTypeSpec.should_return_false_for_unknown_slot_type()
  -- Given
  local api = mock_raw_api( {
    GetLootSlotType = function() return 99 end,
  } )
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_loot_slot_item( 1 ), false )
  eq( ga.is_loot_slot_coin( 1 ), false )
end

-- ---------------------------------------------------------------------------
-- get_raid_member
-- ---------------------------------------------------------------------------

GetRaidMemberSpec = {}

function GetRaidMemberSpec.should_return_structured_table_for_valid_index()
  -- Given
  local api = mock_raw_api( {
    GetRaidRosterInfo = function( index )
      if index == 3 then
        return "Obszczymucha", 2, nil, nil, nil, "PRIEST"
      end
    end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_raid_member( 3 )

  -- Then
  eq( result.name, "Obszczymucha" )
  eq( result.rank, 2 )
  eq( result.class, "PRIEST" )
end

function GetRaidMemberSpec.should_return_nil_for_empty_roster_slot()
  -- Given
  local api = mock_raw_api( {
    GetRaidRosterInfo = function() return nil end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_raid_member( 40 )

  -- Then
  eq( result, nil )
end

-- ---------------------------------------------------------------------------
-- is_party_leader
-- ---------------------------------------------------------------------------

IsPartyLeaderSpec = {}

function IsPartyLeaderSpec.should_use_UnitIsGroupLeader_when_available()
  -- Given
  local api = mock_raw_api( {
    UnitIsGroupLeader = function( unit )
      return unit == "player"
    end,
    UnitIsPartyLeader = function() return false end,
  } )
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_party_leader(), true )
end

function IsPartyLeaderSpec.should_fall_back_to_UnitIsPartyLeader_on_wotlk()
  -- Given – UnitIsGroupLeader not present (WotLK 3.3.5a)
  local api = mock_raw_api( {
    UnitIsPartyLeader = function( unit )
      return unit == "player"
    end,
  } )
  -- Remove UnitIsGroupLeader entirely
  api.UnitIsGroupLeader = nil
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_party_leader(), true )
end

function IsPartyLeaderSpec.should_return_false_when_not_leader()
  -- Given
  local api = mock_raw_api( {
    UnitIsPartyLeader = function() return false end,
  } )
  api.UnitIsGroupLeader = nil
  local ga = m.GameApi.new( api )

  -- When / Then
  eq( ga.is_party_leader(), false )
end

-- ---------------------------------------------------------------------------
-- unit_class
-- ---------------------------------------------------------------------------

UnitClassSpec = {}

function UnitClassSpec.should_return_non_localized_class_name()
  -- Given
  local api = mock_raw_api( {
    UnitClass = function() return "Warrior", "WARRIOR" end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.unit_class( "player" )

  -- Then
  eq( result, "WARRIOR" )
end

-- ---------------------------------------------------------------------------
-- get_master_loot_candidate (AzerothCore 3.3.5a: 1-arg form only)
-- ---------------------------------------------------------------------------

GetMasterLootCandidateSpec = {}

function GetMasterLootCandidateSpec.should_pass_only_index_to_api()
  -- Given
  -- AzerothCore/ChromieCraft only supports GetMasterLootCandidate(index).
  -- The 2-arg form (slot, index) is not implemented on most 3.3.5a cores.
  -- GameApi receives (slot, index) from callers but only passes index to the API.
  local captured_args = {}
  local api = mock_raw_api( {
    GetMasterLootCandidate = function( ... )
      captured_args = { ... }
      return "Obszczymucha"
    end,
  } )
  local ga = m.GameApi.new( api )

  -- When
  local result = ga.get_master_loot_candidate( 1, 3 )

  -- Then
  eq( result, "Obszczymucha" )
  eq( #captured_args, 1 )  -- only index passed, not slot
  eq( captured_args[1], 3 ) -- index = 3
end

os.exit( lu.LuaUnit.run() )
