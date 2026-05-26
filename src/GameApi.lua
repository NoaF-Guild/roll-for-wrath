RollFor = RollFor or {}
local m = RollFor

if m.GameApi then return end

local M = {}
local interface = m.Interface

M.interface = {
  get_num_loot_items = "function",
  get_loot_slot_link = "function",
  get_loot_slot_info = "function",
  is_loot_slot_item = "function",
  is_loot_slot_coin = "function",
  loot_slot = "function",
  get_loot_source_guid = "function",
  get_loot_method = "function",
  get_master_loot_candidate = "function",
  get_raid_member = "function",
  is_party_leader = "function",
  is_in_group = "function",
  is_in_raid = "function",
  unit_name = "function",
  unit_class = "function",
}

---@class LootMethodInfo
---@field method string
---@field party_index number?
---@field raid_index number?

---@class RaidMemberInfo
---@field name string
---@field rank number
---@field class string

---@param api table  -- raw global table (_G)
function M.new( api )
  interface.validate( api, m.WowApi.GameApiInterface )

  -- Loot primitives

  local function get_num_loot_items()
    return api.GetNumLootItems()
  end

  local function get_loot_slot_link( slot )
    return api.GetLootSlotLink( slot )
  end

  local function get_loot_slot_info( slot )
    local texture, name, quantity, quality = api.GetLootSlotInfo( slot )

    return texture and {
      texture = texture,
      name = name,
      quantity = quantity,
      quality = quality,
    } or nil
  end

  local function is_loot_slot_item( slot )
    return api.GetLootSlotType( slot ) == LOOT_SLOT_ITEM
  end

  local function is_loot_slot_coin( slot )
    return api.GetLootSlotType( slot ) == LOOT_SLOT_MONEY
  end

  local function loot_slot( slot )
    api.LootSlot( slot )
  end

  local function get_loot_source_guid()
    -- Delegates to existing version-aware wrapper in compat.lua
    return m.UnitGUID( api, "target" )
  end

  -- Group / loot method primitives

  local function get_loot_method()
    local method, party_id, raid_id = api.GetLootMethod()
    return { method = method, party_index = party_id, raid_index = raid_id }
  end

  local function get_master_loot_candidate( slot, index )
    return api.GetMasterLootCandidate( slot, index )
  end

  local function get_raid_member( index )
    local name, rank, _, _, _, class = api.GetRaidRosterInfo( index )
    return name and { name = name, rank = rank, class = class } or nil
  end

  local function is_party_leader()
    -- UnitIsGroupLeader was added in Cataclysm. If present (modern client), prefer it.
    if api.UnitIsGroupLeader then
      return api.UnitIsGroupLeader( "player" )
    end
    -- WotLK 3.3.5a fallback: UnitIsPartyLeader only works in party context.
    return api.UnitIsPartyLeader and api.UnitIsPartyLeader( "player" ) or false
  end

  local function is_in_group()
    return api.IsInGroup()
  end

  local function is_in_raid()
    return api.IsInRaid()
  end

  local function unit_name( unit )
    return api.UnitName( unit )
  end

  local function unit_class( unit )
    local _, class = api.UnitClass( unit )
    return class
  end

  return {
    get_num_loot_items = get_num_loot_items,
    get_loot_slot_link = get_loot_slot_link,
    get_loot_slot_info = get_loot_slot_info,
    is_loot_slot_item = is_loot_slot_item,
    is_loot_slot_coin = is_loot_slot_coin,
    loot_slot = loot_slot,
    get_loot_source_guid = get_loot_source_guid,
    get_loot_method = get_loot_method,
    get_master_loot_candidate = get_master_loot_candidate,
    get_raid_member = get_raid_member,
    is_party_leader = is_party_leader,
    is_in_group = is_in_group,
    is_in_raid = is_in_raid,
    unit_name = unit_name,
    unit_class = unit_class,
  }
end

m.GameApi = M
return M
