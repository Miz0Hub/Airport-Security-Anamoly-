-- Airport Security (Anomaly): automatic work + instant prompts
-- F6: pause/resume automation. End: stop and restore prompt settings.


local Env = getgenv()
local RS = game:GetService("ReplicatedStorage")
local function startupReady()
    local network = RS:FindFirstChild("Network")
    local gameFolder = RS:FindFirstChild("Game")
    local gameLibrary = gameFolder and gameFolder:FindFirstChild("Library")
    local sharedLibrary = RS:FindFirstChild("Library")
    local sharedClient = sharedLibrary and sharedLibrary:FindFirstChild("Client")
    return game:IsLoaded() and network and network:FindFirstChild("RemoteEvent")
        and network:FindFirstChild("RemoteFunction") and gameLibrary
        and gameLibrary:FindFirstChild("Client") and sharedClient
        and sharedClient:FindFirstChild("Network")
end
local startupDeadline = os.clock() + 30
while (game.GameId == 0 or (game.GameId == 10768761562 and not startupReady()))
    and os.clock() < startupDeadline do task.wait(0.1) end
assert(game.GameId == 10768761562, "This script is for Airport Security (Anomaly).")
assert(startupReady(), "Miz0 Hub: the game is still loading. Run again after loading finishes.")
if Env.AirportAuto and Env.AirportAuto.Stop then Env.AirportAuto.Stop() end

