local _, NS = ...

-- Discover native menus and selectors from Blizzard's shared runtime contracts.
local Menus = { watched = setmetatable({}, { __mode = "k" }) }
NS.Menus = Menus

-- Gossip and quest details are two native surfaces for one NPC conversation.
local function isQuestConversation(panel)
    return panel and (panel == GossipFrame or panel == QuestFrame)
end

-- Loot pickup and its child panels retain their native popup presentation.
function Menus:IsExcluded(panel)
    while self:IsAccessible(panel) do
        if panel == LootFrame or panel == EditModeManagerFrame or panel == GamepadActionBarEditFrame
            or panel == StackSplitFrame or panel == StaticPopup1 or panel == StaticPopup2
            or panel == StaticPopup3 or panel == StaticPopup4 then return true end
        panel = panel:GetParent()
    end
    return false
end

-- Specialized presentations take precedence over the automatic native fallback.
function Menus:IsSpecialized(panel)
    local bags = NS.Integration:GetNativeBagFrames()
    local current = panel
    while current do
        if current == CharacterFrame or current == PlayerSpellsFrame or current == WorldMapFrame
            or current == BankFrame or current == MerchantFrame or current == TradeFrame
            or current == MailFrame then return true end
        for _, bag in ipairs(bags) do
            if current == bag then return true end
        end
        if not self:IsAccessible(current) then return false end
        current = current:GetParent()
    end
    return false
end

function Menus:IsAccessible(panel)
    return (type(panel) == "table" or type(panel) == "userdata") and panel.IsForbidden and not panel:IsForbidden()
        and panel.HookScript and panel.GetWidth and panel.GetHeight
        and panel ~= NS.UI.nativeChrome
        and panel ~= NS.UI.nativeBackground
end

-- Registered child panels belong to their enclosing menu, even when loaded later.
function Menus:GetMenuRoot(panel)
    if not self:IsAccessible(panel) then return panel end
    local root, parent = panel, panel:GetParent()
    while parent and parent ~= UIParent do
        if not self:IsAccessible(parent) then break end
        local name = parent:GetName()
        if self.watched[parent] or parent == NS.UI.genericMenu
            or (name and UIPanelWindows and UIPanelWindows[name])
            or parent:GetAttribute("UIPanelLayout-enabled") then
            root = parent
        end
        parent = parent:GetParent()
    end
    return root
end

-- Menu identities use Blizzard's launcher labels; panel headings can name a selected subtab.
function Menus:GetTitle(panel)
    local name = panel:GetName()
    local labels = {
        GossipFrame = QUESTS_LABEL or "Quests",
        QuestFrame = QUESTS_LABEL or "Quests",
        CollectionsJournal = COLLECTIONS,
        PVEFrame = DUNGEONS_BUTTON,
        EncounterJournal = ENCOUNTER_JOURNAL,
    }
    if name and labels[name] then return labels[name] end
    -- Unknown menus keep a stable root-frame label instead of adopting a changing content title.
    return name and name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2") or (MENU or "Menu")
end

-- Saved menu entries contain only stable navigation metadata, never frame objects.
function Menus:GetCurrentEntry()
    local ui = NS.UI
    local mode = ui.nativeChromeMode
    if mode == "generic" then
        local panel = ui.genericMenu
        local name = panel and panel:GetName()
        if not name then return end
        local addon
        if panel.GetSourceLocation then
            local ok, source = pcall(panel.GetSourceLocation, panel)
            if ok and type(source) == "string" then
                addon = source:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)")
            end
        end
        return { id = "menu:" .. name, frame = name, title = self:GetTitle(panel), addon = addon }
    end
    local titles = { inventory = INVENTORY_TOOLTIP or "Inventory", character = CHARACTER or "Character",
        talents = TALENTS or "Talents", map = WORLD_MAP or "Map", bank = BANK or "Bank" }
    if titles[mode] then return { id = mode, title = titles[mode] } end
end

function Menus:FindSaved(id)
    for index, entry in ipairs(NS.Data.accountDB and NS.Data.accountDB.menuTabs or {}) do
        if entry.id == id then return entry, index end
    end
end

-- Unpinned menus remain reachable during top-row navigation without entering SavedVariables.
function Menus:FindEntry(id)
    local saved = self:FindSaved(id)
    if saved then return saved end
    for _, entry in ipairs(self.sessionTabs or {}) do
        if entry.id == id then return entry end
    end
end

