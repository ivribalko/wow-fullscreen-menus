local addonName, NS = ...
local Data, UI = NS.Data, NS.UI

-- Integration connects native menu entry points, routed panels, interaction state, and native gamepad focus.
local Integration = { interactions = {}, suppress = false }
NS.Integration = Integration

-- Keep native layout editing free of fullscreen presentation.
function Integration:IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false
end

-- Action binding overlays the current menu without changing its presentation.
function Integration:IsActionBarEditing()
    return GamepadActionBarEditFrame and GamepadActionBarEditFrame:IsShown() or false
end

function Integration:SuspendForEditMode()
    UI:HideNativeChrome()
    UI.menuSessionActive = nil
    NS.Menus.sessionTabs = nil
    for panel in pairs(NS.Menus.opening or {}) do NS.Menus:RevealOpening(panel) end
    self.native = false
    self.nativeFocusedPanel = nil
    self:EndUIIsolation()
end

function Integration:InstallEditModeHooks()
    if self.editModeHooksInstalled then return end
    self.editModeHooksInstalled = true
    EventRegistry:RegisterCallback("EditMode.Enter", self.SuspendForEditMode, self)
    if self:IsEditModeActive() then self:SuspendForEditMode() end
end

-- The spellbook's Bind and Edit Action Bar commands share this native editor.
-- Observe visibility only; Blizzard owns its action changes and binding stack.
function Integration:InstallActionBarEditHooks()
    local editor = GamepadActionBarEditFrame
    if not editor or self.actionBarEditFrame == editor then return end
    self.actionBarEditFrame = editor
    local function shown()
        self:ReleaseUIIsolationFrame(editor)
        UI:UpdateControllerBindings()
    end
    editor:HookScript("OnShow", shown)
    editor:HookScript("OnHide", function()
        -- Binding can switch to editing by hiding and showing in the same call.
        -- Restore menu shortcuts only after native focus and visibility settle.
        C_Timer.After(0, function() UI:UpdateControllerBindings() end)
    end)
    if editor:IsShown() then shown() end
end

-- Enter native Lua handlers directly, preserving their own execution context on Forever.
-- This does not grant addon callbacks permission to call restricted APIs.
function Integration:CallNative(handler, ...)
    if InCombatLockdown() or type(handler) ~= "function" then return end
    return securecallfunction(handler, ...)
end

-- Native gamepad navigation owns the registered panels and all item/transaction actions.
function Integration:FocusNativePane(panel)
    if not panel or InCombatLockdown() then return end
    if not InputUtil or not InputUtil.IsGamepadUIEnabled() then return end
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if manager and manager.FocusFrame then self:CallNative(manager.FocusFrame, manager, panel) end
end

-- Follow native shoulder/focus navigation without replacing its handlers or bindings.
function Integration:InstallNativeGamepadHooks()
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if not manager or not manager.RefreshFocus or not manager.GetActiveFrame
        or self.nativeGamepadManager == manager then return end
    self.nativeGamepadManager = manager
    hooksecurefunc(manager, "RefreshFocus", function()
        if self.nativeFocusPending then return end
        self.nativeFocusPending = true
        C_Timer.After(0, function()
            self.nativeFocusPending = nil
            self:ObserveNativeGamepadFocus(manager)
        end)
    end)
end

-- Keep only the presented menu visible without changing native focus registration.
function Integration:SyncNativeMenuVisibility()
    local selected = UI:GetNativePanel()
    local bags = NS.NativeBags
    local candidates = {}
    for panel in pairs(NS.Menus.watched) do candidates[panel] = true end
    for _, panel in pairs({ CharacterFrame, PlayerSpellsFrame, WorldMapFrame,
        self:GetInteractionPanel() }) do candidates[panel] = true end
    for _, panel in ipairs(self:GetNativeBagFrames()) do
        if panel ~= ContainerFrameContainer then candidates[panel] = true end
    end
    for panel in pairs(candidates) do
        if panel:IsShown() and bags:CanChangeVisibility(panel) then
            local visible = panel == selected
                or (UI.nativeChromeMode == "inventory" and bags:IsActive()
                    and bags.saved[panel] ~= nil)
            self:ReleaseUIIsolationFrame(panel)
            if visible then
                -- The selected menu may still be fading in from zero opacity.
                bags:Reveal(panel)
            else
                UI:CancelFade(panel)
                bags:Conceal(panel)
            end
        end
    end
end

-- Native bindings own visibility; follow their final focus using presentation only.
function Integration:ObserveNativeGamepadFocus(manager)
    if self:IsEditModeActive() or self:IsActionBarEditing() or not UI.nativeChrome then return end
    local active = manager:GetActiveFrame()
    if not active or not active:IsShown() then return end
    local bags = NS.NativeBags
    if bags.interaction then
        local inventory = active == ContainerFrameCombinedBags
        if (inventory or active == bags.interaction) and bags.inventorySelected ~= inventory then
            bags:SelectPane(inventory, true)
        end
    else
        local previous = UI:GetNativePanel()
        local entry = NS.Menus:GetCurrentEntry()
        if active ~= previous or not UI.nativeChrome:IsShown() then
            -- Unsupported interactions reject inventory presentation. Do not reveal
            -- their bags or conceal the current menu unless that handoff succeeds.
            if active == ContainerFrameCombinedBags then
                if not self:PresentNativeInventory() then return end
            else
                self:ReleaseUIIsolationFrame(active)
                bags:Reveal(active)
            end
            NS.Menus:RetainCurrent(entry)
            if active == ContainerFrameCombinedBags then
                bags:Reveal(active)
            elseif active == CharacterFrame then UI:ShowNativeChrome(CharacterFrame.activeSubframe, "character")
            elseif active == PlayerSpellsFrame then UI:ShowNativeChrome(active:GetTab(), "talents")
            elseif active == WorldMapFrame then UI:ShowNativeChrome("map")
            elseif NS.Menus.watched[active] then NS.Menus:Open(active)
            else return end
            if previous and previous ~= active and previous:IsShown() then bags:Conceal(previous) end
        end
        self.nativeFocusedPanel = active
    end
    UI:LayoutNativePanel()
    bags:Layout()
    self:SyncNativeMenuVisibility()
    UI:UpdateControllerBindings()