local Players = game:GetService("Players")
local PPS = game:GetService("ProximityPromptService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local Remote = RS.Network.RemoteEvent
local Functions = RS.Network.RemoteFunction
local Client = RS.Game.Library.Client
local IS_LOBBY = game.PlaceId == 108334808788078 or workspace:FindFirstChild("LobbyPads") ~= nil
local Network = require(RS.Library.Client.Network)
local Extinguishers = not IS_LOBBY and require(RS.Game.Library.Extinguishers) or nil
local ShiftState = not IS_LOBBY and require(Client.ShiftCmds) or nil
local InvincibleOutside = not IS_LOBBY and require(RS.Game.Library.InvincibleOutside) or nil
local Crucifixes = not IS_LOBBY and require(RS.Game.Library.Crucifixes) or nil

local A = {
    Enabled = true, InstantPrompts = true, AutoMove = true, ReturnToControlRoom = true,
    Running = true, Actions = 0, LastAction = "Starting",
    LastError = nil, Log = {}, Verified = {}, AttackActive = false, FightingBack = false,
    CircleStats = {Hits = 0, Perfect = 0, Great = 0, Okay = 0, Misses = 0, Errors = 0},
    FightBackStats = {Presses = 0, Completed = 0}, TaserStats = {Shots = 0, Confirmed = 0},
    EmergencyStats = {PotionDodges = 0, HexEscapes = 0, ToadRecoveries = 0, ToadsSaved = 0, AltarLimbs = 0},
    UpgradeStats = {Attempts = 0, Purchased = 0}, HauntStats = {Attempts = 0, Confirmed = 0}, ColaStats = {Attempts = 0}, WitchPotions = {},
    BrainStats = {Hits = 0}, FingerprintStats = {Covered = 0, Total = 0, Reports = 0}, FireStats = {Pulses = 0, SafeMoves = 0, DamageEvents = 0, CellsRemaining = 0},
}
Env.AirportAuto = A
local connections, originals, lastSent = {}, {}, {}
local stages, memories, rooms, sessions, talks = {}, {}, {}, {}, {}
local Anomalies, Items = {}, {}
local lastMove = 0
local handleTaskEvent, dispatchTasks, workFirePrompts, workInterrogationPrompts, tickFightBack, tickAutoTaser, stockTaser, tickWitchSafety, workWitchResponse, workEmergencyPrompts, workUpgrades, tickStoryRead, workGhostEmergency, stockCrucifix
local firePositionUnsafe, escapeGroundFire, stopFireSpray, stockFireTool
local expandedEvent, expandedTick, expandedSync
local privateOverrides = {}
local function restorePrivate()
    for object, fields in privateOverrides do for key, value in fields do object[key] = value end end
    table.clear(privateOverrides)
end
local requests, emergencies, holds, altar = {}, {}, {}, {}
local supplyWait = {}
A.SupplyBlocked = {}
local Collection = game:GetService("CollectionService")
local taskState = "Watching for tasks"
local nativePromptHold
local function releaseNativeHold()
    local held = nativePromptHold
    nativePromptHold = nil
    if not held then return end
    pcall(function() held.prompt:InputHoldEnd() end)
    local record = originals[held.prompt]
    if record then
        record.nativeHold = false
        if held.prompt.Parent then held.prompt.HoldDuration = A.InstantPrompts and 0 or record.hold end
    end
end
local function cancelHolds()
    if stopFireSpray then stopFireSpray() end
    releaseNativeHold()
    for uid, record in holds do
        Remote:FireServer(record.finish, uid)
    end
    table.clear(holds)
end
local function finishExpiredHolds()
    local now = os.clock()
    if nativePromptHold and nativePromptHold.untilTime and now >= nativePromptHold.untilTime then releaseNativeHold() end
    for uid, record in holds do
        if now >= record.untilTime then
            holds[uid] = nil
            Remote:FireServer(record.finish, uid)
        end
    end
end
local HubWindow, masterToggle, softBlur, launcherFrame
local cursorCaptured = false
local savedMouseBehavior, savedMouseIcon
local function releaseMenuMouse()
    if not cursorCaptured then return end
    cursorCaptured = false
    if savedMouseBehavior then UIS.MouseBehavior = savedMouseBehavior end
    if savedMouseIcon ~= nil then UIS.MouseIconEnabled = savedMouseIcon end
end
A.Features = {Checkin = true, Luggage = true, BodyScan = true, Interrogations = true, TaskPrompts = true, Deliveries = true, Emergencies = true, Restock = true, AutoReplay = true, Story = true, Defense = true, Treatment = true, Collectibles = true, Mausoleum = true, FightBack = true, Taser = true, ColaAlways = true, WitchSafety = true, Upgrades = true, Haunt = true}

A.EmergencySupport = {BurningPassenger = true, DownedPassenger = true, FaintedPassenger = true,
    Possession = true, DemonAltar = true, Toad = true, WitchBrew = true, WitchHex = true,
    DaleMeltdown = true, RoomFire = true, Lockdown = true, Infections = true, GhostHaunt = true, PassengerRevive = true}
A.ServerTimeouts = {}
local function invokeServer(name, ...)
    local args = table.pack(...)
    local request = {done = false}
    local worker = task.spawn(function()
        setthreadidentity(8)
        request.result = table.pack(pcall(Functions.InvokeServer, Functions, name, table.unpack(args, 1, args.n)))
        request.done = true
    end)
    local deadline = os.clock() + 3
    while A.Running and not request.done and os.clock() < deadline do task.wait() end
    if not request.done then
        pcall(task.cancel, worker)
        A.ServerTimeouts[name] = (A.ServerTimeouts[name] or 0) + 1
        return nil, false
    end
    if not request.result[1] then A.LastError = tostring(request.result[2]); return nil, false end
    A.ServerTimeouts[name] = nil
    return request.result[2], true
end

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end

local function log(message)
    A.LastAction = message
    table.insert(A.Log, {time = os.clock(), message = message})
    if #A.Log > 60 then table.remove(A.Log, 1) end
end

local function send(key, cooldown, ...)
    if not A.Running or not A.Enabled then return false end
    local now = os.clock()
    if now - (lastSent[key] or -math.huge) < cooldown then return false end
    lastSent[key] = now
    Remote:FireServer(...)
    A.Actions += 1
    return true
end

local function npc(uid)
    local folder = workspace:FindFirstChild("Passengers")
    if folder then
        for _, model in folder:GetChildren() do
            if model:GetAttribute("NpcId") == uid then return model end
        end
    end
    return nil
end

local function anomaly(uid)
    local model = npc(uid)
    local id = model and model:GetAttribute("AnomalyId")
    if typeof(id) ~= "string" or id == "" or id == "None" or id == "Normal" then
        return false, nil
    end
    return true, Anomalies[id]
end

local function position(instance)
    if instance:IsA("Attachment") then return instance.WorldPosition end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Model") then return instance:GetPivot().Position end
    return nil
end

local function moveNear(target, radius)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not A.AutoMove or not root or not humanoid or humanoid.Health <= 0 then return end
    if (root.Position - target).Magnitude <= (radius or 7) then return end
    if os.clock() - lastMove < 0.25 then return end
    lastMove = os.clock()
    local offset = root.Position - target
    local flat = Vector3.new(offset.X, 0, offset.Z)
    local direction = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
    local destination = target + direction * math.clamp((radius or 7) * 0.4, 1, 4) + Vector3.new(0, 1.2, 0)
    if A.Features.Emergencies and firePositionUnsafe and firePositionUnsafe(destination) then
        taskState = "Avoiding ground fire"
        return
    end
    local hex = A.Features.WitchSafety and A.WitchHex
    if hex and typeof(hex.Center) == "Vector3" and workspace:GetServerTimeNow() < hex.EndsAt then
        local delta = destination - hex.Center
        if math.abs(delta.Y) < 12 and Vector2.new(delta.X, delta.Z).Magnitude < (tonumber(hex.Radius) or 10) + 4 then
            taskState = "Waiting outside the witch hex (" .. math.ceil(hex.EndsAt - workspace:GetServerTimeNow()) .. "s)"
            return
        end
    end
    character:PivotTo(CFrame.new(destination))
end

local function setInstant(prompt)
    if not prompt:IsA("ProximityPrompt") or originals[prompt] then return end
    local original = prompt.HoldDuration
    local record = {hold = original}
    originals[prompt] = record
    prompt.HoldDuration = 0
    record.connection = connect(prompt:GetPropertyChangedSignal("HoldDuration"), function()
        if A.Running and A.InstantPrompts and not record.nativeHold and prompt.HoldDuration ~= 0 then
            record.hold = prompt.HoldDuration
            prompt.HoldDuration = 0
        end
    end)
end

local function stop()
    if not A.Running then return end
    A.Running = false
    RunService:UnbindFromRenderStep("Miz0HubCursor")
    releaseMenuMouse()
    if launcherFrame then launcherFrame:Destroy(); launcherFrame = nil end
    cancelHolds()
    restorePrivate()
    pcall(function() writefile("Miz0Hub/enabled.txt", "0") end)
    for _, c in connections do c:Disconnect() end
    for prompt, record in originals do
        if prompt.Parent then pcall(function() prompt.HoldDuration = record.hold end) end
    end
    if softBlur then softBlur:Destroy(); softBlur = nil end
    if HubWindow then
        local window = HubWindow
        HubWindow = nil
        pcall(function() window:Destroy() end)
    end
    log("Stopped; prompt hold times restored")
    print("[AirportAuto] Stopped.")
end
A.Stop = stop
A.Pause = function() A.Enabled = false; cancelHolds(); restorePrivate(); log("Paused") end
A.Resume = function() A.Enabled = true; log("Resumed") end
if STATE and STATE.onCleanup then STATE.onCleanup(stop) end

-- Only inspect modules already loaded by the game; avoid requiring new server-only modules.
for i, module in getloadedmodules() do
    local group, id = module.Name:match("^(.-)%s*@%s*(.+)$")
    if group == "Anomalies" or group == "LuggageItems" then
        local ok, definition = pcall(require, module)
        if ok and type(definition) == "table" then
            if group == "Anomalies" then Anomalies[id] = definition else Items[id] = definition end
        end
    end
    if i % 100 == 0 then task.wait() end
end

local function rememberStage(payload)
    if type(payload) ~= "table" or not payload.InstanceId then return end
    local id = payload.InstanceId
    local key = payload.Side or payload.Track or "Main"
    stages[id] = stages[id] or {}
    if payload.Side and not payload.Choices then stages[id][key] = nil; return end
    stages[id][key] = payload
    local memory = memories[id]
    if not memory or memory.uid ~= payload.PassengerUid then
        memory = {uid = payload.PassengerUid, collected = {}}
        memories[id] = memory
    end
    for k, v in payload.Data or {} do memory[k] = v end
end

local roomNames = {BrainScan = "BrainScan", Fingerprint = "FingerprintScan", EyeExam = "EyeExam", LieDetector = "LieDetector"}
connect(Remote.OnClientEvent, function(name, payload, detail)
    setthreadidentity(8)
    if handleTaskEvent then handleTaskEvent(name, payload) end
    if expandedEvent then expandedEvent(name, payload) end
    if name == "AnomalyAttackView" or name == "VentGrabView" then
        A.AttackActive = true
        A.Attacker = typeof(payload) == "Instance" and (payload:FindFirstAncestorOfClass("Model") or payload) or nil
        A.AttackStartedAt = os.clock()
        cancelHolds()
        restorePrivate()
        if tickFightBack then pcall(tickFightBack) end
    elseif name == "AnomalyAttackViewEnd" or name == "VentGrabViewEnd" then
        A.AttackActive = false
        A.Attacker = nil
        A.FightingBack = false
    elseif name == "WitchPotion" and type(payload) == "table" and typeof(payload.To) == "Vector3"
        and type(payload.At) == "number" and type(payload.Seconds) == "number" then
        table.insert(A.WitchPotions, {center = payload.To, impact = payload.At + payload.Seconds})
    elseif name == "WitchHex" and type(payload) == "table" then
        if payload.Phase == "Dark" and typeof(payload.Center) == "Vector3" and type(payload.EndsAt) == "number" then
            A.WitchHex = payload
        elseif payload.Phase == "End" then A.WitchHex = nil end
    elseif name == "ToadEnded" and type(payload) == "table" and payload.Saved == true then
        A.EmergencyStats.ToadsSaved += 1
        A.Verified.Toad = (A.Verified.Toad or 0) + 1
        if A.Coverage and A.Coverage.Toad then A.Coverage.Toad.confirmed += 1 end
    elseif name == "WallTaserState" and type(payload) == "table" then
        A.WallTaserState = payload
    elseif (name == "Electrocute" and A.PendingTaser and payload == A.PendingTaser.target)
        or (name == "TaserBeam" and A.PendingTaser and detail == A.PendingTaser.target) then
        A.PendingTaser.nativeConfirmed = true
    elseif name == "WallExtinguisherState" and type(payload) == "table" then
        A.WallExtinguisherState = payload
    elseif name == "LieDetectorProgress" and type(payload) == "table" and payload.Missed == true then
        A.CircleStats.Misses += 1
    end
    if name == "StationStage" or name == "StationSide" then
        rememberStage(payload)
    elseif name == "StationClear" and type(payload) == "table" then
        stages[payload.InstanceId] = nil
        memories[payload.InstanceId] = nil
    elseif name == "InterrogationTalkPrompt" and type(payload) == "table" then
        talks[payload.Uid] = true
    elseif name == "InterrogationTalked" and type(payload) == "table" then
        talks[payload.Uid] = nil
    end
    for prefix in roomNames do
        if name == prefix .. "Armed" then rooms[prefix] = payload
        elseif name == prefix .. "Disarmed" then rooms[prefix] = nil; sessions[prefix] = nil
        elseif name == prefix .. "State" and type(payload) == "table" then
            rooms[prefix] = rooms[prefix] or {}
            for k, v in payload do rooms[prefix][k] = v end
        elseif name == prefix .. "Begin" and type(payload) == "table" then
            sessions[prefix] = table.clone(payload)
            sessions[prefix].started = os.clock()
        elseif name == prefix .. "Complete" then
            sessions[prefix] = nil
            if rooms[prefix] then rooms[prefix].Finishing = true end
            A.Verified[prefix] = (A.Verified[prefix] or 0) + 1
            log(prefix .. " completed")
        elseif name == prefix .. "Stop" or name == prefix .. "CrashOut" then
            sessions[prefix] = nil
        end
    end
end)

connect(workspace.DescendantAdded, function(instance)
    if A.InstantPrompts then setInstant(instance) end
end)
for i, instance in workspace:GetDescendants() do
    if instance:IsA("ProximityPrompt") then setInstant(instance) end
    if i % 1500 == 0 then task.wait() end
end
connect(PPS.PromptButtonHoldBegan, function(prompt)
    if A.Running and A.InstantPrompts and prompt.Enabled and not (originals[prompt] and originals[prompt].nativeHold) then
        prompt.HoldDuration = 0
        pcall(fireproximityprompt, prompt)
    end
end)
connect(UIS.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        A.Enabled = not A.Enabled
        if not A.Enabled then cancelHolds(); restorePrivate() end
        if masterToggle then masterToggle:Set(A.Enabled) end
        log(A.Enabled and "Resumed" or "Paused")
        print("[AirportAuto] " .. A.LastAction)
    elseif input.KeyCode == Enum.KeyCode.End then stop() end
end)

local function contraband(memory)
    for _, entry in memory.Contents or {} do
        local definition = Items[entry.ItemId]
        if definition and definition.Contraband == true then return true end
    end
    return false
end

local function workStation(id, payload)
    if payload.StationType == "Checkin" and not A.Features.Checkin then return end
    if payload.StationType == "Conveyor" then
        local luggage = payload.Track == "Luggage" or payload.Side == "Inspection"
        if luggage and not A.Features.Luggage then return end
        if not luggage and not A.Features.BodyScan then return end
    end
    local stage = payload.Side or payload.Stage
    local memory = memories[id] or {}
    local bad, definition = anomaly(payload.PassengerUid or memory.uid)
    local channel = definition and definition.Channel
    local choice
    if payload.Choices then
        if stage == "LuggageDecision" then
            choice = (memory.ScanError or contraband(memory) or (bad and channel == "Luggage")) and "Search" or "Pass"
        elseif stage == "BodyDecision" then
            choice = bad and channel ~= "Luggage" and "Deny" or "Approve"
        elseif stage == "Inspection" then
            choice = contraband(memory) and "Deny" or "Approve"
        else
            return
        end
        local exists = false
        for _, item in payload.Choices do if item.Id == choice then exists = true end end
        if not exists then return end
    elseif not payload.ActionText then
        return
    end
    local key = id .. ":" .. tostring(payload.PassengerUid) .. ":" .. tostring(stage)
    if send(key, 0.85, "StationInteract", id, stage, choice) then
        log(id .. " / " .. tostring(stage) .. (choice and (" / " .. choice) or ""))
    end
    if stage == "Inspection" and choice == "Deny" then
        -- Server owns the inspection verdict. Do not remove ordinary possessions.
        A.LastDecision = "Contraband detected"
    end
end

-- Reuse live session data to align hits with the game's own timing.
local registry = debug.getupvalue(Network.Fired, 1)
local function sessionFrom(eventName, predicate)
    if type(registry) ~= "table" then return end
    for _, callback in registry[eventName] or {} do
        for _, value in debug.getupvalues(callback) do
            if type(value) == "table" and predicate(value) then return value end
        end
    end
    return nil
end


-- Resolve through the active controller, so a stale heap match cannot pick
-- a resolver belonging to a different copy of the minigame.
local function functionUpvalue(parent, name)
    if type(parent) ~= "function" then return nil end
    for _, value in debug.getupvalues(parent) do
        if type(value) == "function" and debug.info(value, "n") == name then return value end
    end
    return nil
end
local function nativeFingerprintSession()
    for _, callback in registry.FingerprintComplete or {} do
        local finish = functionUpvalue(callback, "endSession")
        if finish then
            for _, value in debug.getupvalues(finish) do
                if type(value) == "table" and type(value.Points) == "table" and type(value.Covered) == "number" then
                    return value
                end
            end
        end
    end
    return nil
end
local function nativeSession(prefix)
    if prefix == "Fingerprint" then return nativeFingerprintSession() end
    if prefix == "BrainScan" then return sessionFrom("BrainScanBoard", function(v) return v.Phase ~= nil and v.TargetX ~= nil end) end
    if prefix == "LieDetector" then return sessionFrom("LieDetectorProgress", function(v) return type(v.Circles) == "table" end) end
    if prefix == "EyeExam" then return sessionFrom("EyeExamComplete", function(v) return v.PupilDir ~= nil and v.Aim ~= nil end) end
    return nil
end

local fingerprintSession, fingerprintPainter, fingerprintOverlay
local function tickFingerprint()
    if not A.Features.Interrogations or A.AttackActive then return end
    local current = nativeFingerprintSession()
    if not current then return end
    if not sessions.Fingerprint then sessions.Fingerprint = {Uid = current.Uid, started = os.clock(), OpensAt = current.OpensAt} end
    if current ~= fingerprintSession then
        fingerprintSession = current
        fingerprintPainter, fingerprintOverlay = nil, nil
        for _, callback in registry.FingerprintBegin or {} do
            local begin = functionUpvalue(callback, "beginSession")
            local trace = functionUpvalue(begin, "stepTrace")
            if trace then
                fingerprintPainter = functionUpvalue(trace, "makeDot")
                for _, value in debug.getupvalues(trace) do
                    if typeof(value) == "Instance" and value:IsA("ScreenGui") then
                        local frame = value:FindFirstChild("FingerprintFrame")
                        fingerprintOverlay = frame and frame:FindFirstChild("TraceOverlay")
                    end
                end
            end
        end
        A.FingerprintStats = {Covered = current.Covered, Total = current.Total or #current.Points, Reports = 0}
    end
    if not current.Accepting or workspace:GetServerTimeNow() < (current.OpensAt or math.huge) then return end
    local total = current.Total or #current.Points
    if total <= 0 then return end
    local interval = current.Covered >= total and 0.25 or 0.08
    if os.clock() - (lastSent["finger:trace"] or -math.huge) < interval then return end
    -- Native tracing can cover multiple points per report. Scale the batch to
    -- the actual print, and finish before this session's server deadline.
    local remainingTime = math.max(0.2, (current.Deadline or (workspace:GetServerTimeNow() + 8)) - workspace:GetServerTimeNow() - 0.5)
    local steps = math.max(1, math.min(40, math.floor(remainingTime / interval)))
    local batch = math.max(1, math.ceil((total - current.Covered) / steps), math.ceil(total / 40))
    local added = 0
    for _, point in current.Points do
        if not point.Covered then
            point.Covered = true
            current.Covered += 1
            added += 1
            if point.Hint then point.Hint:Destroy(); point.Hint = nil end
            if fingerprintPainter and fingerprintOverlay and fingerprintOverlay.Parent then
                pcall(fingerprintPainter, point.At, Color3.new(1, 1, 1), fingerprintOverlay)
            end
            if added >= batch then break end
        end
    end
    current.ReportClock = 0
    current.MissClock = 0
    if current.Covered >= total then current.Frozen = true end
    if send("finger:trace", interval, "FingerprintTracePoint", "FingerprintScan", current.Covered) then
        A.FingerprintStats.Covered = current.Covered
        A.FingerprintStats.Total = total
        A.FingerprintStats.Reports += 1
    end
    taskState = "Fingerprint: " .. current.Covered .. "/" .. total .. (current.Frozen and " — confirming" or "")
end

local function activeLieResolver()
    for _, callback in registry.LieDetectorBegin or {} do
        local beginSession = functionUpvalue(callback, "beginSession")
        local stepCircles = functionUpvalue(beginSession, "stepCircles")
        local resolver = functionUpvalue(stepCircles, "resolveCircle")
        if resolver then return resolver end
    end
    return nil
end
local lieSession, lieResolver
local nextResolverLookup = 0
local function tickLieCircles()
    if not A.Features.Interrogations or A.AttackActive then return end
    local current = sessionFrom("LieDetectorProgress", function(v) return type(v.Circles) == "table" end)
    if not current or not current.Accepting then return end
    if current ~= lieSession then
        lieSession = current
        lieResolver = activeLieResolver()
        nextResolverLookup = os.clock() + 1
    elseif not lieResolver and os.clock() >= nextResolverLookup then
        lieResolver = activeLieResolver()
        nextResolverLookup = os.clock() + 1
    end
    if type(lieResolver) ~= "function" then
        A.LastError = "Lie detector: active circle resolver is unavailable"
        return
    end
    if not sessions.LieDetector then
        sessions.LieDetector = {Uid = current.Uid, started = os.clock()}
    end
    -- Run every frame. The previous 60 ms polling could skip fast circles.
    -- Use the game's real judgment windows; recover a late frame with a
    -- valid Great/Okay hit instead of leaving the circle to expire.
    for index = #current.Circles, 1, -1 do
        local circle = current.Circles[index]
        local scale = circle and circle.Scale
        if circle and not circle.Resolved and type(scale) == "number" and scale <= 1 and scale >= 0.6 then
            local verdict = scale >= 0.8 and "Perfect" or (scale >= 0.7 and "Great" or "Okay")
            local ok, problem = pcall(lieResolver, current, circle, verdict)
            if ok then
                A.Actions += 1
                A.CircleStats.Hits += 1
                A.CircleStats[verdict] += 1
                A.CircleStats.LastScale = scale
                A.CircleStats.LastVerdict = verdict
                taskState = "Lie detector: " .. verdict .. " circle"
            else
                A.CircleStats.Errors += 1
                A.LastError = "Lie detector: " .. tostring(problem)
            end
        end
    end
end

local function tickBrainScan()
    if not A.Features.Interrogations or A.AttackActive then return end
    local current = sessionFrom("BrainScanBoard", function(v) return type(v.Phase) == "number" and type(v.TargetX) == "number" end)
    if not current or not current.Accepting or current.TargetTween then return end
    if not sessions.BrainScan then sessions.BrainScan = {Uid = current.Uid, started = os.clock()} end
    local phase = current.Phase <= 1 and current.Phase or 2 - current.Phase
    if math.abs(phase - current.TargetX) <= (current.TargetSize or 0.1) * 0.48 then
        if send("brain:hit", 0.2, "BrainScanHit", "BrainScan") then
            A.BrainStats.Hits += 1
            A.BrainStats.LastPhase = phase
            A.BrainStats.LastTarget = current.TargetX
            taskState = "Brain scan: target matched"
        end
    end
end

local fightTimers = setmetatable({}, {__mode = "k"})
local fightPrompt
local fightPromptCompleted = false
tickFightBack = function()
    A.FightingBack = false
    if fightPrompt and fightPrompt.Parent and not fightPromptCompleted and fightPrompt:GetAttribute("MashComplete") == true then
        fightPromptCompleted = true
        A.FightBackStats.Completed += 1
        A.FightBackStats.LastEscapeSeconds = A.AttackStartedAt and (os.clock() - A.AttackStartedAt) or nil
        A.FightBackStats.LastResult = "Escaped"
        local entry = A.Coverage and A.Coverage.FightBack
        if entry then entry.confirmed += 1 end
    end
    if not A.Features.FightBack then return end
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        A.AttackActive = false
        A.Attacker = nil
        return
    end
    local best, bestScore = nil, math.huge
    for prompt in originals do
        if prompt.Parent and prompt.Enabled then
            local action = prompt.ActionText:lower():gsub("<.->", ""):gsub("[^%w]", "")
            local named = action:find("fightback", 1, true) or action:find("struggle", 1, true) or action:find("breakfree", 1, true)
            local attachedToAttack = prompt:IsDescendantOf(character) or (A.Attacker and prompt:IsDescendantOf(A.Attacker))
            local grabbedMash = A.AttackActive and attachedToAttack and prompt:GetAttribute("MashPrompt") == true
            if named or grabbedMash then
                local target = position(prompt.Parent)
                if target then
                    local distance = (root.Position - target).Magnitude
                    if distance <= prompt.MaxActivationDistance then
                        local score = distance + (named and 0 or 1000)
                        if score < bestScore then best = prompt; bestScore = score end
                    end
                end
            end
        end
    end
    if not best then return end
    A.FightingBack = true
    if stopFireSpray then stopFireSpray() end
    if nativePromptHold then releaseNativeHold() end
    if best ~= fightPrompt then fightPrompt = best; fightPromptCompleted = false end
    local interval = math.max(1 / 60, tonumber(best:GetAttribute("MashDebounce")) or 0.12) + 0.005
    local now = os.clock()
    if now - (fightTimers[best] or -math.huge) >= interval then
        fightTimers[best] = now
        local ok, problem = pcall(fireproximityprompt, best)
        if ok then
            A.Actions += 1
            A.FightBackStats.Presses += 1
            taskState = "Fighting back against the anomaly"
        else A.LastError = "Fight back: " .. tostring(problem) end
    end
end
connect(Player.CharacterAdded, function()
    A.Attacker = nil
    A.AttackActive = false
    A.FightingBack = false
    fightPrompt = nil
    A.Tasing = false
    A.PendingTaser = nil
end)
connect(RunService.Heartbeat, function()
    if not A.Running or not A.Enabled or IS_LOBBY then return end
    setthreadidentity(8)
    local ok, problem = pcall(function()
        finishExpiredHolds()
        tickFightBack()
        if not A.AttackActive and not A.FightingBack and escapeGroundFire then escapeGroundFire() end
        if tickWitchSafety then tickWitchSafety() end
        if tickStoryRead then tickStoryRead() end
        if tickAutoTaser then tickAutoTaser() end
        if not A.AttackActive and not A.FightingBack and not A.Tasing then
            tickLieCircles()
            tickBrainScan()
            tickFingerprint()
        end
    end)
    if not ok then A.LastError = "Frame automation: " .. tostring(problem) end
end)

local function ownedItem(id)
    for _, container in {Player.Character, Player:FindFirstChildOfClass("Backpack")} do
        if container then
            for _, tool in container:GetChildren() do
                if tool:IsA("Tool") and (tool:GetAttribute("ItemId") == id or tool.Name == id
                    or (id == "Crucifix" and Crucifixes and Crucifixes.Is(tool:GetAttribute("ItemId")) and Crucifixes.IsReady(tool))) then
                    return tool
                end
            end
        end
    end
    return nil
end

local function equip(tool)
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and tool and tool.Parent ~= character then humanoid:EquipTool(tool) end
end

local function freeHandsForFire()
    local character = Player.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if tool and Extinguishers and Extinguishers.Is(tool:GetAttribute("ItemId")) then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:UnequipTools() end
        return false
    end
    return true
end

local function closeEnough(target, distance)
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    return root and (root.Position - target).Magnitude <= (distance or 8)
end

local function obtain(id)
    local tool = ownedItem(id)
    if tool then supplyWait[id] = nil; A.SupplyBlocked[id] = nil; return tool end
    local now = os.clock()
    if A.SupplyBlocked[id] and now < A.SupplyBlocked[id] then return nil end
    if A.SupplyBlocked[id] then A.SupplyBlocked[id] = nil; supplyWait[id] = nil end
    supplyWait[id] = supplyWait[id] or now
    if now - supplyWait[id] > 12 then
        A.SupplyBlocked[id] = now + 10
        taskState = id .. " unavailable; retrying later"
        return nil
    end
    if not A.Features.Restock or next(sessions) then return nil end
    local candidate, target, best = nil, nil, math.huge
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    -- Snack prompts live on Terrain attachments. TakePrompt points to the exact prompt.
    for _, model in Collection:GetTagged("InterrogationItem") do
        if model:GetAttribute("Id") == id and model.Parent then
            local reference = model:FindFirstChild("TakePrompt")
            local prompt = reference and reference:IsA("ObjectValue") and reference.Value
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Parent then
                local pos = position(prompt.Parent)
                if pos then
                    local distance = (root.Position - pos).Magnitude
                    local score = distance + (prompt.Enabled and 0 or 10000)
                    if score < best then candidate, target, best = prompt, pos, score end
                end
            end
        end
    end
    -- Reusable tools are obtained from the game's own wall supply prompts.
    if not candidate then
        local things = workspace:FindFirstChild("__THINGS")
        local tag = ({Medkit = "WallMedkit", Crucifix = "WallCrucifix", Disinfectant = "WallDisinfectant", Cola = "MiniFridge", ["Wall Taser"] = "WallTaser"})[id]
        local walls = tag and Collection:GetTagged(tag) or {}
        local fallback = things and things:FindFirstChild(id == "Cola" and "MiniFridge" or id)
        if #walls == 0 and fallback then walls = {fallback} end
        for _, wall in walls do
            for _, item in wall:GetDescendants() do
                if item:IsA("ProximityPrompt") and string.find(string.lower(item.ActionText), "take", 1, true) then
                    local pos = position(item.Parent)
                    if pos then
                        local score = (root.Position - pos).Magnitude + (item.Enabled and 0 or 10000)
                        if score < best then candidate, target, best = item, pos, score end
                    end
                end
            end
        end
    end
    if candidate and target then
        if not closeEnough(target, candidate.MaxActivationDistance - 1) then
            moveNear(target, math.max(2, candidate.MaxActivationDistance * 0.6))
            taskState = "Collecting " .. id
        elseif candidate.Enabled then
            local key = "supply:" .. id
            if os.clock() - (lastSent[key] or -math.huge) > 0.35 then
                lastSent[key] = os.clock()
                candidate.HoldDuration = A.InstantPrompts and 0 or candidate.HoldDuration
                pcall(fireproximityprompt, candidate)
                taskState = "Picking up " .. id
            end
        else
            taskState = id .. " supply is unavailable"
        end
    else
        taskState = "Waiting for " .. id .. " supply"
    end
    return nil
end
A.CollectItem = obtain

-- Use the native TaserFire payload and cooldown. Only hostile NPCs, awake
-- vents and visible ghosts are considered; other players are never targets.
local Taser = {nextStock = 0, scanAt = 0}
local function ownedTaser()
    for _, id in {"Wall Taser", "Taser", "Super Taser"} do
        local tool = ownedItem(id)
        local count = tool and tonumber(tool:GetAttribute("Count"))
        if tool and (not count or count > 0) then return tool end
    end
    return nil
end
local function taserTarget(root)
    local candidates = {}
    local function consider(model, kind, id, part)
        if not model.Parent or not part or not part:IsA("BasePart")
            or model:GetAttribute("Dead") or model:GetAttribute("Tased") or model:GetAttribute("Invulnerable")
            or model:GetAttribute("Toad") == true then return end
        local distance = (root.Position - part.Position).Magnitude
        if distance <= 12 and (not InvincibleOutside or not InvincibleOutside.Contains(part.Position)) then
            table.insert(candidates, {target = model, kind = kind, id = id, position = part.Position, distance = distance})
        end
    end
    local passengers = workspace:FindFirstChild("Passengers")
    if passengers then
        for _, model in passengers:GetChildren() do
            if model:IsA("Model") and (model:GetAttribute("MonsterForm") == true or model:GetAttribute("WitchFlying") == true) then
                local id = model:GetAttribute("NpcId")
                if type(id) == "string" then consider(model, "Npc", id, model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) end
            end
        end
    end
    for _, model in Collection:GetTagged("Vent") do
        if model:IsA("Model") and model:GetAttribute("Awake") == true then
            consider(model, "Vent", model, model:FindFirstChild("Detect"))
        end
    end
    local ghosts = workspace:FindFirstChild("Ghosts")
    if ghosts and not (A.Features.Haunt and ownedItem("Crucifix")) then
        for _, model in ghosts:GetChildren() do
            if model:IsA("Model") and model:GetAttribute("GhostVisible") == true then
                local id = model:GetAttribute("GhostId")
                if type(id) == "string" then consider(model, "Ghost", id, model:FindFirstChild("HumanoidRootPart")) end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {Player.Character}
    params.IgnoreWater = true
    local origin = root.Position + Vector3.new(0, 1, 0)
    for _, candidate in candidates do
        local hit = workspace:Raycast(origin, candidate.position - origin, params)
        if not hit or hit.Instance:IsDescendantOf(candidate.target) then return candidate end
    end
    return nil
end
tickAutoTaser = function()
    local now = os.clock()
    local pending = A.PendingTaser
    if pending then
        if not pending.counted and (pending.nativeConfirmed or
            (pending.target.Parent and pending.target:GetAttribute("Tased") == true)) then
            pending.counted = true
            A.TaserStats.Confirmed += 1
            A.TaserStats.LastResult = "Hit confirmed"
            A.Verified.Taser = (A.Verified.Taser or 0) + 1
            if A.Coverage and A.Coverage.Taser then A.Coverage.Taser.confirmed += 1 end
        end
        if now - pending.at > 4 then A.PendingTaser = nil end
    end
    if not A.Features.Taser or IS_LOBBY or Player:GetAttribute("OperatingMinigame") then A.Tasing = false; return end
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 or character:GetAttribute("Tased") or character:GetAttribute("Toad") == true then A.Tasing = false; return end
    if now < Taser.scanAt then return end
    Taser.scanAt = now + 0.08
    A.Tasing = false
    local tool = ownedTaser()
    if not tool then return end
    local target = taserTarget(root)
    if not target then return end
    A.Tasing = true
    cancelHolds()
    if tool.Parent ~= character then
        equip(tool)
        Taser.equippedAt = now
        taskState = "Equipping taser against an anomaly"
        return
    end
    if Taser.equippedAt and now - Taser.equippedAt < 0.15 then return end
    if now - (lastSent["taser:fire"] or -math.huge) < 2.05 then return end
    A.PendingTaser = {target = target.target, kind = target.kind, id = target.id, at = now}
    if send("taser:fire", 2.05, "TaserFire", {Kind = target.kind, Id = target.id}) then
        A.TaserStats.Shots += 1
        A.TaserStats.LastTarget = target.kind .. ": " .. tostring(target.id)
        A.TaserStats.LastResult = "Shot sent; waiting for confirmation"
        taskState = "Tasing a hostile anomaly"
        log("Taser fired at " .. target.kind)
    end
end
stockTaser = function()
    if ownedTaser() then Taser.prepAt = nil; return false end
    if not A.Features.Taser or not A.Features.Restock or A.AttackActive
        or os.clock() < Taser.nextStock then return false end
    local now = os.clock()
    local state = A.WallTaserState
    if state then
        local cooldown = tonumber(state.CooldownEndTime)
        if cooldown and cooldown > workspace:GetServerTimeNow() then
            Taser.nextStock = now + math.min(30, cooldown - workspace:GetServerTimeNow())
            A.TaserStats.LastResult = "Wall taser is recharging"
            return false
        end
        if state.HolderUserId and state.HolderUserId ~= Player.UserId then
            Taser.nextStock = now + 5
            return false
        end
    end
    Taser.prepAt = Taser.prepAt or now
    local tool = obtain("Wall Taser")
    if tool then Taser.prepAt = nil; A.TaserStats.LastResult = "Taser ready"; return false end
    if A.SupplyBlocked["Wall Taser"] or now - Taser.prepAt > 3 then
        Taser.prepAt = nil
        Taser.nextStock = A.SupplyBlocked["Wall Taser"] or (now + 5)
        return false
    end
    taskState = "Collecting the wall taser"
    return true
end

local function newRequest(uid, items, remote, kind)
    if type(uid) ~= "string" or type(items) ~= "table" then return end
    local existing = requests[uid]
    if existing and existing.remote == remote then return end
    requests[uid] = {items = table.clone(items), checked = {}, remote = remote, kind = kind,
        created = os.clock(), lastProgress = os.clock()}
    log("Requested: " .. table.concat(items, ", "))
end

handleTaskEvent = function(name, payload)
    if name == "InterrogationAsk" and type(payload) == "table" then
        newRequest(payload.Uid, payload.Items, "InterrogationGive", "Interrogation")
    elseif name == "InterrogationItemChecked" and type(payload) == "table" then
        local request = requests[payload.Uid]
        if request then
            request.checked[payload.Index] = true
            request.lastProgress = os.clock()
            log("Delivered snack " .. tostring(payload.Index))
        end
    elseif (name == "InterrogationItemsDone" or name == "InterrogationEnd") and type(payload) == "table" then
        requests[payload.Uid] = nil
    elseif name == "DaleAsk" and type(payload) == "table" and type(payload.Item) == "string" then
        newRequest(payload.Uid, {payload.Item}, "DaleGive", "Dale")
    elseif name == "DaleAskDone" or name == "DaleAskEnd" then
        for uid, request in requests do if request.kind == "Dale" then requests[uid] = nil end end
    elseif name == "EmergencyStarted" and type(payload) == "table" then
        emergencies[payload.Uid] = payload
    elseif name == "EmergencyEnded" and type(payload) == "table" then
        emergencies[payload.Uid] = nil
        local held = holds[payload.Uid]
        if held then Remote:FireServer(held.finish, payload.Uid); holds[payload.Uid] = nil end
        altar[payload.Uid] = nil
        A.LastEmergencyOutcome = {Uid = payload.Uid, Outcome = payload.Outcome}
        if payload.Outcome == "Resolved" then
            A.Verified.Emergencies = (A.Verified.Emergencies or 0) + 1
        else
            log("Emergency ended: " .. tostring(payload.Outcome))
        end
    elseif name == "DemonAltarPrompts" and type(payload) == "table" then
        altar[payload.Uid] = payload
    elseif name == "DemonAltarLimbFreed" and type(payload) == "table" then
        A.EmergencyStats.AltarLimbs += 1
        local record = altar[payload.Uid]
        if record then
            for index, limb in record.Limbs do if limb == payload.Limb then table.remove(record.Limbs, index); break end end
        end
    elseif name == "PhoneRing" then
        send("phone:answer", 2, "PhoneAnswer")
    end
end

local function startHold(uid, beginName, finishName, seconds)
    if not holds[uid] then
        if send("hold:" .. uid, 1, beginName, uid) then
            holds[uid] = {finish = finishName, untilTime = os.clock() + seconds}
        end
    end
end

local function deferEmergencySupply(record, id, tool)
    if tool then record.supplyAt = nil; return false end
    if A.SupplyBlocked[id] then record.retryAt = A.SupplyBlocked[id]; record.supplyAt = nil; return true end
    record.supplyAt = record.supplyAt or os.clock()
    if os.clock() - record.supplyAt > 2 then
        record.supplyAt = nil
        record.retryAt = os.clock() + 2
        return true
    end
    return false
end

dispatchTasks = function()
    if next(sessions) then return false end
    for uid, held in holds do
        if os.clock() >= held.untilTime then
            Remote:FireServer(held.finish, uid)
            holds[uid] = nil
        end
    end
    if A.Features.Emergencies then
        local ordered = {}
        for uid, emergency in emergencies do table.insert(ordered, {uid = uid, data = emergency}) end
        table.sort(ordered, function(a, b) return (a.data.Deadline or math.huge) < (b.data.Deadline or math.huge) end)
        for _, entry in ordered do
            local uid, emergency = entry.uid, entry.data
            if emergency.retryAt and os.clock() < emergency.retryAt then continue end
            local model = npc(uid)
            local target = model and position(model)
            if target and (not emergency.Deadline or emergency.Deadline > workspace:GetServerTimeNow()) then
                if emergency.Id == "BurningPassenger" then
                    if not freeHandsForFire() then taskState = "Preparing to put out the fire"; return true end
                    moveNear(target)
                    if closeEnough(target, 9) then startHold(uid, "BurningExtinguishBegin", "BurningExtinguishEnd", 6.2) end
                    taskState = "Putting out a burning passenger"
                    return true
                elseif emergency.Id == "DownedPassenger" or emergency.Id == "FaintedPassenger" then
                    local tool = obtain("Medkit")
                    if deferEmergencySupply(emergency, "Medkit", tool) then continue end
                    if tool then
                        equip(tool)
                        moveNear(target)
                        if closeEnough(target, 9) then startHold(uid, "MedkitReviveBegin", "MedkitReviveEnd", 3.2) end
                        taskState = "Reviving a passenger"
                    end
                    return true
                elseif model:GetAttribute("Possessed") == true then
                    local tool = obtain("Crucifix")
                    if deferEmergencySupply(emergency, "Crucifix", tool) then continue end
                    if tool then
                        equip(tool)
                        moveNear(target)
                        if closeEnough(target, 9) then send("exorcise:" .. uid, 1.2, "CrucifixUse", {Id = uid}) end
                        taskState = "Exorcising a passenger"
                    end
                    return true
                end
            end
        end
        for uid, record in altar do
            local model = npc(uid)
            local target = model and position(model)
            if target and #record.Limbs > 0 then
                moveNear(target)
                if closeEnough(target, 9) then
                    local limb = record.Limbs[1]
                    send("limb:" .. uid .. ":" .. limb, 1.0, "DemonAltarFreeLimb", {Uid = uid, Limb = limb})
                end
                taskState = "Freeing a passenger from the altar"
                return true
            end
        end
    end
    if A.Features.Deliveries then
        for uid, request in requests do
            if request.retryAt and os.clock() < request.retryAt then continue end
            local model = request.target or (request.targetProvider and request.targetProvider()) or npc(uid)
            if not model or not model.Parent then
                if os.clock() - request.created > 25 then requests[uid] = nil end
            else
                for index, id in request.items do
                    if not request.checked[index] then
                        local tool = obtain(id)
                        if not tool and A.SupplyBlocked[id] then request.retryAt = A.SupplyBlocked[id]; return false end
                        if tool then
                            equip(tool)
                            local target = position(model)
                            if target then
                                moveNear(target)
                                if closeEnough(target, 9) then
                                    if send("give:" .. uid .. ":" .. index, 0.45, request.remote, uid) then
                                        log("Giving " .. id .. " to " .. tostring(model:GetAttribute("DisplayName") or uid))
                                    end
                                    taskState = "Delivering " .. id .. " (" .. index .. "/" .. #request.items .. ")"
                                end
                            end
                        end
                        return true
                    end
                end
                requests[uid] = nil
            end
        end
    end
    taskState = "Watching for tasks"
    return false
end

-- Restore delivery requests already shown before this script was started.
local function recoverDeliveries()
    if type(registry) ~= "table" then return end
    local iconToId = {}
    local catalog = require(RS.Game.Library.Directory.Items)
    for id, definition in catalog do
        if type(definition) == "table" and definition.Icon then iconToId[definition.Icon] = id end
    end
    for _, callback in registry.InterrogationAsk or {} do
        local records = debug.getupvalue(callback, 1)
        if type(records) == "table" then
            for uid, record in records do
                if type(record) == "table" and record.Rows and not requests[uid] then
                    local items, checked = {}, {}
                    for index, row in record.Rows do
                        local image = row:FindFirstChild("ItemImage")
                        local check = row:FindFirstChild("Check")
                        local id = image and iconToId[image.Image]
                        if id then items[index] = id; checked[index] = check and check.Visible or false end
                    end
                    if #items > 0 then
                        newRequest(uid, items, "InterrogationGive", "Interrogation")
                        requests[uid].checked = checked
                    end
                end
            end
        end
    end
end

local function workMinigames()
    if not A.Features.Interrogations or nativePromptHold or next(holds) then return end
    local preparing = false
    for prefix, room in rooms do
        if not next(sessions) and not Player:GetAttribute("OperatingMinigame")
            and room.Uid and not room.Finishing and
            (not room.OperatorUserId or room.OperatorUserId == Player.UserId) and not sessions[prefix] then
            local action
            if prefix == "BrainScan" then action = room.Stage == "Computer" and "BrainScanStart" or "BrainScanLever"
            elseif prefix == "Fingerprint" then action = room.Stage == "Scanner" and "FingerprintStart" or "FingerprintPlug"
            elseif prefix == "EyeExam" then action = room.Stage == "Computer" and "EyeExamStart" or "EyeExamSetup"
            elseif prefix == "LieDetector" then action = "LieDetectorStart" end
            if action then
                local folder = workspace:FindFirstChild("InterrogationRooms")
                folder = folder and folder:FindFirstChild(room.Folder or roomNames[prefix])
                local prompt
                if folder then
                    for _, candidate in folder:GetDescendants() do
                        if candidate:IsA("ProximityPrompt") and candidate.Enabled
                            and not Collection:HasTag(candidate, "RoomFirePrompt")
                            and candidate.ActionText ~= "Put Out" then
                            prompt = candidate
                            break
                        end
                    end
                end
                local target = prompt and position(prompt.Parent)
                if target then
                    local distance = math.max(2, prompt.MaxActivationDistance - 0.5)
                    if not closeEnough(target, distance) then
                        moveNear(target, math.max(2, distance * 0.6))
                    else
                        send(prefix .. ":setup:" .. action .. ":" .. tostring(room.Stage), 0.45, action, roomNames[prefix])
                    end
                    taskState = "Preparing " .. prefix .. ": " .. prompt.ActionText
                else
                    taskState = "Waiting for the " .. prefix .. " interaction"
                end
                preparing = true
                break
            end
        end
    end
    -- Brain Scan and Lie Detector timing run on the frame callback.
    -- Lie detector circles are handled by the frame callback above.
    local eye = sessionFrom("EyeExamComplete", function(v) return v.PupilDir ~= nil and v.Aim ~= nil end)
    if eye and eye.Accepting and eye.BoxCamera and eye.EyeRadius and eye.Tuning then
        if not privateOverrides[eye.Tuning] then
            privateOverrides[eye.Tuning] = {AimResponse = eye.Tuning.AimResponse}
        end
        eye.Tuning.AimResponse = math.huge
        local direction = eye.PupilDir
        local camera = eye.BoxCamera
        eye.Aim = Vector2.new(direction:Dot(camera.RightVector), direction:Dot(camera.UpVector)) * eye.EyeRadius
        taskState = "Eye exam: following the pupil"
    end
    -- Fingerprint tracing runs independently on the frame callback.
    return preparing or next(sessions) ~= nil
end

local taskWords = {
    "interrogate", "start test", "start scan", "plug", "connect", "pull lever",
    "repair", "extinguish", "banish", "free limb", "scan passenger",
    "answer phone", "next shift", "start shift", "start boarding", "board passengers", "hear him out", "read letter",
    "free left", "free right", "free arm", "free leg", "turn on", "reset", "switch on", "unlock scanner",
    "fire turret", "inspect", "look under the hat", "take diamond",
}
-- Read optional story props once, and never target a first-person copy.
Env.Miz0StoryCache = Env.Miz0StoryCache and Env.Miz0StoryCache.JobId == game.JobId and Env.Miz0StoryCache
    or {JobId = game.JobId, Seen = setmetatable({}, {__mode = "k"})}
local storySeen = Env.Miz0StoryCache.Seen
local promptAttempts = setmetatable({}, {__mode = "k"})
local oneShotActions = {inspect = true, ["read note"] = true, ["read letter"] = true,
    ["look under the hat"] = true, ["hear him out"] = true}
local function autoPromptAllowed(prompt)
    if not prompt.Parent or not prompt.Enabled then return false end
    local camera = workspace.CurrentCamera
    if camera and prompt:IsDescendantOf(camera) then return false end
    if Player.Character and prompt:IsDescendantOf(Player.Character) then return false end
    local action = prompt.ActionText:lower()
    if oneShotActions[action] and storySeen[prompt] then return false end
    local record = promptAttempts[prompt]
    if record and record.action ~= action then promptAttempts[prompt] = nil; record = nil end
    return not record or os.clock() >= record.retryAt
end
local function recordAutoPrompt(prompt)
    local action = prompt.ActionText:lower()
    if oneShotActions[action] then
        storySeen[prompt] = true
        if action == "inspect" then A.AutoReadUntil = os.clock() + 1.3 end
    end
    local record = promptAttempts[prompt]
    if not record or record.action ~= action then
        record = {action = action, count = 0, retryAt = 0}
        promptAttempts[prompt] = record
    end
    record.count += 1
    if record.count >= 3 then record.count = 0; record.retryAt = os.clock() + 5 end
end
tickStoryRead = function()
    if not A.AutoReadUntil or os.clock() < A.AutoReadUntil then return end
    A.AutoReadUntil = nil
    -- DaleScrapController registers its native put-away callback here.
    for _, callback in registry.AnomalyAttackView or {} do
        for _, value in debug.getupvalues(callback) do
            if type(value) == "table" and value.Scrap and value.Copy and value.PromptsWere ~= nil then
                pcall(callback)
                return
            end
        end
    end
end

local flavorTalkSeen = setmetatable({}, {__mode = "k"})
local function workPrompts()
    if not A.Features.TaskPrompts or next(sessions) or Player:GetAttribute("OperatingMinigame") then return false end
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local best, target, bestDistance = nil, nil, math.huge
    for prompt in originals do
        if autoPromptAllowed(prompt) then
            local text = string.lower(prompt.ActionText)
            local allowed = false
            for _, word in taskWords do
                if string.find(text, word, 1, true) then allowed = true; break end
            end
            if text == "talk" and A.Features.Story and ShiftState then
                local shift = ShiftState.GetShift()
                local mainWorkPending = ShiftState.GetCheckinsRemaining() > 0
                    or ShiftState.GetScansRemaining() > 0 or ShiftState.GetInterrogationsRemaining() > 0
                allowed = not mainWorkPending and flavorTalkSeen[prompt] ~= shift
            end
            if text == "hang up" and prompt:GetFullName():lower():find("phone", 1, true) then allowed = true end
            if text == "pick up" and prompt:GetFullName():lower():find("phone", 1, true) then allowed = true end
            if Collection:HasTag(prompt, "RoomFirePrompt") or text:find("extinguisher", 1, true)
                or text:find("put back", 1, true) then allowed = false end
            if allowed and not text:find("purchase", 1, true) then
                local pos = position(prompt.Parent)
                if pos then
                    local distance = (root.Position - pos).Magnitude
                    if distance < bestDistance then best, target, bestDistance = prompt, pos, distance end
                end
            end
        end
    end
    if best then
        taskState = (bestDistance <= best.MaxActivationDistance and "Task: " or "Moving to: ") .. best.ActionText
        if bestDistance <= best.MaxActivationDistance then
            local key = "prompt:" .. best:GetFullName() .. best.ActionText
            if os.clock() - (lastSent[key] or -math.huge) >= 0.45 then
                lastSent[key] = os.clock()
                local ok = pcall(fireproximityprompt, best)
                if ok then recordAutoPrompt(best) end
                if best.ActionText:lower() == "talk" then flavorTalkSeen[best] = ShiftState and ShiftState.GetShift() or true end
                log("Prompt: " .. best.ActionText)
            end
        elseif not next(sessions) then
            moveNear(target)
        end
        return true
    end
    return false
end

-- Fetch once on startup, then resync periodically for missed events or late injection.
local function sync()
    if IS_LOBBY then return end
    local snapshots = invokeServer("FetchStationStates")
    if type(snapshots) == "table" then
        stages = {}
        for _, payload in snapshots do rememberStage(payload) end
    end
    local fetches = {BrainScan = "FetchBrainScanState", Fingerprint = "FetchFingerprintState",
        EyeExam = "FetchEyeExamState", LieDetector = "FetchLieDetectorState"}
    for prefix, name in fetches do
        local value, received = invokeServer(name)
        if not received then continue end
        if type(value) == "table" and value.Uid then
            rooms[prefix] = value
            -- Ownership also exists during wiring/setup. Recover an active
            -- test only from the game's real live controller session.
            local active = nativeSession(prefix)
            if active and not value.Finishing and not sessions[prefix] then
                sessions[prefix] = {Uid = active.Uid or value.Uid, started = os.clock(), OpensAt = active.OpensAt}
            elseif not active and sessions[prefix] and not Player:GetAttribute("OperatingMinigame")
                and os.clock() - (sessions[prefix].started or 0) > 5 then
                sessions[prefix] = nil
            end
        else
            rooms[prefix] = nil
            if not nativeSession(prefix) and not Player:GetAttribute("OperatingMinigame") then sessions[prefix] = nil end
        end
    end
end



-- Event-driven adapters for the remaining work, story, defense and seasonal systems.
local Extra = {turrets = {}, story = {}, state = {}, loose = {}, emergencyTypes = {}, coverage = {}, blockers = {}, nextScan = 0}
A.Coverage = Extra.coverage
A.Blockers = Extra.blockers
local function implemented(key)
    Extra.coverage[key] = Extra.coverage[key] or {implemented = true, confirmed = 0}
end
for _, key in {"Checkin","BodyScan","Baggage","LieDetector","BrainScan","EyeExam","Fingerprint",
    "SnackDeliveries","WitchBrew","Medical","Firefighting","Infections","Exorcism","Cola",
    "CameraRepair","Turrets","Lockdown","FightBack","Taser","GhostHaunt","PassengerRevive","Toad","WitchSafety","DemonAltar","Upgrades","SpecialPassengers","Letters","Graveyard","Candy","Pumpkins","Mausoleum","Replay"} do
    implemented(key)
end
local function confirmed(key)
    implemented(key)
    Extra.coverage[key].confirmed += 1
    Extra.blockers[key] = nil
end
local function delayed(key, seconds, action, ...)
    if Extra.story[key] then return end
    Extra.story[key] = {at = os.clock() + seconds, action = action, args = table.pack(...)}
end
local function safeRequire(name)
    local module = RS.Game.Library:FindFirstChild(name)
    if not module then return nil end
    local ok, result = pcall(require, module)
    return ok and result or nil
end
local Mausoleum = not IS_LOBBY and safeRequire("Mausoleum")
local Visitors = not IS_LOBBY and safeRequire("MausoleumVisitors")
local Witch = not IS_LOBBY and safeRequire("Witch")
local function worldModel(uid, attribute)
    for _, folderName in {"Passengers","MausoleumRuntime","Witches","__THINGS"} do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, model in folder:GetChildren() do
                if model:IsA("Model") and (model:GetAttribute(attribute or "NpcId") == uid or model.Name == tostring(uid)) then
                    return model
                end
            end
        end
    end
    return nil
end
local function addBrew(value)
    if not Witch or type(value) ~= "table" or not value.Uid or not value.Items then return end
    newRequest(value.Uid, value.Items, Witch.BREW_ADD_REMOTE, "Witch")
    local request = requests[value.Uid]
    if request then
        request.targetProvider = function()
            local current = sessionFrom(Witch.BREW_TICK_REMOTE, function(v) return v.Cauldron and v.Rows end)
            return current and current.Cauldron
        end
        for key, ticked in value.Ticked or {} do request.checked[key] = ticked == true end
    end
end

local function setCongaState(value)
    if type(value) == "table" and value.Ready == true and value.Opened ~= true then
        Extra.state.conga = value
    else
        Extra.state.conga = nil
        Extra.state.congaCheckAt = nil
    end
end

expandedEvent = function(name, value)
    if name == "EmergencyStarted" and type(value)=="table" and value.Uid then Extra.emergencyTypes[value.Uid]=value.Id end
    if name == "TurretState" and type(value) == "table" then Extra.turrets[value.Key] = value end
    if name == "LockdownLights" and type(value) == "table" then Extra.state.lockdown = value.Mode ~= "Restore" end
    if name == "LockdownRole" and type(value) == "table" then Extra.state.role = value.Role end
    if name == "LockdownTeach" and type(value) == "table" then Extra.state.defend = value.Show end
    if name == "CrashOutMeter" and type(value) == "number" then Extra.state.stress = value end
    if name == "JeffreyFavorPrompt" and type(value) == "table" and A.Features.Story then
        delayed("jeffrey:" .. value.Uid, 0.6, "JeffreyHearOut", value.Uid)
    elseif name == "DaleTalkOpen" and type(value) == "table" and value.Chips == true and A.Features.Story then
        newRequest(value.Uid, {"Roritos"}, "DaleGiveChips", "DaleChips")
    elseif name == "DaleChipsTaken" and type(value) == "table" then
        local request = requests[value.Uid]
        if request and request.kind=="DaleChips" then requests[value.Uid]=nil end
    elseif name == "JeffreyUsbPrompt" and type(value) == "table" and A.Features.Story then
        delayed("usb:" .. value.Uid, 0.6, "JeffreyUsbDeny", value.Uid)
    elseif name == "BritneyPrompt" and type(value) == "table" and A.Features.Story then
        delayed("britney:" .. value.Uid, 0.6, "BritneyDeny", value.Uid)
    elseif name == "JeffreyLetterPrompt" and A.Features.Story then
        delayed("letter:open:" .. os.clock(), 0.5, "JeffreyLetterOpen")
    elseif name == "JeffreyLetterRead" and A.Features.Story then
        delayed("letter:finish:" .. os.clock(), 3, "JeffreyLetterFinished")
    elseif name == "DaleFlightPrompt" and type(value) == "table" and A.Features.Story then
        delayed("dale:board:" .. value.Uid, 1, "DaleLetBoard", value.Uid)
    elseif name == "GraveyardKeyDropped" then Extra.state.graveKey = value
    elseif name == "GraveyardTrail" then Extra.state.graveTrail = value
    elseif name == "GraveyardDoorUnlocked" then
        Extra.state.graveOpen = true
        Extra.state.unlockAt = nil
        Extra.blockers.Graveyard = nil
        confirmed("Graveyard")
    elseif name == "GraveyardReset" then
        Extra.state.graveOpen = false
        Extra.state.graveKey = nil
        Extra.state.graveTrail = nil
        Extra.state.unlockAt = nil
        Extra.state.candyPending = nil
        Extra.state.candyTarget = nil
    elseif name == "GraveyardPumpkinState" then Extra.state.pumpkins = value
    elseif name == "GraveyardPumpkinReset" then
        Extra.state.pumpkins = {Opened = false, Placed = 0, Slots = {}}
        Extra.state.place = nil
        table.clear(Extra.loose)
    elseif name == "GraveyardPumpkinLoose" and type(value) == "table" then Extra.loose[value.Id] = value
    elseif name == "GraveyardPumpkinTaken" then
        if type(value) == "table" then Extra.loose[value.Id] = nil else Extra.loose[value] = nil end
    elseif name == "GraveyardPumpkinPlaced" and type(value) == "table" then
        Extra.state.pumpkins = value.State; Extra.state.place = nil; confirmed("Pumpkins")
    elseif name == "CongaPumpkinReady" then setCongaState(type(value) == "table" and value or {Ready = true, Opened = false})
    elseif name == "CongaPumpkinGone" or name == "CongaPumpkinOpened" then
        Extra.state.conga = nil
        Extra.state.congaCheckAt = nil
    elseif name == "MausoleumState" then Extra.state.mausoleum = value
    elseif name == "MausoleumVaporized" then confirmed("Mausoleum")
    elseif Witch and name == Witch.BREW_START_REMOTE then addBrew(value)
    elseif Witch and name == Witch.BREW_TICK_REMOTE and type(value) == "table" then
        local request = requests[value.Uid]
        if request then request.checked[value.Index] = true end
        confirmed("WitchBrew")
    elseif Witch and name == Witch.BREW_END_REMOTE and type(value) == "table" then requests[value.Uid] = nil
    elseif name == "LieDetectorComplete" then confirmed("LieDetector")
    elseif name == "BrainScanComplete" then confirmed("BrainScan")
    elseif name == "EyeExamComplete" then confirmed("EyeExam")
    elseif name == "FingerprintComplete" then confirmed("Fingerprint")
    elseif name == "InterrogationItemChecked" then confirmed("SnackDeliveries")
    elseif name == "StationClear" and type(value) == "table" then
        confirmed(value.StationType == "Checkin" and "Checkin" or "Baggage")
    elseif name == "EmergencyEnded" then
        local kind = type(value)=="table" and Extra.emergencyTypes[value.Uid]
        local group = ({DownedPassenger="Medical",FaintedPassenger="Medical",BurningPassenger="Firefighting",RoomFire="Firefighting",PossessedPassenger="Exorcism",Possession="Exorcism",DemonAltar="DemonAltar",Toad="Toad",WitchBrew="WitchBrew",WitchHex="WitchSafety",DaleMeltdown="SpecialPassengers"})[kind]
        if type(value) == "table" and value.Outcome == "Resolved" then confirmed(group or "EmergencyResolution") end
        if type(value)=="table" then Extra.emergencyTypes[value.Uid]=nil end
    elseif name == "StationStage" and type(value) == "table" and (value.Stage=="BodyApprove" or value.Stage=="BodyDeny") then confirmed("BodyScan") end
end

local function nativePrompt(prompt, key, seconds)
    if not prompt or not autoPromptAllowed(prompt) then return false end
    local target = position(prompt.Parent)
    if not target then return false end
    if not closeEnough(target, math.max(2, prompt.MaxActivationDistance - 0.5)) then
        moveNear(target, math.max(2, prompt.MaxActivationDistance * 0.65))
        return true
    end
    if Collection:HasTag(prompt, "RoomFirePrompt") then return false end
    if os.clock() - (lastSent[key] or -math.huge) >= (seconds or 2) then
        lastSent[key] = os.clock()
        local ok = pcall(fireproximityprompt, prompt)
        if not ok then return false end
        recordAutoPrompt(prompt)
        A.Actions += 1
        log("Task: " .. prompt.ActionText)
    end
    return true
end
workInterrogationPrompts = function()
    if next(sessions) or Player:GetAttribute("OperatingMinigame") then return false end
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local best, distance = nil, math.huge
    for prompt in originals do
        local action = prompt.Parent and prompt.ActionText:lower() or ""
        local core = (A.Features.Interrogations and action:find("interrogate", 1, true))
            or ((A.Features.BodyScan or A.Features.Luggage) and action == "scan passenger")
            or (A.Features.TaskPrompts and (action == "next shift" or action == "start shift"
                or action == "start boarding" or action == "board passengers"))
        if core and autoPromptAllowed(prompt) then
            local target = position(prompt.Parent)
            if target then
                local d = (root.Position - target).Magnitude
                if d < distance then best = prompt; distance = d end
            end
        end
    end
    if not best then return false end
    taskState = (distance <= best.MaxActivationDistance and "Task: " or "Going to: ") .. best.ActionText
    return nativePrompt(best, "interrogation:" .. best:GetFullName(), 0.5)
end

-- Ground fires use the real extinguisher spray protocol. Never stand in
-- the burning tile to hold its close-range prompt.
local Fire = {padding = 0, escapeUntil = 0, spraying = false, nextSupply = 0}
local function floorFireCells()
    local cells = {}
    for _, prompt in Collection:GetTagged("RoomFirePrompt") do
        if prompt:IsA("ProximityPrompt") and prompt.Parent and prompt:GetAttribute("MashComplete") ~= true then
            local target = position(prompt.Parent)
            if target then
                local parent = prompt.Parent
                local part = parent:IsA("BasePart") and parent or (parent:IsA("Attachment") and parent.Parent:IsA("BasePart") and parent.Parent)
                local radius = 4.5 + Fire.padding
                if part then
                    local side = math.max(part.Size.X, part.Size.Z)
                    if side <= 12 then radius = math.max(radius, side * 0.5 + 1.5 + Fire.padding) end
                end
                table.insert(cells, {prompt = prompt, position = target, radius = radius})
            end
        end
    end
    A.FireStats.CellsRemaining = #cells
    return cells
end
firePositionUnsafe = function(point, cells)
    cells = cells or floorFireCells()
    for _, cell in cells do
        local delta = point - cell.position
        if math.abs(delta.Y) < 7 and Vector2.new(delta.X, delta.Z).Magnitude < cell.radius then return true end
    end
    return false
end
local function fireRayParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if Player.Character then table.insert(exclude, Player.Character) end
    local passengers = workspace:FindFirstChild("Passengers")
    if passengers then table.insert(exclude, passengers) end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    return params
end
local function fireLineClear(origin, target, params)
    local hit = workspace:Raycast(origin, target - origin, params)
    return not hit or (hit.Position - target).Magnitude < 2
end
local function safeFireSpot(target, reach, cells, nozzle, escapeOnly)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then return nil end
    local params = fireRayParams()
    local nozzleOffset = nozzle and (nozzle.WorldPosition - root.Position) or Vector3.new(0, 1, 0)
    local function reachable(spot)
        if escapeOnly then return true end
        local origin = spot + nozzleOffset
        return (origin - target).Magnitude <= reach and fireLineClear(origin, target, params)
    end
    if not escapeOnly and not firePositionUnsafe(root.Position, cells) and reachable(root.Position) then return root.Position end
    local preferred = escapeOnly and reach * 0.8 or (nozzle and math.min(12, reach * 0.85 + 0.8) or reach * 0.75)
    local footHeight = math.max(3, humanoid.HipHeight + root.Size.Y * 0.5) + 0.2
    local best, score = nil, math.huge
    for _, factor in {1, 0.85, 1.1} do
        for index = 0, 11 do
            local angle = index * math.pi / 6
            local point = target + Vector3.new(math.cos(angle), 0, math.sin(angle)) * preferred * factor
            local ground = workspace:Raycast(point + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), params)
            if ground and ground.Normal.Y > 0.7 and math.abs(ground.Position.Y - target.Y) <= 6 then
                local spot = ground.Position + Vector3.new(0, footHeight, 0)
                if not firePositionUnsafe(spot, cells) and reachable(spot) then
                    local distance = (spot - root.Position).Magnitude
                    if distance < score then best = spot; score = distance end
                end
            end
        end
    end
    return best
end
local function moveToFireSpot(spot)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not A.AutoMove or not root or not spot then return false end
    if (root.Position - spot).Magnitude <= 1 then return true end
    if os.clock() - lastMove < 0.3 then return false end
    lastMove = os.clock()
    character:PivotTo(CFrame.new(spot) * root.CFrame.Rotation)
    root.AssemblyLinearVelocity = Vector3.zero
    A.FireStats.SafeMoves += 1
    return true
end
stopFireSpray = function()
    if Fire.spraying then Remote:FireServer("ExtinguisherSpray", false) end
    Fire.spraying = false
    Fire.tool = nil
end
escapeGroundFire = function()
    if not A.Features.Emergencies or A.AttackActive or not A.AutoMove then return false end
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    local damaged = Fire.lastHealth and humanoid.Health < Fire.lastHealth
    Fire.lastHealth = humanoid.Health
    A.FireStats.Health = humanoid.Health
    local cells = floorFireCells()
    if #cells == 0 then return false end
    if damaged then
        Fire.padding = math.min(8, Fire.padding + 1)
        A.FireStats.DamageEvents += 1
    end
    if firePositionUnsafe(root.Position, cells) or damaged then
        stopFireSpray()
        local spot = safeFireSpot(root.Position, 35, cells, nil, true)
        if not spot and A.ControlRoomCFrame and not firePositionUnsafe(A.ControlRoomCFrame.Position, cells) then spot = A.ControlRoomCFrame.Position end
        if spot and moveToFireSpot(spot) then
            Fire.escapeUntil = os.clock() + 1
            Fire.planAt = 0
            taskState = "Moving clear of ground fire"
            return true
        end
    end
    return false
end
local function usableExtinguisher()
    for _, container in {Player.Character, Player:FindFirstChildOfClass("Backpack")} do
        if container then for _, tool in container:GetChildren() do
            if tool:IsA("Tool") and Extinguishers and Extinguishers.Is(tool:GetAttribute("ItemId")) then
                local charge = tonumber(tool:GetAttribute("Charge"))
                if not charge and tool:GetAttribute("ItemId") == Extinguishers.WALL and A.WallExtinguisherState then
                    charge = tonumber(A.WallExtinguisherState.Charge)
                end
                if not charge or charge > 0 then return tool end
            end
        end end
    end
    return nil
end
local function prepareFireTool(cells)
    local tool = usableExtinguisher()
    if tool then return tool end
    if not A.Features.Restock then return nil end
    local model = Collection:GetTagged("WallFireExtinguisher")[1]
    local prompt = model and model:FindFirstChildWhichIsA("ProximityPrompt", true)
    local target = prompt and position(prompt.Parent)
    if not target then
        Extra.blockers.Firefighting = "Waiting for the wall extinguisher."
        return nil
    end
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local range = math.max(2, prompt.MaxActivationDistance - 0.7)
    if (root.Position - target).Magnitude > range or firePositionUnsafe(root.Position, cells) then
        local spot = safeFireSpot(target, range, cells, nil, false)
        if spot then moveToFireSpot(spot) else Extra.blockers.Firefighting = "No safe path to the extinguisher." end
    else
        local depleted = ownedItem(Extinguishers.WALL)
        local charge = depleted and tonumber(depleted:GetAttribute("Charge"))
        if depleted and charge and charge <= 0 then
            -- Return only an empty wall tool. Ordinary task scanning never
            -- touches the take/return supply prompt.
            stopFireSpray()
            send("fire:return-empty", 1.2, "WallExtinguisherReturn", model)
            taskState = "Returning the empty extinguisher"
            return nil
        end
        local state = A.WallExtinguisherState
        if not depleted and state and tonumber(state.Charge) and tonumber(state.Charge) <= 0 then
            Extra.blockers.Firefighting = "Waiting for the wall extinguisher to recharge."
            taskState = "Waiting for extinguisher recharge"
            return nil
        end
        -- Same command and tagged model as WallExtinguisherController.
        send("fire:take", 0.6, "WallExtinguisherTake", model)
    end
    taskState = "Collecting the fire extinguisher"
    return nil
end
local function extinguisherNozzle(tool)
    local nozzle, reach = nil, 0
    for _, emitter in tool:GetDescendants() do
        if emitter:IsA("ParticleEmitter") and emitter.Parent:IsA("Attachment") then
            local distance = emitter.Drag > 0 and emitter.Speed.Max / emitter.Drag or emitter.Speed.Max * emitter.Lifetime.Max
            if distance > reach then nozzle = emitter.Parent; reach = distance end
        end
    end
    return nozzle, math.clamp(reach, 1, 30)
end
stockFireTool = function()
    if not A.Features.Emergencies or not A.Features.Restock or usableExtinguisher() or os.clock() < Fire.nextSupply then return false end
    local now = os.clock()
    Fire.prepAt = Fire.prepAt or now
    if now - Fire.prepAt > 8 then
        Fire.prepAt = nil
        Fire.nextSupply = now + 10
        return false
    end
    local tool = prepareFireTool({})
    if tool then
        Fire.prepAt = nil
        return false
    end
    return true
end
workFirePrompts = function()
    if not A.Features.Emergencies then stopFireSpray(); return false end
    local cells = floorFireCells()
    if #cells == 0 then stopFireSpray(); return false end
    if nativePromptHold then releaseNativeHold() end
    escapeGroundFire()
    if os.clock() < Fire.escapeUntil then taskState = "Staying clear of ground fire"; return true end
    local tool = prepareFireTool(cells)
    if not tool then stopFireSpray(); return true end
    if tool.Parent ~= Player.Character then
        equip(tool)
        Fire.equippedAt = os.clock()
        taskState = "Equipping the extinguisher"
        return true
    end
    if Fire.equippedAt and os.clock() - Fire.equippedAt < 0.15 then return true end
    if Fire.tool ~= tool then pcall(function() tool:Deactivate() end); Fire.tool = tool end
    local nozzle, reach = extinguisherNozzle(tool)
    if not nozzle then
        stopFireSpray()
        Extra.blockers.Firefighting = "The extinguisher nozzle is not ready."
        return true
    end
    local best, distance = nil, math.huge
    for _, cell in cells do
        local d = (cell.position - nozzle.WorldPosition).Magnitude
        if d < distance then best = cell; distance = d end
    end
    if not best then stopFireSpray(); return false end
    if Fire.target ~= best.prompt or os.clock() >= (Fire.planAt or 0) then
        Fire.target = best.prompt
        Fire.planAt = os.clock() + 0.5
        Fire.spot = safeFireSpot(best.position, reach * 0.97, cells, nozzle, false)
    end
    if not Fire.spot or firePositionUnsafe(Fire.spot, cells) then
        stopFireSpray()
        Extra.blockers.Firefighting = "Searching for a safe spray position."
        taskState = "Staying clear of ground fire"
        return true
    end
    moveToFireSpot(Fire.spot)
    local origin = nozzle.WorldPosition
    local delta = best.position - origin
    if not firePositionUnsafe(Player.Character.HumanoidRootPart.Position, cells)
        and delta.Magnitude > 0.1 and delta.Magnitude <= reach then
        if send("fire:spray", 0.1, "ExtinguisherSpray", {Origin = origin, Direction = delta.Unit}) then
            Fire.spraying = true
            A.FireStats.Pulses += 1
        end
        Extra.blockers.Firefighting = nil
        taskState = "Spraying ground fire (" .. #cells .. " left)"
    else
        stopFireSpray()
        taskState = "Moving to a safe fire-fighting position"
    end
    return true
end

-- Survival uses replicated hazard positions; the server owns curse recovery.
local function moveClearOfHazard(center, radius)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not A.AutoMove or not root or os.clock() - lastMove < 0.3 then return false end
    local spot = safeFireSpot(center, (radius + 12) / 0.8, floorFireCells(), nil, true)
    if not spot or Vector2.new(spot.X - center.X, spot.Z - center.Z).Magnitude <= radius + 3 then return false end
    lastMove = os.clock()
    cancelHolds()
    character:PivotTo(CFrame.new(spot) * root.CFrame.Rotation)
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end
tickWitchSafety = function()
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not A.Features.WitchSafety then A.ToadActive = false; return end
    local now = workspace:GetServerTimeNow()
    local toad = character:GetAttribute("Toad") == true
    if toad and not A.ToadActive then A.ToadAt = os.clock(); cancelHolds() end
    if not toad and A.ToadActive then
        A.EmergencyStats.ToadRecoveries += 1
        log("Toad curse cleared; resuming work")
    end
    A.ToadActive = toad
    if A.AttackActive or A.FightingBack then return end
    if toad and A.AutoMove and A.ControlRoomCFrame and not next(sessions) then
        moveNear(A.ControlRoomCFrame.Position, 5)
    end
    for index = #A.WitchPotions, 1, -1 do
        local potion = A.WitchPotions[index]
        if now > potion.impact + 1 then table.remove(A.WitchPotions, index)
        elseif not potion.dodged and potion.impact - now <= 1.3
            and math.abs(root.Position.Y - potion.center.Y) < 12
            and Vector2.new(root.Position.X - potion.center.X, root.Position.Z - potion.center.Z).Magnitude < 11 then
            if moveClearOfHazard(potion.center, 11) then
                potion.dodged = true
                A.EmergencyStats.PotionDodges += 1
                A.WitchSafeUntil = potion.impact + 0.7
                taskState = "Avoiding the witch potion"
            end
        end
    end
    local hex = A.WitchHex
    if hex and now >= hex.EndsAt then A.WitchHex = nil; hex = nil end
    if hex and typeof(hex.Center) == "Vector3" then
        local radius = tonumber(hex.Radius) or 10
        if math.abs(root.Position.Y - hex.Center.Y) < 12
            and Vector2.new(root.Position.X - hex.Center.X, root.Position.Z - hex.Center.Z).Magnitude <= radius + 3 then
            if moveClearOfHazard(hex.Center, radius + 3) then
                A.EmergencyStats.HexEscapes += 1
                A.WitchSafeUntil = now + 0.7
                taskState = "Moving outside the witch hex"
            end
        end
    end
end

local ghostWork = {nextStock = 0, retryAt = 0}
workGhostEmergency = function()
    local pending = ghostWork.pending
    if pending then
        if pending.target:GetAttribute("GhostGone") == true then
            A.HauntStats.Confirmed += 1
            A.Verified.GhostHaunt = (A.Verified.GhostHaunt or 0) + 1
            if A.Coverage and A.Coverage.GhostHaunt then A.Coverage.GhostHaunt.confirmed += 1 end
            ghostWork.pending = nil
            ghostWork.at = nil
            log("Ghost exorcism confirmed")
        elseif os.clock() - pending.at > 4 then ghostWork.pending = nil end
    end
    if not A.Features.Emergencies or not A.Features.Haunt or os.clock() < ghostWork.retryAt then return false end
    local folder = workspace:FindFirstChild("Ghosts")
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not folder or not root then return false end
    local best, distance = nil, math.huge
    for _, model in folder:GetChildren() do
        if model:IsA("Model") and model:GetAttribute("GhostVisible") == true
            and model:GetAttribute("GhostGone") ~= true and type(model:GetAttribute("GhostId")) == "string" then
            local target = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if target and target:IsA("BasePart") then
                local d = (root.Position - target.Position).Magnitude
                if d < distance then best, distance = model, d end
            end
        end
    end
    if not best then ghostWork.at = nil; return false end
    ghostWork.at = ghostWork.at or os.clock()
    if os.clock() - ghostWork.at > 3 then ghostWork.at = nil; ghostWork.retryAt = os.clock() + 3; return false end
    local tool = obtain("Crucifix")
    if not tool then return not A.SupplyBlocked.Crucifix end
    if not Crucifixes.IsReady(tool) then return false end
    equip(tool)
    local ghostRoot = best:FindFirstChild("HumanoidRootPart") or best.PrimaryPart
    local target = ghostRoot and position(ghostRoot)
    if not target then return false end
    if not closeEnough(target, 9.5) then moveNear(target, 6)
    elseif send("ghost:exorcise", 1.2, "CrucifixUse", {Id = best:GetAttribute("GhostId")}) then
        ghostWork.pending = {target = best, at = os.clock()}
        A.HauntStats.Attempts += 1
        log("Using the crucifix on a ghost")
    end
    taskState = "Exorcising a haunting ghost"
    return true
end
stockCrucifix = function()
    if ownedItem("Crucifix") then ghostWork.stockAt = nil; return false end
    if not A.Features.Haunt or not A.Features.Emergencies or not A.Features.Restock
        or os.clock() < ghostWork.nextStock then return false end
    ghostWork.stockAt = ghostWork.stockAt or os.clock()
    local tool = obtain("Crucifix")
    if tool then ghostWork.stockAt = nil; return false end
    if A.SupplyBlocked.Crucifix or os.clock() - ghostWork.stockAt > 3 then
        ghostWork.stockAt = nil
        ghostWork.nextStock = A.SupplyBlocked.Crucifix or (os.clock() + 8)
        return false
    end
    taskState = "Collecting the wall crucifix"
    return true
end

local witchPursuit
workWitchResponse = function()
    if not A.Features.WitchSafety or not A.Features.Emergencies or not A.Features.Taser
        or os.clock() < (A.WitchRetryAt or 0) then return false end
    local passengers = workspace:FindFirstChild("Passengers")
    if not passengers then return false end
    local target, best = nil, math.huge
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    for _, model in passengers:GetChildren() do
        if model:IsA("Model") and model:GetAttribute("WitchFlying") == true
            and not model:GetAttribute("Dead") and not model:GetAttribute("Tased") and not model:GetAttribute("Invulnerable") then
            local at = position(model)
            if at then
                local distance = (root.Position - at).Magnitude
                if distance < best then target, best = model, distance end
            end
        end
    end
    if not target then witchPursuit = nil; return false end
    if not ownedTaser() then return stockTaser and stockTaser() or false end
    if not witchPursuit or witchPursuit.target ~= target then witchPursuit = {target = target, at = os.clock()} end
    if os.clock() - witchPursuit.at > 3 then
        witchPursuit = nil; A.WitchRetryAt = os.clock() + 4
        return false
    end
    moveNear(position(target), 8)
    taskState = "Targeting the flying witch with the taser"
    return true
end

workEmergencyPrompts = function()
    if not A.Features.Emergencies then return false end
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local best, distance = nil, math.huge
    for prompt in originals do
        if autoPromptAllowed(prompt) then
            local action = prompt.ActionText:lower()
            if action == "free arm" or action == "free leg" or action == "banish" or action == "revive"
                or action == "exorcise" or action == "disinfect" then
                local at = position(prompt.Parent)
                if at then
                    local d = (root.Position - at).Magnitude
                    if d < distance then best, distance = prompt, d end
                end
            end
        end
    end
    if not best then return false end
    taskState = "Emergency: " .. best.ActionText
    if best.ActionText:lower() == "revive" then
        local target = position(best.Parent)
        if not target then return false end
        if not closeEnough(target, best.MaxActivationDistance - 0.5) then moveNear(target, 6); return true end
        local record = originals[best]
        local duration = record and record.hold or best.HoldDuration
        if duration > 0 then
            if nativePromptHold then return true end
            if record then record.nativeHold = true end
            best.HoldDuration = duration
            local ok = pcall(best.InputHoldBegin, best)
            if not ok then
                if record then record.nativeHold = false end
                best.HoldDuration = A.InstantPrompts and 0 or duration
                return false
            end
            nativePromptHold = {prompt = best, untilTime = os.clock() + duration + 0.15}
            recordAutoPrompt(best)
            return true
        end
    end
    return nativePrompt(best, "rescue:" .. best:GetFullName() .. best.ActionText, 0.4)
end

-- Match live upgrade offers against the real catalog. Use their native
-- cash purchase prompts, with a bounded retry for an unchanged offer.
local upgradeCatalog
local upgradeAttempts = setmetatable({}, {__mode = "k"})
local upgradePending, nextUpgrade = nil, 0
local function upgradeCash()
    local main = Player.PlayerGui:FindFirstChild("Main")
    local bottom = main and main:FindFirstChild("BottomLeftFrame")
    local label = bottom and bottom:FindFirstChild("Money")
    if not label or not label:IsA("TextLabel") then return nil end
    local text = label.Text:gsub("<.->", ""):gsub("[,%s$]", "")
    local amount, suffix = text:match("([%d%.]+)([KkMmBb]?)")
    local number = tonumber(amount)
    if not number then return nil end
    return number * (({K = 1e3, M = 1e6, B = 1e9})[string.upper(suffix)] or 1)
end
local function upgradeDefinition(model)
    for id, definition in upgradeCatalog do
        if model:GetAttribute("UpgradeId") == id or model:GetAttribute("Id") == id
            or model.Name == definition.DisplayName then return id, definition end
    end
    return nil, nil
end
workUpgrades = function()
    local now = os.clock()
    if upgradePending then
        local tier = tonumber(RS:GetAttribute("UpgradeTier_" .. upgradePending.id)) or 0
        if tier > upgradePending.tier then
            A.UpgradeStats.Purchased += 1
            A.Verified.Upgrades = (A.Verified.Upgrades or 0) + 1
            if A.Coverage and A.Coverage.Upgrades then A.Coverage.Upgrades.confirmed += 1 end
            A.UpgradeStats.LastResult = "Purchased " .. upgradePending.name
            log(A.UpgradeStats.LastResult)
            upgradePending = nil
        elseif now - upgradePending.at > 3 then
            A.UpgradeStats.LastResult = "Waiting for the next available upgrade offer"
            upgradePending = nil
        else return false end
    end
    if not A.Features.Upgrades or IS_LOBBY or now < nextUpgrade then return false end
    local cash = upgradeCash()
    if not cash then return false end
    if not upgradeCatalog then upgradeCatalog = require(RS.Game.Library.Directory.Upgrades) end
    local offers = {}
    for _, model in Collection:GetTagged("ShopDisplayItem") do
        if model:IsA("Model") and model.Parent and not model:GetAttribute("ProductId") and not model:GetAttribute("GamePassId")
            and now >= (upgradeAttempts[model] or 0) then
            local id, definition = upgradeDefinition(model)
            local price = tonumber(model:GetAttribute("Price"))
            if id and definition and price and price >= 0 and cash >= price then
                local tier = tonumber(RS:GetAttribute("UpgradeTier_" .. id)) or 0
                local nextTier = definition.Tiers and definition.Tiers[tier + 1]
                if nextTier and (tonumber(nextTier.ShiftRequired) or 0) <= ShiftState.GetShiftNumber() then
                    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and prompt.Enabled and prompt.ActionText:lower() == "buy" then
                        table.insert(offers, {model = model, prompt = prompt, id = id, tier = tier,
                            price = price, name = definition.DisplayName})
                    end
                end
            end
        end
    end
    table.sort(offers, function(a, b) return a.price < b.price end)
    local offer = offers[1]
    if not offer then nextUpgrade = now + 1; return false end
    local at = position(offer.prompt.Parent)
    if not at then return false end
    taskState = "Buying upgrade: " .. offer.name
    if not closeEnough(at, math.max(2, offer.prompt.MaxActivationDistance - 0.6)) then
        moveNear(at, math.max(2, offer.prompt.MaxActivationDistance * 0.6))
        return true
    end
    upgradeAttempts[offer.model] = now + 12
    nextUpgrade = now + 0.5
    local ok, problem = pcall(fireproximityprompt, offer.prompt)
    if not ok then A.LastError = "Upgrade: " .. tostring(problem); return false end
    A.Actions += 1
    A.UpgradeStats.Attempts += 1
    A.UpgradeStats.LastResult = "Confirming " .. offer.name
    upgradePending = {id = offer.id, tier = offer.tier, name = offer.name, at = now}
    return true
end

local function useNear(id, target, command, payload, key)
    local tool = obtain(id)
    if not tool then return not A.SupplyBlocked[id] end
    equip(tool)
    if not closeEnough(target, 8) then moveNear(target) else send(key, 1.2, command, payload) end
    return true
end

local function classifyVisitor(state)
    if not Visitors or not Mausoleum then return nil end
    for _, key in {"Kind","VisitorKind","VisitorId","Id"} do
        local id = state[key]
        if type(id) == "string" then local def = Visitors.Find(id); if def then return def.Fake end end
    end
    local folder = workspace:FindFirstChild(Mausoleum.FOLDER_NAME)
    if not folder then return nil end
    for _, model in folder:GetChildren() do
        if model:IsA("Model") and model:GetAttribute("MausoleumVisitor") ~= nil then
            for _, value in model:GetAttributes() do
                if type(value) == "string" then local def = Visitors.Find(value); if def then return def.Fake end end
            end
            local names = {}
            for _, object in model:GetDescendants() do
                names[object.Name] = true
                for _, attr in {"SlotId","AppearanceId","Id"} do
                    local id = object:GetAttribute(attr)
                    if type(id) == "string" then names[id] = true end
                end
            end
            local spec = model:GetAttribute("AppearanceSpec")
            if type(spec) == "string" then
                local ok, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(spec) end)
                if ok then for _, id in decoded.Slots or {} do names[id] = true end end
            end
            local best, score, runnerUp = nil, 0, 0
            for _, definition in Visitors.KINDS do
                local s = 0
                for _, id in definition.Slots or {} do if names[id] then s += 2 end end
                for _, slots in definition.BaseSlots or {} do for _, id in slots do if names[id] then s += 2 end end end
                if definition.Prop and names[definition.Prop] then s += 4 end
                if s > score then runnerUp = score; best, score = definition, s
                elseif s > runnerUp then runnerUp = s end
            end
            if best and score >= 4 and score - runnerUp >= 2 then return best.Fake end
        end
    end
    return nil
