local M = {}

---@param overrides table?
function M.new( overrides )
  overrides = overrides or {}

  ---@type GameApi
  local defaults = {
    get_num_loot_items = function() return 0 end,
    get_loot_slot_link = function() return nil end,
    get_loot_slot_info = function() return nil end,
    is_loot_slot_item = function() return false end,
    is_loot_slot_coin = function() return false end,
    loot_slot = function() end,
    get_loot_source_guid = function() return nil end,
    get_loot_method = function() return { method = "group" } end,
    get_master_loot_candidate = function() return nil end,
    get_raid_member = function() return nil end,
    is_party_leader = function() return false end,
    is_in_group = function() return false end,
    is_in_raid = function() return false end,
    unit_name = function() return "Psikutas" end,
    unit_class = function() return "Warrior" end,
  }

  for k, v in pairs( overrides ) do
    defaults[ k ] = v
  end

  return defaults
end

return M
