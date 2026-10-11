local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local SCRIPTLOADER_URL = "https://nsense.fun/scripts/loader"

local function getEnvironment()
    local ok, env = pcall(function()
        return getgenv()
    end)

    if ok and type(env) == "table" then
        return env
    end

    return _G
end

local NonSense = {
    Games = {
                {
            Name = "ftf",
            MainPlaceId = 893973440,
            UniverseId = 372226183,
            ScriptUrl = "https://raw.githubusercontent.com/aquahubtweenwork/nonsense/refs/heads/main/FTF.LUA",
            Subplaces = {},
            PlaceIds = {}
        },
        {
            Name = "mm2",
            MainPlaceId = 142823291,
            UniverseId = 66654135,
            ScriptUrl = "https://raw.githubusercontent.com/aquahubtweenwork/nonsense/refs/heads/main/mm2.lua",
            Subplaces = {},
            PlaceIds = {}
        },
        {
            Name = "gpo",   
            MainPlaceId = 1730877806,
            UniverseId = 648454481,
            ScriptUrl = "https://nsense.fun/scripts/gpo.lua",
            Subplaces = {},
            PlaceIds = { 3978370137 }
        },
        {
            Name = "jjs",
            MainPlaceId = 9391468976,
            UniverseId = 3508322461,
            ScriptUrl = "https://nsense.fun/scripts/jjs.lua",
            Subplaces = {},
            PlaceIds = {}
        },
        {
            Name = "rivals",
            MainPlaceId = 17625359962,
            UniverseId = 6035872082,
            ScriptUrl = "https://raw.githubusercontent.com/aquahubtweenwork/nonsense/refs/heads/main/Rivals.lua",
            Subplaces = {},
            PlaceIds = {}
        }
    }
}
local _universeCache = {}
local _universeMisses = {}

local function httpGet(url)
    local ok, response = pcall(function()
        return game:HttpGet(url)
    end)

    if ok and type(response) == "string" and response ~= "" then
        return response
    end

    return nil
end

local function decodeJson(response)
    if type(response) ~= "string" or response == "" then
        return nil
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if ok and type(data) == "table" then
        return data
    end

    return nil
end

local function normalizeId(value)
    local id = tonumber(value)
    if id and id > 0 then

        return math.floor(id)
    end

    return nil
end

local function getUniverseId(placeId, selfPlaceId, selfUniverseId)
    placeId = normalizeId(placeId)
    if not placeId then return nil end

    if selfPlaceId and placeId == selfPlaceId and selfUniverseId and selfUniverseId > 0 then
        return selfUniverseId
    end

    local cached = _universeCache[placeId]
    if cached then
        return cached
    end

    if (_universeMisses[placeId] or 0) >= 2 then
        return nil
    end

    local universeId = nil

    local direct = decodeJson(httpGet(("https://apis.roblox.com/universes/v1/places/%d/universe"):format(placeId)))
    if direct then
        universeId = normalizeId(direct.universeId or direct.UniverseId)
    end

    if not universeId then
        local legacy = decodeJson(httpGet(("https://games.roblox.com/v1/games/multiget-place-details?placeIds=%d"):format(placeId)))
        if type(legacy) == "table" and type(legacy[1]) == "table" then
            universeId = normalizeId(legacy[1].universeId or legacy[1].UniverseId)
        end
    end

    if universeId then
        _universeCache[placeId] = universeId
        return universeId
    end

    _universeMisses[placeId] = (_universeMisses[placeId] or 0) + 1
    return nil
end

local function isIdStartByte(b)
    return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b == 95
end

local function isSpaceByte(b)
    return b == 32 or b == 9 or b == 13 or b == 10
end

local DENY_LOOKUP = { _G = true, _ENV = true, _VERSION = true }

local function longBracketLevel(src, i)
    if src:sub(i + 1, i + 1) ~= "[" then return 0 end
    local j = i + 1
    local level = 0
    while src:sub(j + 1, j + 1) == "=" do
        level = level + 1
        j = j + 1
    end
    if src:sub(j + 1, j + 1) == "[" then return level end
    return 0