end

-- Read the live controller's candy records so pickup uses the native prompt.
-- Sending only the server collect command leaves local ghost candy behind.
local function liveGraveyardCandies()
    for _, callback in registry.GraveyardTrail or {} do
        if debug.info(callback, "n") == "layTrail" then
            for _, value in debug.getupvalues(callback) do
                if type(value) == "table" then return value end
            end
        end
    end
    return nil
end
local function collectHalloweenCandy(S)
    local now = os.clock()
    if S.candyPending then
        local pending = S.candyPending
        if now - pending.at > 10 then
            S.candyPending = nil
            S.candyTarget = nil
            Extra.blockers.Candy = "Candy confirmation was delayed; retrying after refresh."
            return false
        end
        if now >= pending.verifyAt then
            pending.verifyAt = now + 0.6
            local ok, snapshot = pcall(function() return invokeServer("FetchGraveyard") end)
            if ok and type(snapshot) == "table" then
                S.graveOpen = snapshot.Unlocked == true
                S.graveTrail = snapshot.Trail
                local remains = false
                for _, candy in snapshot.Trail and snapshot.Trail.Candies or {} do
                    if candy.Id == pending.id then remains = true; break end
                end
                if not remains then
                    confirmed("Candy")
                    S.candyPending = nil
                    S.candyTarget = nil
                    taskState = "Candy pickup confirmed"
                    return true
                elseif now - pending.at >= 2.5 then
                    -- Restore the visual from authoritative state before retrying.
                    for _, callback in registry.GraveyardTrail or {} do
                        if debug.info(callback, "n") == "layTrail" then pcall(callback, snapshot.Trail) end
                    end
                    S.candyPending = nil
                    S.candyTarget = nil
                    Extra.blockers.Candy = "Pickup was not accepted; refreshed the candy trail."
                    return true
                end
            end
        end
        taskState = "Confirming candy pickup"
        return true
    end
    local records = liveGraveyardCandies()
    if not records then return false end
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local best, bestPrompt, target, distance = nil, nil, nil, math.huge
    for id, record in records do
        if type(record) == "table" and record.Model and record.Model.Parent and record.Landed
            and (not record.Inside or S.graveOpen) then
            local prompt
            for _, candidate in record.Model:GetDescendants() do
                if candidate:IsA("ProximityPrompt") and candidate.Enabled and candidate.ActionText == "Take Candy" then
                    prompt = candidate
                    break
                end
            end
            local pos = prompt and position(prompt.Parent)
            if pos then
                local d = (root.Position - pos).Magnitude
                if id == S.candyTarget then
                    best, bestPrompt, target = record, prompt, pos
                    break
                elseif d < distance then
                    best, bestPrompt, target, distance = record, prompt, pos, d
                end
            end
        end
    end
    if not best then S.candyTarget = nil; return false end
    S.candyTarget = best.Id
    local range = math.max(2, bestPrompt.MaxActivationDistance - 0.5)
    if not closeEnough(target, range) then
        moveNear(target, math.max(2, range * 0.6))
        taskState = "Moving to Halloween candy"
        return true
    end
    local ok, problem = pcall(fireproximityprompt, bestPrompt)
    if ok then
        A.Actions += 1
        S.candyPending = {id = best.Id, at = now, verifyAt = now + 0.45}
        Extra.blockers.Candy = nil
        taskState = "Collecting Halloween candy"
    else
        A.LastError = "Candy pickup: " .. tostring(problem)
        S.candyTarget = nil
    end
    return true
