local _, NS = ...
local Layout = NS.Layout

-- ConversationModels places native animated unit copies beside interaction panels.
local Models = { generation = 0 }
NS.ConversationModels = Models
local driver = CreateFrame("Frame")
local panels = { "GossipFrame", "QuestFrame", "ClassTrainerFrame", "MerchantFrame" }
local opens = {
    GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true,
    QUEST_PROGRESS = true, QUEST_COMPLETE = true, TRAINER_SHOW = true, MERCHANT_SHOW = true,
}

local function configure(model)
    model:SetPortraitZoom(0)
    model:SetCamDistanceScale(1.1)
    model:SetPosition(0, 0, 0)
    model:SetFacing(model.facing)
    -- Use the model's own standing animation; world emote state is not exposed.
    model:SetAnimation(0)
end

local function createModel(parent, facing)
    local model = CreateFrame("PlayerModel", nil, parent)
    model.facing = facing
    model:EnableMouse(false)
    model:SetKeepModelOnHide(true)
    model:SetScript("OnModelLoaded", configure)
    model:Hide()
    return model
end

function Models:Hide()
    self.generation = self.generation + 1
    self.active, self.npcGUID, self.missingSince = nil, nil, nil
    driver:SetScript("OnUpdate", nil)
    if self.root then
        self.root:Hide()
        for _, model in ipairs({ self.player, self.npc }) do
            model:Hide()
            model:ClearModel()
            model.guid = nil
        end
    end
end

local function bind(model, unit, guid)
    if not guid or not UnitExists(unit) then return end
    if model.guid == guid then return end
    local ok, success = pcall(model.SetUnit, model, unit)
    if ok and success ~= false then
        model.guid = guid
        configure(model)
    end
end

function Models:Update()
    if not self.active then return end
    local panel
    for _, name in ipairs(panels) do
        local candidate = _G[name]
        if candidate and candidate:IsVisible() then panel = candidate; break end
    end
    if not panel then
        self.missingSince = self.missingSince or GetTime()
        if GetTime() - self.missingSince > 0.2 then self:Hide() end
        return
    end
    self.missingSince = nil
    local chrome = NS.UI.nativeChrome
    -- The preserved backdrop keeps models behind menu controls and survives
    -- FullscreenMenus UI isolation when switching merchant/inventory panes.
    local background = NS.UI.nativeBackground
    if not chrome or not background or not chrome:IsShown() then
        if self.root then self.root:Hide() end
        return
    end
    local parent = background
    if not self.root then
        self.root = CreateFrame("Frame", nil, parent)
        self.root:EnableMouse(false)
        self.player = createModel(self.root, -0.35)
        self.npc = createModel(self.root, 0.35)
    elseif self.root:GetParent() ~= parent then
        self.root:SetParent(parent)
    end
    self.root:SetAllPoints(UIParent)
    local strata = background:GetFrameStrata()
    local level = background:GetFrameLevel()
    self.root:SetFrameStrata(strata)
    self.root:SetFrameLevel(level)
    self.root:Show()
    local width, height = self.root:GetWidth(), self.root:GetHeight()
    -- Fixed screen-relative viewports: pane sizes never move or resize the copies.
    for index, model in ipairs({ self.npc, self.player }) do
        model:SetFrameStrata(strata)
        -- Share the backdrop's level, above its texture but below the menu level.
        model:SetFrameLevel(level)
        model:ClearAllPoints()
        model:SetPoint(index == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", self.root,
            index == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT",
            index == 1 and width * Layout.modelSideInset or -width * Layout.modelSideInset, height * Layout.modelBottomInset)
        model:SetSize(width * Layout.modelWidth, height * Layout.modelHeight)
        model:Show()
    end
    bind(self.player, "player", UnitGUID("player"))
    local guid = UnitGUID("npc")
    if guid and self.npcGUID and guid ~= self.npcGUID then
        self.npc:ClearModel()
        self.npc.guid = nil
    end
    self.npcGUID = guid or self.npcGUID
    if guid then bind(self.npc, "npc", guid) end
end

function Models:Open()
    self.active = true
    self.generation = self.generation + 1
    self.missingSince = nil
    local generation = self.generation
    -- Allow native frames and FullscreenMenus to finish opening and fitting first.
    C_Timer.After(0, function()
        if generation ~= self.generation then return end
        self:Update()
        if not self.active then return end
        local elapsed = 0
        driver:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if elapsed < 0.1 then return end
            elapsed = 0
            self:Update()
        end)
    end)
end

driver:SetScript("OnEvent", function(_, event, unit)
    if opens[event] then
        Models:Open()
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_DEAD" then
        Models:Hide()
    elseif Models.active then
        if event == "PLAYER_EQUIPMENT_CHANGED" or unit == "player" then
            if Models.player then Models.player.guid = nil end
        elseif unit == "npc" and Models.npc then
            Models.npc.guid = nil
        end
    end
end)
for event in pairs(opens) do pcall(driver.RegisterEvent, driver, event) end
for _, event in ipairs({ "PLAYER_LEAVING_WORLD", "PLAYER_DEAD", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE" }) do
    pcall(driver.RegisterEvent, driver, event)
end
