-- AutoTrack Mobile
-- Segue o bot mais proximo somente enquanto a bomba estiver com o jogador.
-- A camera permanece totalmente sob controle do jogador.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Backpack = LocalPlayer:WaitForChild("Backpack")

local GLOBAL_STATE_NAME = "__nt_autotrack_bot_debug"
local SCREEN_GUI_NAME = "AutoTrackBotDebugMobile"
local MOVE_BIND_NAME = "NT_AutoTrackMovement_" .. tostring(LocalPlayer.UserId)

local STOP_DISTANCE = 0.65
local TARGET_UPDATE_INTERVAL = 0.12
local BOMB_CHECK_INTERVAL = 0.08
local CACHE_REFRESH_INTERVAL = 1
local DRAG_HOLD_TIME = 0.5

local BOMB_NAME_HINTS = {
	"bomb",
	"bomba",
	"tnt",
	"explosive",
}

local BOMB_ATTRIBUTE_HINTS = {
	"HasBomb",
	"hasBomb",
	"Bomb",
	"bomb",
	"HoldingBomb",
	"holdingBomb",
	"IsBombHolder",
	"isBombHolder",
	"HasTheBomb",
	"hasTheBomb",
}

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

pcall(function()
	RunService:UnbindFromRenderStep(MOVE_BIND_NAME)
end)

local oldGui = PlayerGui:FindFirstChild(SCREEN_GUI_NAME)
if oldGui then
	oldGui:Destroy()
end

-- Remove o contorno da antiga versao de debug, caso ainda exista.
local oldHighlight = workspace:FindFirstChild("AutoTrackDebugTarget")
if oldHighlight and oldHighlight:IsA("Highlight") then
	oldHighlight:Destroy()
end

local state = {
	alive = true,
	enabled = false,
	hasBomb = false,
	movementLocked = false,
	connections = {},
	candidates = {},
	target = nil,
}
environment[GLOBAL_STATE_NAME] = state

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = SCREEN_GUI_NAME
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
MobileButton.TextSize = 17
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

local function getLocalMover()
	local character = LocalPlayer.Character
	if not character then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end

	local root = humanoid.RootPart
	if not root or not root:IsA("BasePart") then
		root = character:FindFirstChild("HumanoidRootPart")
	end

	if not root or not root:IsA("BasePart") then
		return humanoid, nil
	end

	return humanoid, root
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

	return getModelRoot(model, humanoid)
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
	local _, localRoot = getLocalMover()
	if not localRoot then
		return nil
	end

	local nearestModel = nil
	local nearestDistance = math.huge

	for model in pairs(state.candidates) do
		local root = inspectCandidate(model)
		if root then
			local offset = root.Position - localRoot.Position
			local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if horizontalDistance < nearestDistance then
				nearestDistance = horizontalDistance
				nearestModel = model
			end
		end
	end

	return nearestModel
end

local function nameSuggestsBomb(name)
	local loweredName = string.lower(tostring(name or ""))
	for _, hint in ipairs(BOMB_NAME_HINTS) do
		if string.find(loweredName, hint, 1, true) then
			return true
		end
	end
	return false
end

local function hasBombAttribute(instance)
	if not instance then
		return false
	end

	for _, attributeName in ipairs(BOMB_ATTRIBUTE_HINTS) do
		local value = instance:GetAttribute(attributeName)
		local loweredValue = type(value) == "string" and string.lower(value) or nil
		if value == true
			or value == 1
			or value == LocalPlayer
			or value == LocalPlayer.Name
			or value == LocalPlayer.UserId
			or loweredValue == "true" then
			return true
		end
	end

	return false
end

local function containerHasBomb(container)
	if not container then
		return false
	end

	if hasBombAttribute(container) then
		return true
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if hasBombAttribute(descendant) then
			return true
		end

		if nameSuggestsBomb(descendant.Name) then
			if descendant:IsA("Tool")
				or descendant:IsA("Accessory")
				or descendant:IsA("Model")
				or descendant:IsA("BasePart")
				or descendant:IsA("BoolValue")
				or descendant:IsA("ObjectValue")
				or descendant:IsA("StringValue") then
				local disabledBool = descendant:IsA("BoolValue") and descendant.Value == false
				if not disabledBool then
					return true
				end
			end
		end
	end

	return false
end

