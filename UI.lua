local _, NS = ...
local Layout, Data = NS.Layout, NS.Data

local EDGE_MARGIN = Layout.edgeMargin
local function isStorage(mode)
    return mode == "inventory" or mode == "bank"
end
local BACKGROUND_ALPHA = Layout.backgroundAlpha
local LOWER_STRATA = {
    LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG",
}

-- UI owns native menu chrome, selectors, proportional layout, and presentation fades.
local UI = {
    edgeMargin = EDGE_MARGIN,
}
NS.UI = UI

-- Shared short fades use a separate driver so native OnUpdate handlers remain intact.
local FADE_DURATION = Layout.fadeDuration
function UI:CancelFade(frame)
    if self.fades then self.fades[frame] = nil end
end

function UI:FadeFrame(frame, alpha, finished)
    self.fades = self.fades or {}
    local pending = self.fades[frame]
    if pending and pending.target == alpha then return end
    self:CancelFade(frame)
    local readable, start = pcall(function() return frame:GetAlpha() + 0 end)
    if not readable then
        if finished then finished() end
        return
    end
    if start == alpha then
        if finished then finished() end
        return
    end
    if not self.fadeDriver then
        -- No UIParent ancestry: the isolation snapshot must never hide this driver.
        self.fadeDriver = CreateFrame("Frame")
        self.fadeDriver:SetScript("OnUpdate", function(driver, elapsed)
            local completed = {}
            for target, fade in pairs(self.fades) do
                if target:IsForbidden() or InCombatLockdown() and target:IsProtected() then
                    -- Isolation retains the original alpha for restoration after combat.
                    self.fades[target] = nil
                else
                    fade.elapsed = math.min(FADE_DURATION, fade.elapsed + elapsed)
                    local progress = fade.elapsed / FADE_DURATION
                    local updated = pcall(target.SetAlpha, target,
                        fade.start + (fade.target - fade.start) * progress)
                    if not updated or progress == 1 then
                        completed[#completed + 1] = { frame = target, fade = fade }
                    end
                end
            end
            -- Native hide callbacks can start new fades; run them after traversal.
            for _, entry in ipairs(completed) do
                if self.fades[entry.frame] == entry.fade then
                    self.fades[entry.frame] = nil
                    if entry.fade.finished then entry.fade.finished() end
                end
            end
            if not next(self.fades) then driver:Hide() end
        end)
    end
    self.fades[frame] = { start = start, target = alpha, elapsed = 0, finished = finished }
    self.fadeDriver:Show()
end

function UI:SetNativeBackgroundShown(shown)
    local background = self.nativeBackground
    if not background then return end
    if shown then
        if not background:IsShown() then background:SetAlpha(0); background:Show() end
        self:FadeFrame(background, 1)
    elseif background:IsShown() then
        self:FadeFrame(background, 0, function() background:Hide() end)
    end
end

-- Keep menu opacity separate from isolation and inactive interaction-pane opacity.
function UI:RestoreMenuFades()
    local pending = {}
    for frame, alpha in pairs(self.menuFadeAlphas or {}) do
        self:CancelFade(frame)
        if not frame:IsForbidden() then
            if InCombatLockdown() and frame:IsProtected() then pending[frame] = alpha
            else pcall(frame.SetAlpha, frame, alpha) end
        end
    end
    self.menuFadeAlphas = next(pending) and pending or nil
end

function UI:FadeNativeMenuIn(instant)
    self.menuFadeAlphas = self.menuFadeAlphas or {}
    local frames = { self.nativeChrome }
    local panel = self:GetNativePanel()
    if panel then frames[#frames + 1] = panel
    elseif self.nativeChromeMode == "inventory" then
        for _, bag in ipairs(NS.Integration:GetNativeBagFrames()) do
            if bag ~= ContainerFrameContainer then frames[#frames + 1] = bag end
        end
    end
    for _, frame in ipairs(frames) do
        if not frame:IsForbidden() and frame:IsVisible() and not self.menuFadeAlphas[frame] then
            local opening = NS.Menus.opening and NS.Menus.opening[frame]
            local alpha = opening and opening.alpha or frame:GetAlpha()
            if alpha > 0 then
                self.menuFadeAlphas[frame] = alpha
                if instant then
                    frame:SetAlpha(alpha)
                else
                    frame:SetAlpha(0)
                    self:FadeFrame(frame, alpha)
                end
            end
        end
    end
end

local function fill(parent, r, g, b, a, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

-- Available menus combine pinned entries with the current session.
function UI:GetAvailableModes()
    if NS.Integration:GetInteractionMode() then return { "inventory" } end
    local modes = {}
    for _, entry in ipairs(Data.accountDB and Data.accountDB.menuTabs or {}) do
        if entry.id ~= "bank" or Data.bankOpen then modes[#modes + 1] = entry.id end
    end
    for _, entry in ipairs(NS.Menus.sessionTabs or {}) do
        if not NS.Menus:FindSaved(entry.id) and (entry.id ~= "bank" or Data.bankOpen) then
            modes[#modes + 1] = entry.id
        end
    end
    local current = NS.Menus:GetCurrentEntry()
    if current and not NS.Menus:FindEntry(current.id) then modes[#modes + 1] = current.id end
    return modes
end

-- Native lifecycle callers refresh bindings without creating addon header controls.
function UI:LayoutModeTabs()
    self:UpdateControllerBindings()
end

-- Clear item and comparison tooltips before a different page takes focus.
function UI:ClearItemTooltip()
    if GameTooltip_HideShoppingTooltips then GameTooltip_HideShoppingTooltips(GameTooltip) end
    GameTooltip:Hide()
end

function UI:DiscoverTalentTabs()
    local frame = PlayerSpellsFrame
    if not frame or not frame.GetTabButton or not frame.IsTabAvailable then return false end
    local discovered = {}
    for _, field in ipairs({ "specTabID", "talentTabID", "spellBookTabID" }) do
        local tabID = frame[field]
        local nativeButton = tabID and frame:GetTabButton(tabID)
        local text = nativeButton and nativeButton.GetText and nativeButton:GetText()
        if not text and nativeButton and nativeButton.Text then text = nativeButton.Text:GetText() end
        if nativeButton and text and text ~= "" and frame:IsTabAvailable(tabID) then
            discovered[#discovered + 1] = { id = tabID, text = text }
        end
    end
    if #discovered == 0 then return false end
    self.talentTabs = discovered
    return true
end

-- Discovery callers share bounded backoff and coalesce pending retries by key.
function UI:RetryDiscovery(key, request)
    self.discoveryRetries = self.discoveryRetries or {}
    local retry = self.discoveryRetries[key] or {}
    self.discoveryRetries[key] = retry
    if retry.pending then return end
    retry.pending = true
    retry.delay = math.min(Layout.retryMaximumDelay, (retry.delay or Layout.retryInitialDelay) * 2)
    C_Timer.After(retry.delay, function()
        if self.discoveryRetries[key] ~= retry then return end
        retry.pending = nil
        request(self)
    end)
end

function UI:FinishDiscovery(key)
    if self.discoveryRetries then self.discoveryRetries[key] = nil end
end

function UI:RequestTalentTabs(callback)
    if not PlayerSpellsFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    end
    if callback then
        self.talentTabCallbacks = self.talentTabCallbacks or {}
        self.talentTabCallbacks[#self.talentTabCallbacks + 1] = callback
    end
    if self:DiscoverTalentTabs() then
        self:FinishDiscovery("talent")
        local callbacks = self.talentTabCallbacks or {}
        self.talentTabCallbacks = nil
        for _, pending in ipairs(callbacks) do pending() end
        return
    end
    self:RetryDiscovery("talent", self.RequestTalentTabs)
end

function UI:DiscoverCharacterTabs()
    -- Native side tabs carry the target subframe names.
    if CharacterFrame and CharacterFrame.ModeTabs then
        local discovered = {}
        for index, nativeButton in ipairs(CharacterFrame.ModeTabs.Tabs or {}) do
            if nativeButton.frameName and nativeButton:IsShown() then
                discovered[#discovered + 1] = {
                    index = index, panel = nativeButton.frameName,
                    text = nativeButton.tooltipText or nativeButton.frameName,
                }
            end
        end
        self.characterTabs = discovered
        return #discovered > 0
    end
    return false
end

function UI:RequestCharacterTabs(callback)
    if not CharacterFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_UIPanels_Game")
    end
    if callback then
        self.characterTabCallbacks = self.characterTabCallbacks or {}
        self.characterTabCallbacks[#self.characterTabCallbacks + 1] = callback
    end
    if self:DiscoverCharacterTabs() then
        self:FinishDiscovery("character")
        local callbacks = self.characterTabCallbacks or {}
        self.characterTabCallbacks = nil
        for _, pending in ipairs(callbacks) do pending() end
        return
    end
    self:RetryDiscovery("character", self.RequestCharacterTabs)
end

-- Own only Fullscreen Menus bindings and defer cleanup if chrome closes during combat.
function UI:UpdateControllerBindings()
    local chrome = self.nativeChrome
    if not chrome or InCombatLockdown() then return end
    local mode = not NS.Integration:IsEditModeActive() and not NS.Integration:IsActionBarEditing()
        and chrome:IsShown() and self.nativeChromeMode or nil
    local state = mode or "hidden"
    local previous, following
    if mode then
        previous = NS.Menus:GetForeverTriggerBinding(-1)
        following = NS.Menus:GetForeverTriggerBinding(1)
        state = state .. ":" .. (previous or "native") .. ":" .. (following or "native")
    end
    if self.controllerBindingState == state then return end
    ClearOverrideBindings(chrome)
    self.controllerBindingState = state
    if previous then SetOverrideBinding(chrome, true, "PADLTRIGGER", previous) end
    if following then SetOverrideBinding(chrome, true, "PADRTRIGGER", following) end
end

function UI:InitializeNativeChrome()
    if self.nativeChrome then return end
    local background = CreateFrame("Frame", "FullscreenMenusNativeBackground", UIParent)
    self.nativeBackground = background
    background:SetAllPoints(WorldFrame or UIParent)
    background:SetFrameStrata("BACKGROUND")
    fill(background, 0, 0, 0, BACKGROUND_ALPHA)
    background:Hide()

    local chrome = CreateFrame("Frame", "FullscreenMenusNativeChrome", UIParent)
    self.nativeChrome = chrome
    chrome:SetFrameStrata("TOOLTIP")
    chrome:Hide()

    local panelArea = CreateFrame("Frame", nil, chrome)
    self.nativePanelArea = panelArea
    panelArea:SetPoint("LEFT", self.edgeMargin, 0)
    panelArea:SetPoint("RIGHT", -self.edgeMargin, 0)
    panelArea:SetPoint("BOTTOM", 0, self.edgeMargin)

    chrome:SetScript("OnShow", function() self:UpdateControllerBindings() end)
    chrome:SetScript("OnUpdate", function(_, elapsed)
        self.mapTabRefreshElapsed = (self.mapTabRefreshElapsed or 0) + elapsed
        if self.mapTabRefreshElapsed < Layout.refreshInterval then return end
        self.mapTabRefreshElapsed = 0
        if self.nativeChromeMode == "map" then self:RequestMapTabs() end
        self:LayoutNativeBackground(self.nativeChromeTab)
        self:LayoutNativePanel()
        NS.NativeBags:Layout()
    end)
    chrome:SetScript("OnHide", function()
        self:UpdateControllerBindings()
        NS.Integration:ScheduleUIIsolationRestore()
    end)
end

function UI:ApplyNativeVariant()
    if InCombatLockdown() then return end
    NS.NativeBags:Layout()
    self:LayoutNativeBackground(self.nativeChromeTab)
    self:SetNativeBlackoutHidden(true)
    self:SetNativeBackgroundShown(true)
    self:LayoutNativePanel()
    self:ScheduleNativePanelLayout()
end

function UI:GetNativePanel()
    if self.nativeChromeMode == "generic" then return self.genericMenu end
    if self.nativeChromeMode == "map" then return WorldMapFrame end
    if self.nativeChromeMode == "talents" then return PlayerSpellsFrame end
    if isStorage(self.nativeChromeMode) then
        if NS.NativeBags.interaction and not NS.NativeBags.inventorySelected then
            return NS.NativeBags.interaction
        end
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            return ContainerFrameCombinedBags
        end
        return
    end
    return CharacterFrame
end

function UI:UpdateNativePanelArea()
    local area = self.nativePanelArea
    if not area or self.nativePanelAreaAnchored then return end
    area:ClearAllPoints()
    area:SetPoint("LEFT", self.nativeChrome, "LEFT", self.edgeMargin, 0)
    area:SetPoint("RIGHT", self.nativeChrome, "RIGHT", -self.edgeMargin, 0)
    area:SetPoint("BOTTOM", self.nativeChrome, "BOTTOM", 0, self.edgeMargin)
    area:SetPoint("TOP", self.nativeChrome, "TOP", 0, -(self.edgeMargin + Layout.topPadding))
    self.nativePanelAreaAnchored = true
end

function UI:RestoreNativePanelLayout()
    local state = self.nativePanelLayout
    if not state then return end
    local panel = state.panel
    self.restoringNativePanelLayout = true
    panel:SetScale(state.scale)
    panel:ClearAllPoints()
    for _, point in ipairs(state.points) do
        panel:SetPoint(point[1], point[2], point[3], point[4], point[5])
    end
    self.nativePanelLayout = nil
    self.restoringNativePanelLayout = nil
end

-- Measure native selectors and gamepad legends in panel units.
-- Their combined rectangle keeps side tabs and bottom prompts inside the safe area.
function UI:GetNativePanelBounds(panel)
    local width, height = panel:GetWidth(), panel:GetHeight()
    local left, bottom, right, top = 0, 0, width, height
    local panelLeft, panelBottom = panel:GetLeft(), panel:GetBottom()
    if not panelLeft or not panelBottom then return left, bottom, right, top end
    local panelScale = panel:GetEffectiveScale()
    local seen = {}
    local function include(region, owner)
        if not region or region:IsForbidden() or not region:IsVisible() then return end
        local x, y, w, h = region:GetRect()
        if not x or not y or not w or not h then return end
        local scale = owner:GetEffectiveScale() / panelScale
        x, y = x * scale - panelLeft, y * scale - panelBottom
        left, bottom = math.min(left, x), math.min(bottom, y)
        right, top = math.max(right, x + w * scale), math.max(top, y + h * scale)
    end
    local function includeTab(button)
        if not button or seen[button] or button:IsForbidden() then return end
        -- Only descendants share the panel's scale and anchor movement.
        local parent = button
        while parent and parent ~= panel do parent = parent:GetParent() end
        if parent ~= panel then return end
        seen[button] = true
        include(button, button)
        for _, region in ipairs({ button:GetRegions() }) do include(region, button) end
    end
    for _, definition in ipairs(NS.Menus:DiscoverTabs(panel)) do includeTab(definition.button) end
    if panel == PlayerSpellsFrame then
        for _, definition in ipairs(self.talentTabs or {}) do
            includeTab(panel:GetTabButton(definition.id))
        end
    elseif panel == WorldMapFrame then
        for _, definition in ipairs(self.mapTabs or {}) do includeTab(definition.button) end
    end
    -- Native footers create unnamed InputPromptLegend frames under their owner,
    -- including nested subpanels. Read their geometry without refreshing bindings.
    local function includeLegends(owner)
        for _, child in ipairs({ owner:GetChildren() }) do
            if not child:IsForbidden() and child:IsVisible() then
                if child.promptContainerFrame and child.promptFrames then
                    include(child, child)
                    include(child.promptContainerFrame, child.promptContainerFrame)
                else
                    includeLegends(child)
                end
            end
        end
    end
    includeLegends(panel)
    -- Map focus swaps footers after opening. Reserve their below-map footprint
    -- even while hidden, without activating bindings or refitting on focus changes.
    if panel == WorldMapFrame and not panel:IsMaximized() then
        for _, key in ipairs({ "worldMapFooter", "questLogFooter", "questDetailsFooter", "navigationFooter" }) do
            local footer = panel[key]
            local legend = footer and footer.inputLegend
            if legend and not legend:IsForbidden() then
                local container = legend.promptContainerFrame
                local scale = legend:GetEffectiveScale() / panelScale
                local legendHeight = legend:GetHeight()
                if container and not container:IsForbidden() then
                    legendHeight = math.max(legendHeight,
                        container:GetHeight() * container:GetEffectiveScale() / legend:GetEffectiveScale())
                end
                bottom = math.min(bottom, ((footer.yOffset or 0) - legendHeight) * scale - Layout.rowGap)
            end
        end
    end
    return left, bottom, right, top
end

-- Avoid invalidating native button/text geometry on unchanged periodic refreshes.
local function applyPanelPlacement(panel, scale, point, area, x, y)
    local function equal(a, b)
        return a and b and math.abs(a - b) < 0.000001
    end
    if not equal(panel:GetScale(), scale) then panel:SetScale(scale) end
    if panel:GetNumPoints() == 1 then
        local anchor, relative, relativePoint, offsetX, offsetY = panel:GetPoint(1)
        if anchor == point and relative == area and relativePoint == "CENTER"
            and equal(offsetX, x) and equal(offsetY, y) then return end
    end
    panel:ClearAllPoints()
    panel:SetPoint(point, area, "CENTER", x, y)
end

function UI:LayoutNativePanel()
    if NS.Integration:IsEditModeActive() or InCombatLockdown() or self.layingOutNativePanel or self.restoringNativePanelLayout then return end
    if not self.nativeChrome or not self.nativeChrome:IsShown() then return end
    self:UpdateNativePanelArea()
    local panel = self:GetNativePanel()
    if not panel or not panel:IsShown() or panel:GetWidth() <= 0 or panel:GetHeight() <= 0 then return end
    local state = self.nativePanelLayout
    local menuType = self.nativeChromeTab or self.nativeChromeMode
    if state and (state.panel ~= panel or state.menuType ~= menuType) then
        self:RestoreNativePanelLayout()
        state = nil
    end
    if state and state.applied then
        -- Native quest progress/reward transitions can reposition an open panel.
        -- Restore its fitted geometry without measuring changing content again.
        self.layingOutNativePanel = true
        applyPanelPlacement(panel, state.placement.scale, state.placement.point,
            self.nativePanelArea, state.placement.x, state.placement.y)
        self.layingOutNativePanel = nil
        return
    end
    if not state then
        local points = {}
        for index = 1, panel:GetNumPoints() do
            points[index] = { panel:GetPoint(index) }
        end
        state = { panel = panel, points = points, scale = panel:GetScale(), menuType = menuType }
        self.nativePanelLayout = state
    end

    local area = self.nativePanelArea
    local parentScale = panel:GetEffectiveScale() / math.max(panel:GetScale(), 0.001)
    local availableWidth = area:GetWidth() * area:GetEffectiveScale()
    local availableHeight = area:GetHeight() * area:GetEffectiveScale()
    if availableWidth <= 0 or availableHeight <= 0 then return end
    local conversation = panel == GossipFrame or panel == QuestFrame
    local placement = conversation and self.questConversationLayout
    if placement then
        -- Both native frames share the opening conversation's scale and top-left
        -- corner, even when their footer, content size, or parent scale differs.
        self.layingOutNativePanel = true
        applyPanelPlacement(panel, placement.scale * area:GetEffectiveScale() / parentScale,
            "TOPLEFT", area, placement.x, placement.y)
        state.placement = { scale = panel:GetScale(), point = "TOPLEFT", x = placement.x, y = placement.y }
        state.applied = true
        self.layingOutNativePanel = nil
        return
    end
    -- Measure once for this menu type; content and size changes keep its layout.
    local width, height = panel:GetWidth(), panel:GetHeight()
    local left, bottom, right, top = self:GetNativePanelBounds(panel)
    local naturalWidth = (right - left) * parentScale * state.scale
    local naturalHeight = (top - bottom) * parentScale * state.scale
    local fit = math.min(Layout.maxScale, availableWidth / naturalWidth, availableHeight / naturalHeight)
    self.layingOutNativePanel = true
    applyPanelPlacement(panel, state.scale * fit, "CENTER", area,
        (panel:GetWidth() - left - right) / 2,
        (panel:GetHeight() - bottom - top) / 2)
    state.placement = {
        scale = panel:GetScale(), point = "CENTER",
        x = (width - left - right) / 2, y = (height - bottom - top) / 2,
    }
    if conversation then
        self.questConversationLayout = {
            scale = panel:GetEffectiveScale() / area:GetEffectiveScale(),
            x = -(left + right) / 2,
            y = height - (bottom + top) / 2,
        }
    end
    state.applied = true
    self.layingOutNativePanel = nil
end

function UI:ScheduleNativePanelLayout()
    if self.nativePanelLayoutPending then return end
    self.nativePanelLayoutPending = true
    C_Timer.After(0, function()
        self.nativePanelLayoutPending = false
        self:LayoutNativePanel()
    end)
end

function UI:LayoutNativeBackground(nativeTab)
    -- Native bags and interaction panels can use different strata and frame levels.
    -- Keep their shared backdrop below both sides of the open interaction.
    if isStorage(nativeTab) and NS.Integration:GetInteractionPanel() then
        self.nativeBackground:SetFrameStrata("BACKGROUND")
        self.nativeBackground:SetFrameLevel(0)
        return
    end
    local panel = self:GetNativePanel()
    if not panel and nativeTab == "inventory" then
        panel = ContainerFrameCombinedBags
        if not panel or not panel:IsShown() then panel = ContainerFrame1 end
    elseif not panel and nativeTab == "bank" then
        panel = BankFrame
    end
    local strata = panel and panel:GetFrameStrata() or "LOW"
    local level = panel and panel:GetFrameLevel() or 1
    if level > 0 then
        self.nativeBackground:SetFrameStrata(strata)
        self.nativeBackground:SetFrameLevel(level - 1)
    else
        self.nativeBackground:SetFrameStrata(LOWER_STRATA[strata] or "BACKGROUND")
        self.nativeBackground:SetFrameLevel(0)
    end
end

function UI:SetNativeBlackoutHidden(hidden)
    local panel = self:GetNativePanel()
    local blackout = panel and panel.BlackoutFrame
    local state = self.nativeBlackoutState
    if state and (not hidden or state.frame ~= blackout) then
        state.frame:SetAlpha(state.alpha)
        self.nativeBlackoutState = nil
    end
    if hidden and blackout and not self.nativeBlackoutState then
        self.nativeBlackoutState = { frame = blackout, alpha = blackout:GetAlpha() }
        blackout:SetAlpha(0)
    end
end

-- Read native map selectors to include their artwork in layout bounds.
function UI:DiscoverMapTabs()
    local panel = QuestMapFrame
    if not panel or not panel.TabButtons then return false end
    local discovered, candidates, seen = {}, {}, {}
    for _, nativeButton in ipairs(panel.TabButtons) do
        candidates[#candidates + 1] = nativeButton
        seen[nativeButton] = true
    end
    -- Addon map tabs deliberately live outside Blizzard's managed array.
    for _, child in ipairs({ panel:GetChildren() }) do
        if not seen[child] and child.displayMode and child.GetScript
            and child:GetScript("OnMouseUp") then
            candidates[#candidates + 1] = child
        end
    end
    for _, nativeButton in ipairs(candidates) do
        local text = nativeButton.tooltipText
            or (nativeButton.GetText and nativeButton:GetText())
        if nativeButton.displayMode and text and text ~= ""
            and nativeButton:IsShown() then
            discovered[#discovered + 1] = {
                id = nativeButton.displayMode, text = text, button = nativeButton,
            }
        end
    end
    self.mapTabs = discovered
    return #discovered > 0
end

-- Use the tab's own handler so addon hooks and content routing run together.

function UI:RequestMapTabs()
    if self.nativeChromeMode ~= "map" then return end
    if self:DiscoverMapTabs() then
        self:FinishDiscovery("map")
        self:ScheduleNativePanelLayout()
        if not self.mapTabWatch then
            self.mapTabWatch = true
            hooksecurefunc(QuestMapFrame, "SetDisplayMode", function()
                if self.nativeChromeMode == "map" then self:ScheduleNativePanelLayout() end
            end)
        end
        return
    end
    self:RetryDiscovery("map", self.RequestMapTabs)
end

-- Read live safe-area dimensions, including the first menu after reload.
local function resizeSafeArea(frame)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = math.min(1, width / 720, height / 540)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetSize(width / scale, height / scale)
end

function UI:ResizeNativeChrome()
    if not self.nativeChrome then return end
    resizeSafeArea(self.nativeChrome)
    self:LayoutNativePanel()
end

function UI:ShowNativeChrome(nativeTab, mode)
    if NS.Integration:IsEditModeActive() or InCombatLockdown() then return end
    local switching = self.menuSessionActive
    if switching then self:RestoreMenuFades() end
    if mode ~= "generic" and self.genericMenu then
        self:HideNativeChrome()
    end
    self:InitializeNativeChrome()
    self:ClearItemTooltip()
    self.nativeChromeTab = nativeTab
    self.nativeChromeMode = mode or (nativeTab == "map" and "map"
        or isStorage(nativeTab) and nativeTab or "character")
    self:LayoutModeTabs()
    if self.nativeChromeMode == "character" then self:RequestCharacterTabs() end
    if self.nativeChromeMode == "talents" then self:RequestTalentTabs() end
    if self.nativeChromeMode == "map" then self:RequestMapTabs() end
    self:ResizeNativeChrome()
    self.nativeChrome:Show()
    self:UpdateControllerBindings()
    self:ApplyNativeVariant()
    self.menuSessionActive = true
    self:FadeNativeMenuIn(switching)
    NS.Integration:SyncNativeMenuVisibility()
end

function UI:HideNativeChrome()
    self.questConversationLayout = nil
    self:RestoreMenuFades()
    NS.NativeBags:Close()
    local state = self.nativePanelLayout
    if InCombatLockdown() and (state or self.nativeBlackoutState) then
        self.pendingNativeRestore = true
        if self.nativeChrome then self.nativeChrome:Hide() end
        self:SetNativeBackgroundShown(false)
        return
    end
    self.pendingNativeRestore = nil
    self:RestoreNativePanelLayout()
    self:SetNativeBlackoutHidden(false)
    if self.nativeChrome then self.nativeChrome:Hide() end
    self:SetNativeBackgroundShown(false)
    self.genericMenu = nil
end

-- Refresh only the active native presentation; item state belongs to Blizzard.
function UI:Refresh()
    self:LayoutModeTabs()
    if self.nativeChrome and self.nativeChrome:IsShown() then
        self:ScheduleNativePanelLayout()
        NS.NativeBags:Schedule()
    end
end

function UI:Initialize()
    self:InitializeNativeChrome()
    self:ResizeNativeChrome()
end

function UI:Resize()
    self:ResizeNativeChrome()
    self:Refresh()
end
