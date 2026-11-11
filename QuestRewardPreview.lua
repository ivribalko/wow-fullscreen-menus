local _, NS = ...
local Layout = NS.Layout

-- Previews the focused quest reward and adds a visual Triangle hint to its footer.
local driver = CreateFrame("Frame")
local owner, button, hint, hintLegend
local KEY = "PAD4"
local CLICK = "CLICK FullscreenMenusQuestRewardPreview:LeftButton"

local function GetFooter()
    return QuestFrame and QuestFrame:IsVisible() and QuestFrame.gamepadFooter
end

local function RewardsHaveFocus(footer)
    if not UIParent:IsVisible() or not QuestFrameRewardPanel or not QuestFrameRewardPanel:IsVisible()
        or not QuestInfoFrame or QuestInfoFrame.questLog
        or not footer or not footer.isShown or not footer.inputLegend
        or not footer.inputLegend:IsVisible() or GetCurrentKeyBoardFocus() then return false end
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if not manager or not manager.isUIFocused or manager.focusedFrame ~= QuestFrame then return false end
    local bindings = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    local stack = bindings and bindings.bindingSetStack
    local top = stack and stack[#stack]
    return top and footer.bindings and top.name == footer.bindings.name
        and not GamepadSharedUtility.IsSuspendFooterShown()
end

local function GetPreviewLink(footer)
    if not RewardsHaveFocus(footer) or not SmartNavigation then return end
    local focused = SmartNavigation:GetCurrentButton()
    if not focused or not focused:IsVisible() or focused.objectType ~= "item"
        or (focused.type ~= "choice" and focused.type ~= "reward") then return end
    local rewards = QuestInfoFrame.rewardsFrame
    if not rewards or not rewards.RewardButtons then return end
    -- Verify membership instead of trusting a stale navigation button or item choice.
    for _, reward in ipairs(rewards.RewardButtons) do
        if reward == focused then
            if not NS.ConversationModels:CanPreviewReward() then return end
            local link = GetQuestItemLink(reward.type, reward:GetID())
            if link and C_Item.IsDressableItemByID(link) then return link end
            return
        end
    end
end

local function RefreshHint(legend, visible, enabled)
    local container = legend.promptContainerFrame
    if not container then return end
    if not hint then
        hint = CreateFrame("Frame", nil, container)
        hint.ignoreInLayout = true
        hint:SetHeight(Layout.promptIconSize)
        hint.Icon = hint:CreateTexture(nil, "ARTWORK")
        hint.Icon:SetSize(Layout.promptIconSize, Layout.promptIconSize)
        hint.Icon:SetPoint("LEFT")
        local label = hint:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", hint.Icon, "RIGHT", Layout.promptLabelGap, 0)
        label:SetText("Try On")
        hint:SetWidth(label:GetStringWidth() + Layout.promptIconSize + Layout.promptLabelGap)
    end
    if hint:GetParent() ~= container then hint:SetParent(container) end
    hintLegend = legend

    -- Read native prompt bounds afresh; never register in native layout tables
    -- or hook their methods, which run in protected controller focus paths.
    local last, right, bottom = nil, Layout.promptPadding, Layout.promptIconSize + Layout.promptPadding
    for _, key in ipairs(legend.promptFramesAddOrder) do
        local prompt = legend.promptFrames[key]
        if prompt:IsShown() then
            local _, _, _, x, y = prompt:GetPoint(1)
            right = math.max(right, x + prompt:GetWidth() + Layout.promptPadding)
            bottom = math.max(bottom, -y + Layout.promptIconSize + Layout.promptPadding)
            last = prompt
        end
    end
    local width = legend.wrapAroundRowWidth and container:GetWidth() or right
    local height = bottom
    if visible then
        local x, y = Layout.promptPadding, -Layout.promptPadding
        if last then
            local _, _, _, lastX, lastY = last:GetPoint(1)
            x, y = lastX + last:GetWidth() + Layout.promptGap, lastY
        end
        if legend.wrapAroundRowWidth and x + hint:GetWidth() + Layout.promptPadding > width then
            x, y = Layout.promptPadding, y - Layout.promptIconSize - Layout.promptRowGap
        end
        if not legend.wrapAroundRowWidth then width = x + hint:GetWidth() + Layout.promptPadding end
        height = math.max(height, -y + Layout.promptIconSize + Layout.promptPadding)
        local point, relative, relativePoint, oldX, oldY = hint:GetPoint(1)
        if point ~= "TOPLEFT" or relative ~= container or relativePoint ~= "TOPLEFT"
            or oldX ~= x or oldY ~= y then
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
        end
        local atlas = InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(GAMEPAD_FACE_TOP)
        if atlas then hint.Icon:SetAtlas(atlas) end
        hint:SetAlpha(enabled and 1 or 0.4)
    end
    if container:GetWidth() ~= width or container:GetHeight() ~= height then
        container:SetSize(width, height)
    end
    if legend:GetHeight() ~= height then legend:SetHeight(height) end
    if not legend.wrapAroundRowWidth then
        local legendWidth = width + (legend.modifierFrame and legend.modifierFrame:GetWidth() or 0)
        if legend:GetWidth() ~= legendWidth then legend:SetWidth(legendWidth) end
    end
    if legend.modifierFrame and legend.modifierFrame:GetHeight() ~= height then
        legend.modifierFrame:SetHeight(height)
    end
    hint:SetShown(visible)
end

local function Refresh()
    if not owner and not InCombatLockdown() then
        owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        owner:SetAttribute("_onstate-combat", [[
            if newstate == "combat" then self:ClearBindings() end
        ]])
        RegisterStateDriver(owner, "combat", "[combat] combat; peace")
        button = CreateFrame("Button", "FullscreenMenusQuestRewardPreview", UIParent)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyDown")
        button:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local link = GetPreviewLink(GetFooter())
            if link then NS.ConversationModels:PreviewReward(link) end
        end)
    end
    local footer = GetFooter()
    local link = GetPreviewLink(footer)
    local enabled = link and not InCombatLockdown()
    local legend = footer and footer.inputLegend
    if hintLegend and hintLegend ~= legend then RefreshHint(hintLegend, false, false) end
    if legend then RefreshHint(legend, link ~= nil, enabled) end
    if not owner or InCombatLockdown() then return end
    if enabled then
        if GetBindingAction(KEY, true) ~= CLICK then
            owner:Execute([[self:SetBindingClick(true, "PAD4", "FullscreenMenusQuestRewardPreview", "LeftButton")]])
        end
    else
        owner:Execute([[self:ClearBindings()]])
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:SetScript("OnEvent", Refresh)
-- Observe selection and footer rebuilds without registering native callbacks.
driver:SetScript("OnUpdate", function()
    if IsLoggedIn() then Refresh() end
end)
