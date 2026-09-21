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

-- Native model animation IDs, not chat emotes; only the displayed copies act.
local talk, question, bow, wave, nod = 60, 65, 66, 67, 185
local emotes = {
    greeting = { npc = { wave, talk }, player = { wave, nod } },
    QUEST_DETAIL = { npc = { talk }, player = { question, nod } },
    QUEST_PROGRESS = { npc = { question, talk }, player = { talk, nod } },
    QUEST_COMPLETE = { npc = { nod, talk }, player = { bow, nod } },
    TRAINER_SHOW = { npc = { talk }, player = { question, nod } },
    MERCHANT_SHOW = { npc = { talk }, player = { question, nod } },
    conversation = { npc = { talk, question }, player = { talk, nod } },
}
local emoteChance, emoteCooldown, emoteTimeout = 0.35, 3, 3
local rotationDeadzone, rotationSpeed = 0.15, math.pi

-- Read the mapped camera stick without taking ownership of native input bindings.
function Models:RotateNPC(delta)
    local model = self.npc
    if not self.active or not model or not model.guid or not model:IsVisible()
        or not C_GamePad or not C_GamePad.GetDeviceMappedState
        or not C_GamePad.StickIndexToConfigName then return end
    local state = C_GamePad.GetDeviceMappedState()
    if not state then return end
    for index, stick in ipairs(state.sticks) do
        if C_GamePad.StickIndexToConfigName(index - 1) == "Camera" then
            local amount = math.abs(stick.x)
            if amount <= rotationDeadzone then return end
            local direction = stick.x < 0 and -1 or 1
            model.facing = (model.facing + direction * (amount - rotationDeadzone)
                / (1 - rotationDeadzone) * rotationSpeed * math.min(delta, 0.1)) % (2 * math.pi)
            model:SetFacing(model.facing)
            return
        end
    end
end

local function stand(model)
    model.emoteUntil = nil
    model:SetAnimation(0)
end

