-- AutoTrack Mobile - detector de bots (versao de debug)
-- Base visual e comportamento de arraste adaptados do Cerber W.
-- Esta versao NAO move o personagem e NAO altera a camera.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GLOBAL_STATE_NAME = "__nt_autotrack_bot_debug"
local UPDATE_INTERVAL = 0.15
local CACHE_REFRESH_INTERVAL = 1
local DRAG_HOLD_TIME = 0.5

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
	enabled = false,
	connections = {},
	candidates = {},
	target = nil,
	distance = nil,
}
environment[GLOBAL_STATE_NAME] = state

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local oldGui = PlayerGui:FindFirstChild("AutoTrackBotDebugMobile")
if oldGui then
	oldGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoTrackBotDebugMobile"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 1000
ScreenGui.Parent = PlayerGui

local MobileButton = Instance.new("TextButton")
MobileButton.Name = "TrackButton"
MobileButton.Size = UDim2.new(0, 140, 0, 50)
MobileButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
MobileButton.BorderSizePixel = 0
MobileButton.AutoButtonColor = false
MobileButton.Text = "Track Off"
MobileButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileButton.Font = Enum.Font.GothamBold
MobileButton.TextSize = 15
MobileButton.TextWrapped = true
MobileButton.TextStrokeTransparency = 1
MobileButton.Active = true
MobileButton.Selectable = false
MobileButton.ZIndex = 10
MobileButton.Parent = ScreenGui
MobileButton:SetAttribute("LastDragTime", 0)

local inset = GuiService:GetGuiInset()
MobileButton.Position = UDim2.new(0, 150, 0, math.max(8, inset.Y - 8))

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 12)
buttonCorner.Parent = MobileButton

local buttonScale = Instance.new("UIScale")
buttonScale.Scale = 1
buttonScale.Parent = MobileButton

local function addTrueRoundedShadow(parent, cornerRadius, strength, shadowColor)
	strength = strength or 1
	shadowColor = shadowColor or Color3.fromRGB(0, 0, 0)

	local layers = {
		{grow = math.floor(8 * strength), transparency = 0.82, y = 2},
		{grow = math.floor(16 * strength), transparency = 0.90, y = 4},
		{grow = math.floor(24 * strength), transparency = 0.95, y = 6},
	}

	for _, config in ipairs(layers) do
		local shadow = Instance.new("Frame")
		shadow.Name = "TrueShadow"
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.Position = UDim2.new(0.5, 0, 0.5, config.y)
		shadow.Size = UDim2.new(1, config.grow, 1, config.grow)
		shadow.BackgroundColor3 = shadowColor
		shadow.BackgroundTransparency = config.transparency
		shadow.BorderSizePixel = 0
		shadow.ZIndex = parent.ZIndex - 1
		shadow.Active = false
		shadow.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius + math.floor(config.grow / 2.1))
		corner.Parent = shadow
	end
end

addTrueRoundedShadow(MobileButton, 14, 1.15, Color3.fromRGB(0, 0, 0))

local TargetHighlight = Instance.new("Highlight")
TargetHighlight.Name = "AutoTrackDebugTarget"
TargetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
TargetHighlight.FillColor = Color3.fromRGB(255, 255, 255)
TargetHighlight.FillTransparency = 0.86
TargetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
TargetHighlight.OutlineTransparency = 0.08
TargetHighlight.Enabled = false
local oldHighlight = workspace:FindFirstChild("AutoTrackDebugTarget")
if oldHighlight and oldHighlight:IsA("Highlight") then
	oldHighlight:Destroy()
end
TargetHighlight.Parent = workspace

local function getLocalRoot()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if root and root:IsA("BasePart") then
		return root
	end

	root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function belongsToAPlayer(model)
	if Players:GetPlayerFromCharacter(model) then
		return true
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and (model == character or model:IsDescendantOf(character)) then
			return true
		end
	end

	return false
end

local function getModelRoot(model, humanoid)
	local root = humanoid and humanoid.RootPart
	if root and root:IsA("BasePart") then
		return root
	end

	for _, partName in ipairs({"HumanoidRootPart", "UpperTorso", "Torso"}) do
		local part = model:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return nil
