-- Run from the repository with Lua; no game or external speech addon needed.
local ns = { Layout = {} }
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
assert(loadfile("ConversationEmotes.lua"))("FullscreenMenus", ns)
assert(loadfile("ConversationModels.lua"))("FullscreenMenus", ns)
local emotes, models = ns.ConversationEmotes, ns.ConversationModels
local function has(choices, id)
    for _, choice in ipairs(choices) do if choice == id then return true end end
end
assert(has(emotes:Choose("Welcome, friend!"), 67))
assert(has(emotes:Choose("Thank you. I am grateful for your help."), 66))
assert(has(emotes:Choose("How dare you! You will pay, traitor!"), 74))
assert(has(emotes:Choose("Please help. I beg of you!"), 79))
assert(has(emotes:Choose("We won! Victory!"), 68))
assert(has(emotes:Choose("My condolences. Such a tragedy."), 77))
assert(has(emotes:Choose("Have you found anything?"), 65))
assert(not has(emotes:Choose("The foreman welcomes shipments."), 67), "match complete words")
assert(not has(emotes:Choose("Dance for me."), 69), "commands are not speaker actions")
local choices = emotes:Choose("<The speaker cries.> We won, but at what cost?")
assert(#choices == 1 and choices[1] == 77, "narration outranks positive vocabulary")
assert(emotes:Choose("*kneels* Please help.")[1] == 75)
assert(emotes:Choose("Plain unclassified prose.")[1] == 60)
assert(emotes:Normalize(" |cffffffffHello|r|n|Hthing|hfriend|h |Ticon:12|t ") == "Hello friend")
assert(#emotes:Choose("Welcome! Thank you! Victory! Farewell!") <= 5)

local text = "Welcome!"
UnitGUID = function() return "npc" end
C_GossipInfo = { GetText = function() return text end }
local panel = { GetName = function() return "GossipFrame" end }
local function actor()
    return { guid = "npc", bounds = {}, count = 0, IsVisible = function() return true end,
        SetAnimation = function(self, id) self.animation = id; self.count = self.count + 1 end }
end
models.npc, models.player = actor(), actor()
models.suppressGreeting = false
models:UpdateNPCText(panel)
local candidates = models.npc.pendingEmoteChoices
models:UpdateEmotes(1)
assert(has(candidates, models.npc.animation), "first greeting must play")
assert(not models.npc.pendingEmoteChoices)
local count = models.npc.count
models:UpdateNPCText(panel); models:UpdateEmotes(1.1)
assert(models.npc.count == count, "identical text does not replay")
text = "<The speaker laughs.>"
models:UpdateNPCText(panel); models:UpdateEmotes(1.2)
assert(models.npc.animation == 70, "text change bypasses NPC cooldown")
text = "Welcome!"
models:UpdateNPCText(panel); models:UpdateEmotes(1.3)
assert(models.npc.animation == 0 and models.suppressGreeting, "returning greeting suppresses both actors")
text = "<The speaker nods.>"
models:UpdateNPCText(panel); models:UpdateEmotes(1.35)
assert(models.npc.animation == 185 and not models.suppressGreeting, "later dialogue remains eligible")
models.npc.bounds = nil
text = "<The speaker bows.>"
models:UpdateNPCText(panel); models:UpdateEmotes(1.4)
assert(models.npc.pendingEmoteChoices[1] == 66, "queue until geometry is ready")
text = "<The speaker salutes.>"
models:UpdateNPCText(panel); models:UpdateEmotes(1.5)
models.npc.bounds = {}
models:UpdateEmotes(1.6)
assert(models.npc.animation == 113, "loading retains only current prose")
text = ""
models:UpdateNPCText(panel)
assert(not models.npc.pendingEmoteChoices and models.npc.animation == 0)
text = "<The speaker laughs.>"
models.npc.SetAnimation = function(self, id)
    if id == 70 then return false end
    self.animation = id
end
models:UpdateNPCText(panel); models:UpdateEmotes(2)
assert(models.npc.animation == 60, "rejected gesture falls back to talking")

-- Sampling stays inside the chosen list and can reach every candidate.
models.npc = actor()
models.suppressGreeting = false
local seen = {}
math.randomseed(1234)
for i = 1, 100 do
    models.npc.pendingEmoteChoices = { 66, 67, 185 }
    models:UpdateEmotes(i / 100)
    seen[models.npc.animation] = true
end
assert(seen[66] and seen[67] and seen[185])

-- Quest stages read visible prose, not hidden descriptions or option labels.
local function region(value, visible)
    return { IsVisible = function() return visible end, GetText = function() return value end }
end
panel.GetName = function() return "QuestFrame" end
QuestInfoDescriptionText = region("old description", false)
QuestProgressText = region("Have you finished?", true)
QuestInfoRewardText = region("old reward", false)
assert(emotes:ReadText(panel) == "Have you finished?")
QuestProgressText = region("old progress", false)
QuestInfoRewardText = region("Thank you!", true)
assert(emotes:ReadText(panel) == "Thank you!")
panel.GetName = function() return "MerchantFrame" end
assert(emotes:ReadText(panel) == "", "services without prose must not reuse gossip")
models:Hide()
assert(models.interactionText == nil and models.textNPC == nil)
print("Conversation text matching, playback, loading, random selection and text-source checks passed")