end

local function seasonalTasks()
    if not A.Features.Collectibles then return false end
    local S = Extra.state
    -- One seasonal route owns movement: open the graveyard before pickups.
    if not S.graveOpen then
        if ownedItem("Graveyard Key") then
            local grave = safeRequire("Graveyard")
            local door = grave and grave.Door()
            if door then
                local shutter = grave.Shutter()
                if shutter and shutter:GetAttribute(grave.RAISED_ATTR) ~= true then
                    S.unlockAt = nil
                    local folder = workspace:FindFirstChild(grave.FOLDER_NAME)
                    local lift = folder and folder:FindFirstChild(grave.LIFT_ANCHOR)
                    local prompt = lift and lift:FindFirstChildOfClass("ProximityPrompt")
                    local target = lift and position(lift)
                    if target and prompt and prompt.Enabled then
                        moveNear(target, prompt.MaxActivationDistance)
                        if closeEnough(target, prompt.MaxActivationDistance) then
                            local now = os.clock()
                            local interval = math.max(tonumber(prompt:GetAttribute("MashDebounce")) or 0.12, 0.12) + 0.03
                            if now - (S.liftAt or -math.huge) >= interval then
                                S.liftAt = now
                                pcall(fireproximityprompt, prompt)
                            end
                        end
                        taskState = "Lifting the graveyard shutter"
                        return true
                    end
                    Extra.blockers.Graveyard = "Waiting for the shutter lift prompt."
                    return false
                end
                Extra.blockers.Graveyard = nil
                local target = position(door)
                local nearest = math.huge
                local shutterPosition = shutter and position(shutter) or target
                local handle = door:FindFirstChild(grave.DOOR_HANDLE)
                if handle then
                    for _, part in handle:GetDescendants() do
                        if part:IsA("BasePart") then
                            local distance = (part.Position - shutterPosition).Magnitude
                            if distance < nearest then target = part.Position; nearest = distance end
                        end
                    end
                end
                -- The door model includes decorative parts far from its usable lock.
                -- Prefer the actual interaction anchor created by the game.
                for _, prompt in door:GetDescendants() do
                    if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt.ActionText == "Unlock" then
                        target = position(prompt.Parent) or target
                        break
                    end
                end
                moveNear(target, 8)
                if closeEnough(target, 7.5) then
                    equip(ownedItem("Graveyard Key"))
                    local now = os.clock()
                    if not S.unlockAt then
                        send("grave:begin", 0.5, "GraveyardUnlockBegin")
                        S.unlockAt = now
                    elseif now - S.unlockAt >= (S.graveHold or 3) then
                        send("grave:unlock", 0.5, "GraveyardUnlock")
                        S.unlockAt = nil
                    end
                else
                    S.unlockAt = nil
                end
                taskState = "Unlocking the graveyard"
                return true
            end
        elseif type(S.graveKey) == "table" and typeof(S.graveKey.Position) == "Vector3" then
            moveNear(S.graveKey.Position)
            if closeEnough(S.graveKey.Position, 8) then send("grave:key", 0.5, "GraveyardKeyPickup") end
            taskState = "Picking up the graveyard key"
            return true
        end
    end
    local pumpkin = ownedItem("Pumpkin")
    if pumpkin and S.pumpkins and S.pumpkins.Opened then
        local folder = workspace:FindFirstChild("GraveyardPumpkinsLocal")
        local slots = S.pumpkins.Slots or {}
        if S.place and (slots[tostring(S.place.slot)] or slots[S.place.slot]) then S.place = nil end
        if folder then for slot = 1, 10 do
            -- The server indexes occupied slots with strings, e.g. Slots["1"].
            if not slots[tostring(slot)] and not slots[slot] then
                local model = folder:FindFirstChild("PumpkinSlot" .. slot)
                if model then
                    local prompt
                    for _, candidate in model:GetDescendants() do
                        if candidate:IsA("ProximityPrompt") and candidate.Enabled then prompt = candidate; break end
                    end
                    local target = prompt and position(prompt.Parent) or position(model)
                    moveNear(target, 6)
                    if not closeEnough(target, 7.5) then
                        S.place = nil
                        taskState = "Moving to pumpkin slot " .. slot
                        return true
                    end
                    if pumpkin.Parent ~= Player.Character then
                        equip(pumpkin)
                        S.place = nil
                        taskState = "Equipping the pumpkin"
                        return true
                    end
                    local now = os.clock()
                    if S.place and (S.place.slot ~= slot or S.place.tool ~= pumpkin) then S.place = nil end
                    if S.place and S.place.sentAt and now - S.place.sentAt > 2.5 then
                        -- Reconcile with the server before retrying an unconfirmed attempt.
                        if now - (S.lastPumpkinRefresh or -math.huge) > 2.5 then
                            S.lastPumpkinRefresh = now
                            local ok, snapshot = pcall(function() return invokeServer("FetchGraveyardPumpkins") end)
                            if ok and type(snapshot) == "table" and type(snapshot.State) == "table" then
                                S.pumpkins = snapshot.State
                                S.placeSeconds = snapshot.PlaceSeconds or S.placeSeconds
                            end
                        end
                        S.place = nil
                        return true
                    end
                    if not S.place then
                        if send("pumpkin:begin:" .. slot, 0.5, "GraveyardPumpkinPlaceBegin", slot) then
                            S.place = {slot = slot, tool = pumpkin, at = now}
                        end
                    elseif not S.place.sentAt and now - S.place.at >= (S.placeSeconds or 1) + 0.15 then
                        if send("pumpkin:place:" .. slot, 0.5, "GraveyardPumpkinPlace", slot) then S.place.sentAt = now end
                    end
                    taskState = "Placing pumpkin " .. slot
                    return true
                end
            end
        end end
        S.place = nil
    else
        S.place = nil
    end
    for id, loose in Extra.loose do
        if typeof(loose.Position) == "Vector3" then
            moveNear(loose.Position)
            if closeEnough(loose.Position, 8) then send("pumpkin:pickup:" .. id, 0.5, "GraveyardPumpkinPickup", id) end
            taskState = "Collecting a loose pumpkin"
            return true
        end
    end
    if collectHalloweenCandy(S) then return true end
    if S.conga then
        -- Ready can remain true after Opened becomes true. A completed
        -- pumpkin must never occupy the task queue again.
        if S.conga.Ready ~= true or S.conga.Opened == true then
            setCongaState(nil)
        else
            local now = os.clock()
            if now >= (S.congaCheckAt or 0) then
                local ok, snapshot = pcall(function() return invokeServer("FetchCongaPumpkin") end)
                if ok then setCongaState(snapshot) end
                S.congaCheckAt = now + 2
            end
            local state = S.conga
            if state and (tonumber(state.BusyUntil) or 0) <= workspace:GetServerTimeNow() then
                local model = workspace:FindFirstChild("CongaPumpkin")
                local target = model and position(model)
                if target then
                    moveNear(target)
                    if closeEnough(target, 9) and send("conga:open", 3, "CongaPumpkinOpen") then
                        S.congaCheckAt = now + 0.5
                    end
                    taskState = "Opening the Halloween pumpkin"
                    return true
                end
            end
        end
    end
    if A.Features.Mausoleum and Mausoleum and type(S.mausoleum) == "table" then
        local state = S.mausoleum
        local now = os.clock()
        if state.Phase == "Empty" then S.mausoleumAttempt = nil; S.mausoleumRetryAt = nil end
        if state.Phase ~= "Mauler" and not state.Mauler then
            if now < (S.mausoleumRetryAt or 0) then return false end
            if not S.mausoleumAttempt or S.mausoleumAttempt.phase ~= state.Phase then
                S.mausoleumAttempt = {phase = state.Phase, at = now}
            elseif now - S.mausoleumAttempt.at > 3 then
                S.mausoleumAttempt = nil
                S.mausoleumRetryAt = now + 8
                Extra.blockers.Mausoleum = "Waiting for a visitor update; continuing airport work."
                return false
            end
        end
        local target = Mausoleum.DoorCenter()
        if target and state.Phase ~= "Empty" then
            moveNear(target)
            if not closeEnough(target, 9) then return true end
            if state.Phase == "Mauler" or state.Mauler then
                send("mausoleum:hold", 0.15, "MausoleumMaulerHold")
                taskState = "Holding the mausoleum door"
                return true
            elseif state.Phase == "Waiting" then
                local bad = classifyVisitor(state)
                if bad == true then send("mausoleum:deny", 3, "MausoleumVaporize")
                elseif bad == false then send("mausoleum:open", 3, "MausoleumOpen")
                else
                    send("mausoleum:ask", 8, "MausoleumWhosThere")
                    Extra.blockers.Mausoleum = "Visitor identity is not exposed clearly; awaiting a recognizable tell."
                end
            elseif state.Phase == "Ashes" then
                if not state.DoorOpen then send("mausoleum:ashes", 3, "MausoleumOpen")
                elseif state.Ash and state.Ash.Candy then send("mausoleum:candy", 2, "MausoleumTakeAsh") end
            end
            taskState = "Inspecting mausoleum visitor"
            return true
        end
    end
    return false
