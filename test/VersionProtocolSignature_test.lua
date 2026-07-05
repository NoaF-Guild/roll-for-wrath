package.path = "./?.lua;" .. package.path .. ";../?.lua"

require( "src/wotlk/compat" )
local u = require( "test/utils" )
local lu = u.luaunit()

local m = require( "src/modules" )
local VersionBroadcast = require( "src/VersionBroadcast" )
local PlayerInfo = require( "mocks/PlayerInfo" )

local function mock_config()
  return u.mock_config( {} )
end

---@type ModuleRegistry
local module_registry = {
  { module_name = "Config",  mock = mock_config },
  { module_name = "ChatApi", mock = "mocks/ChatApi" }
}

u.mock_libraries()

local injected = {}
u.load_real_stuff_and_inject( module_registry, injected )

local sent_messages = {}

local function setup_send_addon_message()
  sent_messages = {}
  u.mock( "SendAddonMessage", function( prefix, message, channel )
    table.insert( sent_messages, { prefix = prefix, message = message, channel = channel } )
  end )
end

local function find_message( pattern )
  for _, msg in ipairs( sent_messages ) do
    if string.match( msg.message, pattern ) then
      return msg
    end
  end
  return nil
end

local function load_main()
  u.player( "Psikutas", mock_config() )
  local main = require( "main" )
  lu.assertNotNil( main.version_broadcast )
  return main
end

VersionProtocolSignatureSpec = {}

function VersionProtocolSignatureSpec:should_broadcast_version_with_roll_for_wrath_signature()
  -- Given
  setup_send_addon_message()
  u.mock( "IsInGroup", true )
  u.mock( "IsInRaid", true )
  u.mock( "IsInGuild", true )

  local vb = VersionBroadcast.new( {}, PlayerInfo.new( "Psikutas", "Warrior", false, true ), "1.5.2" )

  -- When
  vb.broadcast()

  -- Then
  local msg = find_message( "^VERSION::" )
  lu.assertNotNil( msg )
  lu.assertEquals( msg.message, "VERSION::roll-for-wrath::1.5.2" )
  -- broadcast() sends to both GUILD and group; group channel is RAID because IsInRaid is true.
  lu.assertTrue( msg.channel == "RAID" or msg.channel == "GUILD" )
end

function VersionProtocolSignatureSpec:should_send_version_request_with_roll_for_wrath_signature()
  -- Given
  setup_send_addon_message()
  u.mock( "IsInGroup", true )
  u.mock( "IsInRaid", true )

  local vb = VersionBroadcast.new( {}, PlayerInfo.new( "Psikutas", "Warrior", false, true ), "1.5.2" )

  -- When
  vb.group_version_request()

  -- Then
  local msg = find_message( "^VERSION_REQUEST::" )
  lu.assertNotNil( msg )
  lu.assertEquals( msg.message, "VERSION_REQUEST::roll-for-wrath::RAID::Psikutas" )
  lu.assertEquals( msg.channel, "RAID" )
end

function VersionProtocolSignatureSpec:should_send_version_response_with_roll_for_wrath_signature()
  -- Given
  setup_send_addon_message()
  u.mock( "IsInGroup", true )
  u.mock( "IsInRaid", true )

  local vb = VersionBroadcast.new( {}, PlayerInfo.new( "Psikutas", "Warrior", false, true ), "1.5.2" )

  -- When
  vb.on_version_request( "RAID", "Obszczymucha" )

  -- Then
  local msg = find_message( "^VERSION_RESPONSE::" )
  lu.assertNotNil( msg )
  lu.assertEquals( msg.message, "VERSION_RESPONSE::roll-for-wrath::Obszczymucha::RAID::Psikutas::Warrior::1.5.2" )
  lu.assertEquals( msg.channel, "RAID" )
end

function VersionProtocolSignatureSpec:should_parse_signed_version_broadcast()
  -- Given
  local main = load_main()
  local versions = {}
  local original = main.version_broadcast.on_version
  main.version_broadcast.on_version = function( ver )
    table.insert( versions, ver )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION::roll-for-wrath::1.5.3", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version = original
  lu.assertEquals( #versions, 1 )
  lu.assertEquals( versions[ 1 ], "1.5.3" )
end

function VersionProtocolSignatureSpec:should_ignore_unsigned_version_broadcast()
  -- Given
  local main = load_main()
  local versions = {}
  local original = main.version_broadcast.on_version
  main.version_broadcast.on_version = function( ver )
    table.insert( versions, ver )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION::1.5.3", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version = original
  lu.assertEquals( #versions, 0 )
end

function VersionProtocolSignatureSpec:should_ignore_version_broadcast_with_wrong_signature()
  -- Given
  local main = load_main()
  local versions = {}
  local original = main.version_broadcast.on_version
  main.version_broadcast.on_version = function( ver )
    table.insert( versions, ver )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION::roll-for-vanilla::1.5.3", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version = original
  lu.assertEquals( #versions, 0 )
end

function VersionProtocolSignatureSpec:should_parse_signed_version_request()
  -- Given
  local main = load_main()
  local requests = {}
  local original = main.version_broadcast.on_version_request
  main.version_broadcast.on_version_request = function( channel, player )
    table.insert( requests, { channel = channel, player = player } )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION_REQUEST::roll-for-wrath::RAID::Obszczymucha", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version_request = original
  lu.assertEquals( #requests, 1 )
  lu.assertEquals( requests[ 1 ].channel, "RAID" )
  lu.assertEquals( requests[ 1 ].player, "Obszczymucha" )
end

function VersionProtocolSignatureSpec:should_ignore_unsigned_version_request()
  -- Given
  local main = load_main()
  local requests = {}
  local original = main.version_broadcast.on_version_request
  main.version_broadcast.on_version_request = function( channel, player )
    table.insert( requests, { channel = channel, player = player } )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION_REQUEST::RAID::Obszczymucha", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version_request = original
  lu.assertEquals( #requests, 0 )
end

function VersionProtocolSignatureSpec:should_parse_signed_version_response()
  -- Given
  local main = load_main()
  local responses = {}
  local original = main.version_broadcast.on_version_response
  main.version_broadcast.on_version_response = function( requesting_player, channel, name, class, version )
    table.insert( responses, { requesting_player = requesting_player, channel = channel, name = name, class = class, version = version } )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION_RESPONSE::roll-for-wrath::Psikutas::RAID::Obszczymucha::Druid::1.5.3", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version_response = original
  lu.assertEquals( #responses, 1 )
  lu.assertEquals( responses[ 1 ].requesting_player, "Psikutas" )
  lu.assertEquals( responses[ 1 ].channel, "RAID" )
  lu.assertEquals( responses[ 1 ].name, "Obszczymucha" )
  lu.assertEquals( responses[ 1 ].class, "Druid" )
  lu.assertEquals( responses[ 1 ].version, "1.5.3" )
end

function VersionProtocolSignatureSpec:should_ignore_unsigned_version_response()
  -- Given
  local main = load_main()
  local responses = {}
  local original = main.version_broadcast.on_version_response
  main.version_broadcast.on_version_response = function( requesting_player, channel, name, class, version )
    table.insert( responses, { requesting_player = requesting_player, channel = channel, name = name, class = class, version = version } )
  end

  -- When
  main.on_chat_msg_addon( "RollFor", "VERSION_RESPONSE::Psikutas::RAID::Obszczymucha::Druid::1.5.3", nil, "Obszczymucha" )

  -- Then
  main.version_broadcast.on_version_response = original
  lu.assertEquals( #responses, 0 )
end

os.exit( lu.LuaUnit.run() )
