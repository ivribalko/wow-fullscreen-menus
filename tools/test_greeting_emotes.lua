-- Run with Lua 5.1 from the FullscreenMenus repository; no game or speech addon needed.
local ns = { Layout = {} }
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
local npc, text = "npc-a", "Welcome"
UnitGUID = function() return npc end
C_GossipInfo = { GetText = function() return text end }
GetGreetingText = function() return text end
assert(loadfile("ConversationModels.lua"))("FullscreenMenus", ns)
local models = ns.ConversationModels
models:TrackGreeting("GOSSIP_SHOW")
assert(not models.suppressGreeting)
models:Hide()
models:TrackGreeting("GOSSIP_SHOW")
assert(models.suppressGreeting, "closure must retain greeting memory")
local function actor()
    return { pendingEmoteChoices = { 67 }, emoteUntil = 3,
        SetAnimation = function(self, animation) self.animation = animation end }
end
models.npc, models.player = actor(), actor()
models:UpdateEmotes(1)
for _, model in ipairs({ models.npc, models.player }) do
    assert(model.pendingEmoteChoices == nil and model.emoteUntil == nil and model.animation == 0)
end
text = "Another page"
models:TrackGreeting("GOSSIP_SHOW")
assert(not models.suppressGreeting, "later gossip must remain eligible")
text = "Welcome"
models:TrackGreeting("QUEST_GREETING")
assert(models.suppressGreeting, "returning to the introduction must suppress both models")
models:TrackGreeting("QUEST_DETAIL")
assert(not models.suppressGreeting, "quest prose must remain eligible")
npc = "npc-b"
models:TrackGreeting("MERCHANT_SHOW")
assert(not models.suppressGreeting)
npc = "npc-a"
models:TrackGreeting("GOSSIP_SHOW")
assert(not models.suppressGreeting, "another NPC without a greeting resets memory")
models:TrackGreeting("GOSSIP_SHOW")
assert(models.suppressGreeting)
npc = "npc-b"
models:TrackGreeting("GOSSIP_SHOW")
assert(not models.suppressGreeting, "same text from another NPC is a new greeting")
print("Independent greeting emote checks passed")