end

expandedTick = function()
    if IS_LOBBY then return false end
    local S = Extra.state
    for key, action in Extra.story do
        if os.clock() >= action.at then
            if A.Features.Story then send("story:" .. key, 1, action.action, table.unpack(action.args, 1, action.args.n)) end
            Extra.story[key] = nil
        end
    end
    -- Resume active witch deliveries after late injection.
    if Witch and A.Features.Deliveries then
        local current = sessionFrom(Witch.BREW_TICK_REMOTE, function(v) return v.Cauldron and v.Rows end)
        if current then
            local request = requests[current.Uid]
            if request then request.target = current.Cauldron end
        end
    end
    if next(sessions) or Player:GetAttribute("OperatingMinigame") then return false end
    if A.Features.Defense and S.lockdown then
        local anchors = S.defend or Collection:GetTagged("LockdownDefend")
        for _, anchor in anchors do
            if typeof(anchor) == "Instance" and anchor.Parent then
                local target = position(anchor)
                if target then
                    if closeEnough(target, anchor:GetAttribute("Distance") or 10) then
                        send("defend:" .. anchor:GetFullName(), math.max(0.12, anchor:GetAttribute("Debounce") or 0.12), "LockdownDefend", anchor)
                    else moveNear(target) end
                    taskState = "Defending lockdown barricade"
                    return true
                end
            end
        end
    end
    if A.Features.Defense then
        for key, turret in Extra.turrets do
            if turret.Phase == "Armed" or turret.Phase == "Ready" then
                local target = typeof(turret.Button) == "Instance" and position(turret.Button)
                if target then
                    moveNear(target)
                    if closeEnough(target, 8) then send("turret:" .. key, 2.6, "TurretPress", key) end
                    taskState = "Firing armed interrogation turret"
                    return true
                end
            end
        end
    end
    if A.Features.Treatment then
        local main = Player.PlayerGui:FindFirstChild("Main")
        local label = main and main:FindFirstChild("CrashOutPercent", true)
        local stress = S.stress or (label and tonumber(label.Text:match("%d+"))) or 0
        local shouldDrink = (A.Features.ColaAlways and stress > 0) or stress >= 55
        if shouldDrink and os.clock() >= (S.colaRetryAt or 0) then
            local cola = obtain("Cola")
            if not cola and A.SupplyBlocked.Cola then S.colaRetryAt = A.SupplyBlocked.Cola; return false end
            S.colaAttemptAt = S.colaAttemptAt or os.clock()
            if not cola and os.clock() - S.colaAttemptAt > 2 then
                S.colaAttemptAt = nil; S.colaRetryAt = os.clock() + 5
                return false
            end
            if cola then
                equip(cola)
                if os.clock() - (lastSent["cola:drink"] or -math.huge) >= 2.1 then
                    S.colaAttemptAt = nil
                    S.colaRetryAt = os.clock() + 2.1
                    lastSent["cola:drink"] = os.clock()
                    A.ColaStats.Attempts += 1
                    A.ColaStats.LastStressBefore = stress
                    cola:Activate()
                    log("Drinking cola to reduce crash out")
                end
            end
            taskState = "Reducing crash out"
            return true
        end
        for _, tag in {"InfectedPassenger","WaterFountain"} do
            for _, model in Collection:GetTagged(tag) do
                if model.Parent and (tag == "InfectedPassenger" or model:GetAttribute("Infected") == true) then
                    local target = position(model)
                    if target then
                        local payload = tag == "InfectedPassenger" and {Uid = model:GetAttribute("NpcId")} or {Id = model:GetAttribute("Id")}
                        taskState = "Disinfecting " .. model.Name
                        return useNear("Disinfectant", target, "DisinfectantUse", payload, "disinfect:" .. model:GetFullName())
                    end
                end
            end
        end
    end
    -- Optional prompts must not steal movement during an unlock or pickup.
    if S.unlockAt or S.candyPending then return false end
    if os.clock() >= Extra.nextScan then
        Extra.nextScan = os.clock() + 0.25
        for prompt in originals do
            if autoPromptAllowed(prompt) then
                local action = prompt.ActionText:lower()
                local path = prompt:GetFullName()
                if action:find("repair camera",1,true) or action=="take diamond" or action=="inspect"
                    or action=="look under the hat" or action=="hear him out" or action=="read letter"
                    then
                    if nativePrompt(prompt,"expanded:" .. path,0.65) then return true end
                end
            end
        end
    end
    return false
