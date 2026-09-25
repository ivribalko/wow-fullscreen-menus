-- Regression coverage for combat fitting, frame protection, and deferred CVar restoration.
local function read(path)
    local file = assert(io.open(path))
    local source = file:read('*a')
    file:close()
    return source
end
local integrationSource, uiSource, bagsSource = read('Integration.lua'), read('UI.lua'), read('NativeBags.lua')
local combat, writes = true, 0
local values = { nameplateShowEnemies = '1', UnitNameNPC = '1' }
local Integration, UI, Bags = {}, { nativeChrome = {} }, { saved = {}, concealed = {} }
local NS = { Integration = Integration, UI = UI, NativeBags = Bags }
local environment = setmetatable({
    Integration = Integration, UI = UI, Bags = Bags, NS = NS, Data = {},
    isStorage = function(mode) return mode == 'inventory' or mode == 'bank' end,
    isNativeGamepadFrame = function() return false end,
    InCombatLockdown = function() return combat end,
    C_CVar = {
        GetCVar = function(name) return values[name] end,
        SetCVar = function(name, value)
            assert(not combat, 'CVar write during combat')
            writes = writes + 1
            values[name] = value
        end,
    },
}, { __index = _G })
local function methods(source, first, following)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(following, start + #first, true))
    assert(load(source:sub(start, finish - 1), nil, 't', environment))()
end
local function panel(protected)
    local frame = { protected = protected, hooks = {}, children = {} }
    function frame:IsForbidden() return false end
    function frame:IsProtected() return self.protected end
    function frame:IsShown() return true end
    frame.IsVisible = frame.IsShown
    function frame:GetAlpha() return 1 end
    function frame:GetChildren() return table.unpack(self.children) end
    function frame:HookScript(event, callback) self.hooks[event] = callback end
    return frame
end
local safe, protected = panel(false), panel(true)
local bagFrames = { safe }
Integration.IsEditModeActive = function() return false end
Integration.GetInteractionPanel = function() return nil end
Integration.GetNativeBagFrames = function() return bagFrames end
Integration.SyncNativeMenuVisibility = function() end
methods(bagsSource, 'function Bags:CanChangeVisibility(', '-- Conceal the inactive surface')
methods(bagsSource, 'function Bags:CanLayoutInCombat()', 'function Bags:Restore()')
methods(uiSource, 'function UI:CanPresentInCombat(', 'function UI:LayoutNativePanel()')
methods(uiSource, 'function UI:GetNativePanel(', 'function UI:UpdateNativePanelArea()')
methods(integrationSource, 'local worldNameCVars =', 'function Integration:EndUIIsolation()')
methods(integrationSource, 'function Integration:InstallNativePanelHooks(', 'function Integration:InstallCharacterFrameHooks()')

Integration:BeginUIIsolation()
Integration:HideWorldNames()
assert(writes == 0 and Integration.hiddenUIFrames == nil)
combat = false
Integration:HideWorldNames()
assert(writes == 2 and values.nameplateShowEnemies == '0')
combat = true
Integration:RestoreWorldNames()
assert(writes == 2 and Integration.worldNameSettings.nameplateShowEnemies == '1')
combat = false
Integration:RestoreWorldNames()
assert(writes == 4 and values.nameplateShowEnemies == '1')
assert(next(Integration.worldNameSettings) == nil)

combat = true
local shown, hidden = 0, 0
Integration:InstallNativePanelHooks(protected, function() shown = shown + 1 end, function() hidden = hidden + 1 end)
protected.hooks.OnShow(protected)
assert(shown == 2, 'protected menu was excluded from combat presentation')
protected.hooks.OnHide(protected)
assert(hidden == 1, 'hide cleanup skipped during combat')
Integration:InstallNativePanelHooks(safe, function() shown = shown + 1 end)
assert(shown == 3, 'already visible unprotected panel was not adopted')
safe.hooks.OnShow(safe)
assert(shown == 4)

-- Every menu family can take the combat path without native actions or binding writes.
local calls = {}
for _, name in ipairs({ 'RestoreMenuFades', 'ResizeNativeChrome', 'LayoutNativePanel',
    'LayoutNativeBackground', 'SetNativeBlackoutHidden', 'SetNativeBackgroundShown',
    'InitializeNativeChrome', 'ClearItemTooltip', 'LayoutModeTabs', 'RequestCharacterTabs',
    'RequestTalentTabs', 'RequestMapTabs', 'ScheduleNativePanelLayout', 'FadeNativeMenuIn' }) do
    UI[name] = function() calls[name] = (calls[name] or 0) + 1 end
end
Bags.Layout = function() end
UI.nativeChrome.Show = function() calls.Show = (calls.Show or 0) + 1 end
UI.nativeChrome.IsShown = function() return true end
environment.WorldMapFrame = safe
environment.CharacterFrame = safe
environment.PlayerSpellsFrame = safe
environment.ContainerFrameCombinedBags = safe
UI.HideNativeChrome = function(self) self.genericMenu = nil end
methods(uiSource, 'function UI:UpdateControllerBindings()', 'function UI:InitializeNativeChrome()')
methods(uiSource, 'function UI:ApplyNativeVariant()', 'function UI:GetNativePanel(')
methods(uiSource, 'function UI:ShowNativeChrome(', 'function UI:HideNativeChrome()')
for _, mode in ipairs({ 'map', 'character', 'talents', 'generic', 'inventory', 'bank' }) do
    if mode == 'generic' then UI.genericMenu = safe end
    UI:ShowNativeChrome(mode, mode)
    assert(UI.nativeChromeMode == mode)
end
assert(calls.Show == 6 and calls.LayoutNativePanel == 6)
UI.nativePanelLayout = { panel = protected }
UI:ShowNativeChrome('map')
assert(calls.Show == 7 and UI.nativePanelLayout.panel == protected, 'previous protected geometry was discarded')
UI.nativePanelLayout = nil
safe.protected = true
for _, mode in ipairs({ 'map', 'character', 'talents', 'generic', 'inventory', 'bank' }) do
    if mode == 'generic' then UI.genericMenu = safe end
    UI.pendingNativeRestore = true
    UI:ShowNativeChrome(mode, mode)
    assert(UI.nativeChromeMode == mode and not UI.pendingNativeRestore)
end
assert(calls.Show == 13 and calls.SetNativeBackgroundShown == 13, 'protected menu lost its backdrop')
safe.protected = false

-- A protected child prevents pane opacity/mouse changes; a protected bag prevents grid fitting.
safe.children = { protected }
assert(not Bags:CanChangeVisibility(safe))
assert(not Bags:CanSwitchPanesInCombat())
safe.children = {}
assert(Bags:CanChangeVisibility(safe) and Bags:CanSwitchPanesInCombat())
assert(Bags:CanLayoutInCombat())
bagFrames = { protected }
assert(not Bags:CanLayoutInCombat())
bagFrames = { safe }
Bags.saved[protected] = {}
assert(not Bags:CanLayoutInCombat())
Bags.saved = {}

-- Combat skips unrelated UI isolation entirely, while fitting and the backdrop remain active.
environment.UIParent = { GetChildren = function() return safe, protected end }
UI.FadeFrame = function(_, frame) assert(frame == safe); calls.isolated = true end
Integration:BeginUIIsolation(panel(false))
assert(not calls.isolated and Integration.hiddenUIFrames == nil and writes == 4)

-- Existing fitted geometry is reapplied only to unprotected panels.
methods(uiSource, 'local function applyPanelPlacement(', 'function UI:ScheduleNativePanelLayout()')
UI.UpdateNativePanelArea = function() end
UI.nativePanelArea = {}
UI.nativeChromeMode = 'map'
local scale, anchor = 1, nil
safe.GetWidth = function() return 100 end
safe.GetHeight = function() return 100 end
safe.GetScale = function() return scale end
safe.SetScale = function(self, value) assert(not self.protected); scale = value end
safe.GetNumPoints = function() return 0 end
safe.ClearAllPoints = function(self) assert(not self.protected) end
safe.SetPoint = function(self, point) assert(not self.protected); anchor = point end
UI.nativePanelLayout = { panel = safe, menuType = 'map', applied = true,
    placement = { scale = 1.5, point = 'CENTER', x = 0, y = 0 } }
UI.nativeChromeTab = 'map'
UI:LayoutNativePanel()
assert(scale == 1.5 and anchor == 'CENTER')
safe.protected = true
scale, anchor = 1, nil
UI:LayoutNativePanel()
assert(scale == 1 and anchor == nil)
safe.protected = false

-- Direct restoration and anchor resizing also skip protected geometry.
methods(uiSource, 'function UI:RestoreNativePanelLayout()', 'function UI:GetNativePanelBounds(')
UI.nativePanelLayout = { panel = protected }
UI:RestoreNativePanelLayout()
assert(UI.nativePanelLayout.panel == protected)
methods(uiSource, 'local function resizeSafeArea(', 'function UI:ShowNativeChrome(')
UI:ResizeNativeChrome() -- UIParent deliberately lacks geometry methods: none may run here.
assert(UI.nativePanelLayout.panel == protected)
UI.nativePanelLayout = { panel = safe }

-- Closing an unprotected menu restores immediately; protected geometry waits.
Bags.Close = function() end
UI.nativeChrome.Hide = function() calls.hidden = true end
UI.RestoreNativePanelLayout = function(self) calls.restored = true; self.nativePanelLayout = nil end
methods(uiSource, 'function UI:HideNativeChrome()', 'function UI:Refresh()')
UI:HideNativeChrome()
assert(calls.restored and calls.hidden and not UI.pendingNativeRestore)
calls.restored = nil
UI.nativePanelLayout = { panel = protected }
UI:HideNativeChrome()
assert(UI.pendingNativeRestore and not calls.restored)
-- Entering combat releases isolation without closing the menu or changing its backdrop.
local released = false
Integration.EndUIIsolation = function() released = true end
local enterStart = assert(integrationSource:find('elseif event == "PLAYER_REGEN_DISABLED" then', 1, true))
local enterBody = integrationSource:sub(enterStart + #'elseif event == "PLAYER_REGEN_DISABLED" then',
    assert(integrationSource:find('elseif event == "PLAYER_REGEN_ENABLED" then', enterStart, true)) - 1)
calls.hidden = nil
assert(load(enterBody, nil, 't', environment))()
assert(released and not calls.hidden)

-- A fade queued before combat leaves protected opacity alone and resumes afterward.
local menusSource = read('Menus.lua')
local Menus = { opening = { [protected] = { alpha = 1 } } }
environment.Menus = Menus
UI.menuFadeAlphas = nil
local restoredOpacity = false
protected.SetAlpha = function(_, alpha) assert(not combat and alpha == 1); restoredOpacity = true end
methods(menusSource, 'function Menus:RevealOpening(', 'function Menus:SchedulePresentationCheck()')
Menus:RevealOpening(protected)
assert(Menus.opening[protected] and not restoredOpacity)
combat = false
Menus:RevealOpening(protected)
assert(not Menus.opening[protected] and restoredOpacity)
print('Combat presentation and isolation regression checks passed')
