local _, NS = ...

-- Data owns persistent menu settings and coalesced presentation refreshes.
local Data = {}
NS.Data = Data

function Data:Initialize()
    FullscreenMenusDB = type(FullscreenMenusDB) == "table" and FullscreenMenusDB or {}
    -- Discard obsolete renderer snapshots and settings instead of resaving unused data.
    for _, key in ipairs({ "items", "bank", "initialized", "sortMode", "developerMode",
        "showInactiveNames", "previousEnhanceBagsEnabled", "reopenAfterReload" }) do
        FullscreenMenusDB[key] = nil
    end
    FullscreenMenusAccountDB = type(FullscreenMenusAccountDB) == "table" and FullscreenMenusAccountDB or {}
    -- Import the current character's existing list only before a shared list exists.
    if type(FullscreenMenusAccountDB.menuTabs) ~= "table" then
        FullscreenMenusAccountDB.menuTabs = type(FullscreenMenusDB.menuTabs) == "table" and FullscreenMenusDB.menuTabs or {}
    end
    FullscreenMenusDB.menuTabs = nil
    self.accountDB = FullscreenMenusAccountDB
    self.db = FullscreenMenusDB
end

function Data:Refresh()
    if not self.db then return end
    NS.UI:Refresh()
end

function Data:ScheduleRefresh()
    if self.scheduled then return end
    self.scheduled = true
    C_Timer.After(0, function()
        self.scheduled = false
        self:Refresh()
    end)
end