end

expandedSync = function()
    if IS_LOBBY then return end
    if A.Features.Story and type(registry)=="table" then
        for event, action in {JeffreyFavorPrompt="JeffreyHearOut",BritneyPrompt="BritneyDeny"} do
            for _, callback in registry[event] or {} do
                for _, records in debug.getupvalues(callback) do
                    if type(records)=="table" then
                        for uid, record in records do
                            if type(uid)=="string" and type(record)=="table" and record.Prompt then
                                delayed("recover:" .. event .. uid, 0.5, action, uid)
                            end
                        end
                    end
                end
            end
        end
        local heldLetter = sessionFrom("JeffreyLetterRead",function(v) return v.Model and v.Held ~= nil end)
        if heldLetter then delayed("recover:letter",3,"JeffreyLetterFinished") end
    end
    local queries = {
        {"FetchInterrogationTurretStates","turrets"}, {"FetchGraveyard","grave"},
        {"FetchGraveyardPumpkins","pumpkin"}, {"FetchMausoleum","mausoleum"},
        {"FetchWitchBrew","brew"}, {"FetchCongaPumpkin","conga"}, {"FetchCrashOut","stress"},
        {"WallTaserGetState","taser"},
    }
    for _, query in queries do
        if not A.Running then return end
        local ok, value, received = pcall(function() return invokeServer(query[1]) end)
        if ok and received and value ~= nil then
            if query[2]=="turrets" and type(value)=="table" then
                for _, state in value do if type(state)=="table" and state.Key then Extra.turrets[state.Key]=state end end
            elseif query[2]=="grave" and type(value)=="table" then
                Extra.state.graveKey=value.Key; Extra.state.graveTrail=value.Trail
                Extra.state.graveOpen=value.Unlocked; Extra.state.graveHold=value.HoldSeconds
            elseif query[2]=="pumpkin" and type(value)=="table" then
                Extra.state.pumpkins=value.State; Extra.state.placeSeconds=value.PlaceSeconds
                for _, item in value.Loose or {} do Extra.loose[item.Id]=item end
            elseif query[2]=="brew" then
                if type(value)=="table" and value.Brewing then addBrew(value) end
            elseif query[2]=="taser" and type(value)=="table" then
                A.WallTaserState = value
            elseif query[2]=="conga" then
                setCongaState(value)
            else Extra.state[query[2]]=value end
        end
        task.wait(0.05)
    end
