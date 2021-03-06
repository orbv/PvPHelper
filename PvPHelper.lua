-----------------------------------------------------------------------------------------------
-- Client Lua Script for PvPHelper
-- by orbv - Bloodsworn - Dominion
-----------------------------------------------------------------------------------------------

require "Window"
require "Apollo"

-----------------------------------------------------------------------------------------------
-- PvPHelper Module Definition
-----------------------------------------------------------------------------------------------
local PvPHelper = { 
	db, 
	pvphelperdb, 
	currentMatch
} 

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

-- TODO: This will be expanded to a table if more views are added
local kEventTypeToWindowName = "ResultGrid"

local tDataKeys = {
	"tDate",
	"sGameType",
	"sResult",
	"sRating",
}

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function PvPHelper:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 

  -- initialize variables here

  return o
end

function PvPHelper:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		--"Gemini:Logging-1.2",
	}
	Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)

	self.db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self)
end


-----------------------------------------------------------------------------------------------
-- PvPHelper OnLoad
-----------------------------------------------------------------------------------------------
function PvPHelper:OnLoad()
  -- load our form file
  self.xmlDoc = XmlDoc.CreateFromFile("PvPHelper.xml")
  self.xmlDoc:RegisterCallback("OnDocLoaded", self)

  if self.db.char.PvPHelper == nil then
  	self.db.char.PvPHelper = {}
  end

  self.pvphelperdb = self.db.char.PvPHelper
end