end

-- Native bank interaction events share one lifecycle.
local function isBankInteraction(interactionType)
    local types = Enum.PlayerInteractionType
    return interactionType ~= nil and (interactionType == types.Banker
        or interactionType == types.CharacterBanker or interactionType == types.AccountBanker)
end

BINDING_HEADER_FULLSCREENMENUS = "Fullscreen Menus"
BINDING_NAME_FULLSCREENMENUS_TOGGLE = "Toggle Fullscreen Menus browser"

--@alpha@
-- Capture protected-action attribution and call sites without inspecting frame contents.
function Integration:TraceBlockedAction(event, blockedAddon, action)
    if blockedAddon ~= addonName or not Data.db then return end
    local entries = Data.db.blockedActions
    if type(entries) ~= "table" then entries = {}; Data.db.blockedActions = entries end
    entries[#entries + 1] = {
        event = event, action = action, elapsed = GetTime(),
        combat = InCombatLockdown(), mode = UI.nativeChromeMode,
        stack = debugstack and debugstack(2, 12, 12) or nil,
    }
    -- Retain the original failures when native popup callbacks cascade.
    if #entries > 32 then table.remove(entries, 32) end
end

-- Keep bounded development diagnostics in SavedVariables, without player or item data.
function Integration:TraceBank(event, argument)
    if not Data.db then return end
    local trace = Data.db.bankDiagnostics
    if type(trace) ~= "table" or trace.version ~= 1 then
        trace = { version = 1, entries = {} }
        Data.db.bankDiagnostics = trace
    end
    local function frameState(frame)
        if not frame then return "absent" end
        local ok, state = pcall(function()
            return frame:IsShown() and (frame:IsVisible() and "visible" or "hidden-parent") or "hidden"
        end)
        return ok and state or "unavailable"
    end
    local kinds = {}
    for kind in pairs(self.interactions) do kinds[#kinds + 1] = tostring(kind) end
    table.sort(kinds)
    local accessible
    if C_Bank.AreAnyBankTypesViewable then
        local ok, value = pcall(C_Bank.AreAnyBankTypesViewable)
        if ok then accessible = value end
    end
    local entries = trace.entries
    entries[#entries + 1] = {
        event = event, argument = argument, elapsed = GetTime(),
        bankOpen = Data.bankOpen == true, bankAccessible = accessible,
        bankFrame = frameState(BankFrame),
        chrome = frameState(UI.nativeChrome), native = self.native == true,
        mode = UI.nativeChromeMode,
        interactions = table.concat(kinds, ","), suppress = self.suppress == true,
        closingBank = self.closingBank == true,
        combat = InCombatLockdown(),
    }
    if #entries > 128 then table.remove(entries, 1) end
end
--@end-alpha@

-- Either native close event can end a bank session; repeated cleanup is harmless.
function Integration:BankClosed()
    --@alpha@
    self:TraceBank("BankClosed:before")
    --@end-alpha@
    -- Close hides the chrome before cleanup, so its visibility cannot gate routing reset.
    local nativeBank = self.native and (UI.nativeChromeMode == "bank"
        or UI.nativeChromeMode == "inventory")
    Data.bankOpen = false
    for kind in pairs(self.interactions) do
        if isBankInteraction(kind) then self.interactions[kind] = nil end
    end
    if nativeBank then
        self:CloseNative(true)
        self:ScheduleUIIsolationRestore()
    end
    UI:LayoutModeTabs()
    Data:ScheduleRefresh()
    UI:Refresh()
    --@alpha@
    self:TraceBank("BankClosed:after")
    --@end-alpha@
end

-- Close the native panel as well as the interaction, without waiting for an event.
function Integration:CloseBankInteraction()
    if InCombatLockdown() then return end
    --@alpha@
    self:TraceBank("CloseBankInteraction:before")
    --@end-alpha@
    if self.closingBank then return end
    if not Data.bankOpen and not (BankFrame and BankFrame:IsShown()) then return end
    self.closingBank = true

    self:ReleaseUIIsolationFrame(BankFrame)
    local suppressed = self.suppress
    self.suppress = true
    if BankFrame and BankFrame:IsShown() then
        -- BankFrame's native OnHide closes its bags and the server interaction.
        self:CallNative(HideUIPanel, BankFrame)
    else
        self:CallNative(C_Bank.CloseBankFrame)
    end
    self.suppress = suppressed
    self:BankClosed()
    self.closingBank = nil
    --@alpha@
    self:TraceBank("CloseBankInteraction:after")
    --@end-alpha@
end

-- Service definitions retain only the native differences required to end each session.
local services = {
    merchant = { event = "MERCHANT_SHOW", interaction = Enum.PlayerInteractionType.Merchant,
        panel = "MerchantFrame", close = CloseMerchant },
    trade = { event = "TRADE_SHOW", interaction = Enum.PlayerInteractionType.TradePartner,
        panel = "TradeFrame" },
    mail = { event = "MAIL_SHOW", interaction = Enum.PlayerInteractionType.MailInfo,
        panel = "MailFrame", close = CloseMail },
}

-- Either native event can dismiss a service; reentrant cleanup shares one guard.
function Integration:ServiceClosed(mode)
    if self.serviceCleanup then return end
    self.serviceCleanup = true
    local service = services[mode]

    self.interactions[service.event] = nil
    self.interactions[service.interaction] = nil
    local suppressed = self.suppress
    self.suppress = true
    -- Forever's merchant OnHide closes its bags in native execution context.
    -- MailFrame_Hide also owns bag closure after dismissing the mailbox.
    -- Repeating it from the close event can run gamepad focus teardown in addon context.
    if CloseAllBags and mode ~= "merchant" and mode ~= "mail" then
        self:CallNative(CloseAllBags)
    end
    self.suppress = suppressed
    if UI.nativeChromeMode == "inventory" then
        self.native = false
        UI:HideNativeChrome()
    end
    self:ScheduleUIIsolationRestore()
    self.serviceCleanup = nil
end

-- Native OnHide owns transaction cancellation and confirmation cleanup.
function Integration:CloseServiceInteraction(mode)
    if InCombatLockdown() then return end
    local service = services[mode]
    if not self.interactions[service.event] or self.closingService then return end
    self.closingService = true

    local panel = _G[service.panel]
    self:ReleaseUIIsolationFrame(panel)
    local suppressed = self.suppress
    self.suppress = true
    if panel and panel:IsShown() then self:CallNative(HideUIPanel, panel)
    elseif service.close then self:CallNative(service.close) end
    self.suppress = suppressed
    self:ServiceClosed(mode)
    self.closingService = nil
end

function Integration:QueueBankOpen()
    --@alpha@
    self:TraceBank("QueueBankOpen")
    --@end-alpha@
    -- Banking replaces the NPC dialogue; its manager hide event may never arrive.
    self.interactions[Enum.PlayerInteractionType.Gossip] = nil

    if self.bankOpenPending then return end
    self.bankOpenPending = true
    C_Timer.After(0, function()
        self.bankOpenPending = nil
        --@alpha@
        self:TraceBank("QueueBankOpen:callback")
        --@end-alpha@
        if not self.ready or not Data.bankOpen then return end
        self:ReleaseUIIsolationFrame(BankFrame)
        self:PresentNativeInventory()
    end)
end

-- Services retain their native panels beside native bags.
function Integration:GetInteractionPanel()
    if Data.bankOpen and BankFrame and BankFrame:IsShown() then return BankFrame end
    if self.interactions.MERCHANT_SHOW and MerchantFrame and MerchantFrame:IsShown() then return MerchantFrame end
    if self.interactions.TRADE_SHOW and TradeFrame and TradeFrame:IsShown() then return TradeFrame end
    if MailFrame and MailFrame:IsShown() then return MailFrame end
end

function Integration:QueueInteractionOpen()
    if self.interactions.MERCHANT_SHOW then
        self.interactions[Enum.PlayerInteractionType.Gossip] = nil
    end

    if self.interactionOpenPending then return end
    self.interactionOpenPending = true
    C_Timer.After(0, function()
        self.interactionOpenPending = nil
        local panel = self:GetInteractionPanel()
        if not self.ready or not panel then return end
        self:ReleaseUIIsolationFrame(panel)
        self:PresentNativeInventory()
    end)
end

-- Frames visible at isolation start may be shown again by their owning addon.
function Integration:WatchIsolatedFrame(frame)
    self.uiIsolationWatches = self.uiIsolationWatches or setmetatable({}, { __mode = "k" })
    if self.uiIsolationWatches[frame] then return end
    local hooked = pcall(frame.HookScript, frame, "OnShow", function(shownFrame)
        if not self.hiddenUIFrameSet or not self.hiddenUIFrameSet[shownFrame] then return end
        if shownFrame == Minimap then
            if not InCombatLockdown() or not shownFrame:IsProtected() then
                pcall(shownFrame.Hide, shownFrame)
            end
            return
        end
    end)
    if hooked then self.uiIsolationWatches[frame] = true end
end

-- A frame intentionally opened as the active native panel must leave the set
-- captured from the UI that Fullscreen Menus replaced.
function Integration:ReleaseUIIsolationFrame(frame)
    if not frame or not self.hiddenUIFrameSet or not self.hiddenUIFrameSet[frame] then return end
    if InCombatLockdown() and frame:IsProtected() then return end
    UI:CancelFade(frame)
    local alpha = self.hiddenUIAlphas and self.hiddenUIAlphas[frame]
    if alpha then pcall(frame.SetAlpha, frame, alpha); self.hiddenUIAlphas[frame] = nil end
    self.hiddenUIFrameSet[frame] = nil
    for index = #self.hiddenUIFrames, 1, -1 do
        if self.hiddenUIFrames[index] == frame then table.remove(self.hiddenUIFrames, index) end
    end
end

-- Forever's navigation frame owns Back bindings; its input buttons live under UIParent.
local function isNativeGamepadFrame(frame)
    local name = frame:GetName()
    return frame == SmartNavigation or frame == SoftCursor
        or frame == GamepadScrollBarHint or frame == GamepadItemPickupCursor
        or (name and name:match("^InputFunctionBindingButton_"))
end

-- World-space names and enemy nameplates are rendered outside the UIParent frame tree.
local worldNameCVars = {
    "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
    "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC",
    "UnitNameInteractiveNPC", "UnitNameNonCombatCreatureName",
    "UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
    -- Disable at the native source so newly appearing enemies stay hidden too.
    "nameplateShowEnemies",
}

function Integration:HideWorldNames()
    if InCombatLockdown() then return end
    local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
    local setCVar = C_CVar and C_CVar.SetCVar or SetCVar
    if not getCVar or not setCVar then return end
    self.worldNameSettings = self.worldNameSettings or {}
    for _, name in ipairs(worldNameCVars) do
        local readable, value = pcall(getCVar, name)
        if readable and value and value ~= "0" and not self.worldNameSettings[name] then
            local changed, success = pcall(setCVar, name, "0")
            if changed and success ~= false then self.worldNameSettings[name] = value end
        end
    end
end

function Integration:RestoreWorldNames()
    -- Keep saved values until PLAYER_REGEN_ENABLED can restore protected CVars.
    if InCombatLockdown() then return end
    local setCVar = C_CVar and C_CVar.SetCVar or SetCVar
    if not setCVar then return end
    for name, value in pairs(self.worldNameSettings or {}) do
        local restored, success = pcall(setCVar, name, value)
        if restored and success ~= false then self.worldNameSettings[name] = nil end
    end
end

-- UI isolation hides unrelated top-level UI while preserving native input infrastructure.
function Integration:BeginUIIsolation(...)
    if self:IsEditModeActive() or InCombatLockdown() or self.hiddenUIFrames then return end
    self:HideWorldNames()
    self.hiddenUIFrames = {}
    self.hiddenUIFrameSet = setmetatable({}, { __mode = "k" })
    self.hiddenUIAlphas = self.hiddenUIAlphas or setmetatable({}, { __mode = "k" })
    local preserved = {}
    if Data.bankOpen and BankFrame then preserved[BankFrame] = true end
    local interactionPanel = self:GetInteractionPanel()
    if interactionPanel then preserved[interactionPanel] = true end
    -- Item menus, split dialogs, and native confirmations must remain actionable.
    for _, name in ipairs({ "GameTooltip", "StackSplitFrame",
        "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "UIErrorsFrame",
        "GamepadActionBarEditFrame" }) do
        if _G[name] then preserved[_G[name]] = true end
    end
    if UI.nativeChrome then preserved[UI.nativeChrome] = true end
    if UI.nativeBackground then preserved[UI.nativeBackground] = true end
    for index = 1, select("#", ...) do
        local preservedFrame = select(index, ...)
        if preservedFrame then preserved[preservedFrame] = true end
    end
    local candidates = { UIParent:GetChildren() }
    -- Capture the minimap separately: its client-rendered markers require Hide,
    -- not just zero alpha on the minimap or its enclosing cluster.
    if Minimap then table.insert(candidates, 1, Minimap) end
    for _, candidate in ipairs(candidates) do
        local inspected, visible, combatProtected = pcall(function()
            if candidate:IsForbidden() or not candidate:IsVisible() or isNativeGamepadFrame(candidate) then
                return false, false
            end
            if InCombatLockdown() and candidate:IsProtected() then return true, true end
            return true, false
        end)
        if inspected and visible and not combatProtected and not preserved[candidate]
            and not self.hiddenUIFrameSet[candidate] then
            local readable, alpha = pcall(function() return candidate:GetAlpha() + 0 end)
            if readable then
                self.hiddenUIFrames[#self.hiddenUIFrames + 1] = candidate
                self.hiddenUIFrameSet[candidate] = true
                -- Keep the pre-isolation alpha when reversing a restoration fade.
                self.hiddenUIAlphas[candidate] = self.hiddenUIAlphas[candidate] or alpha
                if candidate == Minimap then self:WatchIsolatedFrame(candidate) end
                UI:FadeFrame(candidate, 0, function()
                    if not self.hiddenUIFrameSet or not self.hiddenUIFrameSet[candidate] then return end
                    if InCombatLockdown() and candidate:IsProtected() then return end
                    -- Native gamepad focus callbacks can invoke Blizzard-only actions.
                    if candidate == Minimap then pcall(candidate.Hide, candidate) end
                end)
            end
        end
    end
end

function Integration:EndUIIsolation()
    self:RestoreWorldNames()
    local hidden = self.hiddenUIFrames
    if not hidden then return end
    self.restoringUI = true
    -- Disable re-hide hooks before intentionally restoring the captured frames.
    self.hiddenUIFrameSet = nil
    local remaining = {}
    for _, hiddenFrame in ipairs(hidden) do
        UI:CancelFade(hiddenFrame)
        local alpha = self.hiddenUIAlphas[hiddenFrame]
        local inspected, hiddenNow, combatProtected = pcall(function()
            if hiddenFrame:IsForbidden() then return false, false end
            if InCombatLockdown() and hiddenFrame:IsProtected() then return true, true end
            return true, false
        end)
        if inspected and hiddenNow then
            if combatProtected then
                remaining[#remaining + 1] = hiddenFrame
            else
                if hiddenFrame == Minimap then
                    if not hiddenFrame:IsShown() then pcall(hiddenFrame.Show, hiddenFrame) end
                end
                local function restored()
                    if self.hiddenUIFrameSet and self.hiddenUIFrameSet[hiddenFrame] then return end
                    if alpha then pcall(hiddenFrame.SetAlpha, hiddenFrame, alpha) end
                    self.hiddenUIAlphas[hiddenFrame] = nil
                end
                if alpha and hiddenFrame:IsShown() then UI:FadeFrame(hiddenFrame, alpha, restored)
                else restored() end
            end
        end
    end
    self.hiddenUIFrames = #remaining > 0 and remaining or nil
    self.restoringUI = nil
end

function Integration:ScheduleUIIsolationRestore()
    if self.uiIsolationRestorePending then return end
    self.uiIsolationRestorePending = true
    C_Timer.After(0, function()
        self.uiIsolationRestorePending = false
        if UI.nativeChrome and not UI.nativeChrome:IsShown() then
            local manager = GamepadMode and GamepadMode.FrameControlsManager
            if manager and InputUtil and InputUtil.IsGamepadUIEnabled() then
                self:ObserveNativeGamepadFocus(manager)
            elseif self:AreNativeBagsShown() then
                self:PresentNativeInventory()
            end
        end
        local nativeShown = UI.nativeChrome and UI.nativeChrome:IsShown()
        if not nativeShown then
            UI.menuSessionActive = nil
            NS.Menus.sessionTabs = nil

            self:EndUIIsolation()
        end
    end)
end

-- Interaction identity labels the transaction pane beside Inventory.
function Integration:GetInteractionMode()
    if Data.bankOpen then return "bank" end
    if self.interactions.MERCHANT_SHOW then return "merchant" end
    if self.interactions.TRADE_SHOW then return "trade" end
    if self.interactions.MAIL_SHOW then return "mail" end
end

function Integration:HasInteraction()
    return Data.bankOpen == true or next(self.interactions) ~= nil
end

function Integration:ConstrainMode(mode)
    if self:HasInteraction() then return "inventory" end
    return mode
end

function Integration:IsNativeContext()
    if self:IsEditModeActive() or InCombatLockdown() or self.native then return true end
    for kind in pairs(self.interactions) do
        if kind ~= "MERCHANT_SHOW" and kind ~= "TRADE_SHOW"
            and kind ~= Enum.PlayerInteractionType.Merchant
            and kind ~= Enum.PlayerInteractionType.TradePartner then return true end
    end
    for _, name in ipairs({ "BankFrame", "MailFrame", "AuctionHouseFrame" }) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end

function Integration:Close(keepUIIsolated)
    --@alpha@
    self:TraceBank("Close", keepUIIsolated)
    --@end-alpha@
    UI:HideNativeChrome()
    if not keepUIIsolated then

        self:CloseBankInteraction()
        self:CloseServiceInteraction("merchant")
        self:CloseServiceInteraction("trade")
        self:CloseServiceInteraction("mail")
        self:EndUIIsolation()
    end
end

function Integration:GetNativeBagFrames()
    local frames, seen = {}, {}
    local function add(frame)
        if frame and frame.IsShown and frame.HookScript and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end
    add(ContainerFrameContainer)
    add(ContainerFrameCombinedBags)
    local managed = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    if type(managed) == "table" then
        for _, frame in ipairs(managed) do add(frame) end
    end
    for index = 1, (NUM_CONTAINER_FRAMES or 6) do add(_G["ContainerFrame" .. index]) end
    return frames
end

function Integration:AreNativeBagsShown()
    for _, frame in ipairs(self:GetNativeBagFrames()) do
        -- The layout container stays shown even when every actual bag is closed.
        if frame ~= ContainerFrameContainer then
            local inspected, shown = pcall(function() return frame:IsVisible() and true or false end)
            if inspected and shown then return true end
        end
    end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
        local inspected, open = pcall(function() return IsBagOpen(bag) and true or false end)
        if inspected and open then return true end
    end
    return false
end

function Integration:Open(tab)
    if self:IsEditModeActive() then return end
    if self:IsNativeContext() and not (Data.bankOpen and not InCombatLockdown() and not self.native) then return end
    tab = self:ConstrainMode(tab)

    if tab == "map" then return self:OpenMap() end
    if tab == "talents" then return self:OpenTalents() end
    if tab == "character" then return self:OpenNative("character") end
    return self:OpenNative(tab or "inventory")
end

function Integration:OpenTalents(tabID)
    if self:IsEditModeActive() then return end
    if self:HasInteraction() then return self:Open("inventory") end
    if InCombatLockdown() then return end

    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_PlayerSpells") end
    self:InstallPlayerSpellsHooks()
    if not UI:DiscoverTalentTabs() then
        UI:RequestTalentTabs(function() self:OpenTalents(tabID) end)
        return
    end
    if not tabID then
        local preferred = PlayerSpellsFrame and PlayerSpellsFrame.talentTabID
        for _, definition in ipairs(UI.talentTabs or {}) do
            if definition.id == preferred then tabID = preferred end
        end
        if not tabID and UI.talentTabs and UI.talentTabs[1] then tabID = UI.talentTabs[1].id end
    end
    local discovered = false
    for _, definition in ipairs(UI.talentTabs or {}) do
        if definition.id == tabID then discovered = true end
    end
    if not discovered and UI.talentTabs and UI.talentTabs[1] then
        tabID = UI.talentTabs[1].id
    end
    self:CloseNative(true)
    self:Close(true)
    self:BeginUIIsolation()
    self.native = true
    if TogglePlayerSpellsFrame then
        self:CallNative(TogglePlayerSpellsFrame, tabID)
        if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
            UI:ShowNativeChrome(tabID, "talents")
        else
            self.native = false
            self:EndUIIsolation()
        end
    else
        self.native = false
        self:EndUIIsolation()
    end
end

function Integration:Toggle()
    if not self.ready then return end
    if UI.nativeChrome:IsShown() then
        self:CloseNative()
    elseif self:IsNativeContext() then
        self:CallNative(ToggleAllBags)
    else
        self:Open()
    end
end

function Integration:OpenMap()
    if self:IsEditModeActive() then return end
    if InCombatLockdown() then return end
    if self:HasInteraction() then return self:Open("inventory") end

    self:Close(true)
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    self:InstallMapHooks()
    if WorldMapFrame then
        self:BeginUIIsolation()
        self:CallNative(ShowUIPanel, WorldMapFrame)
        UI:ShowNativeChrome("map")
    end
end

function Integration:OpenNative(tab, mode)
    if self:IsEditModeActive() then return end
    if InCombatLockdown() then return end
    tab = self:ConstrainMode(tab)

    if tab == "bank" then tab = "inventory" end
    if mode == "talents" or tab == "talents" then
        return self:OpenTalents(tab == "talents" and nil or tab)
    end
    if tab ~= "map" and tab ~= "inventory" then
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_UIPanels_Game")
        end
        UI:DiscoverCharacterTabs()
        if tab == "character" then
            tab = UI.characterTabs and UI.characterTabs[1] and UI.characterTabs[1].panel
        end
        local discovered = false
        for _, definition in ipairs(UI.characterTabs or {}) do
            if definition.panel == tab then discovered = true end
        end
        if not tab or not discovered then
            local requested = tab or "character"
            UI:RequestCharacterTabs(function() self:OpenNative(requested) end)
            return
        end
    end
    if tab == "inventory" and self:AreNativeBagsShown()
        and (not UI.nativeChrome:IsShown() or UI.nativeChromeMode == "inventory") then
        self:PresentNativeInventory()
        return
    end
    if self.native or (UI.nativeChrome and UI.nativeChrome:IsShown()) then
        self:CloseNative(true)
    else
        self:Close(true)
    end
    if tab == "map" then
        return self:OpenMap()
    end
    self.native = true
    local characterPanel = tab ~= "inventory" and tab
    if characterPanel then
        self:BeginUIIsolation()
        self:InstallCharacterFrameHooks()
        if ToggleCharacter then
            self:CallNative(ToggleCharacter, characterPanel, true)
            if CharacterFrame and CharacterFrame:IsShown() then
                UI:ShowNativeChrome(tab)
            else
                self.native = false
                self:EndUIIsolation()
            end
        else
            self.native = false
            self:EndUIIsolation()
        end
        return
    end
    -- Start a fresh isolation snapshot for native Inventory so bag frames that
    -- participated in the original shortcut cannot remain in its re-hide set.
    self:EndUIIsolation()
    Data:Refresh()
    self:CallNative(OpenAllBags)
    local preserved = self:GetNativeBagFrames()
    local interaction = self:GetInteractionPanel()
    if interaction then preserved[#preserved + 1] = interaction end
    self:BeginUIIsolation(unpack(preserved))
    UI:ShowNativeChrome("inventory")
end

-- Native panels can be shown while their load-on-demand addon is still loading.
-- Registering through this helper hooks future visibility changes and reconciles
-- a show that occurred before hook installation.

function Integration:InstallNativePanelHooks(panel, onShow, onHide)
    if not panel then return false end
    self.nativePanelHooks = self.nativePanelHooks or setmetatable({}, { __mode = "k" })
    local callbacks = self.nativePanelHooks[panel]
    if not callbacks then
        callbacks = {}
        self.nativePanelHooks[panel] = callbacks
        panel:HookScript("OnShow", function(shownPanel)
            if callbacks.onShow and not self:IsEditModeActive() then
                callbacks.onShow(shownPanel)
            end
        end)
        panel:HookScript("OnHide", function(hiddenPanel)
            if callbacks.onHide then callbacks.onHide(hiddenPanel) end
        end)
    end
    callbacks.onShow = onShow
    callbacks.onHide = onHide
    if panel:IsShown() and onShow and UI.nativeChrome
        and not self:IsEditModeActive() then onShow(panel) end
    return true
end

function Integration:InstallCharacterFrameHooks()
    self:InstallNativePanelHooks(CharacterFrame, function(panel)
        self:BeginUIIsolation(panel)
        self.native = true
        UI:ShowNativeChrome(panel.activeSubframe, "character")
    end, function()
        self.native = false
        UI:HideNativeChrome()
        self:ScheduleUIIsolationRestore()
    end)
end

function Integration:InstallPlayerSpellsHooks()
    if not PlayerSpellsFrame then return end
    self:InstallNativePanelHooks(PlayerSpellsFrame, function(panel)
        self:BeginUIIsolation(panel)
        self.native = true
        local tabID = panel.GetTab and panel:GetTab()
        UI:ShowNativeChrome(tabID, "talents")
    end, function()
        self.native = false
        UI:HideNativeChrome()
        self:ScheduleUIIsolationRestore()
    end)
    if self.playerSpellsTabHookInstalled then return end
    self.playerSpellsTabHookInstalled = true
    hooksecurefunc(PlayerSpellsFrame, "SetTab", function(_, tabID)
        if PlayerSpellsFrame:IsShown() then
            UI:ShowNativeChrome(tabID or PlayerSpellsFrame:GetTab(), "talents")
        end
    end)
end

function Integration:CloseNative(keepUIIsolated)
    if InCombatLockdown() then

        UI:HideNativeChrome()
        return
    end
    if not keepUIIsolated then
        self:CloseBankInteraction()
        self:CloseServiceInteraction("merchant")
        self:CloseServiceInteraction("trade")
        self:CloseServiceInteraction("mail")
    end
    local genericMenu = UI.genericMenu
    if genericMenu and not InCombatLockdown() then self:CallNative(HideUIPanel, genericMenu) end

    self.suppress = true
    if WorldMapFrame and WorldMapFrame:IsShown() then self:CallNative(HideUIPanel, WorldMapFrame) end
    if CharacterFrame and CharacterFrame:IsShown() then self:CallNative(HideUIPanel, CharacterFrame) end
    if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then self:CallNative(HideUIPanel, PlayerSpellsFrame) end
    if CloseAllBags then self:CallNative(CloseAllBags) end
    self.suppress = false
    self.native = false
    UI:HideNativeChrome()
    if not keepUIIsolated then self:EndUIIsolation() end
end

-- Adopt native visibility after its handlers finish; never replay the bag shortcut.
function Integration:PresentNativeInventory()
    if self:IsEditModeActive() then return end
    if not self.ready or self.suppress then return end
    local panel = self:GetInteractionPanel()
    -- A wheel selection opens the backpack before focusing Character. Its
    -- deferred bag callback must not replace the final native selection.
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if not panel and InputUtil and InputUtil.IsGamepadUIEnabled()
        and manager and manager:GetActiveFrame() == CharacterFrame
        and CharacterFrame and CharacterFrame:IsShown() and self:AreNativeBagsShown() then
        UI:ShowNativeChrome(CharacterFrame.activeSubframe, "character")
        self.nativeFocusedPanel = CharacterFrame
        return
    end
    -- Deferred bag updates must not replace the item window owning native focus.
    local active = manager and manager:GetActiveFrame()
    if not panel and InputUtil and InputUtil.IsGamepadUIEnabled()
        and active and active:IsShown() and NS.Menus.watched[active] then
        self:ReleaseUIIsolationFrame(active)
        NS.NativeBags:Reveal(active)
        NS.Menus:Open(active)
        return
    end
    if not panel and not self:AreNativeBagsShown() then
        if UI.nativeChromeMode == "inventory" then
            self.native = false
            UI:HideNativeChrome()
            self:ScheduleUIIsolationRestore()
        end
        return
    end
    -- Bags opened by unsupported services must keep their native context.
    if not panel and self:HasInteraction() then return end
    if not panel and ((MailFrame and MailFrame:IsShown())
        or (AuctionHouseFrame and AuctionHouseFrame:IsShown())) then return end
    local preserved = self:GetNativeBagFrames()
    if panel then preserved[#preserved + 1] = panel end
    for _, frame in ipairs(preserved) do self:ReleaseUIIsolationFrame(frame) end
    self:BeginUIIsolation(unpack(preserved))
    self.native = true
    UI:ShowNativeChrome("inventory")
    return true
end

function Integration:QueueNativeInventory(bagsClosing)
    if self:IsEditModeActive() then return end
    if not self.ready or self.suppress then return end
    if bagsClosing and self.interactions.MERCHANT_SHOW then self.merchantBagClosePending = true end
    if self.nativeInventoryPending then return end
    self.nativeInventoryPending = true
    C_Timer.After(0, function()
        self.nativeInventoryPending = nil
        local closeMerchant = self.merchantBagClosePending
        self.merchantBagClosePending = nil
        -- Native Back closes inventory before focus returns to the merchant.
        -- Wait for all bag hides, then dismiss the remaining interaction.
        if closeMerchant and self.interactions.MERCHANT_SHOW and not self:AreNativeBagsShown()
            and not self:IsEditModeActive() and not InCombatLockdown() then
            self:CloseServiceInteraction("merchant")
            return
        end
        self:PresentNativeInventory()
    end)
end

function Integration:InstallMapHooks()
    if not WorldMapFrame then return end
    self:InstallNativePanelHooks(WorldMapFrame, function(panel)
        self:BeginUIIsolation(panel)
        UI:ShowNativeChrome("map")
    end, function()
        UI:HideNativeChrome()
        self:ScheduleUIIsolationRestore()
    end)
end

function Integration:ConfigureBagOwner()
    local addon = EnhanceQoL
    if not addon or not addon.db or not Data.db then return end
    if addon.db.enableBagsModule == true then
        addon.db.enableBagsModule = false
        if addon.Bags and addon.Bags.functions and addon.Bags.functions.Disable then
            addon.Bags.functions.Disable()
        end
        -- EnhanceQoL reparents native frames during initialization; its documented reset is a reload.
        if addon.variables then addon.variables.requireReload = true end
        print("Fullscreen Menus: EnhanceQoL Bags disabled. Reload the UI once to restore native inventory windows.")
    end
end

function Integration:InstallHooks()
    if BankFrame then
        BankFrame:HookScript("OnHide", function()
            --@alpha@
            self:TraceBank("BankFrame:OnHide")
            --@end-alpha@
            if Data.bankOpen and not self.closingBank then self:BankClosed() end
        end)
        --@alpha@
        BankFrame:HookScript("OnShow", function() self:TraceBank("BankFrame:OnShow") end)
        --@end-alpha@
    end
    if MerchantFrame_Update then
        hooksecurefunc("MerchantFrame_Update", function()
            if self:GetInteractionMode() == "merchant" then Data:ScheduleRefresh() end
        end)
    end
    for _, name in ipairs({ "OpenBag", "OpenAllBags", "OpenAllBagsMatchingContext", "OpenBackpack" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(bag)
                if name == "OpenBag" and (type(bag) ~= "number" or bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5)) then return end
                self:QueueNativeInventory()
            end)
        end
    end
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(bag)
                if name == "ToggleBag" and (type(bag) ~= "number" or bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5)) then return end
                self:QueueNativeInventory()
            end)
        end
    end
    for _, name in ipairs({ "CloseAllBags", "CloseBackpack", "CloseBag" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(bag)
                if name == "CloseBag" and (type(bag) ~= "number" or bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5)) then return end
                self:QueueNativeInventory(true)
            end)
        end
    end
    if ToggleCharacter then
        hooksecurefunc("ToggleCharacter", function(tab)
            if self.native then
                if CharacterFrame and CharacterFrame:IsShown() then
                    UI:ShowNativeChrome(tab or CharacterFrame.activeSubframe)
                end
                return
            end
            if self:IsNativeContext() then return end

            UI:DiscoverCharacterTabs()
            if CharacterFrame and CharacterFrame:IsShown() then
                self:ReleaseUIIsolationFrame(CharacterFrame)
                self:BeginUIIsolation(CharacterFrame)
                self:InstallCharacterFrameHooks()
                self.native = true
                UI:ShowNativeChrome(tab or CharacterFrame.activeSubframe, "character")
            end
        end)
    end
    self:InstallCharacterFrameHooks()
    self:InstallPlayerSpellsHooks()
    self:InstallMapHooks()
    for _, frame in ipairs(self:GetNativeBagFrames()) do
        self:InstallNativePanelHooks(frame, function(panel)
            if self.native then self:ReleaseUIIsolationFrame(panel) end
            self:QueueNativeInventory()
        end,
            function() self:QueueNativeInventory(true) end)
    end
end

function FullscreenMenus_Toggle()
    Integration:Toggle()
end

SLASH_FULLSCREENMENUS1 = "/fullscreenmenus"
SlashCmdList.FULLSCREENMENUS = function(message)
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command == "native" then
        Integration:OpenNative("inventory")
    elseif command == "" then
        Integration:Toggle()
    else
        print("Fullscreen Menus commands:")
        print("  /fullscreenmenus          Toggle Fullscreen Menus browser")
        print("  /fullscreenmenus native   Open native inventory")
    end
end

local frame = CreateFrame("Frame")
local loadOnDemandPanelInstallers = {
    Blizzard_GamepadActionBars = function() Integration:InstallActionBarEditHooks() end,
    Blizzard_WorldMap = function() Integration:InstallMapHooks() end,
    Blizzard_PlayerSpells = function() Integration:InstallPlayerSpellsHooks() end,
}
local interactionEvents = {
    MERCHANT_SHOW = true, MERCHANT_CLOSED = "MERCHANT_SHOW",
    MAIL_SHOW = true, MAIL_CLOSED = "MAIL_SHOW",
    TRADE_SHOW = true, TRADE_CLOSED = "TRADE_SHOW",
}
for _, event in ipairs({
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "BAG_UPDATE",
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GOSSIP_CLOSED",
    "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE",
}) do frame:RegisterEvent(event) end
for event in pairs(interactionEvents) do frame:RegisterEvent(event) end
--@alpha@
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
--@end-alpha@

frame:SetScript("OnEvent", function(_, event, argument, secondArgument)
    --@alpha@
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        Integration:TraceBlockedAction(event, argument, secondArgument)
        return
    end
    if event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED"
        or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" or event == "GOSSIP_CLOSED"
        or event == "PLAYER_ENTERING_WORLD" or interactionEvents[event] then
        Integration:TraceBank(event, argument)
        C_Timer.After(0, function() Integration:TraceBank(event .. ":settled", argument) end)
    end
    --@end-alpha@
    if event == "ADDON_LOADED" then
        if argument == addonName then Data:Initialize() end
        local installer = loadOnDemandPanelInstallers[argument]
        if installer then installer() end
        Integration:InstallNativeGamepadHooks()
        Integration:ConfigureBagOwner()
    elseif event == "PLAYER_LOGOUT" then
        Integration:RestoreWorldNames()
    elseif event == "PLAYER_LOGIN" then
        UI:Initialize()
        Integration:InstallEditModeHooks()
        Integration:InstallActionBarEditHooks()
        Integration:ConfigureBagOwner()
        Integration:InstallHooks()
        Integration:InstallNativeGamepadHooks()
        Integration.ready = true
        NS.Menus:Initialize()
        Data:ScheduleRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Integration.interactions = {}
        Data.bankOpen = false
        UI:LayoutModeTabs()

        Integration.native = false
        Data:ScheduleRefresh()
    elseif event == "BANKFRAME_OPENED" then
        Data.bankOpen = true
        Integration:QueueBankOpen()
        Data:ScheduleRefresh()
    elseif event == "BANKFRAME_CLOSED" then
        Integration:BankClosed()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Keep menu fitting and the backdrop, but release unrelated UI isolation.
        Integration:EndUIIsolation()
    elseif event == "PLAYER_REGEN_ENABLED" then
        for panel in pairs(NS.Menus.opening or {}) do NS.Menus:RevealOpening(panel) end
        UI:UpdateControllerBindings()
        UI:RestoreMenuFades()
        if UI.pendingNativeRestore then UI:HideNativeChrome() end
        if NS.NativeBags.closePending then NS.NativeBags:Close()
        elseif NS.NativeBags.restorePending then NS.NativeBags:Restore() end
        Integration:EndUIIsolation()
        Integration:InstallNativeGamepadHooks()
        if UI.nativeChrome and UI.nativeChrome:IsShown() then
            local preserved = Integration:GetNativeBagFrames()
            local panel = UI:GetNativePanel()
            if panel then preserved[#preserved + 1] = panel end
            Integration:BeginUIIsolation(unpack(preserved))
            UI:ApplyNativeVariant()
        else
            NS.Menus:SchedulePresentationCheck()
        end
        Data:ScheduleRefresh()
    elseif event == "GOSSIP_CLOSED" then
        Integration.interactions[Enum.PlayerInteractionType.Gossip] = nil
        UI:Refresh()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if isBankInteraction(argument) then
            Data.bankOpen = true
            Integration:QueueBankOpen()
            return
        end
        if argument == Enum.PlayerInteractionType.MailInfo then
            Integration.interactions.MAIL_SHOW = true
            Integration:QueueInteractionOpen()
            return
        end
        if argument == Enum.PlayerInteractionType.Merchant or argument == Enum.PlayerInteractionType.TradePartner then
            Integration.interactions[argument == Enum.PlayerInteractionType.Merchant and "MERCHANT_SHOW" or "TRADE_SHOW"] = true
            Integration:QueueInteractionOpen()
            return
        end
        Integration.interactions[argument] = true

        if not (UI.genericMenu and UI.genericMenu:IsVisible()) then Integration:Close() end
        NS.Menus:Discover()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if isBankInteraction(argument) then
            Integration:BankClosed()
            return
        end
        if argument == Enum.PlayerInteractionType.Merchant then
            Integration:ServiceClosed("merchant")
            return
        end
        if argument == Enum.PlayerInteractionType.TradePartner then
            Integration:ServiceClosed("trade")
            return
        end
        if argument == Enum.PlayerInteractionType.MailInfo then
            Integration:ServiceClosed("mail")
            return
        end
        Integration.interactions[argument] = nil
        UI:LayoutModeTabs()
    elseif interactionEvents[event] then
        local kind = interactionEvents[event]
        if kind == true then
            Integration.interactions[event] = true
            if event == "MERCHANT_SHOW" or event == "TRADE_SHOW" or event == "MAIL_SHOW" then
                Integration:QueueInteractionOpen()
                return
            end

            if not (UI.genericMenu and UI.genericMenu:IsVisible()) then Integration:Close() end
            NS.Menus:Discover()
        else
            if event == "MERCHANT_CLOSED" then
                Integration:ServiceClosed("merchant")
                return
            end
            if event == "TRADE_CLOSED" then
                Integration:ServiceClosed("trade")
                return
            end
            if event == "MAIL_CLOSED" then
                Integration:ServiceClosed("mail")
                return
            end
            Integration.interactions[kind] = nil

            UI:Refresh()
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        UI:Resize()
    else
        Data:ScheduleRefresh()
    end
end)
