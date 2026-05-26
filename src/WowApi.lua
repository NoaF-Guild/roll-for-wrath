RollFor = RollFor or {}
local m = RollFor

if m.WowApi then return end

local M = {}

M.LootInterface = {
  GetNumLootItems = "function",
  UnitName = "function",
  GetLootSlotLink = "function",
  GetLootSlotInfo = "function",
  GetLootSlotType = "function"
}

M.GameApiInterface = {
  GetNumLootItems = "function",
  GetLootSlotLink = "function",
  GetLootSlotInfo = "function",
  GetLootSlotType = "function",
  LootSlot = "function",
  UnitGUID = "function",
  UnitName = "function",
  UnitClass = "function",
  GetLootMethod = "function",
  GetMasterLootCandidate = "function",
  GetRaidRosterInfo = "function",
  UnitIsPartyLeader = "function",
  IsInRaid = "function",
  IsInGroup = "function",
}

m.WowApi = M
return M
