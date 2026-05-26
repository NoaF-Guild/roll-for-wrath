package.path = "./?.lua;" .. package.path .. ";../?.lua"

local lu = require( "luaunit" )
local test_utils = require( "test/utils" )
test_utils.mock_wow_api()
require( "src/modules" )
require( "src/Types" )
require( "src/SoftResDataTransformer" )
local mod = require( "src/SoftRes" )

local sr = test_utils.soft_res_item
local data = test_utils.create_softres_data

SoftResIntegrationSpec = {}

function SoftResIntegrationSpec.new_instances_should_have_empty_item_lists()
  -- Given
  local soft_res = mod.new()
  local soft_res2 = mod.new()

  -- Expect
  lu.assertEquals( soft_res.get( 123 ), nil )
  lu.assertEquals( soft_res2.get( 123 ), nil )
end

function SoftResIntegrationSpec:should_create_a_proper_object_and_add_an_item()
  -- Given
  local soft_res = mod.new()
  soft_res.import( data( sr( "Psikutas", 123 ) ) )
  local soft_res2 = mod.new()

  -- When
  local result = soft_res.get( 123 )
  local result2 = soft_res2.get( 123 )

  -- Then
  lu.assertEquals( result, {
    { name = "Psikutas", rolls = 1, type = "Roller" }
  } )
  lu.assertEquals( result2, {} )
end

function SoftResIntegrationSpec:should_return_nil_for_untracked_item()
  -- Given
  local soft_res = mod.new()
  soft_res.import( data( sr( "Psikutas", 123 ) ) )

  -- When
  local result = soft_res.get( "111" )

  -- Then
  lu.assertEquals( result, {} )
end

function SoftResIntegrationSpec:should_add_multiple_players()
  -- Given
  local soft_res = mod.new()
  soft_res.import( data( sr( "Psikutas", 123 ), sr( "Obszczymucha", 123 ) ) )

  -- When
  local result = soft_res.get( 123 )

  -- Then
  lu.assertEquals( result, {
    { name = "Obszczymucha", rolls = 1, type = "Roller" },
    { name = "Psikutas",     rolls = 1, type = "Roller" }
  } )
end

function SoftResIntegrationSpec:should_accumulate_rolls()
  -- Given
  local soft_res = mod.new()
  soft_res.import( data( sr( "Psikutas", 123 ), sr( "Psikutas", 123 ) ) )

  -- When
  local result = soft_res.get( 123 )

  -- Then
  lu.assertEquals( result, {
    { name = "Psikutas", rolls = 2, type = "Roller" }
  } )
end

function SoftResIntegrationSpec:should_check_if_player_is_soft_ressing()
  -- When
  local soft_res = mod.new()
  soft_res.import( data( sr( "Psikutas", 123 ), sr( "Obszczymucha", 111 ) ) )

  -- Expect
  lu.assertEquals( soft_res.is_player_softressing( "Psiktuas", 123 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Psikutas", 123 ), true )
  lu.assertEquals( soft_res.is_player_softressing( "Psikutas", 333 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Psikutas", 111 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Obszczymucha", 111 ), true )
  lu.assertEquals( soft_res.is_player_softressing( "Obszczymucha", 123 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Obszczymucha", 124 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Ponpon", 123 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Ponpon", 111 ), false )
  lu.assertEquals( soft_res.is_player_softressing( "Ponpon", 333 ), false )
end

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

os.exit( lu.LuaUnit.run() )
