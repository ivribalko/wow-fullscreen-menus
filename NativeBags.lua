local _, NS = ...

-- NativeBags distributes separate Blizzard bag windows without changing their item grids.
local Bags = { saved = {}, concealed = {} }
NS.NativeBags = Bags

-- Conceal the inactive surface without firing native OnHide interaction handlers.
function Bags:Reveal(frame)
    local saved = self.concealed[frame]
    if not saved then return end
    frame:SetAlpha(saved.alpha)
    for control, enabled in pairs(saved.mouse) do control:EnableMouse(enabled) end
    self.concealed[frame] = nil
end

function Bags:Conceal(frame)
    if frame:IsForbidden() then return end
    local saved = self.concealed[frame]
    if not saved then
        saved = { alpha = frame:GetAlpha(), mouse = {} }
        self.concealed[frame] = saved
    end
    local function disable(control)
        if control:IsForbidden() then return end
        if saved.mouse[control] == nil then saved.mouse[control] = control:IsMouseEnabled() end
        control:EnableMouse(false)
        for _, child in ipairs({ control:GetChildren() }) do disable(child) end
    end
    disable(frame)
    frame:SetAlpha(0)
end

function Bags:UpdatePane()
    if InCombatLockdown() then return end
    local ui = NS.UI
    local panel = NS.Integration:GetInteractionPanel()
    if not ui.nativeChrome or not ui.nativeChrome:IsShown() or ui.nativeChromeMode ~= "inventory" then panel = nil end
    local changed = self.interaction ~= panel
    if changed then
        for frame in pairs(self.concealed) do self:Reveal(frame) end
        self.interaction = panel
        self.inventorySelected = panel == nil
        -- Mail loads its inbox before choosing initial native focus. Preserve
        -- the currently focused bags until that native handoff completes.
        local manager = GamepadMode and GamepadMode.FrameControlsManager
        if panel and panel == MailFrame and InputUtil and InputUtil.IsGamepadUIEnabled() and manager then
            self.inventorySelected = manager:GetActiveFrame() == ContainerFrameCombinedBags
        end
        ui:LayoutModeTabs()
    end
    if not panel then return end
    if self.inventorySelected then self:Conceal(panel) else self:Reveal(panel) end
    for _, frame in ipairs(NS.Integration:GetNativeBagFrames()) do
        if frame ~= ContainerFrameContainer then
            if self.inventorySelected then self:Reveal(frame) else self:Conceal(frame) end
        end
    end
    if changed and panel ~= MailFrame then NS.Integration:FocusNativePane(panel) end
end

function Bags:SelectPane(inventory, fromNativeFocus)
    if InCombatLockdown() then return end
    NS.UI:RestoreMenuFades()
    self.inventorySelected = inventory
    NS.UI:ClearItemTooltip()
    NS.UI:RestoreNativePanelLayout()
    self:UpdatePane()
    self:Layout()
    NS.UI:LayoutModeTabs()
    NS.UI:LayoutNativePanel()
    NS.UI:FadeNativeMenuIn(true)
    local panel = self.inventorySelected and ContainerFrameCombinedBags or self.interaction
    if not fromNativeFocus then NS.Integration:FocusNativePane(panel) end
end

function Bags:Close()
    if InCombatLockdown() then self.closePending = true; return end
    self.closePending = nil
    self:Restore()
    for frame in pairs(self.concealed) do self:Reveal(frame) end
    self.interaction = nil
    self.inventorySelected = true
end

function Bags:IsActive()
    local ui = NS.UI
    return ui.nativeChrome and ui.nativeChrome:IsShown()
        and ui.nativeChromeMode == "inventory"
        and (not self.interaction or self.inventorySelected)
        and not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
end

function Bags:Schedule()
    if self.updating or self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        self.pending = nil
        self:Layout()
    end)
end

function Bags:Restore()
    if InCombatLockdown() then self.restorePending = true; return end
    self.restorePending = nil
    self.updating = true
    for frame, saved in pairs(self.saved) do
        frame:SetScale(saved.scale)
        frame:ClearAllPoints()
        for _, point in ipairs(saved.points) do frame:SetPoint(unpack(point)) end
    end
    self.saved = {}
    self.layoutApplied = nil
    self.updating = nil
end

function Bags:Layout()
    if NS.Integration:IsEditModeActive() or InCombatLockdown() or self.updating then return end
    self:UpdatePane()
    if not self:IsActive() then self:Restore(); return end
    if self.layoutApplied then return end
    local frames = {}
    for _, frame in ipairs(NS.Integration:GetNativeBagFrames()) do
        if frame ~= ContainerFrameContainer and frame ~= ContainerFrameCombinedBags
            and not frame:IsForbidden() and frame:IsVisible()
            and frame:GetWidth() > 0 and frame:GetHeight() > 0 then
            frames[#frames + 1] = frame
        end
    end
    if #frames == 0 then self:Restore(); return end
    table.sort(frames, function(a, b)
        local aID, bID = a:GetID(), b:GetID()
        if aID ~= bID then return aID > bID end
        return (a:GetName() or "") > (b:GetName() or "")
    end)
    local ui, gap = NS.UI, NS.Layout.rowGap
    local chrome = ui.nativeChrome
    local top = ui.edgeMargin + NS.Layout.topPadding
    local width = chrome:GetWidth() - ui.edgeMargin * 2
    local height = chrome:GetHeight() - top - ui.edgeMargin
    if width <= 0 or height <= 0 then return end
    local maxWidth, maxHeight = 0, 0
    for _, frame in ipairs(frames) do
        maxWidth = math.max(maxWidth, frame:GetWidth())
        maxHeight = math.max(maxHeight, frame:GetHeight())
    end
    local bestColumns, bestScale = 1, 0
    for columns = 1, #frames do
        local rows = math.ceil(#frames / columns)
        local scale = math.min((width - gap * (columns - 1)) / columns / maxWidth,
            (height - gap * (rows - 1)) / rows / maxHeight)
        if scale > bestScale then bestColumns, bestScale = columns, scale end
    end
    bestScale = math.min(bestScale, NS.Layout.maxScale)
    if bestScale <= 0 then return end
    local rows = math.ceil(#frames / bestColumns)
    local cellHeight = (height - gap * (rows - 1)) / rows
    self.updating = true
    for index, frame in ipairs(frames) do
        if not self.saved[frame] then
            local points = {}
            for point = 1, frame:GetNumPoints() do points[point] = { frame:GetPoint(point) } end
            self.saved[frame] = { scale = frame:GetScale(), points = points }
        end
        local row = math.floor((index - 1) / bestColumns)
        local column = (index - 1) % bestColumns
        local count = math.min(bestColumns, #frames - row * bestColumns)
        local cellWidth = (width - gap * (count - 1)) / count
        local parentScale = frame:GetEffectiveScale() / frame:GetScale()
        frame:SetScale(bestScale * chrome:GetEffectiveScale() / parentScale)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", chrome, "TOPLEFT",
            (ui.edgeMargin + column * (cellWidth + gap) + cellWidth / 2) / bestScale,
            -(top + row * (cellHeight + gap) + cellHeight / 2) / bestScale)
    end
    self.layoutApplied = true
    self.updating = nil
end
