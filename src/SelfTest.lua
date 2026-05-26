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

    -- Lua build assumptions
    -- WoW 3.3.5a retains table.setn as a stub even though it uses Lua 5.1.
    -- Event handlers use function params (5.1 behavior) regardless of table.setn presence.
    if table.setn then
      print( "   INFO: table.setn present (WoW Lua 5.1 with 5.0 stubs — expected on 3.3.5a)" )
    end
    check( "table.getn exists", table.getn ~= nil )

    -- Library presence
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
    local pl = game_api.is_party_leader()
    check( "is_party_leader() is boolean", type( pl ) == "boolean" )

    -- get_loot_method record shape
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

    -- Loot slot shape (only if loot window open)
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
end

m.SelfTest = M
return M
