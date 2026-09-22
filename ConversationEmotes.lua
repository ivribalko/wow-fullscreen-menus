local _, NS = ...

-- ConversationEmotes ranks expressive model animations against native NPC prose.
local Emotes = {}
NS.ConversationEmotes = Emotes

-- AnimationData IDs (not Emotes/EmotesText IDs). Chat-only emotes have no
-- animation to play. Shared/no-sheathe/flying variants add no new intent.
-- Source: TrinityCore src/server/game/Miscellaneous/SharedDefines.h, Anim enum.
-- Combat, death, locomotion and prop-dependent animations are not conversation
-- gestures. Physical actions below require explicit narrated NPC stage cues.
local rules = {
    { ids = { 67, 66, 185 }, cues = { "hello", "greetings", "welcome", "well met", "good to see you", "farewell", "goodbye", "safe travels" } },
    { ids = { 66, 185, 80 }, cues = { "thank you", "thanks", "grateful", "gratitude", "owe you", "well done", "excellent work" } },
    { ids = { 68, 80, 185 }, cues = { "victory", "we won", "we did it", "wonderful", "congratulations", "celebrate", "hooray" } },
    { ids = { 70, 83 }, cues = { "haha", "hahaha", "ha ha", "hehe", "funny", "hilarious", "what a joke" } },
    { ids = { 77, 186 }, cues = { "my condolences", "i am sorry", "i'm sorry", "i miss", "grief", "mourn", "heartbroken", "tragic", "tragedy", "sorrow" } },
    { ids = { 64, 74, 81 }, cues = { "how dare", "you fool", "traitor", "betrayed", "revenge", "vengeance", "furious", "you will pay" } },
    { ids = { 225, 65 }, cues = { "i am afraid", "i'm afraid", "terrified", "frightened", "scared", "we are doomed", "save me", "help me" } },
    { ids = { 79, 65 }, cues = { "i beg", "i implore", "please help", "beg of you", "our only hope", "desperate", "i need your help" } },
    { ids = { 65, 186 }, cues = { "i wonder", "i don't know", "i do not know", "confused", "puzzling", "strange", "perhaps", "are you sure" } },
    { ids = { 185, 60 }, cues = { "i agree", "of course", "indeed", "certainly", "that's right", "that is right", "you are right" } },
    { ids = { 186, 64 }, cues = { "i refuse", "absolutely not", "i disagree", "impossible", "you are wrong", "don't you dare", "do not dare" } },
    { ids = { 84, 60 }, cues = { "go to", "look at", "over there", "head to", "travel to", "bring me", "find the", "seek out", "follow the" } },
    { ids = { 113, 185, 82 }, cues = { "for the alliance", "for the horde", "for our people", "at your service", "duty", "honor", "honour" } },
    { ids = { 83, 76 }, cues = { "i love you", "my beloved", "my darling", "my love" } },
    { ids = { 64, 81, 84 }, cues = { "hurry", "watch out", "beware", "look out", "make haste", "no time", "danger" } },
}

local actions = {
    { 60, "talks", "speaks" }, { 61, "eats", "drinks", "chews" },
    { 62, "hammers", "works" }, { 63, "crafts" },
    { 64, "exclaims" }, { 65, "shrugs", "questions" }, { 66, "bows" },
    { 67, "waves" }, { 68, "cheers" }, { 69, "dances" },
    { 70, "laughs", "chuckles", "giggles" }, { 71, "sleeps", "snores" },
    { 72, "sits" }, { 73, "gestures rudely" }, { 74, "roars", "growls" },
    { 75, "kneels" }, { 76, "blows a kiss" }, { 77, "cries", "sobs", "weeps" },
    { 78, "clucks" }, { 79, "begs", "pleads" }, { 80, "applauds", "claps" },
    { 81, "shouts", "yells" }, { 82, "flexes" }, { 83, "blushes" },
    { 84, "points" }, { 113, "salutes" }, { 185, "nods" },
    { 186, "shakes his head", "shakes her head", "shakes their head" },
    { 225, "cowers", "trembles" }, { 506, "sniffs" }, { 520, "reads" },
}

function Emotes:Normalize(text)
    if type(text) ~= "string" then return "" end
    return text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
        :gsub("|n", " "):gsub("||", "|"):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function contains(text, cue)
    return text:find("%f[%a]" .. cue .. "%f[%A]") ~= nil
end

-- Return at most five equally eligible candidates near the strongest match.
-- English cue matching is conservative; other locales use neutral talking.
function Emotes:Choose(text)
    text = self:Normalize(text):lower():gsub("’", "'")
    local scores = {}
    local function add(id, score) scores[id] = math.max(scores[id] or 0, score) end
    for _, rule in ipairs(rules) do
        local score = 0
        for _, cue in ipairs(rule.cues) do
            if contains(text, cue) then score = score + 3 end
        end
        if score > 0 then
            for _, id in ipairs(rule.ids) do add(id, score) end
        end
    end
    -- Narration inside <...> or *...* outranks inferred sentiment. Do not
    -- interpret instructions such as "dance for me" as the speaker dancing.
    for stage in text:gmatch("<([^>]+)>") do
        for _, action in ipairs(actions) do
            for i = 2, #action do if contains(stage, action[i]) then add(action[1], 20) end end
        end
    end
    for stage in text:gmatch("%*([^*]+)%*") do
        for _, action in ipairs(actions) do
            for i = 2, #action do if contains(stage, action[i]) then add(action[1], 20) end end
        end
    end
    if text:find("?", 1, true) then add(65, 2) end
    if text:find("!", 1, true) then add(64, 1) end
    local ranked = {}
    for id, score in pairs(scores) do ranked[#ranked + 1] = { id = id, score = score } end
    table.sort(ranked, function(a, b)
        if a.score == b.score then return a.id < b.id end
        return a.score > b.score
    end)
    if #ranked == 0 then return { 60, 185 } end
    local choices = {}
    for _, entry in ipairs(ranked) do
        if #choices == 5 or entry.score < ranked[1].score - 1 then break end
        choices[#choices + 1] = entry.id
    end
    return choices
end

-- Read only the active conversation surface, never quest objectives, option
-- labels, inventory text or stale prose from another hidden interaction panel.
function Emotes:ReadText(panel)
    local name = panel:GetName()
    if name == "GossipFrame" then
        local getter = C_GossipInfo and C_GossipInfo.GetText or GetGossipText
        if type(getter) == "function" then
            local ok, text = pcall(getter)
            if ok then return self:Normalize(text) end
        end
    elseif name == "QuestFrame" then
        for _, name in ipairs({ "QuestInfoDescriptionText", "QuestProgressText", "QuestInfoRewardText", "GreetingText" }) do
            local region = _G[name]
            if region and region:IsVisible() then
                local text = self:Normalize(region:GetText())
                if text ~= "" then return text end
            end
        end
    elseif name == "ClassTrainerFrame" then
        local region = _G.ClassTrainerGreetingText
        if region and region:IsVisible() then return self:Normalize(region:GetText()) end
    end
    return ""
end
