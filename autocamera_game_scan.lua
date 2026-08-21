-- AutoCamera Game Scanner
-- Apenas observa e registra estruturas de time, bomba e cronometro.
-- Nao move o personagem e nao altera a camera.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Backpack = LocalPlayer:WaitForChild("Backpack")

local GLOBAL_STATE_NAME = "__nt_autocamera_game_scan"

local environment = _G
pcall(function()
	if getgenv then
		environment = getgenv()
	end
end)

local previousState = environment[GLOBAL_STATE_NAME]
if type(previousState) == "table" and type(previousState.cleanup) == "function" then
	pcall(previousState.cleanup)
end

local state = {
	alive = true,
	connections = {},
	watched = setmetatable({}, {__mode = "k"}),
	lastText = setmetatable({}, {__mode = "k"}),
	lastValue = setmetatable({}, {__mode = "k"}),
	lastAttributes = setmetatable({}, {__mode = "k"}),
	teamSnapshots = {},
}
environment[GLOBAL_STATE_NAME] = state

local BOMB_HINTS = {
	"bomb",
	"bomba",
	"tnt",
	"explosive",
	"holder",
	"carrier",
	"hotpotato",
	"hot_potato",
}

local TIMER_HINTS = {
	"time",
	"timer",
	"countdown",
	"count",
	"fuse",
	"remain",
	"second",
	"clock",
	"duration",
	"explode",
	"detonate",
}

local TEAM_HINTS = {
	"team",
	"squad",
	"side",
	"group",
	"ally",
	"enemy",
}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local function log(section, message)
	warn(string.format("[AC-SCAN][%s] %s", section, message))
end

local function safeFullName(instance)
	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)
	return ok and fullName or tostring(instance)
end

local function lower(value)
	return string.lower(tostring(value or ""))
end

local function containsHint(value, hints)
	local text = lower(value)
	for _, hint in ipairs(hints) do
		if string.find(text, hint, 1, true) then
			return true
		end
	end
	return false
end

local function isSmallTimerNumber(value)
	return type(value) == "number" and value >= 0 and value <= 15
end

local function numberFromText(text)
	local normalized = tostring(text or ""):gsub(",", ".")
	local minutes, seconds = normalized:match("(%d+)%s*:%s*(%d+%.?%d*)")
	if minutes and seconds then
		local total = (tonumber(minutes) * 60) + tonumber(seconds)
		if total >= 0 and total <= 15 then
			return total
		end
	end

	local direct = normalized:match("%f[%d](%d+%.?%d*)%f[^%d%.]")
	local value = tonumber(direct)
	if value and value >= 0 and value <= 15 then
		return value
	end
	return nil
end

local function valueToText(value)
	local valueType = typeof(value)
	if valueType == "Instance" then
		return safeFullName(value)
	elseif valueType == "BrickColor" then
		return value.Name
	elseif valueType == "Color3" then
		return string.format("Color3(%.3f,%.3f,%.3f)", value.R, value.G, value.B)
	end
	return tostring(value)
end

local function isBombContext(instance)
	local current = instance
	for _ = 1, 8 do
		if not current then
			break
		end
		if current:IsA("Tool") or containsHint(current.Name, BOMB_HINTS) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isTimerContext(instance)
	return containsHint(instance.Name, TIMER_HINTS)
		or containsHint(safeFullName(instance), TIMER_HINTS)
end

local function tagsToText(instance)
	local ok, tags = pcall(function()
		return CollectionService:GetTags(instance)
	end)
	if not ok or #tags == 0 then
		return "none"
	end
	table.sort(tags)
	return table.concat(tags, ",")
end

local function reportAttributes(instance, reason, force)
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if not ok then
		return
	end

	local hadSnapshot = state.lastAttributes[instance] ~= nil
	local previous = state.lastAttributes[instance] or {}
	local nextSnapshot = {}
	for name, value in pairs(attributes) do
		nextSnapshot[name] = valueToText(value)
		local relevant = force
			or isBombContext(instance)
			or isTimerContext(instance)
			or containsHint(name, BOMB_HINTS)
			or containsHint(name, TIMER_HINTS)
			or containsHint(name, TEAM_HINTS)
			or isSmallTimerNumber(value)
		if relevant and (force or (hadSnapshot and previous[name] ~= nextSnapshot[name])) then
			log(
				"ATTR",
				string.format(
					"%s | %s | %s=%s",
					reason,
					safeFullName(instance),
					name,
					nextSnapshot[name]
				)
			)
		end
	end
	state.lastAttributes[instance] = nextSnapshot
