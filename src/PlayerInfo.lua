RollFor = RollFor or {}
local m = RollFor

if m.PlayerInfo then return end

---@class PlayerInfo
---@field get_name fun(): string
---@field get_class fun(): string
---@field is_master_looter fun(): boolean
---@field is_leader fun(): boolean
---@field is_assistant fun(): boolean

local M = {}
local interface = m.Interface

---@param game_api GameApi
function M.new( game_api )
  interface.validate( game_api, m.GameApi.interface )
  local function get_name()
    return game_api.unit_name( "player" )
  end

  local function get_class()
    return game_api.unit_class( "player" )
  end

  local function is_master_looter()
    if not game_api.is_in_group() then return false end

    local loot = game_api.get_loot_method()
    if loot.method ~= "master" then return false end

    -- Party context: party_index == 0 means we are the ML
    if loot.party_index and loot.party_index == 0 then
      return true
    end

    -- Raid context: raid_index is our raid roster index; compare name
    if loot.raid_index then
      local member = game_api.get_raid_member( loot.raid_index )
      return member and member.name == get_name()
    end

    return false
  end

  local function is_leader()
    if not game_api.is_in_group() then return false end

    if game_api.is_in_raid() then
      local my_name = get_name()
      for i = 1, 40 do
        local member = game_api.get_raid_member( i )
        if member and member.name == my_name then
          return member.rank == 2
        end
      end
      return false
    end

    return game_api.is_party_leader()
  end

  local function is_assistant()
    if not game_api.is_in_raid() then return false end
    local my_name = get_name()

    for i = 1, 40 do
      local member = game_api.get_raid_member( i )

      if member and member.name == my_name then
        return member.rank > 0
      end
    end

    return false
  end

  ---@type PlayerInfo
  return {
    get_name = get_name,
    get_class = get_class,
    is_master_looter = is_master_looter,
    is_leader = is_leader,
    is_assistant = is_assistant
  }
end

m.PlayerInfo = M
return M