end

local function inspectCandidate(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return nil
	end

	if belongsToAPlayer(model) then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local root = getModelRoot(model, humanoid)
	if not root then
		return nil
	end

	return root
end

local function registerPossibleModel(instance)
	local model = nil

	if instance:IsA("Model") then
		model = instance
	else
		model = instance:FindFirstAncestorOfClass("Model")
	end

	if model
		and model:IsDescendantOf(workspace)
		and model:FindFirstChildOfClass("Humanoid") then
		state.candidates[model] = true
	end
end

local function refreshCandidateCache()
	local refreshed = {}

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			local model = descendant:FindFirstAncestorOfClass("Model")
			if model then
				refreshed[model] = true
			end
		end
	end

	state.candidates = refreshed
end

local function getNearestBot()
	local localRoot = getLocalRoot()
	if not localRoot then
		return nil, nil, 0
	end

	local nearestModel = nil
	local nearestDistance = math.huge
	local validCount = 0

	for model in pairs(state.candidates) do
		local root = inspectCandidate(model)
		if root then
			validCount = validCount + 1
			local distance = (root.Position - localRoot.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestModel = model
			end
		end
	end

	if not nearestModel then
		return nil, nil, validCount
	end

	return nearestModel, nearestDistance, validCount
end

local function shortenName(name)
	name = tostring(name or "Bot")
	if #name > 16 then
		return string.sub(name, 1, 14) .. ".."
	end
	return name
end

local function setHighlight(model)
	TargetHighlight.Adornee = model
	TargetHighlight.Enabled = state.enabled and model ~= nil
end

local function updateButtonText(validCount)
	if not state.enabled then
		MobileButton.Text = "Track Off"
		return
	end

	if not state.target then
		MobileButton.Text = "Track On\nNo Bot"
		return
	end

	local roundedDistance = math.floor((state.distance or 0) + 0.5)
	MobileButton.Text = "Track On\n" .. shortenName(state.target.Name) .. " - " .. roundedDistance .. "st"

	if validCount and validCount > 1 then
		MobileButton.Text = MobileButton.Text .. " (" .. validCount .. ")"
	end
end

local function printTargetChange(newTarget, distance, validCount)
	if newTarget then
		local fullName = newTarget.Name
		pcall(function()
			fullName = newTarget:GetFullName()
		end)
		warn(string.format(
			"[AutoTrack Debug] Bot mais proximo: %s | distancia: %.1f studs | bots validos: %d",
			fullName,
			distance or 0,
			validCount or 0
		))
	else
		warn("[AutoTrack Debug] Nenhum Model com Humanoid, vivo e sem Player associado foi encontrado.")
	end
end

local function updateDetection(forcePrint)
	if not state.enabled then
		state.target = nil
		state.distance = nil
		setHighlight(nil)
		updateButtonText(0)
		return
	end

	local previousTarget = state.target
	local target, distance, validCount = getNearestBot()
	state.target = target
	state.distance = distance
	setHighlight(target)
	updateButtonText(validCount)

	if forcePrint or target ~= previousTarget then
		printTargetChange(target, distance, validCount)
	end
end

local function animateButtonPress(pressed)
	TweenService:Create(
		buttonScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = pressed and 0.96 or 1}
	):Play()
end

local function toggleDetection()
	state.enabled = not state.enabled

	TweenService:Create(
		MobileButton,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = state.enabled and Color3.fromRGB(8, 8, 8) or Color3.fromRGB(0, 0, 0)}
	):Play()

	if state.enabled then
		refreshCandidateCache()
		updateDetection(true)
	else
		updateDetection(false)
		warn("[AutoTrack Debug] Detector desligado.")
	end
end

local function clampButtonToScreen(position)
	local camera = workspace.CurrentCamera
	if not camera then
		return position
	end

	local viewport = camera.ViewportSize
	local x = math.clamp(position.X.Offset, 4, math.max(4, viewport.X - MobileButton.AbsoluteSize.X - 4))
	local y = math.clamp(position.Y.Offset, 4, math.max(4, viewport.Y - MobileButton.AbsoluteSize.Y - 4))
	return UDim2.new(0, x, 0, y)