end

local LobbyCmds
if IS_LOBBY then LobbyCmds = require(RS.Game.Lobby.Client.LobbyPartyCmds) end
local function workLobby()
    if not A.Features.AutoReplay or not LobbyCmds then return end
    if LobbyCmds.IsDeparting() then
        taskState = "Starting a new run"
        return
    end
    local pad = LobbyCmds.GetPad()
    if pad then
        local party = LobbyCmds.GetPartyOnPad()
        if not party or not party.Members or #party.Members == 0 then
            if os.clock() - (lastSent["lobby:create"] or -math.huge) >= 3 then
                lastSent["lobby:create"] = os.clock()
                LobbyCmds.CreateParty(1, true)
                log("Starting solo run")
            end
        end
        taskState = "Waiting for solo run departure"
        return
    end
    local pads = workspace:FindFirstChild("LobbyPads")
    local character = Player.Character
    if not pads or not character then return end
    for _, anchor in pads:GetChildren() do
        local id = anchor:GetAttribute("PadId")
        if id and anchor:IsA("BasePart") then
            local party = LobbyCmds.GetParty(id)
            if not party or not party.Members or #party.Members == 0 then
                if os.clock() - lastMove >= 2 then
                    lastMove = os.clock()
                    character:PivotTo(anchor.CFrame + Vector3.new(0, 3, 0))
                end
                taskState = "Joining empty lobby pad " .. id
                return
            end
        end
    end
    taskState = "Waiting for an empty lobby pad"
end

local function returnAfterRun()
    if not A.Features.AutoReplay then return end
    local gui = Player.PlayerGui:FindFirstChild("GameOver")
    if gui and gui:IsA("ScreenGui") and gui.Enabled then
        send("run:restart", 5, "GameOverReturnToLobby")
        taskState = "Run finished; returning to lobby"
    end
end

local idleSince = os.clock()
local lastIdleActions = A.Actions
local function waitInControlRoom(busy)
    if busy or next(sessions) or next(holds) or next(talks)
        or Player:GetAttribute("OperatingMinigame") or A.Actions ~= lastIdleActions then
        idleSince = os.clock()
        lastIdleActions = A.Actions
        A.WaitingInControlRoom = false
        return
    end
    if not A.ReturnToControlRoom or not A.AutoMove or os.clock() - idleSince < 2.5 then return end
    local gameOver = Player.PlayerGui:FindFirstChild("GameOver")
    if gameOver and gameOver:IsA("ScreenGui") and gameOver.Enabled then return end
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then return end
    -- Pick a walkable navigation node in the middle of the actual office.
    if not A.ControlRoomCFrame then
        local nav = workspace:FindFirstChild("Nav")
        local nodes = nav and nav:FindFirstChild("Nodes")
        local office = nodes and nodes:FindFirstChild("Office")
        if not office then return end
        local sum, count = Vector3.zero, 0
        for _, node in office:GetChildren() do
            if node:IsA("BasePart") then sum += node.Position; count += 1 end
        end
        if count == 0 then return end
        local center = sum / count
        local nearest, distance = nil, math.huge
        for _, node in office:GetChildren() do
            if node:IsA("BasePart") then
                local d = (node.Position - center).Magnitude
                if d < distance then nearest = node; distance = d end
            end
        end
        if not nearest then return end
        local spot = nearest.Position + Vector3.new(0, 3.2, 0)
        local screen = Collection:GetTagged("CameraScreen")[1]
        local look = screen and position(screen)
        A.ControlRoomCFrame = look and CFrame.lookAt(spot, Vector3.new(look.X, spot.Y, look.Z)) or CFrame.new(spot)
    end
    if (root.Position - A.ControlRoomCFrame.Position).Magnitude > 5 and os.clock() - lastMove >= 1 then
        lastMove = os.clock()
        character:PivotTo(A.ControlRoomCFrame)
    end
    local reason = "Waiting in the control room"
    if ShiftState then
        local checkins = ShiftState.GetCheckinsRemaining()
        local scans = ShiftState.GetScansRemaining()
        local interrogations = ShiftState.GetInterrogationsRemaining()
        if checkins > 0 then
            reason = "Control room: waiting for " .. checkins .. " passenger check-in(s)"
        elseif scans > 0 then
            reason = "Control room: waiting for " .. scans .. " passenger scan(s)"
        elseif interrogations > 0 then
            reason = "Control room: waiting for an interrogation assignment"
        elseif ShiftState.IsBoardingReady() then
            reason = "Control room: waiting for passengers to board"
        end
    end
    if not A.WaitingInControlRoom then log(reason) end
    A.WaitingInControlRoom = true
    taskState = reason
end

task.spawn(function()
    setthreadidentity(8)
    local syncing, expandedSyncing = false, false
    local function queueSync()
        if syncing or not A.Running then return end
        syncing = true
        task.spawn(function()
            setthreadidentity(8)
            pcall(recoverDeliveries)
            local ok, problem = pcall(sync)
            if not ok then A.LastError = tostring(problem) end
            syncing = false
        end)
    end
    local function queueExpandedSync()
        if expandedSyncing or not A.Running then return end
        expandedSyncing = true
        task.spawn(function()
            setthreadidentity(8)
            local ok, problem = pcall(expandedSync)
            if not ok then A.LastError = tostring(problem) end
            expandedSyncing = false
        end)
    end
    queueSync()
    queueExpandedSync()
    task.spawn(function()
        setthreadidentity(8)
        local emergencyList = not IS_LOBBY and invokeServer("FetchEmergencies") or {}
        if type(emergencyList) == "table" then
            for _, entry in emergencyList do
                if type(entry) == "table" and entry.Uid then
                    emergencies[entry.Uid] = entry
                    Extra.emergencyTypes[entry.Uid] = entry.Id
                end
            end
        end
        local dale = not IS_LOBBY and invokeServer("FetchDaleAsk") or nil
        if type(dale) == "table" and dale.Uid and dale.Item then newRequest(dale.Uid, {dale.Item}, "DaleGive", "Dale") end
    end)
    local nextExpandedSync = os.clock() + 25
    local nextSync = os.clock() + 8
    while A.Running do
        if A.Enabled then
            local worked, problem = pcall(function()
                if IS_LOBBY then workLobby(); return end
                returnAfterRun()
                if A.AttackActive or A.FightingBack or A.Tasing then
                    taskState = A.Tasing and "Using the taser against an anomaly" or (A.Features.FightBack and "Fighting back against the anomaly" or "Attack: waiting for manual fight back")
                    return
                end
                if A.ToadActive then
                    taskState = "Toad curse: safe recovery (" .. math.floor(os.clock() - (A.ToadAt or os.clock())) .. "s)"
                    return
                end
                if workspace:GetServerTimeNow() < (A.WitchSafeUntil or 0) then taskState = "Staying clear of the witch potion"; return end
                local groundFireBusy = workFirePrompts and workFirePrompts()
                local alreadyOperating = next(sessions) ~= nil or Player:GetAttribute("OperatingMinigame") == true
                -- Checkpoint commands do not move the character and can run
                -- while a minigame owns the camera and movement.
                for id, tracks in stages do for _, payload in tracks do workStation(id, payload) end end
                if not groundFireBusy and not alreadyOperating and not nativePromptHold and not next(holds) and A.Features.Interrogations then
                    for uid in talks do send("talk:" .. uid, 0.6, "InterrogationTalk", uid) end
                end
                -- Handle emergency work before starting another test; never
                -- interrupt a test that already owns the player's controls.
                local urgentWork = groundFireBusy or nativePromptHold ~= nil or (not alreadyOperating and ((dispatchTasks and dispatchTasks())
                    or (workGhostEmergency and workGhostEmergency()) or (workEmergencyPrompts and workEmergencyPrompts())
                    or (workWitchResponse and workWitchResponse())))
                local preparingTest = (alreadyOperating or not urgentWork) and workMinigames()
                local minigameBusy = preparingTest or next(sessions) ~= nil or Player:GetAttribute("OperatingMinigame") == true
                local busy = urgentWork or minigameBusy
                if not busy then busy = workInterrogationPrompts() end
                if not busy and expandedTick then busy = expandedTick() end
                if not busy and seasonalTasks then busy = seasonalTasks() end
                if not busy then busy = workPrompts() end
                if not busy and stockFireTool then busy = stockFireTool() end
                if not busy and stockTaser then busy = stockTaser() end
                if not busy and stockCrucifix then busy = stockCrucifix() end
                if not busy and workUpgrades then busy = workUpgrades() end
                waitInControlRoom(busy)
            end)
            if not worked then A.LastError = tostring(problem) end
        end
        if os.clock() >= nextExpandedSync then
            nextExpandedSync = os.clock() + 25
            queueExpandedSync()
        end
        if os.clock() >= nextSync then
            nextSync = os.clock() + 8
            queueSync()
        end
        task.wait(0.03)
    end
end)
print("[AirportAuto] Active. F6 = pause/resume. End = stop and restore prompts.")

-- Miz0 Hub / custom light-blue WindUI glass theme.
A.Status = function()
    return {Running = A.Running, Enabled = A.Enabled, Actions = A.Actions,
        Latest = A.LastAction, Task = taskState, PendingDeliveries = requests, Coverage = A.Coverage, Blockers = A.Blockers, Error = A.LastError, Verified = A.Verified,
        WaitingInControlRoom = A.WaitingInControlRoom == true, ControlRoomCFrame = A.ControlRoomCFrame,
        ActiveMinigames = sessions, FireHoldActive = nativePromptHold ~= nil, LastEmergencyOutcome = A.LastEmergencyOutcome,
        CircleStats = A.CircleStats, BrainStats = A.BrainStats, FingerprintStats = A.FingerprintStats, FireStats = A.FireStats, ServerTimeouts = A.ServerTimeouts,
        FightBackStats = A.FightBackStats, TaserStats = A.TaserStats, EmergencyStats = A.EmergencyStats, EmergencySupport = A.EmergencySupport, HauntStats = A.HauntStats, UpgradeStats = A.UpgradeStats, ColaStats = A.ColaStats, ToadActive = A.ToadActive == true, AttackActive = A.AttackActive, TaserActive = A.Tasing == true,
        Halloween = {GraveyardOpen = Extra.state.graveOpen == true, UnlockHolding = Extra.state.unlockAt ~= nil,
            CandyTarget = Extra.state.candyTarget, CandyPending = Extra.state.candyPending and Extra.state.candyPending.id}}
end
local Hub = {Status = A.Status, Stop = stop, Controls = {}, CollectItem = obtain}
Env.Miz0Hub = Hub

