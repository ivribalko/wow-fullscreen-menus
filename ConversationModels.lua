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
            self:PositionModels()
            return
        end
    end
end

local function stand(model)
    model.emoteUntil = nil
    model:SetAnimation(0)
end

local function tryEmote(model, now)
    local choices = model.pendingEmoteChoices
    if not choices or not model.guid or not model.bounds or not model:IsVisible()
        or (model.nextEmote and now < model.nextEmote) then return end
    -- Consume each request only after loading and cooldown have completed.
    model.pendingEmoteChoices = nil
    model.nextEmote = now + emoteCooldown
    if math.random() >= emoteChance then return end
    model.emoteUntil = now + emoteTimeout
    local ok, success = pcall(model.SetAnimation, model, choices[math.random(#choices)])
    if not ok or success == false then stand(model) end
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Read the native geometry bounds once; animation never refits the camera.
local function readBounds(actor)
    local x0, y0, z0, x1, y1, z1 = actor:GetActiveBoundingBox()
    if type(x0) == "table" and x0.GetXYZ and type(y0) == "table" and y0.GetXYZ then
        local bottom, top = x0, y0
        x0, y0, z0 = bottom:GetXYZ()
        x1, y1, z1 = top:GetXYZ()
    end
    if not (finite(x0) and finite(y0) and finite(z0)
        and finite(x1) and finite(y1) and finite(z1)) then return end
    if x1 <= x0 or y1 <= y0 or z1 <= z0 then return end
    local scale = actor:GetScale()
    return { minX = x0 * scale, maxX = x1 * scale,
        minY = y0 * scale, maxY = y1 * scale,
        bottom = z0 * scale, top = z1 * scale }
end

local function measure(actor)
    if actor.bounds or not actor:IsLoaded() then return end
    if actor.IsGeoReady and not actor:IsGeoReady() then return end
    actor:SetUseCenterForOrigin(false, false, false)
    actor:SetScale(Layout.modelScale)
    actor:SetPitch(0)
    actor:SetRoll(0)
    stand(actor)
    actor:SetPreferModelCollisionBounds(false)
    local bounds = readBounds(actor)
    if not bounds then return end
    -- Body collision bounds keep a sword, cape, or particle from defining feet.
    -- The API falls back to model bounds when collision bounds are unavailable.
    actor:SetPreferModelCollisionBounds(true)
    local body = readBounds(actor) or bounds
    actor:SetPreferModelCollisionBounds(false)
    bounds.centerX = (body.minX + body.maxX) / 2
    bounds.centerY = (body.minY + body.maxY) / 2
    bounds.ground = body.bottom
    actor.bounds = bounds
end

function Models:PositionModels()
    if not self.cameraDistance then return end
    for _, model in ipairs({ self.npc, self.player }) do
        local bounds = model.bounds
        if bounds then
            local cosine, sine = math.cos(model.facing), math.sin(model.facing)
            model:SetYaw(model.facing)
            model:SetPosition(-bounds.centerX * cosine + bounds.centerY * sine,
                model.sideOffset - bounds.centerX * sine - bounds.centerY * cosine, -bounds.ground)
        end
    end
end

--@alpha@
-- Numeric world positions and native projected ground points verify alignment.
function Models:TraceProjection()
    if not NS.Data or not NS.Data.db or not self.cameraDistance then return end
    local now = GetTime()
    if self.projectionGeneration ~= self.generation then
        self.projectionGeneration, self.projectionSamples, self.projectionNext = self.generation, 0, 0
    end
    if self.projectionSamples >= 4 or now < self.projectionNext then return end
    self.projectionSamples = self.projectionSamples + 1
    self.projectionNext = now + 1
    local entry = { elapsed = now, sample = self.projectionSamples,
        camera = { self.root:GetCameraPosition() },
        fieldOfView = self.root:GetCameraFieldOfView(),
        frameSize = { self.root:GetWidth(), self.root:GetHeight() } }
    for _, role in ipairs({ "player", "npc" }) do
        local model = self[role]
        entry[role] = { modelFile = model:GetModelFileID(), bounds = model.bounds,
            scale = model:GetScale(), position = { model:GetPosition() }, facing = model:GetYaw(),
            projectedGround = { self.root:Project3DPointTo2D(0, model.sideOffset, 0) } }
    end
    local trace = NS.Data.db.modelProjectionDiagnostics
    if type(trace) ~= "table" or trace.version ~= 3 then
        trace = { version = 3, entries = {} }
        NS.Data.db.modelProjectionDiagnostics = trace
    end
    trace.entries[#trace.entries + 1] = entry
    if #trace.entries > 16 then table.remove(trace.entries, 1) end
end
--@end-alpha@

-- Fit against the client's projection, whose magnification and axis signs
-- differ from a textbook camera on this client. Never infer them from FOV.
function Models:FitPair()
    local player, npc = self.player, self.npc
    measure(player)
    measure(npc)
    if not player.bounds or not npc.bounds then return end
    local width, height = self.root:GetWidth(), self.root:GetHeight()
    if width * Layout.modelWidth <= 2 * Layout.edgeMargin
        or height * Layout.modelHeight <= 2 * Layout.edgeMargin then return end
    if self.fittedPlayer ~= player.bounds or self.fittedNPC ~= npc.bounds
        or self.fittedWidth ~= width or self.fittedHeight ~= height then
        local corners, maximumDepth, maximumHeight = {}, 0, 0
        for _, model in ipairs({ npc, player }) do
            local bounds = model.bounds
            local cosine, sine = math.cos(model.defaultFacing), math.sin(model.defaultFacing)
            local left = model.side < 0 and width * Layout.modelSideInset
                or width * (1 - Layout.modelSideInset - Layout.modelWidth)
            local limits = { left = left + Layout.edgeMargin,
                right = left + width * Layout.modelWidth - Layout.edgeMargin }
            for _, x in ipairs({ bounds.minX - bounds.centerX, bounds.maxX - bounds.centerX }) do
                for _, y in ipairs({ bounds.minY - bounds.centerY, bounds.maxY - bounds.centerY }) do
                    local depth, lateral = x * cosine - y * sine, x * sine + y * cosine
                    maximumDepth = math.max(maximumDepth, depth)
                    for _, z in ipairs({ bounds.bottom - bounds.ground, bounds.top - bounds.ground }) do
                        corners[#corners + 1] = { model = model, x = depth, y = lateral, z = z, limits = limits }
                        maximumHeight = math.max(maximumHeight, math.abs(z))
                    end
                end
            end
        end
        local bottom = height * Layout.modelBottomInset + Layout.edgeMargin
        local top = height * (Layout.modelBottomInset + Layout.modelHeight) - Layout.edgeMargin
        local function evaluate(distance)
            self.root:SetCameraPosition(distance, 0, 0)
            local originX = self.root:Project3DPointTo2D(0, 0, 0)
            local unitX = self.root:Project3DPointTo2D(0, 1, 0)
            if not finite(originX) or not finite(unitX) or math.abs(unitX - originX) < 0.000001 then return end
            local offsets = {}
            for _, model in ipairs({ npc, player }) do
                local center = width * (Layout.modelSideInset + Layout.modelWidth / 2)
                if model.side > 0 then center = width - center end
                offsets[model] = (center - originX) / (unitX - originX)
            end
            local minimumHeight, maximumCameraHeight = -math.huge, math.huge
            for _, corner in ipairs(corners) do
                local y = corner.y + offsets[corner.model]
                local screenX, screenY = self.root:Project3DPointTo2D(corner.x, y, corner.z)
                local _, higherY = self.root:Project3DPointTo2D(corner.x, y, corner.z + 1)
                if not finite(screenX) or not finite(screenY) or not finite(higherY) then return end
                if screenX < corner.limits.left or screenX > corner.limits.right then return end
                local slope = higherY - screenY
                if math.abs(slope) < 0.000001 then return end
                local low, high = (screenY - top) / slope, (screenY - bottom) / slope
                if low > high then low, high = high, low end
                minimumHeight = math.max(minimumHeight, low)
                maximumCameraHeight = math.min(maximumCameraHeight, high)
            end
            if minimumHeight > maximumCameraHeight then return end
            return maximumCameraHeight, offsets
        end
        local near = maximumDepth + 0.02
        local far = near + maximumHeight
        local cameraHeight, offsets
        -- Bracket a visible fit, then find the closest fitting shared distance.
        for _ = 1, 16 do
            cameraHeight, offsets = evaluate(far)
            if cameraHeight then break end
            far = far * 2
            if far >= 900 then return end
        end
        if not cameraHeight then return end
        for _ = 1, 16 do
            local candidate = (near + far) / 2
            local candidateHeight, candidateOffsets = evaluate(candidate)
            if candidateHeight then
                far, cameraHeight, offsets = candidate, candidateHeight, candidateOffsets
            else
                near = candidate
            end
        end
        self.cameraDistance = far
        self.root:SetCameraPosition(far, 0, cameraHeight)
        for _, model in ipairs({ npc, player }) do model.sideOffset = offsets[model] end
        self.fittedPlayer, self.fittedNPC = player.bounds, npc.bounds
        self.fittedWidth, self.fittedHeight = width, height
    end
    self:PositionModels()
    player:Show()
    npc:Show()
    --@alpha@
    self:TraceProjection()
    --@end-alpha@
end

-- Actors share one scene, one native projection, and the scene's z=0 floor.
local function createModel(scene, facing, side)
    local model = scene:CreateActor()
    model.facing, model.defaultFacing, model.side = facing, facing, side
    model:Hide()
    return model
end

function Models:Hide()
    self.generation = self.generation + 1
    self.active, self.npcGUID, self.missingSince = nil, nil, nil
    self.pendingEmote, self.emoteContext, self.emoteEvent = nil, nil, nil
    self.cameraDistance, self.fittedPlayer, self.fittedNPC = nil, nil, nil
    driver:SetScript("OnUpdate", nil)
    if self.root then
        self.root:Hide()
        for _, model in ipairs({ self.player, self.npc }) do
            model:Hide()
            model:ClearModel()
            model.bounds, model.sideOffset = nil, nil
            model.guid = nil
            model.unit = nil
            model.facing = model.defaultFacing
            model.emoteUntil, model.nextEmote, model.pendingEmoteChoices = nil, nil, nil
        end
    end
end

local function bind(model, unit, guid)
    if not guid or not UnitExists(unit) then return end
    if model.guid == guid then return end
    model.bounds = nil
    model.unit = unit
    model:Hide()
    model:ClearModel()
    local ok, success
    if unit == "player" then
        ok, success = pcall(model.SetModelByUnit, model, unit, false, true, false, false)
    else
        ok, success = pcall(model.SetModelByUnitCreatureDisplayID, model, unit)
    end
    if ok and success ~= false then
        model.guid = guid
        measure(model)
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
        self.root = CreateFrame("ModelScene", nil, parent)
        self.root:EnableMouse(false)
        self.root:SetCameraFieldOfView(Layout.modelCameraFieldOfView)
        -- Let the engine construct its camera basis; hand-built axis vectors
        -- can reflect the view and reverse triangle winding.
        self.root:SetCameraOrientationByYawPitchRoll(math.pi, 0, 0)
        self.root:SetCameraNearClip(0.01)
        self.root:SetCameraFarClip(1000)
        self.root:SetLightAmbientColor(0.8, 0.8, 0.8)
        self.root:SetLightDiffuseColor(0.8, 0.8, 0.8)
        self.root:SetLightDirection(-1, 0, -1)
        self.root:SetLightVisible(true)
        self.player = createModel(self.root, -0.35, 1)
        self.npc = createModel(self.root, 0.35, -1)
    elseif self.root:GetParent() ~= parent then
        self.root:SetParent(parent)
    end
    self.root:SetAllPoints(UIParent)
    local strata = background:GetFrameStrata()
    local level = background:GetFrameLevel()
    self.root:SetFrameStrata(strata)
    self.root:SetFrameLevel(level)
    self.root:Show()
    bind(self.player, "player", UnitGUID("player"))
    local guid = UnitGUID("npc")
    if guid and self.npcGUID and guid ~= self.npcGUID then
        self.npc:ClearModel()
        self.npc.bounds = nil
        self.npc.guid = nil
        self.npc.emoteUntil, self.npc.nextEmote, self.npc.pendingEmoteChoices = nil, nil, nil
        self.npc.facing = self.npc.defaultFacing
    end
    self.npcGUID = guid or self.npcGUID
    if guid then bind(self.npc, "npc", guid) end
    local now = GetTime()
    for _, model in ipairs({ self.npc, self.player }) do
        -- Actor emotes can loop; always return to standing after the timeout.
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
        -- Keep the latest context per actor while either model loads.
        self.npc.pendingEmoteChoices = choices.npc
        self.player.pendingEmoteChoices = choices.player
    end
    tryEmote(self.npc, now)
    tryEmote(self.player, now)
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