end

local activeInput = nil
local dragStart = nil
local startPosition = nil
local dragUnlocked = false
local holdCanceled = false
local touchMoved = false
local holdId = 0

connect(MobileButton.InputBegan, function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	activeInput = input
	dragStart = input.Position
	startPosition = MobileButton.Position
	dragUnlocked = false
	holdCanceled = false
	touchMoved = false
	holdId = holdId + 1
	local myHoldId = holdId
	animateButtonPress(true)

	task.delay(DRAG_HOLD_TIME, function()
		if state.alive
			and activeInput == input
			and not holdCanceled
			and holdId == myHoldId then
			dragUnlocked = true
			MobileButton:SetAttribute("LastDragTime", tick())
		end
	end)
end)

connect(UserInputService.InputChanged, function(input)
	if input ~= activeInput or not dragStart or not startPosition then
		return
	end

	local delta = input.Position - dragStart
	if not dragUnlocked then
		if delta.Magnitude >= 8 then
			holdCanceled = true
			touchMoved = true
		end
		return
	end

	if delta.Magnitude >= 6 then
		MobileButton:SetAttribute("LastDragTime", tick())
	end

	local nextPosition = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
	MobileButton.Position = clampButtonToScreen(nextPosition)
end)

connect(UserInputService.InputEnded, function(input)
	if input ~= activeInput then
		return
	end

	local wasLongHold = dragUnlocked
	local wasMoved = touchMoved
	activeInput = nil
	dragStart = nil
	startPosition = nil
	dragUnlocked = false
	holdCanceled = false
	touchMoved = false
	holdId = holdId + 1
	animateButtonPress(false)

	if not wasLongHold and not wasMoved then
		toggleDetection()
	end
end)

connect(workspace.DescendantAdded, function(descendant)
	if descendant:IsA("Model")
		or descendant:IsA("Humanoid")
		or descendant:IsA("BasePart") then
		task.defer(registerPossibleModel, descendant)
	end
end)

connect(workspace.DescendantRemoving, function(descendant)
	if descendant:IsA("Model") then
		state.candidates[descendant] = nil
		if state.target == descendant then
			state.target = nil
			state.distance = nil
			setHighlight(nil)
		end
	end
end)

local detectionElapsed = 0
local cacheElapsed = 0
connect(RunService.Heartbeat, function(deltaTime)
	if not state.alive then
		return
	end

	detectionElapsed = detectionElapsed + deltaTime
	cacheElapsed = cacheElapsed + deltaTime

	if state.enabled and cacheElapsed >= CACHE_REFRESH_INTERVAL then
		cacheElapsed = 0
		refreshCandidateCache()
	end

	if state.enabled and detectionElapsed >= UPDATE_INTERVAL then
		detectionElapsed = 0
		updateDetection(false)
	end
end)

function state.getSnapshot()
	local snapshot = {
		enabled = state.enabled,
		target = state.target and state.target:GetFullName() or nil,
		distance = state.distance,
		candidates = {},
	}

	local localRoot = getLocalRoot()
	for model in pairs(state.candidates) do
		local root = inspectCandidate(model)
		if root then
			table.insert(snapshot.candidates, {
				name = model:GetFullName(),
				distance = localRoot and (root.Position - localRoot.Position).Magnitude or nil,
			})
		end
	end

	table.sort(snapshot.candidates, function(a, b)
		return (a.distance or math.huge) < (b.distance or math.huge)
	end)

	return snapshot
end

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

	if ScreenGui then
		ScreenGui:Destroy()
	end
	if TargetHighlight then
		TargetHighlight:Destroy()
	end

	if environment[GLOBAL_STATE_NAME] == state then
		environment[GLOBAL_STATE_NAME] = nil
	end
end

refreshCandidateCache()
warn("[AutoTrack Debug] Carregado. Toque para detectar; segure por 0.5s e arraste para mover o botao.")
