package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/bcc/compat" )
local utils = require( "test/utils" )
local lu, eq = utils.luaunit( "assertEquals" )
require( "src/modules" )
require( "src/Interface" )
require( "src/GameApi" )
require( "src/PlayerInfo" )

local m = RollFor
local GameApiMock = require( "test/mocks/GameApi" )

PlayerInfoSpec = {}

-- Helper: build a game_api mock for raid context.
-- members is a list of { name, rank, class } tables indexed by roster position.
local function raid_game_api( player_name, player_class, loot_method_info, members )
  local member_map = {}
  for i, member in ipairs( members or {} ) do
    member_map[ i ] = { name = member[ 1 ], rank = member[ 2 ], class = member[ 3 ] }
  end

  return GameApiMock.new( {
    unit_name = function() return player_name end,
    unit_class = function() return player_class end,
    is_in_group = function() return true end,
    is_in_raid = function() return true end,
    get_loot_method = function() return loot_method_info end,
    get_raid_member = function( index ) return member_map[ index ] end,
  } )
end

-- ============================================================
-- get_name / get_class
-- ============================================================

function PlayerInfoSpec.should_return_player_name()
  -- Given
  local game_api = GameApiMock.new( {
    unit_name = function() return "Obszczymucha" end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When
  local result = pi.get_name()

  -- Then
  eq( result, "Obszczymucha" )
end

function PlayerInfoSpec.should_return_player_class()
  -- Given
  local game_api = GameApiMock.new( {
    unit_class = function() return "Priest" end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When
  local result = pi.get_class()

  -- Then
  eq( result, "Priest" )
end

-- ============================================================
-- is_master_looter
-- ============================================================

function PlayerInfoSpec.should_not_be_master_looter_when_not_in_group()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_group = function() return false end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), false )
end

function PlayerInfoSpec.should_not_be_master_looter_when_loot_method_is_group()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_group = function() return true end,
    get_loot_method = function() return { method = "group" } end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), false )
end

function PlayerInfoSpec.should_be_master_looter_in_party_when_party_index_is_zero()
  -- Given
  local game_api = GameApiMock.new( {
    unit_name = function() return "Psikutas" end,
    is_in_group = function() return true end,
    get_loot_method = function() return { method = "master", party_index = 0 } end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), true )
end

function PlayerInfoSpec.should_not_be_master_looter_in_party_when_party_index_is_not_zero()
  -- Given
  local game_api = GameApiMock.new( {
    unit_name = function() return "Psikutas" end,
    is_in_group = function() return true end,
    get_loot_method = function() return { method = "master", party_index = 2 } end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), false )
end

function PlayerInfoSpec.should_be_master_looter_in_raid_when_raid_index_points_to_our_name()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "master", party_index = nil, raid_index = 2 },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Psikutas", 1, "Warrior" },
      { "Ponpon", 0, "Mage" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), true )
end

function PlayerInfoSpec.should_not_be_master_looter_in_raid_when_raid_index_points_to_different_name()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "master", party_index = nil, raid_index = 1 },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Psikutas", 1, "Warrior" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_master_looter(), false )
end

-- ============================================================
-- is_leader
-- ============================================================

function PlayerInfoSpec.should_not_be_leader_when_not_in_group()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_group = function() return false end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), false )
end

function PlayerInfoSpec.should_be_leader_in_party_when_is_party_leader()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_group = function() return true end,
    is_in_raid = function() return false end,
    is_party_leader = function() return true end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), true )
end

function PlayerInfoSpec.should_not_be_leader_in_party_when_not_party_leader()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_group = function() return true end,
    is_in_raid = function() return false end,
    is_party_leader = function() return false end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), false )
end

function PlayerInfoSpec.should_be_leader_in_raid_when_rank_is_two()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "group" },
    {
      { "Obszczymucha", 1, "Priest" },
      { "Psikutas", 2, "Warrior" },
      { "Ponpon", 0, "Mage" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), true )
end

function PlayerInfoSpec.should_not_be_leader_in_raid_when_rank_is_one()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "group" },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Psikutas", 1, "Warrior" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), false )
end

function PlayerInfoSpec.should_not_be_leader_in_raid_when_player_not_found_in_roster()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "group" },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Ponpon", 0, "Mage" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_leader(), false )
end

-- ============================================================
-- is_assistant
-- ============================================================

function PlayerInfoSpec.should_not_be_assistant_when_not_in_raid()
  -- Given
  local game_api = GameApiMock.new( {
    is_in_raid = function() return false end,
  } )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_assistant(), false )
end

function PlayerInfoSpec.should_be_assistant_in_raid_when_rank_is_greater_than_zero()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "group" },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Psikutas", 1, "Warrior" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_assistant(), true )
end

function PlayerInfoSpec.should_not_be_assistant_in_raid_when_rank_is_zero()
  -- Given
  local game_api = raid_game_api( "Psikutas", "Warrior",
    { method = "group" },
    {
      { "Obszczymucha", 2, "Priest" },
      { "Psikutas", 0, "Warrior" },
    }
  )
  local pi = m.PlayerInfo.new( game_api )

  -- When / Then
  eq( pi.is_assistant(), false )
end

os.exit( lu.LuaUnit.run() )