end

local function reportValue(instance, reason, force)
	if not instance:IsA("ValueBase") then
		return
	end
	local value = instance.Value
	local rendered = valueToText(value)
	local previous = state.lastValue[instance]
	state.lastValue[instance] = rendered

	local relevant = isBombContext(instance)
		or isTimerContext(instance)
		or containsHint(instance.Name, TEAM_HINTS)
		or isSmallTimerNumber(value)
	if relevant and (force or (previous ~= nil and previous ~= rendered)) then
		log(
			"VALUE",
			string.format(
				"%s | %s (%s) = %s",
				reason,
				safeFullName(instance),
				instance.ClassName,
				rendered
			)
		)
	end
end

local function reportText(instance, reason, force)
	if not (instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("TextBox")) then
		return
	end

	local text = tostring(instance.Text or "")
	local previous = state.lastText[instance]
	state.lastText[instance] = text
	local numeric = numberFromText(text)
	local relevant = isBombContext(instance)
		or isTimerContext(instance)
		or numeric ~= nil

	if relevant and (force or (previous ~= nil and previous ~= text)) then
		local visibleText = "unknown"
		pcall(function()
			visibleText = tostring(instance.Visible)
		end)
		log(
			"UI",
			string.format(
				"%s | %s | visible=%s | text=%q | number=%s",
				reason,
				safeFullName(instance),
				visibleText,
				text,
				tostring(numeric)
			)
		)
	end
end

local function watchInstance(instance, forceInitial)
	if not instance or state.watched[instance] then
		return
	end
	state.watched[instance] = true

	local relevantContext = instance:IsA("Tool")
		or instance:IsA("ValueBase")
		or instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("TextBox")
		or isBombContext(instance)
		or isTimerContext(instance)

	if instance:IsA("Tool") then
		log(
			"TOOL",
			string.format(
				"found | %s | parent=%s | tags=%s",
				safeFullName(instance),
				instance.Parent and safeFullName(instance.Parent) or "nil",
				tagsToText(instance)
			)
		)
	elseif containsHint(instance.Name, BOMB_HINTS)
		or containsHint(instance.Name, TIMER_HINTS) then
		log(
			"OBJECT",
			string.format(
				"found | %s (%s) | parent=%s | tags=%s",
				safeFullName(instance),
				instance.ClassName,
				instance.Parent and safeFullName(instance.Parent) or "nil",
				tagsToText(instance)
			)
		)
	end

	reportValue(instance, "initial", forceInitial and relevantContext)
	reportText(instance, "initial", forceInitial and (isBombContext(instance) or isTimerContext(instance)))
	reportAttributes(instance, "initial", forceInitial and relevantContext)

	if instance:IsA("ValueBase") then
		connect(instance.Changed, function()
			reportValue(instance, "changed", false)
		end)
	end

	if instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("TextBox") then
		connect(instance:GetPropertyChangedSignal("Text"), function()
			reportText(instance, "changed", false)
		end)
		connect(instance:GetPropertyChangedSignal("Visible"), function()
			reportText(instance, "visibility", true)
		end)
	end

	if relevantContext then
		connect(instance.AttributeChanged, function()
			reportAttributes(instance, "changed", false)
		end)
	end

	if instance:IsA("Tool") then
		connect(instance.AncestryChanged, function()
			log(
				"TOOL",
				string.format(
					"moved | %s | parent=%s",
					safeFullName(instance),
					instance.Parent and safeFullName(instance.Parent) or "nil"
				)
			)
		end)
	end
end

local function watchTree(root, forceInitial)
	if not root then
		return
	end
	watchInstance(root, forceInitial)
	for _, descendant in ipairs(root:GetDescendants()) do
		watchInstance(descendant, forceInitial)
	end
	connect(root.DescendantAdded, function(descendant)
		watchInstance(descendant, true)
	end)
