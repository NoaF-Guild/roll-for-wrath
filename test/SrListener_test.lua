package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/bcc/compat" )
local utils = require( "test/utils" )
local lu, eq = utils.luaunit( "assertEquals" )
local m = require( "src/modules" )
require( "src/SrListener" )

SrListenerSpec = {}

local last_whisper_target, last_whisper_text

local function setup( opts )
  opts = opts or {}
  last_whisper_target = nil
  last_whisper_text = nil

  m.api = {
    SendChatMessage = function( text, type, _, target )
      last_whisper_target = target
      last_whisper_text = text
    end
  }

  m.fetch_item_link = opts.fetch_item_link or function( item_id, quality )
    return string.format( "[Item%d]", item_id )
  end

  local player_info = {
    is_leader = function() return opts.is_leader or false end,
    is_master_looter = function() return opts.is_master_looter or false end,
  }

  local softres = {
    get_player_items = function( name )
      return opts.player_items and opts.player_items[ name ] or {}
    end
  }

  return m.SrListener.new( player_info, softres )
end

function SrListenerSpec.should_ignore_whisper_when_not_leader_or_master_looter()
  -- Given
  local listener = setup( { is_leader = false, is_master_looter = false } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, nil )
  eq( last_whisper_text, nil )
end

function SrListenerSpec.should_ignore_whisper_that_does_not_start_with_sr()
  -- Given
  local listener = setup( { is_leader = true } )

  -- When
  listener.on_chat_msg_whisper( "hello there", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, nil )
  eq( last_whisper_text, nil )
end

function SrListenerSpec.should_respond_with_no_reserves_when_player_has_none()
  -- Given
  local listener = setup( { is_leader = true, player_items = {} } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "You have no soft reserves." )
end

function SrListenerSpec.should_respond_with_sr_item_link_when_player_has_one_item()
  -- Given
  local listener = setup( {
    is_leader = true,
    player_items = {
      Obszczymucha = { { item_id = 12345, quality = 4 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "Your SRs: [Item12345]" )
end

function SrListenerSpec.should_respond_with_multiple_sr_items_comma_separated()
  -- Given
  local listener = setup( {
    is_leader = true,
    player_items = {
      Obszczymucha = {
        { item_id = 12345, quality = 4 },
        { item_id = 67890, quality = 3 },
      }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "Your SRs: [Item12345], [Item67890]" )
end

function SrListenerSpec.should_fallback_to_item_id_format_when_fetch_item_link_returns_nil()
  -- Given
  local listener = setup( {
    is_leader = true,
    fetch_item_link = function() return nil end,
    player_items = {
      Obszczymucha = { { item_id = 99999, quality = 4 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "Your SRs: item:99999" )
end

function SrListenerSpec.should_handle_uppercase_sr_command()
  -- Given
  local listener = setup( {
    is_leader = true,
    player_items = {
      Psikutas = { { item_id = 111, quality = 2 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?SR", "Psikutas" )

  -- Then
  eq( last_whisper_target, "Psikutas" )
  eq( last_whisper_text, "Your SRs: [Item111]" )
end

function SrListenerSpec.should_handle_sr_command_with_extra_text()
  -- Given
  local listener = setup( {
    is_leader = true,
    player_items = {
      Psikutas = { { item_id = 222, quality = 3 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr please", "Psikutas" )

  -- Then
  eq( last_whisper_target, "Psikutas" )
  eq( last_whisper_text, "Your SRs: [Item222]" )
end

function SrListenerSpec.should_respond_when_player_is_master_looter_but_not_leader()
  -- Given
  local listener = setup( {
    is_leader = false,
    is_master_looter = true,
    player_items = {
      Obszczymucha = { { item_id = 333, quality = 4 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "Your SRs: [Item333]" )
end

function SrListenerSpec.should_respond_when_player_is_leader_but_not_master_looter()
  -- Given
  local listener = setup( {
    is_leader = true,
    is_master_looter = false,
    player_items = {
      Obszczymucha = { { item_id = 444, quality = 4 } }
    }
  } )

  -- When
  listener.on_chat_msg_whisper( "?sr", "Obszczymucha" )

  -- Then
  eq( last_whisper_target, "Obszczymucha" )
  eq( last_whisper_text, "Your SRs: [Item444]" )
end

os.exit( lu.LuaUnit.run() )