function Menus:RetainCurrent(entry)
    if not entry or self:FindEntry(entry.id) then return end
    self.sessionTabs = self.sessionTabs or {}
    self.sessionTabs[#self.sessionTabs + 1] = entry
end

function Menus:Open(panel)
    panel = self:GetMenuRoot(panel)
    local integration, ui = NS.Integration, NS.UI
    if integration:IsEditModeActive() or not ui.nativeChrome or (InCombatLockdown() and not ui:CanPresentInCombat(panel)) or integration.suppress or integration.restoringUI
        or not self:IsAccessible(panel) or self:IsExcluded(panel) or self:IsSpecialized(panel)
        or not panel:IsVisible() then return end
    -- A fading-out snapshot can remain visible until its short transition finishes.
    if integration.hiddenUIFrameSet and integration.hiddenUIFrameSet[panel] then return end
    if ui.genericMenu == panel and ui.nativeChrome:IsShown() then
        ui:ScheduleNativePanelLayout()
        return
    end
    -- Restore geometry before changing the panel owning the shared presentation.
    local conversationSwitch = isQuestConversation(panel) and isQuestConversation(ui.genericMenu)
    if conversationSwitch then
        -- Restore the old frame while retaining the shared conversation placement.
        ui:RestoreMenuFades()
        ui:RestoreNativePanelLayout()
    else
        if ui.nativeChrome and ui.nativeChrome:IsShown() then
            ui:HideNativeChrome()
        end
        -- Closing an owner can dismiss a dependent panel during native hide callbacks.
        if not panel:IsVisible() then return end
        ui:HideNativeChrome()
    end
    integration:ReleaseUIIsolationFrame(panel)
    integration:BeginUIIsolation(panel)
    ui.genericMenu = panel
    integration.native = true
    ui:ShowNativeChrome(nil, "generic")
end

-- Conceal the native opening position until the manager finishes its first layout.
function Menus:QueueOpen(panel)
    panel = self:GetMenuRoot(panel)
    local integration, ui = NS.Integration, NS.UI
    if integration:IsEditModeActive() or not ui.nativeChrome or (InCombatLockdown() and not ui:CanPresentInCombat(panel)) or integration.suppress or integration.restoringUI
        or not self:IsAccessible(panel) or self:IsExcluded(panel) or self:IsSpecialized(panel) or not panel:IsVisible()
        or integration.hiddenUIFrameSet and integration.hiddenUIFrameSet[panel] then return end
    if InCombatLockdown() then self:Open(panel); return end
    if ui.genericMenu == panel and ui.nativeChrome and ui.nativeChrome:IsShown() then
        ui:LayoutNativePanel()
        return
    end
    if isQuestConversation(panel) and isQuestConversation(ui.genericMenu) then
        -- Fit the replacement in the native show callback, without a transparent frame.
        self:Open(panel)
        return
    end
    self.opening = self.opening or setmetatable({}, { __mode = "k" })
    if self.opening[panel] then return end
    local opening = { alpha = panel:GetAlpha() }
    self.opening[panel] = opening
    panel:SetAlpha(0)
    C_Timer.After(0, function()
        if self.opening[panel] ~= opening then return end
        self:Open(panel)
        self:RevealOpening(panel)
    end)
end

function Menus:RevealOpening(panel)
    local opening = self.opening and self.opening[panel]
    if not opening then return end
    if InCombatLockdown() and panel:IsProtected() then return end
    self.opening[panel] = nil
    if not NS.UI.menuFadeAlphas or not NS.UI.menuFadeAlphas[panel] then
        panel:SetAlpha(opening.alpha)
    end
end

-- Native interaction events can clear presentation after a panel's show hook.
function Menus:SchedulePresentationCheck()
    if self.presentationCheckPending then return end
    self.presentationCheckPending = true
    C_Timer.After(0, function()
        self.presentationCheckPending = nil
        local ui, integration = NS.UI, NS.Integration
        if integration:IsEditModeActive() or integration.suppress or integration.restoringUI
            or not ui.nativeChrome or ui.nativeChrome:IsShown() then return end
        for panel in pairs(self.watched) do
            if panel:IsVisible() then
                self:Open(panel)
                if ui.nativeChrome:IsShown() then return end
            end
        end
    end)
end

function Menus:Watch(panel)
    panel = self:GetMenuRoot(panel)
    if not self:IsAccessible(panel) or self:IsExcluded(panel) or self:IsSpecialized(panel) or self.watched[panel] then return end
    self.watched[panel] = true
    panel:HookScript("OnShow", function()
        self:QueueOpen(panel)
        self:SchedulePresentationCheck()
    end)
    panel:HookScript("OnHide", function()
        self:RevealOpening(panel)
        if NS.UI.genericMenu ~= panel then return end
        if isQuestConversation(panel) then
            -- Native conversation changes hide gossip before showing quest details.
            -- Let that handoff settle without closing and reopening the backdrop.
            C_Timer.After(0, function()
                if NS.UI.genericMenu ~= panel or panel:IsShown() then return end
                local nextPanel = panel == GossipFrame and QuestFrame or GossipFrame
                if self:IsAccessible(nextPanel) and nextPanel:IsVisible() then
                    self:Open(nextPanel)
                    if NS.UI.genericMenu ~= panel then return end
                end
                NS.UI:HideNativeChrome()
                NS.Integration.native = false
                NS.Integration:ScheduleUIIsolationRestore()
            end)
            return
        end
        NS.UI:HideNativeChrome()
        NS.Integration.native = false
        NS.Integration:ScheduleUIIsolationRestore()
    end)
    if panel:IsShown() then self:QueueOpen(panel) end
end

function Menus:Discover()
    for name in pairs(UIPanelWindows or {}) do self:Watch(_G[name]) end
    for _, name in pairs(UISpecialFrames or {}) do self:Watch(_G[name]) end
    -- Layout attributes also register unnamed and dynamically created panels.
    -- Close buttons alone also occur on tutorials and transient popups, not just menus.
    for _, panel in ipairs({ UIParent:GetChildren() }) do
        if self:IsAccessible(panel) and panel:GetAttribute("UIPanelLayout-enabled") then
            self:Watch(panel)
        end
    end
    self:SchedulePresentationCheck()
end

function Menus:Initialize()
    if self.initialized then return end
    self.initialized = true
    hooksecurefunc("ShowUIPanel", function(panel)
        self:Watch(panel)
        self:QueueOpen(panel)
        self:SchedulePresentationCheck()
    end)
    hooksecurefunc("UpdateUIPanelPositions", function() NS.UI:LayoutNativePanel() end)
    self:Discover()
    -- Registrations can be added after ADDON_LOADED, including by other addons.
    self.discoveryTicker = C_Timer.NewTicker(NS.Layout.discoveryInterval, function() self:Discover() end)
end

-- Modern TabSystem and legacy PanelTemplates both expose ordered button arrays.
function Menus:DiscoverTabs(panel)
    local definitions, seen = {}, {}
    if not self:IsAccessible(panel) then return definitions end
    local function collect(owner)
        local system = owner.TabSystem or owner.tabSystem
        local buttons = system and system.tabs or owner.Tabs or owner.tabs or owner.TabButtons
        if type(buttons) ~= "table" then
            buttons = {}
            local name = owner:GetName()
            for index = 1, tonumber(owner.numTabs) or 0 do
                buttons[#buttons + 1] = owner["Tab" .. index] or (name and _G[name .. "Tab" .. index])
            end
        end
        for _, button in ipairs(buttons) do
            if self:IsAccessible(button) and not seen[button] and button:IsShown() then
                local text = button.GetText and button:GetText()
                    or button.Text and button.Text:GetText() or button.tooltipText
                if text and text ~= "" and (button.Click or button:GetScript("OnMouseUp")) then
                    seen[button] = true
                    definitions[#definitions + 1] = { button = button }
                end
            end
        end
    end
    collect(panel)
    if panel.ModeTabs then collect(panel.ModeTabs) end
    -- Forever's bank pages are pooled side tabs, ordered by bank type and page.
    if panel.bankPageTabPool then
        local buttons = {}
        for button in panel.bankPageTabPool:EnumerateActive() do
            buttons[#buttons + 1] = button
        end
        table.sort(buttons, function(a, b)
            if a.bankType ~= b.bankType then return a.bankType < b.bankType end
            return a.pageNumber < b.pageNumber
        end)
        collect({ Tabs = buttons })
    end
    -- Content children own nested selectors; leave those controls in their native layout.
    return definitions
end

-- Forever trigger targets use native bindings, never addon callbacks opening UI.
function Menus:GetForeverTriggerBinding(direction)
    if NS.Integration:HasInteraction() then return end
    local bindings = {
        inventory = { "OPENALLBAGS", "ContainerFrameCombinedBags" },
        character = { "TOGGLECHARACTER0", "CharacterFrame" },
        talents = { "TOGGLESPELLBOOK", "PlayerSpellsFrame" },
        map = { "TOGGLEWORLDMAP", "WorldMapFrame" },
        ["menu:CollectionsJournal"] = { "TOGGLECOLLECTIONS", "CollectionsJournal" },
        ["menu:FriendsFrame"] = { "TOGGLESOCIAL", "FriendsFrame" },
        ["menu:GuildFrame"] = { "TOGGLEGUILDTAB", "GuildFrame" },
    }
    local modes = NS.UI:GetAvailableModes()
    local current = self:GetCurrentEntry()
    local index = 0
    for i, id in ipairs(modes) do if current and current.id == id then index = i; break end end
    for offset = 1, #modes - 1 do
        local id = modes[(index - 1 + direction * offset) % #modes + 1]
        local binding = bindings[id]
        if binding then
            local panel = _G[binding[2]]
            if panel and panel:IsShown() then
                -- Native focus paging runs through Blizzard's existing input buttons.
                local manager = GamepadMode and GamepadMode.FrameControlsManager
                local active = manager and manager:GetActiveFrame()
                local activeIndex, targetIndex
                for i, shown in ipairs(manager and manager.shownFrames or {}) do
                    if shown == active then activeIndex = i end
                    if shown == panel then targetIndex = i end
                end
                if activeIndex and targetIndex and math.abs(activeIndex - targetIndex) == 1 then
                    local key = targetIndex < activeIndex and "PADLTRIGGER" or "PADRTRIGGER"
                    return "CLICK InputFunctionBindingButton_" .. key .. ":LeftButton"
                end
            else
                return binding[1]
            end
        end
    end
end