end

local function getTeamSnapshot(player)
	local teamName = player.Team and player.Team.Name or "nil"
	local teamColor = "nil"
	pcall(function()
		teamColor = player.TeamColor.Name
	end)
	local neutral = "unknown"
	pcall(function()
		neutral = tostring(player.Neutral)
	end)
	return string.format(
		"name=%s userId=%s team=%s teamColor=%s neutral=%s",
		player.Name,
		tostring(player.UserId),
		teamName,
		teamColor,
		neutral
	)
end

local function reportTeam(player, reason)
	local snapshot = getTeamSnapshot(player)
	if state.teamSnapshots[player] ~= snapshot or reason == "initial" then
		state.teamSnapshots[player] = snapshot
		log("TEAM", reason .. " | " .. snapshot)
	end
	reportAttributes(player, "player-" .. reason, true)
end

local function watchPlayer(player)
	reportTeam(player, "initial")
	connect(player:GetPropertyChangedSignal("Team"), function()
		reportTeam(player, "Team changed")
	end)
	connect(player:GetPropertyChangedSignal("TeamColor"), function()
		reportTeam(player, "TeamColor changed")
	end)
	pcall(function()
		connect(player:GetPropertyChangedSignal("Neutral"), function()
			reportTeam(player, "Neutral changed")
		end)
	end)
	connect(player.AttributeChanged, function()
		reportAttributes(player, "player-attribute", false)
	end)
	connect(player.CharacterAdded, function(character)
		log("CHARACTER", "added | " .. safeFullName(character))
		watchTree(character, true)
	end)
end

local function reportInventory(reason)
	local items = {}
	local function append(container, label)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") or containsHint(child.Name, BOMB_HINTS) then
				table.insert(items, label .. ":" .. child.Name .. "(" .. child.ClassName .. ")")
			end
		end
	end
	append(Backpack, "Backpack")
	append(LocalPlayer.Character, "Character")
	table.sort(items)
	log("INVENTORY", reason .. " | " .. (#items > 0 and table.concat(items, ", ") or "no tool/bomb candidate"))
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
connect(Players.PlayerAdded, function(player)
	watchPlayer(player)
end)
connect(Players.PlayerRemoving, function(player)
	log("TEAM", "player removing | " .. player.Name)
	state.teamSnapshots[player] = nil
end)

watchTree(LocalPlayer, true)
watchTree(Backpack, true)
watchTree(PlayerGui, false)
watchInstance(workspace, true)
watchInstance(ReplicatedStorage, true)

if LocalPlayer.Character then
	watchTree(LocalPlayer.Character, true)
end

connect(Backpack.ChildAdded, function(child)
	reportInventory("Backpack child added: " .. child.Name)
end)
connect(Backpack.ChildRemoved, function(child)
	reportInventory("Backpack child removed: " .. child.Name)
end)

connect(LocalPlayer.CharacterAdded, function(character)
	task.defer(function()
		reportInventory("Character respawned")
		watchTree(character, true)
	end)
end)

connect(workspace.AttributeChanged, function()
	reportAttributes(workspace, "workspace-attribute", false)
end)
connect(ReplicatedStorage.AttributeChanged, function()
	reportAttributes(ReplicatedStorage, "replicated-attribute", false)
end)

reportInventory("initial")
log("READY", "Scanner ativo. Abra o console antes de pegar a bomba.")
log("READY", "Pegue a bomba, observe de 10 ate perto de 0, passe/receba novamente e fique perto de aliado e adversario.")
log("READY", "Depois envie as linhas [TEAM], [INVENTORY], [TOOL], [ATTR], [VALUE] e [UI] que mudarem durante o teste.")

function state.cleanup()
	if not state.alive then
		return
	end
	state.alive = false
	for _, connection in ipairs(state.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	state.connections = {}
	if environment[GLOBAL_STATE_NAME] == state then
		environment[GLOBAL_STATE_NAME] = nil
	end
	log("STOP", "Scanner anterior encerrado.")
end
