RollFor = RollFor or {}
local m = RollFor

if m.LootFacade then return end

local M = {}
local interface = m.Interface

M.interface = {
  subscribe = "function",
  get_item_count = "function",
  get_source_guid = "function",
  get_link = "function",
  get_info = "function",
  is_item = "function",
  is_coin = "function",
  loot_slot = "function"
}

---@class LootSlotInfo
---@field texture string
---@field name string
---@field quantity number
---@field quality number

---@class LootFacade
---@field subscribe fun( event_name: LootEventName, callback: fun( arg: any? ) )
---@field get_item_count fun(): number
---@field get_source_guid fun(): string
---@field get_link fun( slot: number ): ItemLink
---@field get_info fun( slot: number ): LootSlotInfo
---@field is_item fun( slot: number ): boolean
---@field is_coin fun( slot: number ): boolean
---@field loot_slot fun( slot: number )

---@alias LootEventName
---| "LootOpened"
---| "LootClosed"
---| "LootSlotCleared"
---| "ChatMsgLoot"

function M.new( event_frame, game_api )
  interface.validate( game_api, m.GameApi.interface )

  ---@param event_name LootEventName
  ---@param callback fun()
  local function subscribe( event_name, callback )
    local blizz_event =
        event_name == "LootOpened" and "LOOT_OPENED" or
        event_name == "LootClosed" and "LOOT_CLOSED" or
        event_name == "LootSlotCleared" and "LOOT_SLOT_CLEARED" or
        event_name == "ChatMsgLoot" and "CHAT_MSG_LOOT"

    if blizz_event then
      event_frame.subscribe( blizz_event, callback )
    end
  end

  ---@return number
  local function get_item_count()
    return game_api.get_num_loot_items()
  end

  ---@return string?
  local function get_source_guid()
    return game_api.get_loot_source_guid()
  end

  ---@param slot number
  ---@return ItemLink?
  local function get_link( slot )
    return game_api.get_loot_slot_link( slot )
  end

  ---@param slot number
  ---@return LootSlotInfo?
  local function get_info( slot )
    return game_api.get_loot_slot_info( slot )
  end

  ---@param slot number
  ---@return boolean
  local function is_item( slot )
    return game_api.is_loot_slot_item( slot )
  end

  ---@param slot number
  ---@return boolean
  local function is_coin( slot )
    return game_api.is_loot_slot_coin( slot )
  end

  ---@param slot number
  local function loot_slot( slot )
    game_api.loot_slot( slot )
  end

  ---@type LootFacade
  return {
    subscribe = subscribe,
    get_item_count = get_item_count,
    get_source_guid = get_source_guid,
    get_link = get_link,
    get_info = get_info,
    is_item = is_item,
    is_coin = is_coin,
    loot_slot = loot_slot
  }
end

m.LootFacade = M
return M