task.spawn(function()
    setthreadidentity(8)
    local ok, problem = pcall(function()
        local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
        if not A.Running then return end
        WindUI:SetParent(Player:WaitForChild("PlayerGui"))
        local theme = table.clone(WindUI:GetThemes().Light)
        theme.Name = "Miz0 Light Blue"
        local colors = {
            Accent = "D8EEFF", Background = "DCEFFF", Dialog = "EAF6FF",
            Outline = "91BFE0", Text = "163850", Placeholder = "53728B",
            Button = "397CA8", Icon = "36759F", Toggle = "59B5EE",
            Slider = "59B5EE", Checkbox = "59B5EE", PanelBackground = "CEE8FA",
            ElementBackground = "F0F9FF", TabBackground = "E4F3FD",
            TabBackgroundActive = "A6D7F6", TabBackgroundHover = "C6E7FC",
            DropdownBackground = "EBF7FF", DropdownTabBackground = "C0E1F8",
            LabelBackground = "C8E7FC",
        }
        for name, hex in colors do theme[name] = Color3.fromHex(hex) end
        theme.PanelBackgroundTransparency = 0.48
        theme.ElementBackgroundTransparency = 0.22
        WindUI:AddTheme(theme)

        -- The supplied picture is embedded so this file stays portable.
        local picture
        if type(getcustomasset) == "function" and type(writefile) == "function" then
            local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local lookup = {}
            for index=1,#alphabet do lookup[alphabet:sub(index,index)] = index-1 end
            local encoded = "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"
            local bytes, value, bits = {}, 0, 0
            for index=1,#encoded do
                local n = lookup[encoded:sub(index,index)]
                if n then
                    value = value*64+n
                    bits += 6
                    if bits >= 8 then
                        bits -= 8
                        table.insert(bytes,string.char(math.floor(value / 2^bits) % 256))
                        value %= 2^bits
                    end
                end
                if index % 4096 == 0 then task.wait() end
            end
            writefile("Miz0Hub/portrait.jpg",table.concat(bytes))
            picture = getcustomasset("Miz0Hub/portrait.jpg")
        end
        local touchLayout = UIS.TouchEnabled and not UIS.KeyboardEnabled
        local preferredScale = 1
        local function layoutFor(viewport)
            return {
                width = math.min(650, math.max(280, viewport.X-24)),
                height = math.min(540, math.max(260, viewport.Y-72)),
                sidebar = (touchLayout or viewport.X < 560) and 122 or 178,
            }
        end
        Hub.LayoutFor = layoutFor
        local initialLayout = layoutFor(workspace.CurrentCamera.ViewportSize)

        local Window = WindUI:CreateWindow({
            Title = "Miz0 Hub",
            Author = "Airport Security  /  Blue Hour",
            Icon = picture or "plane",
            Folder = "Miz0Hub",
            Theme = theme.Name,
            Size = UDim2.fromOffset(initialLayout.width, initialLayout.height),
            MinSize = Vector2.new(280,260),
            MaxSize = Vector2.new(850,800),
            SideBarWidth = initialLayout.sidebar,
            AutoScale = true,
            Radius = 18,
            ElementsRadius = 12,
            NewElements = true,
            Transparent = true,
            Acrylic = false,
            Resizable = not touchLayout,
            HideSearchBar = true,
            ScrollBarEnabled = true,
            IgnoreAlerts = true,
            Background = WindUI:Gradient({
                ["0"] = {Color = Color3.fromHex("E2F5FF"), Transparency = 0.10},
                ["100"] = {Color = Color3.fromHex("ACD7F4"), Transparency = 0.08},
            }, {Rotation = 32}),
            BackgroundImageTransparency = 0.25,
            User = {Enabled = not touchLayout, Anonymous = false},
            OpenButton = {
                Title = "Miz0 Hub", Icon = "plane", Enabled = false,
                OnlyMobile = false, Draggable = true,
                Color = ColorSequence.new(Color3.fromHex("80CCFA"), Color3.fromHex("B6E4FF")),
            },
        })
        HubWindow = Window
        Hub.Window = Window
        Window:SetToggleKey(Enum.KeyCode.RightShift)
        Window:SetBackgroundTransparency(0.12)
        WindUI:ToggleAcrylic(false)
        A.BlurEnabled = true
        local Lighting = game:GetService("Lighting")
        local previousBlur = Lighting:FindFirstChild("Miz0HubSoftBlur")
        if previousBlur then previousBlur:Destroy() end
        softBlur = Instance.new("BlurEffect")
        softBlur.Name = "Miz0HubSoftBlur"
        softBlur.Size = 6
        softBlur.Parent = Lighting
        if type(Window.OnOpen) == "function" then Window:OnOpen(function() if softBlur then softBlur.Enabled = A.BlurEnabled end end) end
        if type(Window.OnClose) == "function" then Window:OnClose(function() if softBlur then softBlur.Enabled = false end end) end
        if not touchLayout and initialLayout.width >= 560 then Window:Tag({Title = "BLUE HOUR", Color = Color3.fromHex("4B9DCE")}) end
        if picture then Window:SetBackgroundImage(picture); Window:SetBackgroundImageTransparency(0.15) end
        Window:OnDestroy(function()
            if A.Running then stop() end
        end)
        -- Put the menu above the game's floating world labels.
        local playerGui = Player.PlayerGui
        for _, screen in playerGui:GetChildren() do
            if screen:IsA("ScreenGui") then
                for _, label in screen:GetDescendants() do
                    if label:IsA("TextLabel") and label.Text == "Miz0 Hub" then
                        screen.DisplayOrder = 10000
                        break
                    end
                end
            end
        end


        local function fitWindow()
            setthreadidentity(8)
            if not A.Running then return end
            local viewport = workspace.CurrentCamera.ViewportSize
            local layout = layoutFor(viewport)
            Window:SetSize(UDim2.fromOffset(layout.width,layout.height))
            local fit = math.min((viewport.X-16)/layout.width,(viewport.Y-60)/layout.height,1.2)
            Window:SetUIScale(math.min(preferredScale,fit))
        end
        local function watchCamera()
            local camera = workspace.CurrentCamera
            if camera then connect(camera:GetPropertyChangedSignal("ViewportSize"),fitWindow) end
            fitWindow()
        end
        connect(workspace:GetPropertyChangedSignal("CurrentCamera"),watchCamera)
        watchCamera()
        RunService:UnbindFromRenderStep("Miz0HubCursor")
        RunService:BindToRenderStep("Miz0HubCursor",Enum.RenderPriority.Last.Value+10,function()
            if not A.Running then return end
            local opened = Window.Closed == false and not Window.Destroyed
            A.MenuOpen = opened
            if UIS.MouseEnabled then
                if opened then
                    if not cursorCaptured then
                        savedMouseBehavior = UIS.MouseBehavior
                        savedMouseIcon = UIS.MouseIconEnabled
                        cursorCaptured = true
                    end
                    if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then UIS.MouseBehavior = Enum.MouseBehavior.Default end
                    if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
                else
                    releaseMenuMouse()
                end
            end
            if launcherFrame then launcherFrame.Visible = not opened end
        end)

        -- A small touch-friendly launcher, positioned independently of the window.
        local guiRoot = Player.PlayerGui:FindFirstChild("WindUI")
        if guiRoot then
            local launcher = Instance.new("TextButton")
            launcher.Name = "Miz0Open"
            launcherFrame = launcher
            launcher.AnchorPoint = Vector2.new(0, 0.5)
            launcher.Position = UDim2.new(0, 12, 0.5, 0)
            launcher.Size = UDim2.fromOffset(116, 42)
            launcher.BackgroundColor3 = Color3.new(1, 1, 1)
            launcher.BackgroundTransparency = 0.06
            launcher.BorderSizePixel = 0
            launcher.Text = "Miz0 Hub  ›"
            launcher.TextColor3 = Color3.fromHex("244B67")
            launcher.TextSize = 14
            launcher.Font = Enum.Font.GothamMedium
            launcher.AutoButtonColor = true
            launcher.Visible = false
            launcher.ZIndex = 100
            launcher.Parent = guiRoot
            local sky = Instance.new("UIGradient")
            sky.Name = "Miz0SkyGradient"
            sky.Rotation = 90
            sky.Color = ColorSequence.new(Color3.fromHex("F3FBFF"), Color3.fromHex("BCDEFA"))
            sky.Parent = launcher
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 15)
            corner.Parent = launcher
            local border = Instance.new("UIStroke")
            border.Color = Color3.fromHex("8EBDE0")
            border.Thickness = 0.8
            border.Transparency = 0.3
            border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            border.Parent = launcher
            local dragging, dragOrigin, startPosition, dragInput
            local draggedAt = -math.huge
            connect(launcher.InputBegan, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragOrigin = input.Position
                    startPosition = launcher.Position
                    dragInput = input
                end
            end)
            connect(UIS.InputChanged, function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
                    local delta = input.Position - dragOrigin
                    if delta.Magnitude > 6 then
                        draggedAt = os.clock()
                        local view = workspace.CurrentCamera.ViewportSize
                        local x = math.clamp(startPosition.X.Offset + delta.X, 4, math.max(4, view.X - 120))
                        local y = math.clamp(startPosition.Y.Scale * view.Y + startPosition.Y.Offset + delta.Y, 25, math.max(25, view.Y - 25))
                        launcher.Position = UDim2.fromOffset(x, y)
                    end
                end
            end)
            connect(UIS.InputEnded, function(input)
                if input == dragInput then dragging = false; dragInput = nil end
            end)
            connect(launcher.Activated, function()
                if os.clock() - draggedAt > 0.25 then Window:Open() end
            end)
        end

        local disclaimer = Window:Tab({Title = "Disclaimer", Icon = "info"})
        disclaimer:Button({
            Title = "Credit Miz0",
            Desc = "If you share or redistribute Miz0 Hub, give credit to Miz0.",
            Icon = "info",
            Callback = function() end,
        })
        local main = Window:Tab({Title = "Control Room", Icon = "zap"})
        main:Button({Title = "Miz0  /  Blue Hour", Desc = "Your airport control desk.", Icon = picture or "plane", Callback = function() end})
        local checks = Window:Tab({Title = "Checkpoint", Icon = "scan-line"})
        local tasks = Window:Tab({Title = "Missions", Icon = "package"})
        local style = Window:Tab({Title = "Style", Icon = "palette"})
        local controls = Window:Tab({Title = "Quick Keys", Icon = "keyboard"})
        local coverageTab = Window:Tab({Title = "Coverage", Icon = "list-checks"})
        local coverageRows = {}
        for _, key in {"Checkin","BodyScan","Baggage","LieDetector","BrainScan","EyeExam","Fingerprint","SnackDeliveries","WitchBrew","Medical","Firefighting","Infections","Exorcism","Cola","CameraRepair","Turrets","Lockdown","FightBack","SpecialPassengers","Letters","Graveyard","Candy","Pumpkins","Mausoleum","Replay"} do
            coverageRows[key] = coverageTab:Button({Title = key:gsub("(%l)(%u)","%1 %2"),
                Desc = "Routine enabled; waiting for a completion during this run.", Callback = function() end})
        end

        masterToggle = main:Toggle({
            Title = "Miz0 Autopilot",
            Desc = "Handles the enabled work stages automatically.",
            Value = A.Enabled,
            Callback = function(value)
                setthreadidentity(8)
                if A.Running and A.Enabled ~= value then
                    A.Enabled = value
                    if not value then cancelHolds(); restorePrivate() end
                    log(value and "Resumed" or "Paused")
                end
            end,
        })
        Hub.Controls.Automation = masterToggle
        local instant = main:Toggle({
            Title = "Tap & Go",
            Desc = "Use prompts immediately, without holding the key.",
            Value = A.InstantPrompts,
            Callback = function(value)
                setthreadidentity(8)
                A.InstantPrompts = value
                for prompt, record in originals do
                    if prompt.Parent and not record.nativeHold then prompt.HoldDuration = value and 0 or record.hold end
                end
            end,
        })
        Hub.Controls.InstantPrompts = instant
        Hub.Controls.AutoMove = main:Toggle({
            Title = "Smart Routes",
            Desc = "Moves to active task prompts when required.",
            Value = A.AutoMove,
            Callback = function(value) A.AutoMove = value end,
        })
        Hub.Controls.IdleReturn = main:Toggle({
            Title = "Wait in Control Room",
            Desc = "Return to the office after a short idle wait, then leave for the next task.",
            Value = A.ReturnToControlRoom,
            Callback = function(value) A.ReturnToControlRoom = value end,
        })
        local function feature(title, description, key, tab)
            Hub.Controls[key] = (tab or checks):Toggle({
                Title = title, Desc = description, Value = A.Features[key],
                Callback = function(value)
                    A.Features[key] = value
                    if key == "Interrogations" and not value then restorePrivate() end
                end,
            })
        end
        feature("Auto Check-in", "Take ID, insert ID, take photo, print and hand over the pass.", "Checkin")
        feature("Auto Baggage", "Read luggage contents and handle pass / search decisions.", "Luggage")
        feature("Auto Body Scan", "Scan passengers and identify marked anomalies.", "BodyScan")
        feature("Auto Interrogations", "Handle interrogation setup and supported minigames.", "Interrogations")
        feature("Auto Task Prompts", "Interact with active work and emergency prompts.", "TaskPrompts")

        feature("Auto Special Passengers", "Handle special passenger dialogue and story prompts.", "Story", tasks)
        feature("Auto Defense", "Lockdown barricades and armed interrogation turrets.", "Defense", tasks)
        feature("Auto Cola & Treatment", "Reduce crash out and treat infections.", "Treatment", tasks)
        feature("Keep Drinking Cola", "Drink whenever stress is above zero, including below 50%, while supplies are available.", "ColaAlways", tasks)
        feature("Auto Seasonal Tasks", "Graveyard key, candy, pumpkins and witch deliveries.", "Collectibles", tasks)
        feature("Auto Mausoleum", "Inspect visitors and act when their identity is recognizable.", "Mausoleum", tasks)
        feature("Auto Start Next Run", "Starts a solo run from an empty lobby pad and retries after game over.", "AutoReplay", tasks)
        feature("Auto Snack Deliveries", "Collect, equip and give every requested snack in order.", "Deliveries", tasks)
        feature("Auto Restock Supplies", "Pick up the requested food or required reusable tool.", "Restock", tasks)
        feature("Auto Emergency Tasks", "Handle burning, downed and possessed passengers and altar rescues.", "Emergencies", tasks)
        feature("Auto Buy Upgrades", "Buy affordable upgrade offers with run cash, starting with the cheapest available option.", "Upgrades", tasks)
        feature("Auto Ghost Exorcism", "Collect a crucifix and exorcise visible haunting ghosts.", "Haunt", tasks)
        feature("Auto Witch & Toad Safety", "Avoid potions and hex zones, target flying witches, and recover safely from a toad curse.", "WitchSafety", tasks)
        feature("Auto Taser Anomalies", "Collect a wall taser and fire at nearby hostile anomalies. Uses the game\'s taser range and cooldown.", "Taser", tasks)
        feature("Auto Fight Back", "React immediately and press at the game\'s allowed rate when an anomaly grabs you.", "FightBack", tasks)
        tasks:Button({Title = "Refresh Existing Requests", Desc = "Recover snack requests already visible when the script loaded.",
            Icon = "refresh-cw", Callback = function() setthreadidentity(8); recoverDeliveries() end})

        Hub.Controls.Blur = style:Toggle({
            Title = "Soft Background Blur", Desc = "A gentle blur behind the light-blue glass menu.",
            Value = true,
            Callback = function(value)
                setthreadidentity(8)
                A.BlurEnabled = value
                if softBlur then softBlur.Enabled = value end
            end,
        })
        style:Slider({
            Title = "Picture Visibility",
            Desc = "Your artwork fills the menu background.",
            Value = {Min = 10, Max = 100, Default = 85},
            Step = 5,
            Callback = function(value)
                setthreadidentity(8)
                Window:SetBackgroundImageTransparency(1 - value / 100)
            end,
        })
        style:Slider({
            Title = "Glass Transparency",
            Value = {Min = 0, Max = 45, Default = 12},
            Step = 1,
            Callback = function(value)
                setthreadidentity(8)
                Window:SetBackgroundTransparency(value / 100)
            end,
        })
        style:Slider({
            Title = "Menu Scale",
            Value = {Min = 80, Max = 120, Default = 100},
            Step = 5,
            Callback = function(value) preferredScale = value / 100; fitWindow() end,
        })
        controls:Button({
            Title = touchLayout and "Touch Controls" or "PC Controls",
            Desc = touchLayout and "Tap the Miz0 Hub button to reopen. Use Autopilot to pause or resume." or "Right Shift opens the menu and frees the mouse. F6 pauses. End stops.",
            Icon = "keyboard",
            Callback = function() end,
        })
        controls:Button({
            Title = "Stop & Unload",
            Desc = "Stops automation, restores prompt settings and removes Miz0 Hub.",
            Icon = "power",
            Callback = stop,
        })
        -- Plain rounded backgrounds avoid artifacts from clipping nine-slice textures.
        local TweenService = game:GetService("TweenService")
        local function removeCornerTexture(object)
            object.Image = ""
            connect(object:GetPropertyChangedSignal("Image"), function()
                if object.Image ~= "" then object.Image = "" end
            end)
        end
        local function skyButton(row, topbar)
            if not row:IsA("ImageButton") or row:GetAttribute("Miz0Styled") then return end
            if not topbar and (not row.Parent:IsA("ScrollingFrame") or not row:FindFirstChild("TitleFrame", true)) then return end
            row:SetAttribute("Miz0Styled", true)
            removeCornerTexture(row)
            row.ImageTransparency = 1
            row.BackgroundColor3 = Color3.new(1, 1, 1)
            row.BackgroundTransparency = topbar and 0.42 or 0.14
            -- Native hover/lock overlays use the same corner textures. Keep their
            -- labels and input behavior while removing only the full-card images.
            for _, layer in row:GetDescendants() do
                local parent = layer.Parent
                if layer:IsA("ImageLabel") and parent and parent:IsA("Frame") and parent.Parent == row
                    and parent.Size.X.Scale >= 0.9 and parent.Size.Y.Scale >= 0.9
                    and layer.Size.X.Scale >= 0.9 and layer.Size.Y.Scale >= 0.9 then
                    removeCornerTexture(layer)
                end
            end
            local gradient = Instance.new("UIGradient")
            gradient.Name = "Miz0SkyGradient"
            gradient.Rotation = 90
            gradient.Color = ColorSequence.new(Color3.fromHex("F3FBFF"), Color3.fromHex("CEE9FB"))
            gradient.Parent = row
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, topbar and 10 or 12)
            corner.Parent = row
            local outline = Instance.new("UIStroke")
            outline.Name = "Miz0SkyEdge"
            outline.Color = Color3.fromHex("8EBDE0")
            outline.Thickness = 0.8
            outline.Transparency = 0.52
            outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            outline.Parent = row
            if not topbar then
                for _, decoration in row:GetChildren() do
                    if decoration:IsA("Frame") and decoration:FindFirstChildOfClass("ImageLabel")
                        and decoration.Size.X.Scale == 0 and decoration.Size.Y.Scale == 0
                        and decoration.Size.X.Offset <= 24 and decoration.Size.Y.Offset <= 24
                        and not decoration:FindFirstChildWhichIsA("GuiButton", true) then
                        decoration.Visible = false
                    end
                end
                for _, label in row:GetDescendants() do
                    if label:IsA("TextLabel") then label.TextColor3 = Color3.fromHex("244B67") end
                end
            end
            local hovered = false
            local animation
            local function highlight(pressed)
                if animation then animation:Cancel() end
                animation = TweenService:Create(outline, TweenInfo.new(0.15), {
                    Transparency = pressed and 0.05 or (hovered and 0.22 or 0.52),
                    Thickness = pressed and 1.25 or 0.8,
                })
                animation:Play()
            end
            connect(row.MouseEnter, function() hovered = true; highlight(false) end)
            connect(row.MouseLeave, function() hovered = false; highlight(false) end)
            connect(row.InputBegan, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then highlight(true) end
            end)
            connect(row.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then highlight(false) end
            end)
        end
        local windGui = Player.PlayerGui:FindFirstChild("WindUI")
        if windGui then
            for _, row in windGui:GetDescendants() do
                if row:IsA("TextLabel") and row.Text == "Locked" then row.Visible = false end
                skyButton(row, false)
            end
            local topbar = windGui:FindFirstChild("Topbar", true)
            if topbar then
                for _, row in topbar:GetDescendants() do skyButton(row, true) end
            end
            -- Keep decorative accents inside the welcome card, clear of controls.
            for _, label in windGui:GetDescendants() do
                if label:IsA("TextLabel") and label.Text == "Miz0  /  Blue Hour" then
                    local card = label:FindFirstAncestorWhichIsA("ImageButton")
                    if card then
                        local badge = Instance.new("TextLabel")
                        badge.Name = "Miz0SkyBadge"
                        badge.Visible = card.AbsoluteSize.X >= 300
                        connect(card:GetPropertyChangedSignal("AbsoluteSize"), function() badge.Visible = card.AbsoluteSize.X >= 300 end)
                        badge.AnchorPoint = Vector2.new(1, 0)
                        badge.Position = UDim2.new(1, -14, 0, 12)
                        badge.Size = UDim2.fromOffset(42, 20)
                        badge.BackgroundColor3 = Color3.fromHex("A6D7F6")
                        badge.BackgroundTransparency = 0.35
                        badge.BorderSizePixel = 0
                        badge.Text = "SKY"
                        badge.TextColor3 = Color3.fromHex("35779F")
                        badge.TextSize = 10
                        badge.Font = Enum.Font.GothamMedium
                        badge.ZIndex = card.ZIndex + 3
                        badge.Active = false
                        badge.Parent = card
                        local round = Instance.new("UICorner")
                        round.CornerRadius = UDim.new(1, 0)
                        round.Parent = badge
                        local line = Instance.new("Frame")
                        line.Name = "Miz0SkyAccent"
                        line.Position = UDim2.new(0, 18, 1, -5)
                        line.Size = UDim2.new(1, -36, 0, 1)
                        line.BackgroundColor3 = Color3.fromHex("6BB5E5")
                        line.BackgroundTransparency = 0.25
                        line.BorderSizePixel = 0
                        line.ZIndex = card.ZIndex + 2
                        line.Parent = card
                        local fade = Instance.new("UIGradient")
                        fade.Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 0),
                            NumberSequenceKeypoint.new(0.7, 0.65),
                            NumberSequenceKeypoint.new(1, 1),
                        })
                        fade.Parent = line
                    end
                    break
                end
            end
        end
        Window:SelectTab(1)
        Window:Open()
        Hub.Ready = true
        print("[Miz0 Hub] Light blue WindUI ready. Right Shift opens or hides the menu.")
        local Shift = require(Client.ShiftCmds)
        while A.Running do
            setthreadidentity(8)
            local state = A.Enabled and "Running" or "Paused"
            for key, row in coverageRows do
                local evidence = A.Coverage and A.Coverage[key]
                local count = evidence and evidence.confirmed or 0
                row:SetDesc(count > 0 and ("Completion observed: " .. count) or ((A.Blockers and A.Blockers[key]) or "Routine enabled; waiting for a completion during this run."))
            end
            masterToggle:SetDesc(state .. "  |  " .. (IS_LOBBY and "Lobby" or ("Shift " .. Shift.GetShiftNumber()))
                .. "  |  " .. A.Actions .. " actions\n" .. A.LastAction .. "\n" .. taskState)
            task.wait(1)
        end
    end)
    if not ok then
        A.LastError = "Menu: " .. tostring(problem)
        Hub.Error = A.LastError
        warn("[Miz0 Hub] " .. A.LastError)
    end
end)

-- Re-run the installed copy after a game teleport. Stop & Unload cancels it.
pcall(function()
    writefile("Miz0Hub/enabled.txt", "1")
    if isfile("Miz0Hub/miz0-hub.luau") then
        local alreadyQueued = isfile("Miz0Hub/queued-job.txt") and readfile("Miz0Hub/queued-job.txt") == game.JobId
        if not alreadyQueued then
            writefile("Miz0Hub/queued-job.txt", game.JobId)
            queue_on_teleport([[
                repeat task.wait(1) until game:IsLoaded()
                if game.GameId == 10768761562 then
                    local rs = game:GetService("ReplicatedStorage")
                    rs:WaitForChild("Game", 30)
                    rs:WaitForChild("Network", 30)
                    if isfile("Miz0Hub/enabled.txt") and readfile("Miz0Hub/enabled.txt") == "1"
                        and isfile("Miz0Hub/miz0-hub.luau") then
                        local run, err = loadstring(readfile("Miz0Hub/miz0-hub.luau"))
                        if run then run() else warn("[Miz0 Hub] " .. tostring(err)) end
                    end
                end
            ]])
        end
    end
end)