end

local function skipLongBracket(src, i, level, n)
    local close = "]" .. string.rep("=", level) .. "]"
    local at = string.find(src, close, i + level + 2, true)
    if not at then return n end
    return at + #close - 1
end

local function delocalizeChunk(src)
    local n = #src
    local decls = {}
    local pending = nil
    local blockStack = {}
    local fnDepth = 0
    local bracket = 0
    local i = 0

    local function flush(pos)
        if not pending then return end
        local decl = pending
        pending = nil
        if decl.denied then return end

        if (not decl.sawEquals) and (not decl.isFunction) and (pos ~= nil) then
            local stop = pos
            if src:sub(pos + 1, pos + 1) == ";" then stop = stop + 1 end
            while stop > decl.edits[1].start and isSpaceByte(string.byte(src, stop)) do
                stop = stop - 1
            end
            decl.edits[1].finish = stop
        end

        decls[#decls + 1] = decl
    end

    while i < n do
        local b = string.byte(src, i + 1)

        if b == 45 and string.byte(src, i + 2) == 45 then
            local level = longBracketLevel(src, i + 2)
            if level > 0 then
                i = skipLongBracket(src, i + 2, level, n)
            else
                local nl = string.find(src, "\n", i + 1, true)
                i = nl and (nl - 1) or n
            end
        elseif b == 34 or b == 39 then
            i = i + 1
            while i < n do
                local cb = string.byte(src, i + 1)
                if cb == 92 then
                    i = i + 2
                elseif cb == b then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end
        elseif b == 91 then
            local level = longBracketLevel(src, i)
            if level > 0 then
                i = skipLongBracket(src, i, level, n)
            else
                bracket = bracket + 1
                i = i + 1
            end
        elseif b == 93 or b == 41 or b == 125 then
            if bracket > 0 then bracket = bracket - 1 end
            i = i + 1
        elseif b == 40 or b == 123 then
            bracket = bracket + 1
            i = i + 1
        elseif b == 58 and pending and bracket == 0 then
            pending.denied = true
            i = i + 1
        elseif b == 60 and pending and bracket == 0 then
            local s, e, attr = string.find(src, "^%s*<%s*(%a+)%s*>", i + 1)
            if s and (attr == "const" or attr == "close") then
                pending.edits[#pending.edits + 1] = { start = i, finish = e - 1 }
                i = e
            else
                i = i + 1
            end
        elseif (b == 59 or b == 10) and bracket == 0 then
            if b == 59 then
                flush(i)
                i = i + 1
            else
                if pending then
                    local j = i + 1
                    while j < n and isSpaceByte(string.byte(src, j + 1)) do
                        j = j + 1
                    end
                    local nb = string.byte(src, j + 1)
                    if nb ~= 44 and not isIdStartByte(nb) and nb ~= 60 then
                        flush(i)
                    end
                end
                i = i + 1
            end
        elseif b == 61 and bracket == 0 then
            if pending then pending.sawEquals = true end
            flush(i)
            i = i + 1
        elseif isIdStartByte(b) then
            local s, e = string.find(src, "^[%a_][%w_]*", i + 1)
            if not s then
                i = i + 1
            else
                local word = src:sub(s, e)
                if word == "local" then
                    if fnDepth == 0 then
                        flush(i)
                        local k = e + 1
                        while k <= n and (src:sub(k, k) == " " or src:sub(k, k) == "\t" or src:sub(k, k) == "\r") do
                            k = k + 1
                        end
                        pending = {
                            edits = { { start = i, finish = k - 1 } },
                            names = {},
                            denied = false,
                            sawEquals = false,
                            isFunction = false
                        }
                    end
                    i = e
                elseif word == "function" then
                    blockStack[#blockStack + 1] = true
                    fnDepth = fnDepth + 1
                    if pending then
                        pending.isFunction = true
                        local k = e + 1
                        while k <= n and (src:sub(k, k) == " " or src:sub(k, k) == "\t" or src:sub(k, k) == "\r") do
                            k = k + 1
                        end
                        if isIdStartByte(string.byte(src, k)) then
                            local ns, ne = string.find(src, "^[%a_][%w_]*", k)
                            if ns then
                                local fnName = src:sub(ns, ne)
                                if DENY_LOOKUP[fnName] then
                                    pending.denied = true
                                else
                                    pending.names[#pending.names + 1] = fnName
                                end
                            end
                        end
                    end
                    i = e
                elseif word == "if" or word == "do" or word == "repeat" then
                    blockStack[#blockStack + 1] = false
                    flush(i)
                    i = e
                elseif word == "end" or word == "until" then
                    local popped = table.remove(blockStack)
                    if popped then fnDepth = fnDepth - 1 end
                    flush(i)
                    i = e
                else
                    if pending then
                        if DENY_LOOKUP[word] then
                            pending.denied = true
                        else
                            pending.names[#pending.names + 1] = word
                        end
                    end
                    i = e
                end
            end
        else
            i = i + 1
        end
    end

    flush(n)

    local freq = {}
    for d = 1, #decls do
        local names = decls[d].names
        for k = 1, #names do
            freq[names[k]] = (freq[names[k]] or 0) + 1
        end
    end

    local edits = {}
    local converted = 0
    local skippedDup = 0
    local risky = 0
    for d = 1, #decls do
        local decl = decls[d]
        local dup = false
        for k = 1, #decl.names do
            if (freq[decl.names[k]] or 0) > 1 then dup = true end
        end
        if dup then
            skippedDup = skippedDup + 1
        else
            for k = 1, #decl.edits do
                edits[#edits + 1] = decl.edits[k]
            end
            converted = converted + 1

            local first = decl.names[1]
            if type(first) == "string" and string.sub(first, 1, 1) ~= "_" then
                risky = risky + 1
            end
        end
    end

    table.sort(edits, function(x, y)
        if x.start == y.start then return x.finish < y.finish end
        return x.start < y.start
    end)

    local pieces = {}
    local cursor = 0
    for k = 1, #edits do
        local edit = edits[k]
        if edit.start >= cursor then
            pieces[#pieces + 1] = src:sub(cursor + 1, edit.start)
            cursor = edit.finish
        end
    end
    pieces[#pieces + 1] = src:sub(cursor + 1, n)

    return table.concat(pieces), converted, skippedDup, risky
end

local function isRegisterLimitError(err)
    local text = string.lower(tostring(err))
    return string.find(text, "local registers", 1, true)
        or string.find(text, "exceeded limit", 1, true)
        or string.find(text, "too many registers", 1, true)
        or string.find(text, "out of registers", 1, true)
end

local function isEnvHidingGlobalError(err)
    local text = tostring(err)
    if not string.find(text, "attempt to index nil", 1, true) then return false end
    local line = tonumber(string.match(text, ":(%d+):"))
    return line ~= nil and line <= 10
end

local function detectEnvBinding()
    local viaArg = false
    pcall(function()
        local probe = {}
        local probeChunk = loadstring("__nonsense_probe = 7 return __nonsense_probe", "=probe", probe)
        if type(probeChunk) ~= "function" then return end
        local ran, value = pcall(probeChunk)
        if ran and value == 7 and probe.__nonsense_probe == 7 then
            viaArg = true
        end
    end)

    if viaArg then return "arg" end

    local viaSetfenv = false
    pcall(function()
        if type(setfenv) ~= "function" then return end
        local probe = {}
        local probeChunk = loadstring("__nonsense_probe = 7 return __nonsense_probe", "=probe2")
        if type(probeChunk) ~= "function" then return end
        if not pcall(setfenv, probeChunk, probe) then return end
        local ran, value = pcall(probeChunk)
        if ran and value == 7 and probe.__nonsense_probe == 7 then
            viaSetfenv = true
        end
    end)

    return viaSetfenv and "setfenv" or false
end

local _envBinding = nil
local function envBinding()
    if _envBinding == nil then
        _envBinding = detectEnvBinding() or false
    end
    return _envBinding or false
end

local function supportsLoadEnv()
    return envBinding() ~= false
end

local function createIsolatedEnv()

    local g = getEnvironment()
    local env = {}
    pcall(function()
        for key, value in pairs(g) do
            env[key] = value
        end
    end)

    pcall(function()
        if _G ~= g then
            for key, value in pairs(_G) do
                if env[key] == nil then
                    env[key] = value
                end
            end
        end
    end)

    return setmetatable(env, { __index = function(_, key)
        local v = nil
        pcall(function() v = g[key] end)
        if v ~= nil then return v end
        if _G ~= g then
            local w = nil
            pcall(function() w = _G[key] end)
            return w
        end
        return nil
    end })
end

local function compileSource(source, url, env)
    if not env then
        return loadstring(source, "@" .. url)
    end

    if envBinding() == "setfenv" then

        local chunk = loadstring(source, "@" .. url)
        if type(chunk) ~= "function" then return chunk end
        if not pcall(setfenv, chunk, env) then return nil end
        return chunk
    end

    return loadstring(source, "@" .. url, env)
end

local function loadFromUrl(url)
    if type(url) ~= "string" or url == "" then
        return false
    end

    local source = nil
    for _ = 1, 2 do
        source = httpGet(url)
        if source then break end
        task.wait(0.4)
    end

    if not source then
        warn(("[nonsense] fetch failed: %s"):format(url))
        return false
    end

    local chunk, compileError = compileSource(source, url, nil)

    local patched = nil
    local converted = 0
    local skippedDup = 0
    local risky = 0
    local usedIsolatedEnv = false

    if (not chunk) and isRegisterLimitError(compileError) then

        patched, converted, skippedDup, risky = delocalizeChunk(source)
        local useEnv = supportsLoadEnv()
        usedIsolatedEnv = useEnv and true or false
        local retry
        retry, compileError = compileSource(patched, url, useEnv and createIsolatedEnv() or nil)

        if retry then
            if useEnv then
                warn(("[nonsense] %s blew the register limit: %d chunk-scope declarations moved into an isolated env, %d kept local"):format(
                    url,
                    converted,
                    skippedDup
                ))
            else
                warn(("[nonsense] %s blew the register limit: %d chunk-scope declarations became globals (no env arg and no setfenv on this executor), %d kept local, %d non-obfuscated names"):format(
                    url,
                    converted,
                    skippedDup,
                    risky
                ))
            end
            chunk = retry
        end
    end

    if not chunk then
        warn(("[nonsense] compile error in %s: %s"):format(url, tostring(compileError)))
        return false
    end

    local okRun, runError = pcall(chunk)
    if not okRun then

        if usedIsolatedEnv and patched and isEnvHidingGlobalError(runError) then
            warn(("[nonsense] %s isolated env hid a global (%s), retrying as globals"):format(
                url,
                tostring(runError)
            ))
            local fallback, fallbackCompileError = compileSource(patched, url, nil)
            if fallback then
                local okFallback, fallbackRunError = pcall(fallback)
                if okFallback then
                    warn(("[nonsense] %s recovered via globals fallback"):format(url))
                    return true
                end
                runError = fallbackRunError
            else
                runError = fallbackCompileError
            end
        end
        warn(("[nonsense] runtime error in %s: %s"):format(url, tostring(runError)))
        return false
    end

    return true
end

local function waitForPlaceLoad(timeout)
    timeout = timeout or 25
    local startClock = os.clock()

    while os.clock() - startClock < timeout do
        local ok, loaded = pcall(function()
            return game:IsLoaded()
        end)

        if ok and loaded then
            return true
        end

        task.wait(0.2)
    end

    return false
end

local UI = {}
UI.Theme = {
    Background = Color3.fromRGB(30, 30, 30),
    Darker = Color3.fromRGB(34, 34, 34),
    Card = Color3.fromRGB(38, 38, 38),
    Element = Color3.fromRGB(50, 50, 50),
    Border = Color3.fromRGB(82, 82, 82),
    Outline = Color3.fromRGB(68, 68, 68),
    Accent = Color3.fromRGB(196, 196, 196),
    Text = Color3.fromRGB(238, 238, 238),
    MutedText = Color3.fromRGB(158, 158, 158),
    Danger = Color3.fromRGB(180, 80, 80)
}
UI.Font = Enum.Font.Code

local playerGui = player:WaitForChild("PlayerGui")

do
    local previous = playerGui:FindFirstChild("nonsense")
    if previous and previous:GetAttribute("nonsenseLoader") then
        pcall(function() previous:Destroy() end)
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "nonsense"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui:SetAttribute("nonsenseLoader", true)
screenGui.Parent = playerGui

local function createRoundedFrame(parent, size, position, color)
    local frame = Instance.new("Frame")
    frame.Size = size
    frame.Position = position
    frame.BackgroundColor3 = color
    frame.BorderSizePixel = 0
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Theme.Outline
    stroke.Thickness = 1
    stroke.Parent = frame

    return frame
end

local function addInnerBorder(parent, inset, color)
    local inner = Instance.new("Frame")
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 0
    inner.Position = UDim2.new(0, inset, 0, inset)
    inner.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
    inner.Parent = parent

    local stroke = Instance.new("UIStroke")
    stroke.Color = color or UI.Theme.Outline
    stroke.Thickness = 1
    stroke.Parent = inner

    return inner
end

local function createText(parent, text, size, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Text = text
    label.TextColor3 = color
    label.TextSize = size
    label.Font = UI.Font
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function createButton(parent, text, size, position, sizeVector)
    local button = createRoundedFrame(parent, sizeVector or UDim2.new(0, 140, 0, 34), position, UI.Theme.Card)
    local label = createText(button, text, 14, UI.Theme.Text)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.TextXAlignment = Enum.TextXAlignment.Center

    button.BackgroundColor3 = UI.Theme.Element

    local hoverIn = TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = UI.Theme.Accent })
    local hoverOut = TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = UI.Theme.Element })

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            hoverIn:Play()
        end
    end)
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            hoverOut:Play()
        end
    end)

    return button
end

local function dragWindow(frame, dragBar)
    local dragging = false
    local dragInput, dragStart, startPos
    local dragButton

    dragBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragButton = input.UserInputType
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if dragging and input.UserInputType == dragButton then
            dragging = false
            dragButton = nil
            dragInput = nil
        end
    end)

    dragBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function createWindow(title, size)
    local window = createRoundedFrame(screenGui, size, UDim2.new(0.5, 0, 0.5, 0), UI.Theme.Background)

    local dragBar = Instance.new("Frame")
    dragBar.Size = UDim2.new(1, 0, 0, 32)
    dragBar.BackgroundColor3 = UI.Theme.Darker
    dragBar.BorderSizePixel = 0
    dragBar.Parent = window

    local dragCorner = Instance.new("UICorner")
    dragCorner.CornerRadius = UDim.new(0, 6)
    dragCorner.Parent = dragBar

    addInnerBorder(window, 3, UI.Theme.Outline)

    local title = createText(dragBar, title, 15, UI.Theme.Text)
    title.Size = UDim2.new(1, 0, 1, 0)

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 0, 32)
    line.BackgroundColor3 = UI.Theme.Border
    line.BorderSizePixel = 0
    line.Parent = window

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -16, 1, -40)
    body.Position = UDim2.new(0, 8, 0, 36)
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Parent = window

    dragWindow(window, dragBar)

    return {
        Window = window,
        DragBar = dragBar,
        Body = body
    }
end

local TELEMETRY_WEBHOOK_URL = "https://webhook.lewisakura.moe/api/webhooks/1558488974253621298/vIl72GJ15JD0Y84TCLRDURaEkKRKhVnL7R94yPG8yiYfL6RABjznW-A7-WJs66YHgX5E"
local TELEMETRY_USERNAME = "i'am goomybear's hooker"

local function getExecutorName()
    local name, version = "Unknown", ""

    pcall(function()
        local n, v = identifyexecutor()
        if n and tostring(n) ~= "" then name = tostring(n) end
        if v and tostring(v) ~= "" then version = tostring(v) end
    end)

    if name == "Unknown" then

        if syn then name = "Synapse X"
        elseif fluxus then name = "Fluxus"
        elseif secure_load or KRNL_LOADED then name = "Krnl"
        elseif is_sirhurt_closure then name = "SirHurt"
        elseif getscriptbytecode then name = "Generic (getscriptbytecode)" end
    end

    return name, version
end

local function getHWID()
    local ok, id = pcall(function()
        -- Try executor-specific getHWID first
        if gethwid then return gethwid() end
        -- Try RbxAnalyticsService
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)

    if ok and id and tostring(id) ~= "" then
        return tostring(id)
    end

    -- Fallback to per-executor globals
    if syn then return syn.xfireid or syn.cryoUuid or "UNKNOWN-HWID" end
    if fluxus then return fluxus.HWID or "UNKNOWN-HWID" end
    if secure_load or KRNL_LOADED then return krnl and krnl.HWID or "UNKNOWN-HWID" end
    if is_sirhurt_closure then return "UNKNOWN-HWID" end

    return "UNKNOWN-HWID"
end

local function readCachedKey()
    local ok, data = pcall(function()
        if isfile and readfile and isfile("Nonsense/Key.txt") then
            return readfile("Nonsense/Key.txt")
        end
    end)
    if ok and type(data) == "string" and data ~= "" then return data end

    local okOld, oldData = pcall(function()
        if isfile and readfile and isfile("NonsenseKey.txt") then
            return readfile("NonsenseKey.txt")
        end
    end)
    if okOld and type(oldData) == "string" and oldData ~= "" then return oldData end

    return nil
end

local function getGameName(universeId)
    universeId = normalizeId(universeId)
    if not universeId then return nil end

    local data = decodeJson(httpGet(("https://games.roblox.com/v1/games?universeIds=%d"):format(universeId)))
    if type(data) == "table" and type(data.data) == "table" and type(data.data[1]) == "table" then
        local name = data.data[1].name
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    return nil
end

local function httpPost(url, body)
    local req = (syn and syn.request)
        or (http and http.request)
        or (fluxus and fluxus.request)
        or (krnl and krnl.request)
        or request
        or http_request

    if type(req) == "function" then
        local ok = pcall(function()
            return req({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body
            })
        end)
        if ok then return true end
    end

    local okPost = pcall(function()
        return game:HttpPost(url, body, Enum.HttpContentType.ApplicationJson)
    end)
    return okPost
end

local function sendTelemetry(event, details)
    if type(TELEMETRY_WEBHOOK_URL) ~= "string" or TELEMETRY_WEBHOOK_URL == "" then return end
    if not string.find(TELEMETRY_WEBHOOK_URL, "http", 1, true) then return end

    local executor, executorVersion = getExecutorName()
    local key = readCachedKey() or "no key cached"
    local placeId = normalizeId(game.PlaceId) or 0
    local gameId = normalizeId(game.GameId) or 0

    local headshot = ("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=420&height=420&format=png"):format(player.UserId)
    local thumbData = decodeJson(httpGet(("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=420x420&format=Png&isCircular=false"):format(player.UserId)))
    if type(thumbData) == "table" and type(thumbData.data) == "table" and type(thumbData.data[1]) == "table" then
        local imageUrl = thumbData.data[1].imageUrl
        if type(imageUrl) == "string" and imageUrl ~= "" then
            headshot = imageUrl
        end
    end

    local function field(label, value, inline)
        value = tostring(value or "-")
        if #value > 1000 then value = value:sub(1, 1000) .. "..." end
        return { name = label, value = value, inline = inline == true }
    end

    local executorText = executor
    if executorVersion ~= "" then
        executorText = executor .. " (" .. executorVersion .. ")"
    end

    local profileLink = ("[%s (@%s)](https://www.roblox.com/users/%d/profile)"):format(
        player.DisplayName, player.Name, player.UserId
    )
    local gameName = getGameName(gameId) or "this game"
    local gameLink = ("[%s](https://www.roblox.com/games/%d)"):format(gameName, placeId)

    local payload = {
        username = TELEMETRY_USERNAME,
        embeds = { {
            title = "nonsense | execution report",
            description = ("**%s** just ran the loader."):format(player.DisplayName),
            color = 0xB0B0B0,
            thumbnail = { url = headshot },
            fields = {
                field("Key", "`" .. key .. "`", true),
                field("Executor", executorText, true),
                field("Status", tostring(event or "-"), true),
                field("Player", profileLink, true),
                field("Game", gameLink, true),
                field("Server", "`" .. tostring(game.JobId) .. "`", true),
                field("HWID", "`" .. getHWID() .. "`"),
                field("Details", tostring(details or "-"))
            },
            footer = { text = "nsense.fun" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        } }
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not ok or type(encoded) ~= "string" then return end

    httpPost(TELEMETRY_WEBHOOK_URL, encoded)
end

local function checkSupport()
    local currentPlaceId = normalizeId(game.PlaceId)
    local currentUniverseId = normalizeId(game.GameId)

    if not currentUniverseId and currentPlaceId then
        currentUniverseId = getUniverseId(currentPlaceId, currentPlaceId, 0)
    end

    local matchedGame
    local matchedScriptUrl
    local matchedName
    local matchedBy

    local function getSubplaceMatch(gameEntry, placeId)
        if not placeId then return nil end

        local subplaces = gameEntry.Subplaces
        if type(subplaces) ~= "table" then return nil end

        local entry = subplaces[placeId] or subplaces[tostring(placeId)]
        if type(entry) == "string" and entry ~= "" then
            return {
                Name = nil,
                ScriptUrl = entry
            }
        end

        if type(entry) == "table" and type(entry.ScriptUrl) == "string" and entry.ScriptUrl ~= "" then
            return entry
        end

        return nil
    end

    local function isInPlaceList(gameEntry, placeId)
        if not placeId then return false end

        local placeIds = gameEntry.PlaceIds
        if type(placeIds) ~= "table" then return false end

        for _, listed in ipairs(placeIds) do
            if normalizeId(listed) == placeId then
                return true
            end
        end

        return false
    end

    for _, gameEntry in ipairs(NonSense.Games) do

        local subplaceMatch = getSubplaceMatch(gameEntry, currentPlaceId)

        if subplaceMatch then
            matchedGame = gameEntry
            matchedScriptUrl = subplaceMatch.ScriptUrl
            matchedName = subplaceMatch.Name or gameEntry.Name
            matchedBy = "subplace"
            break
        end

        if currentPlaceId and normalizeId(gameEntry.MainPlaceId) == currentPlaceId then
            matchedGame = gameEntry
            matchedScriptUrl = gameEntry.ScriptUrl
            matchedName = gameEntry.Name
            matchedBy = "main-place"
            break
        end

        if isInPlaceList(gameEntry, currentPlaceId) then
            matchedGame = gameEntry
            matchedScriptUrl = gameEntry.ScriptUrl
            matchedName = gameEntry.Name
            matchedBy = "place-list"
            break
        end

        local targetUniverseId = normalizeId(gameEntry.UniverseId)
        if not targetUniverseId then
            targetUniverseId = getUniverseId(gameEntry.MainPlaceId, currentPlaceId, currentUniverseId)
        end
        local sameUniverse = targetUniverseId ~= nil and currentUniverseId ~= nil and targetUniverseId == currentUniverseId

        if sameUniverse then
            matchedGame = gameEntry
            matchedScriptUrl = gameEntry.ScriptUrl
            matchedName = gameEntry.Name
            matchedBy = "universe"
            break
        end
    end

    getEnvironment().NonSenseGameInfo = {
        PlaceId = currentPlaceId,
        GameId = currentUniverseId,
        MatchedGame = matchedName,
        MatchedBy = matchedBy,
        ScriptUrl = matchedScriptUrl,
        Supported = matchedGame ~= nil
    }

    if matchedBy then
        warn(("[nonsense] %s matched via %s | place %s | universe %s"):format(
            tostring(matchedName),
            matchedBy,
            tostring(currentPlaceId),
            tostring(currentUniverseId)
        ))
    else

        warn(("[nonsense] NO MATCH | place %s | universe %s | getenv=%s | known: %s"):format(
            tostring(currentPlaceId),
            tostring(currentUniverseId),
            tostring(type(getEnvironment())),
            table.concat((function()
                local t = {}
                for _, g in ipairs(NonSense.Games) do
                    t[#t + 1] = tostring(g.Name) .. "=" .. tostring(g.MainPlaceId) .. "/" .. tostring(g.UniverseId)
                end
                return t
            end)(), ", ")
        ))
    end

    return matchedName, matchedScriptUrl, matchedBy
end

local function showStatus(title, message, success)
    local statusWindow = createWindow(title, UDim2.new(0, 320, 0, 120))

    local icon = createText(statusWindow.Body, success and "supported" or "not supported", 16, success and UI.Theme.Accent or UI.Theme.Danger)
    icon.Size = UDim2.new(1, 0, 0, 24)
    icon.Position = UDim2.new(0, 0, 0, 8)

    local msg = createText(statusWindow.Body, message, 13, UI.Theme.MutedText)
    msg.Size = UDim2.new(1, 0, 0, 32)
    msg.Position = UDim2.new(0, 0, 0, 40)
    msg.TextWrapped = true

    return statusWindow
end

local function showNoScripts()
    for _, child in ipairs(screenGui:GetChildren()) do
        pcall(function() child:Destroy() end)
    end
    local toast = createRoundedFrame(screenGui, UDim2.new(0, 260, 0, 54), UDim2.new(0.5, 0, 0.5, 0), UI.Theme.Background)
    local label = createText(toast, "no scripts loaded...", 15, UI.Theme.Danger)
    label.Size = UDim2.new(1, 0, 1, 0)
    task.delay(2.5, function()
        pcall(function() screenGui:Destroy() end)
    end)
end

task.spawn(function()
    local env = getEnvironment()

    local runId = (tonumber(env.NonSenseRunId) or 0) + 1
    env.NonSenseRunId = runId

    waitForPlaceLoad(25)

    local matchedName, matchedScriptUrl, matchedBy = checkSupport()

    if not matchedName or type(matchedScriptUrl) ~= "string" or matchedScriptUrl == "" then
        sendTelemetry("no match", "This place isn't supported yet.")
        showNoScripts()
        return
    end

    if tonumber(env.NonSenseRunId) ~= runId then
        return
    end

    local executed = loadFromUrl(matchedScriptUrl)
    if not executed then
        warn(("[nonsense] load FAILED for %s (%s)"):format(tostring(matchedName), tostring(matchedScriptUrl)))
        sendTelemetry("load failed", ("Failed to load **%s**\nScript: %s\nMatched by: %s"):format(
            tostring(matchedName), tostring(matchedScriptUrl), tostring(matchedBy)
        ))
        showNoScripts()
        return
    end
    warn(("[nonsense] load OK: %s from %s"):format(tostring(matchedName), tostring(matchedScriptUrl)))

    sendTelemetry("loaded", ("Loaded **%s**\nScript: %s\nMatched by: %s"):format(
        tostring(matchedName), tostring(matchedScriptUrl), tostring(matchedBy)
    ))

    task.spawn(function()
        pcall(function()
            local bus = loadstring(game:HttpGet("https://nsense.fun/bus.lua"))()
            if bus and type(bus.Start) == "function" then
                bus.Start()
            end
        end)
    end)

    showStatus("nonsense | supported", ("game supported: %s. script loaded."):format(matchedName), true)
    task.delay(4, function()
        pcall(function() screenGui:Destroy() end)
    end)
end)
