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
  local tracker = new_tracker()

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
  local notified_name, notified_link, notified_roll, notified_roll_type, notified_strategy
  tracker.subscribe_for_winner_found( function( name, link, roll, roll_type, strategy )
    notified_name = name
    notified_link = link
    notified_roll = roll
    notified_roll_type = roll_type
    notified_strategy = strategy
  end )

  -- When
  tracker.track( "Psikutas", "[Thunderfury]", "MainSpec", 95, "NormalRoll" )

  -- Then
  eq( notified_name, "Psikutas" )
  eq( notified_link, "[Thunderfury]" )
  eq( notified_roll, 95 )
  eq( notified_roll_type, "MainSpec" )
  eq( notified_strategy, "NormalRoll" )
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