local function tryEmote(model, choices, now)
    if not model.guid or (model.nextEmote and now < model.nextEmote) then return end
    model.nextEmote = now + emoteCooldown
    if math.random() >= emoteChance then return end
    model.emoteUntil = now + emoteTimeout
    local ok, success = pcall(model.SetAnimation, model, choices[math.random(#choices)])
    if not ok or success == false then stand(model) end
end

-- An invisible actor measures the same model file displayed by PlayerModel.
-- It never supplies appearance, lighting, orientation, or animation to the view.
local function measure(model)
    local file = model:GetModelFileID()
    if not file or file == 0 then return end
    local actor = model.measureActor
    if model.measureFile ~= file then
        model.bounds = nil
        actor:ClearModel()
        if actor:SetModelByFileID(file) == false then return end
        actor:SetScale(1)
        actor:SetAnimation(0)
        model.measureFile = file
    end
    if model.bounds or not actor:IsLoaded() or actor:GetModelFileID() ~= file then return end
    local x0, y0, z0, x1, y1, z1 = actor:GetActiveBoundingBox()
    if type(x0) == "table" and x0.GetXYZ and type(y0) == "table" and y0.GetXYZ then
        local bottom, top = x0, y0
        x0, y0, z0 = bottom:GetXYZ()
        x1, y1, z1 = top:GetXYZ()
    end
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    if not (finite(x0) and finite(y0) and finite(z0)
        and finite(x1) and finite(y1) and finite(z1)) then return end
    if x1 <= x0 or y1 <= y0 or z1 <= z0 then return end
    model.bounds = {
        bottom = z0 * Layout.modelScale,
        top = z1 * Layout.modelScale,
        minX = x0 * Layout.modelScale, maxX = x1 * Layout.modelScale,
        minY = y0 * Layout.modelScale, maxY = y1 * Layout.modelScale,
    }
end

local function applyCamera(model, distance, cameraHeight)
    local file = model:GetModelFileID()
    if not file or file == 0 then return false end
    model:SetModelScale(Layout.modelScale)
    model:SetPosition(0, 0, 0)
    model:SetCustomCamera(1)
    if not model:HasCustomCamera() then return false end
    model:SetCameraPosition(distance, 0, cameraHeight)
    model:SetCameraTarget(0, 0, cameraHeight)
    model.cameraDistance = distance
    model.cameraHeight = cameraHeight
    return true
end

function Models:FitPair()
    local player, npc = self.player, self.npc
    if not player or not npc then return end
    measure(player)
    measure(npc)
    local distance = Layout.modelCameraDistance
    local cameraHeight = Layout.modelCameraHeight
    if player.bounds and npc.bounds then
        local bottom = math.min(player.bounds.bottom, npc.bounds.bottom)
        local top = math.max(player.bounds.top, npc.bounds.top)
        cameraHeight = (bottom + top) / 2
        distance = 0
        for _, model in ipairs({ player, npc }) do
            local width, height = model:GetWidth(), model:GetHeight()
            if width <= 2 * Layout.edgeMargin or height <= 2 * Layout.edgeMargin then return end
            -- PlayerModel does not expose its projection field of view. This
            -- nominal angle estimates fitting from real base-mesh dimensions.
            local vertical = math.tan(Layout.modelCameraFieldOfView / 2)
            local horizontal = vertical * width / height
            vertical = vertical * (1 - 2 * Layout.edgeMargin / height)
            horizontal = horizontal * (1 - 2 * Layout.edgeMargin / width)
            local bounds = model.bounds
            local verticalExtent = math.max(cameraHeight - bounds.bottom, bounds.top - cameraHeight)
            local cosine, sine = math.cos(model.defaultFacing), math.sin(model.defaultFacing)
            -- Fit the opening angle. Rotation may clip the edges but must not
            -- change either copy's shared zoom, including on periodic updates.
            for _, x in ipairs({ bounds.minX, bounds.maxX }) do
                for _, y in ipairs({ bounds.minY, bounds.maxY }) do
                    local depth = x * cosine - y * sine
                    local side = x * sine + y * cosine
                    distance = math.max(distance, depth
                        + math.max(math.abs(side) / horizontal, verticalExtent / vertical))
                end
            end
        end
    end
    for _, model in ipairs({ player, npc }) do
        if model.cameraDistance ~= distance or model.cameraHeight ~= cameraHeight then
            applyCamera(model, distance, cameraHeight)
        end
    end
end

local function configure(model)
    model.cameraDistance = nil
    if not applyCamera(model, Layout.modelCameraDistance, Layout.modelCameraHeight) then return end
    model:SetFacing(model.facing)
    stand(model)
end

local function createModel(parent, facing)
    local model = CreateFrame("PlayerModel", nil, parent)
    model.facing = facing
    model.defaultFacing = facing
    model:EnableMouse(false)
    model:SetKeepModelOnHide(true)
    model.measureScene = CreateFrame("ModelScene", nil, model)
    model.measureScene:SetSize(1, 1)
    model.measureScene:SetPoint("CENTER", model, "CENTER")
    model.measureScene:EnableMouse(false)
    model.measureScene:SetAlpha(0)
    model.measureActor = model.measureScene:CreateActor()
    model.measureActor:Show()
    model:SetScript("OnModelLoaded", configure)
    model:SetScript("OnAnimFinished", function(self)
        if self.emoteUntil then stand(self) end
    end)
    model:Hide()
    return model
end

function Models:Hide()
    self.generation = self.generation + 1
    self.active, self.npcGUID, self.missingSince = nil, nil, nil
    self.pendingEmote, self.emoteContext, self.emoteEvent = nil, nil, nil
    driver:SetScript("OnUpdate", nil)
    if self.root then
        self.root:Hide()
        for _, model in ipairs({ self.player, self.npc }) do
            model:Hide()
            model:ClearModel()
            model.measureActor:ClearModel()
            model.bounds, model.measureFile, model.cameraDistance = nil, nil, nil
            model.guid = nil
            model.facing = model.defaultFacing
            model.emoteUntil, model.nextEmote = nil, nil
        end
    end
end

local function bind(model, unit, guid)
    if not guid or not UnitExists(unit) then return end
    if model.guid == guid then return end
    model.bounds, model.measureFile, model.cameraDistance = nil, nil, nil
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
        self.npc.measureActor:ClearModel()
        self.npc.bounds, self.npc.measureFile = nil, nil
        self.npc.guid = nil
        self.npc.facing = self.npc.defaultFacing
    end
    self.npcGUID = guid or self.npcGUID
    if guid then bind(self.npc, "npc", guid) end
    local now = GetTime()
    for _, model in ipairs({ self.npc, self.player }) do
        -- Some models omit the completion callback or loop an emote indefinitely.
        if model.emoteUntil and now >= model.emoteUntil then stand(model) end
    end
    self:FitPair()
    local context = table.concat({ panel:GetName(), NS.UI.nativeChromeMode or "",
        tostring(panel.selectedTab or ""), tostring(NS.NativeBags.inventorySelected or false) }, ":")
    if self.pendingEmote or self.emoteContext ~= context then
        local opening = not self.emoteContext
        self.emoteContext = context
        local event = self.pendingEmote and self.emoteEvent
        self.pendingEmote = nil
        local choices = emotes[event] or (opening and emotes.greeting) or emotes.conversation
        tryEmote(self.npc, choices.npc, now)
        tryEmote(self.player, choices.player, now)
    end
end

function Models:Open(event)
    self.active = true
    self.pendingEmote, self.emoteEvent = true, event
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
            self:RotateNPC(delta)
            elapsed = elapsed + delta
            if elapsed < 0.1 then return end
            elapsed = 0
            self:Update()
        end)
    end)
end

driver:SetScript("OnEvent", function(_, event, unit)
    if opens[event] then
        Models:Open(event)
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