-----------------------------------------------------------------------------------------------
-- PvPHelper OnDocLoaded
-----------------------------------------------------------------------------------------------
function PvPHelper:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
		self.wndMain = Apollo.LoadForm(self.xmlDoc, "PvPHelperForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
		self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("pvphelperclear",       "OnPvPHelperClear", self)
		Apollo.RegisterSlashCommand("pvphelper",            "OnPvPHelperOn", self)
		Apollo.RegisterEventHandler("MatchEntered",         "OnPVPMatchEntered", self)
		Apollo.RegisterEventHandler("MatchExited",          "OnPVPMatchExited", self)
		Apollo.RegisterEventHandler("PvpRatingUpdated",     "OnPVPRatingUpdated", self)
		-- Apollo.RegisterEventHandler("PVPMatchStateUpdated", "OnPVPMatchStateUpdated", self)	
		Apollo.RegisterEventHandler("PVPMatchFinished",     "OnPVPMatchFinished", self)	
		Apollo.RegisterEventHandler("PublicEventStart",     "OnPublicEventStart", self)

		-- TODO: I feel that this could be done in a more elegant way, clean it up later
		-- Maybe the UI reloaded so be sure to check if we are in a match already
		if MatchingGame:IsInMatchingGame() then
			local tMatchState = MatchingGame:GetPVPMatchState()

			if tMatchState ~= nil then
				--Print("Attempting to restore PVPMatchEntered()")
				self:OnPVPMatchEntered()
			end

			-- Do the same for public event
			local tActiveEvents = PublicEvent.GetActiveEvents()
			for idx, peEvent in pairs(tActiveEvents) do
				self:OnPublicEventStart(peEvent)
			end
		end
	end
end

-----------------------------------------------------------------------------------------------
-- PvPHelper Events
-----------------------------------------------------------------------------------------------

function PvPHelper:OnPVPMatchEntered()
	local tDate = GameLib:GetLocalTime()
	tDate["nTickCount"] = GameLib:GetTickCount()
	local tRating = MatchingGame.GetPvpRating(MatchingGame.RatingType.RatedBattleground)

	self.currentMatch = {
		["tDate"]     = tDate,
		["sGameType"] = "N/A",
		["sResult"]   = "N/A", 
		["sRating"]   = "N/A",
		["nBGRating"] = tRating["nRating"]
	}
end

function PvPHelper:OnPVPMatchExited()
	if self.currentMatch then
		-- User left before match finished.
		self.currentMatch["sResult"] = "Forfeit"
		self:UpdateMatchHistory(self.currentMatch)
	end
end

-- TODO: It would be better to update personal BG rating before this call is made.
--       Possible if the rating change is passed via another event.
function PvPHelper:OnPVPRatingUpdated(eType)
	if eType == MatchingGame.RatingType["RatedBattleground"] then
		self:UpdateBattlegroundRating()
	end
end

function PvPHelper:OnPVPMatchFinished(eWinner, eReason, nDeltaTeam1, nDeltaTeam2)
	local tMatchState = MatchingGame:GetPVPMatchState()
	local eMyTeam = nil
	local tRatingDeltas = {
		nDeltaTeam1,
		nDeltaTeam2
	}
	
	if tMatchState then
		eMyTeam = tMatchState.eMyTeam
	end	
	
	self.currentMatch["sResult"] = self:GetResultString(eMyTeam, eWinner)
	self.currentMatch["sRating"] = self:GetArenaRatingString(tMatchState, tRatingDeltas)

	self:UpdateMatchHistory(self.currentMatch)
end

function PvPHelper:OnPublicEventStart(peEvent)
	local eEventType = peEvent:GetEventType()
	local strType    = self:GetGameTypeString(eEventType)
	
	-- Only worry about PvP events
	if strType == "" then
		return
	end
	
	self.currentMatch["sGameType"] = strType
end

-----------------------------------------------------------------------------------------------
-- PvPHelper Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/pvphelper"
function PvPHelper:OnPvPHelperOn()
	
	PvPHelper:HelperBuildGrid(self.wndMain:FindChild("GridContainer"), self.pvphelperdb.MatchHistory)
	self.wndMain:Invoke() -- show the window
end

-- on SlashCommand "/pvphelperclear"
function PvPHelper:OnPvPHelperClear()
	Print("PvPHelper: Match History cleared")
	self.pvphelperdb.MatchHistory = {}
end

function PvPHelper:UpdateBattlegroundRating()
	if not self.pvphelperdb.MatchHistory then
		return
	end

	local nLastEntry = #self.pvphelperdb.MatchHistory
	local tLastEntry = self.pvphelperdb.MatchHistory[nLastEntry]
	local nRating    = tLastEntry["nBGRating"]
	
	tLastEntry["sRating"] = self:GetBattlegroundRatingString(nRating)
end

function PvPHelper:GetDateString(tDate)	
	local strDate = string.format("%02d/%02d/%4d %s", tDate["nMonth"], tDate["nDay"], tDate["nYear"], tDate["strFormattedTime"])
	return strDate
end

function PvPHelper:GetResultString(eMyTeam, eWinner)
	if eMyTeam == eWinner then
		return "Win"
	else
		return "Loss"
	end
end

function PvPHelper:GetBattlegroundRatingString(nPreviousRating)
	local result = "N/A (N/A)"
	local currentRating = MatchingGame.GetPvpRating(MatchingGame.RatingType.RatedBattleground)
	
	if nPreviousRating and currentRating then
		currentRating  = currentRating["nRating"]
		if nPreviousRating < currentRating then
			result = string.format("%d (+%d)", currentRating, (currentRating - nPreviousRating))
		elseif nPreviousRating > currentRating then
			result = string.format("%d (-%d)", currentRating, (nPreviousRating - currentRating))
		end
	end
	 
	return result
end

-- Return a string which shows the current rating after difference
function PvPHelper:GetArenaRatingString(tMatchState, tRatingDeltas)
	local eMyTeam = tMatchState.eMyTeam	
	local result  = "N/A (N/A)"

	if tMatchState.arTeams then
		for idx, tCurr in pairs(tMatchState.arTeams) do
			if eMyTeam == tCurr.nTeam then
				result = string.format("%d (%d)", tCurr.nRating, tRatingDeltas[idx])
			end
		end
	end
	
	return result
end

function PvPHelper:GetGameTypeString(eEventType)
	local result = ""
	
	-- Leave these as if/elseif in case you want to add more specifics in the future
	if eEventType == PublicEvent.PublicEventType_PVP_Battleground_HoldTheLine then
		result = "Battleground"
	elseif eEventType == PublicEvent.PublicEventType_PVP_Battleground_Vortex then
		result = "Battleground"		
	elseif eEventType == PublicEvent.PublicEventType_PVP_Warplot then
		result = "Warplot"
	elseif eEventType == PublicEvent.PublicEventType_PVP_Arena then
		result = "Arena"
	elseif eEventType == PublicEvent.PublicEventType_PVP_Battleground_Sabotage then
		result = "Battleground"
	end

	return result
end

function PvPHelper:UpdateMatchHistory(tMatch)
	if self.pvphelperdb.MatchHistory == nil then
		self.pvphelperdb.MatchHistory = {}
	end
	table.insert(self.pvphelperdb.MatchHistory, tMatch)
	
	tMatch = nil
end

-----------------------------------------------------------------------------------------------
-- PvPHelperForm Functions
-----------------------------------------------------------------------------------------------

function PvPHelper:HelperBuildGrid(wndParent, tData)
	if not tData then
		-- Print("No data found")
		return
	end
	
	-- Print("Data found: building grid")

	local wndGrid = wndParent:FindChild("ResultGrid")

	local nVScrollPos 	= wndGrid:GetVScrollPos()
	local nSortedColumn	= wndGrid:GetSortColumn() or 1
	local bAscending 	= wndGrid:IsSortAscending()
	
	wndGrid:DeleteAll()
	
	for row, tMatch in pairs(tData) do
		local wndResultGrid = wndGrid
		row = wndResultGrid:AddRow("")

		for col, sDataKey in pairs(tDataKeys) do
			local value = tMatch[sDataKey]
			if type(value) == "table" then
				wndResultGrid:SetCellSortText(row, col, value["nTickCount"])
				wndResultGrid:SetCellText(row, col, self:GetDateString(value))
			else
				wndResultGrid:SetCellSortText(row, col, value)
				wndResultGrid:SetCellText(row, col, value)
			end
		end
	end

	wndGrid:SetVScrollPos(nVScrollPos)
	wndGrid:SetSortColumn(nSortedColumn, bAscending)

end

function PvPHelper:OnClose( wndHandler, wndControl )
	self.wndMain:Close()
end

-----------------------------------------------------------------------------------------------
-- PvPHelper Instance
-----------------------------------------------------------------------------------------------
local PvPHelperInst = PvPHelper:new()
PvPHelperInst:Init()