local function directPlayerValueHasBomb()
	for _, child in ipairs(LocalPlayer:GetChildren()) do
		if nameSuggestsBomb(child.Name) then
			if child:IsA("BoolValue") and child.Value then
				return true
			elseif child:IsA("ObjectValue") then
				if child.Value == LocalPlayer or child.Value == LocalPlayer.Character then
					return true
				end
			elseif child:IsA("StringValue") then
				local value = string.lower(child.Value)
				if value == string.lower(LocalPlayer.Name) or value == "true" then
					return true
				end
			elseif child:IsA("IntValue") or child:IsA("NumberValue") then
				if child.Value == 1 or child.Value == LocalPlayer.UserId then
					return true
				end
			end
		end
	end

	return false
end

local function playerHasBomb()
	local character = LocalPlayer.Character
	return hasBombAttribute(LocalPlayer)
		or directPlayerValueHasBomb()
		or containerHasBomb(character)
		or containerHasBomb(Backpack)
end

local function releaseMovement()
	if not state.movementLocked then
		return
	end

	state.movementLocked = false
	local humanoid = getLocalMover()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end
end

local function updateTarget()
	if not state.enabled then
		state.target = nil
		return
	end

	state.target = getNearestBot()
end

local function movementStep()
	if not state.alive then
		return
	end

	if not state.enabled or not state.hasBomb or not state.target then
		releaseMovement()
		return
	end

	local humanoid, localRoot = getLocalMover()
	local targetRoot = inspectCandidate(state.target)
	if not humanoid or not localRoot or not targetRoot then
		releaseMovement()
		return
	end

	local offset = targetRoot.Position - localRoot.Position
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontalOffset.Magnitude

	state.movementLocked = true
	if distance > STOP_DISTANCE then
		humanoid:Move(horizontalOffset.Unit, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

local function updateButtonText()
	MobileButton.Text = state.enabled and "Track On" or "Track Off"
end

local function toggleTrack()
	state.enabled = not state.enabled
	updateButtonText()

	TweenService:Create(
		MobileButton,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = state.enabled and Color3.fromRGB(8, 8, 8) or Color3.fromRGB(0, 0, 0)}
	):Play()

	if state.enabled then
		state.hasBomb = playerHasBomb()
		refreshCandidateCache()
		updateTarget()
	else
		state.hasBomb = false
		state.target = nil
		releaseMovement()
	end
end

local function animateButtonPress(pressed)
	TweenService:Create(
		buttonScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = pressed and 0.96 or 1}
	):Play()
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
		toggleTrack()
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
			releaseMovement()
		end
	end
end)

connect(LocalPlayer.CharacterAdded, function()
	state.hasBomb = false
	state.target = nil
	releaseMovement()
end)

local targetElapsed = 0
local bombElapsed = 0
local cacheElapsed = 0

connect(RunService.Heartbeat, function(deltaTime)
	if not state.alive or not state.enabled then
		return
	end

	targetElapsed = targetElapsed + deltaTime
	bombElapsed = bombElapsed + deltaTime
	cacheElapsed = cacheElapsed + deltaTime

	if bombElapsed >= BOMB_CHECK_INTERVAL then
		bombElapsed = 0
		local hadBomb = state.hasBomb
		state.hasBomb = playerHasBomb()
		if hadBomb and not state.hasBomb then
			releaseMovement()
		end
	end

	if cacheElapsed >= CACHE_REFRESH_INTERVAL then
		cacheElapsed = 0
		refreshCandidateCache()
	end

	if targetElapsed >= TARGET_UPDATE_INTERVAL then
		targetElapsed = 0
		updateTarget()
	end
end)

function state.cleanup()
	if not state.alive then
		return
	end

	state.alive = false
	state.enabled = false
	state.hasBomb = false
	state.target = nil
	releaseMovement()

	pcall(function()
		RunService:UnbindFromRenderStep(MOVE_BIND_NAME)
	end)

	for _, connection in ipairs(state.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	state.connections = {}

	if ScreenGui then
		ScreenGui:Destroy()
	end

	local leftoverHighlight = workspace:FindFirstChild("AutoTrackDebugTarget")
	if leftoverHighlight and leftoverHighlight:IsA("Highlight") then
		leftoverHighlight:Destroy()
	end

	if environment[GLOBAL_STATE_NAME] == state then
		environment[GLOBAL_STATE_NAME] = nil
	end
end

refreshCandidateCache()
RunService:BindToRenderStep(MOVE_BIND_NAME, Enum.RenderPriority.Last.Value, movementStep)
warn("[AutoTrack] Carregado: segue o bot mais proximo a 0.65 stud quando a bomba estiver com voce.")
