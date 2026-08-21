-- Camera Track Mobile - variante de teste
-- O movimento do boneco permanece totalmente livre pelo controle nativo.
-- A camera acompanha o bot e pode ser ajustada entre -60 e 60 graus.

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

local MIN_STOP_DISTANCE = 1
local MAX_STOP_DISTANCE = 3
local DISTANCE_BIAS_POWER = 1.8
local DISTANCE_CHANGE_INTERVAL = 1
local MIN_DISTANCE_DELTA = 0.15
local INNER_GUARD_DISTANCE = 1.03
local OUTER_GUARD_DISTANCE = 2.96
local MICRO_OFFSET_BASE = 0.008
local MICRO_OFFSET_VARIATION = 0.003
local MICRO_MOVE_MIN = 0.01
local MICRO_MOVE_MAX = 0.26
local INNER_RECOVERY_TRIGGER_DISTANCE = 1.8
local INNER_RECOVERY_TARGET_MIN = 2.05
local INNER_RECOVERY_TARGET_MAX = 2.2
local INNER_RECOVERY_NEXT_DISTANCE_MIN = 2.02
local INNER_RECOVERY_NEXT_DISTANCE_MAX = 2.38
local INNER_RECOVERY_MOVE_MIN = 0.14
local INNER_RECOVERY_MOVE_MAX = 0.28
local MANUAL_MOVE_WEIGHT = 0.1
local MANUAL_OUTER_GUARD_DISTANCE = 2.85

local AIM_MIN_ABSOLUTE_OFFSET = 0.14
local AIM_NEAR_MAX_OFFSET = 0.58
local AIM_MIDDLE_MAX_OFFSET = 0.98
local AIM_EDGE_MAX_OFFSET = 1.35
local AIM_NEAR_CHANCE = 0.55
local AIM_MIDDLE_CHANCE = 0.86
local AIM_CHANGE_MIN = 0.22
local AIM_CHANGE_MAX = 0.55
local AIM_EDGE_CHANGE_MIN = 0.1
local AIM_EDGE_CHANGE_MAX = 0.16
local AIM_RETURN_CHANGE_MIN = 0.16
local AIM_RETURN_CHANGE_MAX = 0.3
local AIM_SMOOTH_SPEED = 18

local TRACK_HORIZONTAL_OFFSET_DEGREES = 45
local CAMERA_MIN_TRACK_ANGLE_DEGREES = -60
local CAMERA_MAX_TRACK_ANGLE_DEGREES = 60
local CAMERA_MIN_MANUAL_OFFSET_DEGREES = CAMERA_MIN_TRACK_ANGLE_DEGREES
	- TRACK_HORIZONTAL_OFFSET_DEGREES
local CAMERA_MAX_MANUAL_OFFSET_DEGREES = CAMERA_MAX_TRACK_ANGLE_DEGREES
	- TRACK_HORIZONTAL_OFFSET_DEGREES
local CAMERA_INPUT_NOISE_THRESHOLD_DEGREES = 0.01
local CAMERA_INPUT_MAX_DELTA_DEGREES = 60
local CAMERA_BASE_ERROR_LIMIT_DEGREES = 5
local CAMERA_BASE_MIN_ABSOLUTE_DEGREES = 0.35
local CAMERA_BASE_CHANGE_MIN = 0.38
local CAMERA_BASE_CHANGE_MAX = 0.78
local CAMERA_BASE_SMOOTH_SPEED = 5.4
local CAMERA_MICRO_PRIMARY_DEGREES = 0.14
local CAMERA_MICRO_SECONDARY_DEGREES = 0.06
local CAMERA_MICRO_PRIMARY_SPEED = 2.1
local CAMERA_MICRO_SECONDARY_SPEED = 0.83
local CAMERA_FLICK_ROUTINE_MIN = 0.8
local CAMERA_FLICK_ROUTINE_MAX = 1.6
local CAMERA_FLICK_LIGHT_MIN = 0.5
local CAMERA_FLICK_LIGHT_MAX = 1.4
local CAMERA_FLICK_TURN_MIN = 2.2
local CAMERA_FLICK_TURN_MAX = 4.6
local CAMERA_FLICK_DURATION_MIN = 0.16
local CAMERA_FLICK_DURATION_MAX = 0.28
local CAMERA_FLICK_TURN_THRESHOLD_DEGREES = 26
local CAMERA_FLICK_SAMPLE_DISTANCE = 0.08
local CAMERA_FLICK_COOLDOWN = 0.18
local CAMERA_MIN_HORIZONTAL_RADIUS = 0.08
local CAMERA_ENGAGE_DURATION_MIN = 0.18
local CAMERA_ENGAGE_DURATION_MAX = 0.28
local CAMERA_ENGAGE_SLOW_CHANCE = 0.3
local CAMERA_ENGAGE_FAST_DURATION_MIN = 0.04
local CAMERA_ENGAGE_FAST_DURATION_MAX = 0.1
local CAMERA_ENGAGE_FAST_BIAS_POWER = 2.2
local BOT_APPEAR_WAIT_MIN = 0.2
local BOT_APPEAR_WAIT_MAX = 0.5
local BOT_APPEAR_ENGAGE_DURATION_MIN = 0.1
local BOT_APPEAR_ENGAGE_DURATION_MAX = 0.3
local BOT_SEQUENCE_MOTION_EPSILON = 0.01
local BOT_SEQUENCE_TELEPORT_MIN_DISTANCE = 0.65
local BOT_SEQUENCE_TELEPORT_MIN_RESIDUAL = 0.45
local BOT_SEQUENCE_TELEPORT_HARD_DISTANCE = 2.4
local BOT_SEQUENCE_TELEPORT_HARD_SPEED = 25
local BOT_SEQUENCE_PHYSICS_VELOCITY_SPIKE = 90
local BOT_SEQUENCE_MAX_SAMPLE_INTERVAL = 0.25
local BOT_SEQUENCE_VELOCITY_BLEND = 0.55
local BOT_SEQUENCE_VELOCITY_DECAY = 3

local SHARP_TURN_THRESHOLD_DEGREES = 52
local SHARP_TURN_DISTANCE_MIN = 2
local SHARP_TURN_DISTANCE_MAX = 3
local SHARP_TURN_SETTLE_TOLERANCE = 0.18
local SHARP_TURN_SETTLE_TIME = 0.06
local SHARP_TURN_HOLD_MIN = 0.16
local SHARP_TURN_HOLD_MAX = 0.24
local SHARP_TURN_MAX_DURATION_MIN = 0.58
local SHARP_TURN_MAX_DURATION_MAX = 0.78
local SHARP_TURN_COOLDOWN = 0.42
local CHARACTER_TURN_SMOOTH_SPEED = 10
local TARGET_UPDATE_INTERVAL = 0.12
local BOMB_CHECK_INTERVAL = 0.08
local CACHE_REFRESH_INTERVAL = 1
local DRAG_HOLD_TIME = 0.5
local RandomGenerator = Random.new()

local function getCameraEngageDuration()
	if RandomGenerator:NextNumber(0, 1) < CAMERA_ENGAGE_SLOW_CHANCE then
		return RandomGenerator:NextNumber(
			CAMERA_ENGAGE_DURATION_MIN,
			CAMERA_ENGAGE_DURATION_MAX
		)
	end

	local sample = RandomGenerator:NextNumber(0, 1)
	local biasedSample = sample ^ CAMERA_ENGAGE_FAST_BIAS_POWER
	return CAMERA_ENGAGE_FAST_DURATION_MIN
		+ ((CAMERA_ENGAGE_FAST_DURATION_MAX
			- CAMERA_ENGAGE_FAST_DURATION_MIN) * biasedSample)
end

local function getBiasedTrackDistance()
	local sample = RandomGenerator:NextNumber(0, 1)
	local biasedSample = sample ^ DISTANCE_BIAS_POWER
	return MIN_STOP_DISTANCE
		+ ((MAX_STOP_DISTANCE - MIN_STOP_DISTANCE) * biasedSample)
end

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
	stopDistance = getBiasedTrackDistance(),
	distanceElapsed = 0,
	microSign = RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1,
	microPhase = RandomGenerator:NextNumber(0, math.pi * 2),
	microFrequency = RandomGenerator:NextNumber(0.72, 1.08),
	aimTargetOffset = (RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1)
		* RandomGenerator:NextNumber(0.2, 0.5),
	aimAppliedOffset = 0.24,
	aimElapsed = 0,
	aimChangeInterval = RandomGenerator:NextNumber(AIM_CHANGE_MIN, AIM_CHANGE_MAX),
	aimReturnFromEdge = false,
	innerRecoveryActive = false,
	innerRecoveryTarget = INNER_RECOVERY_TARGET_MIN,
	cameraRequestedOffsetDegrees = 0,
	cameraAppliedOffsetDegrees = 0,
	cameraBaseTargetOffsetDegrees = 1.25,
	cameraBaseAppliedOffsetDegrees = 1.25,
	cameraBaseElapsed = 0,
	cameraBaseChangeInterval = RandomGenerator:NextNumber(
		CAMERA_BASE_CHANGE_MIN,
		CAMERA_BASE_CHANGE_MAX
	),
	cameraMicroPhaseA = RandomGenerator:NextNumber(0, math.pi * 2),
	cameraMicroPhaseB = RandomGenerator:NextNumber(0, math.pi * 2),
	cameraFlickElapsed = 1,
	cameraFlickDuration = 1,
	cameraFlickAmplitude = 0,
	cameraFlickOffsetDegrees = 0,
	cameraFlickRoutineElapsed = 0,
	cameraFlickRoutineInterval = RandomGenerator:NextNumber(
		CAMERA_FLICK_ROUTINE_MIN,
		CAMERA_FLICK_ROUTINE_MAX
	),
	cameraFlickCooldown = 0,
	cameraLastBotSamplePosition = nil,
	cameraLastBotMoveDirection = nil,
	cameraEngageActive = false,
	cameraEngageElapsed = 0,
	cameraEngageDuration = CAMERA_ENGAGE_DURATION_MIN,
	cameraEngageStartCFrame = nil,
	trackingActiveLastFrame = false,
	cameraLastOutputForward = nil,
	botAppearSequenceTarget = nil,
	botAppearWaitUntil = 0,
	botAppearEngageDuration = BOT_APPEAR_ENGAGE_DURATION_MIN,
	botSequencePhase = "idle",
	botSequenceRoot = nil,
	botSequenceLastPosition = nil,
	botSequenceLastSampleAt = 0,
	botSequenceEstimatedVelocity = Vector3.zero,
	botSequenceLastPhysicsVelocity = Vector3.zero,
	sharpTurnSpacingActive = false,
	sharpTurnSpacingTarget = 2.5,
	sharpTurnSpacingElapsed = 0,
	sharpTurnSpacingHold = SHARP_TURN_HOLD_MIN,
	sharpTurnSpacingMaxDuration = SHARP_TURN_MAX_DURATION_MIN,
	sharpTurnSpacingSettled = 0,
	sharpTurnSpacingCooldown = 0,
	controlledHumanoid = nil,
	savedAutoRotate = nil,
}
state.aimAppliedOffset = state.aimTargetOffset
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
ScreenGui.IgnoreGuiInset = true
pcall(function()
	ScreenGui.ScreenInsets = Enum.ScreenInsets.None
	ScreenGui.ClipToDeviceSafeArea = false
end)
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

local function restoreCharacterFacing()
	local humanoid = state.controlledHumanoid
	if humanoid then
		pcall(function()
			humanoid.AutoRotate = state.savedAutoRotate ~= false
		end)
	end

	state.controlledHumanoid = nil
	state.savedAutoRotate = nil
end

local function enableCharacterFacing(humanoid)
	if state.controlledHumanoid ~= humanoid then
		restoreCharacterFacing()
		state.controlledHumanoid = humanoid
		state.savedAutoRotate = humanoid.AutoRotate
	end

	humanoid.AutoRotate = false
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

local function releaseTrackingControl()
	releaseMovement()
	restoreCharacterFacing()
	state.innerRecoveryActive = false
	state.sharpTurnSpacingActive = false
	state.sharpTurnSpacingElapsed = 0
	state.sharpTurnSpacingSettled = 0
	state.aimElapsed = state.aimChangeInterval
	state.cameraRequestedOffsetDegrees = 0
	state.cameraAppliedOffsetDegrees = 0
	state.cameraFlickOffsetDegrees = 0
	state.cameraFlickElapsed = state.cameraFlickDuration
	state.cameraLastBotSamplePosition = nil
	state.cameraLastBotMoveDirection = nil
	state.cameraEngageActive = false
	state.cameraEngageElapsed = 0
	state.cameraEngageStartCFrame = nil
	state.cameraLastOutputForward = nil
	state.trackingActiveLastFrame = false
end

local function resetBotSequenceState()
	state.botAppearSequenceTarget = nil
	state.botAppearWaitUntil = 0
	state.botSequencePhase = "idle"
	state.botSequenceRoot = nil
	state.botSequenceLastPosition = nil
	state.botSequenceLastSampleAt = 0
	state.botSequenceEstimatedVelocity = Vector3.zero
	state.botSequenceLastPhysicsVelocity = Vector3.zero
end

local function beginBotSequence(target, targetRoot, waitBeforeTurning)
	local currentTime = os.clock()
	state.botAppearSequenceTarget = target
	state.botSequenceRoot = targetRoot
	state.botSequenceLastPosition = targetRoot and targetRoot.Position or nil
	state.botSequenceLastSampleAt = currentTime
	state.botSequenceEstimatedVelocity = targetRoot
		and targetRoot.AssemblyLinearVelocity
		or Vector3.zero
	state.botSequenceLastPhysicsVelocity = state.botSequenceEstimatedVelocity

	if waitBeforeTurning then
		state.botSequencePhase = "waiting"
		state.botAppearWaitUntil = currentTime + RandomGenerator:NextNumber(
			BOT_APPEAR_WAIT_MIN,
			BOT_APPEAR_WAIT_MAX
		)
		state.botAppearEngageDuration = RandomGenerator:NextNumber(
			BOT_APPEAR_ENGAGE_DURATION_MIN,
			BOT_APPEAR_ENGAGE_DURATION_MAX
		)
	else
		state.botSequencePhase = "engaging"
		state.botAppearWaitUntil = currentTime
		state.botAppearEngageDuration = getCameraEngageDuration()
	end

	state.cameraLastBotSamplePosition = nil
	state.cameraLastBotMoveDirection = nil
	state.cameraEngageActive = false
	state.cameraEngageElapsed = 0
	state.cameraEngageStartCFrame = nil
	state.cameraLastOutputForward = nil
	state.trackingActiveLastFrame = false
end

local function randomizeStopDistance()
	local previousDistance = state.stopDistance
	local nextDistance = getBiasedTrackDistance()

	for _ = 1, 8 do
		if not previousDistance or math.abs(nextDistance - previousDistance) >= MIN_DISTANCE_DELTA then
			break
		end
		nextDistance = getBiasedTrackDistance()
	end

	if previousDistance and math.abs(nextDistance - previousDistance) < MIN_DISTANCE_DELTA then
		local middleDistance = (MIN_STOP_DISTANCE + MAX_STOP_DISTANCE) * 0.5
		if previousDistance <= middleDistance then
			nextDistance = math.min(MAX_STOP_DISTANCE, previousDistance + 0.18)
		else
			nextDistance = math.max(MIN_STOP_DISTANCE, previousDistance - 0.18)
		end
	end

	state.stopDistance = nextDistance
end

local function updateTarget(applySequenceDelay)
	if not state.enabled then
		state.target = nil
		resetBotSequenceState()
		return
	end

	local nextTarget = getNearestBot()
	local targetChanged = nextTarget ~= state.target

	if targetChanged then
		state.innerRecoveryActive = false
		state.sharpTurnSpacingActive = false
		state.sharpTurnSpacingElapsed = 0
		state.sharpTurnSpacingSettled = 0
		state.aimElapsed = state.aimChangeInterval
		state.cameraLastBotSamplePosition = nil
		state.cameraLastBotMoveDirection = nil
		state.cameraLastOutputForward = nil
		state.trackingActiveLastFrame = false
		state.target = nextTarget

		if nextTarget then
			beginBotSequence(
				nextTarget,
				inspectCandidate(nextTarget),
				applySequenceDelay == true
			)
		else
			resetBotSequenceState()
		end
	elseif nextTarget and state.botAppearSequenceTarget ~= nextTarget then
		beginBotSequence(nextTarget, inspectCandidate(nextTarget), false)
	end
end

local function getSmoothAlpha(speed, deltaTime)
	return 1 - math.exp(-speed * math.max(deltaTime or 0, 0))
end

local function getSmoothStep(progress)
	local clamped = math.clamp(progress, 0, 1)
	return clamped * clamped * (3 - (2 * clamped))
end

local function rotateHorizontalLeft(direction, degrees)
	return CFrame.fromAxisAngle(
		Vector3.new(0, 1, 0),
		math.rad(degrees)
	):VectorToWorldSpace(direction)
end

local function getHorizontalUnit(direction)
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end
	return horizontal.Unit
end

local function getSignedHorizontalAngle(fromDirection, toDirection)
	local fromHorizontal = getHorizontalUnit(fromDirection)
	local toHorizontal = getHorizontalUnit(toDirection)
	if not fromHorizontal or not toHorizontal then
		return 0
	end

	local dot = math.clamp(fromHorizontal:Dot(toHorizontal), -1, 1)
	local crossY = fromHorizontal:Cross(toHorizontal).Y
	return math.deg(math.atan2(crossY, dot))
end

local function getDirectionSign(value)
	return value >= 0 and 1 or -1
end

local function randomizeAimTarget()
	local previousTarget = state.aimTargetOffset or AIM_MIN_ABSOLUTE_OFFSET
	local previousSign = getDirectionSign(previousTarget)
	local nextSign = previousSign
	local magnitude = AIM_MIN_ABSOLUTE_OFFSET

	if state.aimReturnFromEdge then
		-- Depois de mirar perto de um braco, cruza rapidamente para o outro lado.
		nextSign = -previousSign
		magnitude = RandomGenerator:NextNumber(0.22, 0.72)
		state.aimChangeInterval = RandomGenerator:NextNumber(
			AIM_RETURN_CHANGE_MIN,
			AIM_RETURN_CHANGE_MAX
		)
		state.aimReturnFromEdge = false
	else
		local roll = RandomGenerator:NextNumber(0, 1)
		if roll < AIM_NEAR_CHANCE then
			magnitude = RandomGenerator:NextNumber(
				AIM_MIN_ABSOLUTE_OFFSET,
				AIM_NEAR_MAX_OFFSET
			)
		elseif roll < AIM_MIDDLE_CHANCE then
			magnitude = RandomGenerator:NextNumber(
				AIM_NEAR_MAX_OFFSET,
				AIM_MIDDLE_MAX_OFFSET
			)
		else
			magnitude = RandomGenerator:NextNumber(
				AIM_MIDDLE_MAX_OFFSET,
				AIM_EDGE_MAX_OFFSET
			)
			state.aimReturnFromEdge = true
		end

		if RandomGenerator:NextNumber(0, 1) < 0.62 then
			nextSign = -previousSign
		else
			nextSign = RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1
		end

		if state.aimReturnFromEdge then
			state.aimChangeInterval = RandomGenerator:NextNumber(
				AIM_EDGE_CHANGE_MIN,
				AIM_EDGE_CHANGE_MAX
			)
		else
			state.aimChangeInterval = RandomGenerator:NextNumber(
				AIM_CHANGE_MIN,
				AIM_CHANGE_MAX
			)
		end
	end

	local nextTarget = nextSign * magnitude
	if math.abs(nextTarget - previousTarget) < 0.12 then
		nextTarget = -previousSign * math.max(
			AIM_MIN_ABSOLUTE_OFFSET,
			magnitude
		)
	end

	state.aimTargetOffset = nextTarget
	state.aimElapsed = 0
end

local function updateAimPosition(targetRoot, deltaTime)
	state.aimElapsed = state.aimElapsed + deltaTime
	if state.aimElapsed >= state.aimChangeInterval then
		randomizeAimTarget()
	end

	local alpha = getSmoothAlpha(AIM_SMOOTH_SPEED, deltaTime)
	local appliedOffset = state.aimAppliedOffset
		+ ((state.aimTargetOffset - state.aimAppliedOffset) * alpha)
	if math.abs(appliedOffset) < AIM_MIN_ABSOLUTE_OFFSET then
		appliedOffset = getDirectionSign(state.aimTargetOffset)
			* AIM_MIN_ABSOLUTE_OFFSET
	end
	state.aimAppliedOffset = appliedOffset

	local right = targetRoot.CFrame.RightVector
	local horizontalRight = Vector3.new(right.X, 0, right.Z)
	if horizontalRight.Magnitude <= 0.001 then
		return targetRoot.Position
	end

	return targetRoot.Position + (horizontalRight.Unit * appliedOffset)
end

local function randomizeCameraBaseOffset()
	local previousOffset = state.cameraBaseTargetOffsetDegrees or 0
	local nextOffset = previousOffset

	for _ = 1, 8 do
		nextOffset = RandomGenerator:NextNumber(
			-CAMERA_BASE_ERROR_LIMIT_DEGREES,
			CAMERA_BASE_ERROR_LIMIT_DEGREES
		)
		if math.abs(nextOffset) >= CAMERA_BASE_MIN_ABSOLUTE_DEGREES
			and math.abs(nextOffset - previousOffset) >= 0.65 then
			break
		end
	end

	if math.abs(nextOffset) < CAMERA_BASE_MIN_ABSOLUTE_DEGREES then
		nextOffset = getDirectionSign(nextOffset)
			* CAMERA_BASE_MIN_ABSOLUTE_DEGREES
	end
	if math.abs(nextOffset - previousOffset) < 0.65 then
		nextOffset = -getDirectionSign(previousOffset)
			* RandomGenerator:NextNumber(
				CAMERA_BASE_MIN_ABSOLUTE_DEGREES + 0.3,
				CAMERA_BASE_ERROR_LIMIT_DEGREES
			)
	end

	state.cameraBaseTargetOffsetDegrees = nextOffset
	state.cameraBaseElapsed = 0
	state.cameraBaseChangeInterval = RandomGenerator:NextNumber(
		CAMERA_BASE_CHANGE_MIN,
		CAMERA_BASE_CHANGE_MAX
	)
end

local function startCameraFlick(minimumAmplitude, maximumAmplitude)
	local sign = RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1
	state.cameraFlickAmplitude = sign
		* RandomGenerator:NextNumber(minimumAmplitude, maximumAmplitude)
	state.cameraFlickDuration = RandomGenerator:NextNumber(
		CAMERA_FLICK_DURATION_MIN,
		CAMERA_FLICK_DURATION_MAX
	)
	state.cameraFlickElapsed = 0
	state.cameraFlickCooldown = CAMERA_FLICK_COOLDOWN
end

local function startSharpTurnSpacing()
	if state.sharpTurnSpacingCooldown > 0 then
		return
	end

	state.sharpTurnSpacingActive = true
	state.sharpTurnSpacingTarget = RandomGenerator:NextNumber(
		SHARP_TURN_DISTANCE_MIN,
		SHARP_TURN_DISTANCE_MAX
	)
	state.sharpTurnSpacingElapsed = 0
	state.sharpTurnSpacingSettled = 0
	state.sharpTurnSpacingHold = RandomGenerator:NextNumber(
		SHARP_TURN_HOLD_MIN,
		SHARP_TURN_HOLD_MAX
	)
	state.sharpTurnSpacingMaxDuration = RandomGenerator:NextNumber(
		SHARP_TURN_MAX_DURATION_MIN,
		SHARP_TURN_MAX_DURATION_MAX
	)
	state.sharpTurnSpacingCooldown = SHARP_TURN_COOLDOWN
	state.innerRecoveryActive = false
end

local function updateCameraVariation(targetRoot, deltaTime)
	state.cameraBaseElapsed = state.cameraBaseElapsed + deltaTime
	if state.cameraBaseElapsed >= state.cameraBaseChangeInterval then
		randomizeCameraBaseOffset()
	end

	local baseAlpha = getSmoothAlpha(CAMERA_BASE_SMOOTH_SPEED, deltaTime)
	state.cameraBaseAppliedOffsetDegrees = state.cameraBaseAppliedOffsetDegrees
		+ ((state.cameraBaseTargetOffsetDegrees
			- state.cameraBaseAppliedOffsetDegrees) * baseAlpha)

	state.cameraFlickCooldown = math.max(
		0,
		state.cameraFlickCooldown - deltaTime
	)
	state.sharpTurnSpacingCooldown = math.max(
		0,
		state.sharpTurnSpacingCooldown - deltaTime
	)
	local targetPosition = targetRoot.Position
	if not state.cameraLastBotSamplePosition then
		state.cameraLastBotSamplePosition = targetPosition
	else
		local displacement = targetPosition - state.cameraLastBotSamplePosition
		local horizontalDisplacement = Vector3.new(
			displacement.X,
			0,
			displacement.Z
		)
		if horizontalDisplacement.Magnitude >= CAMERA_FLICK_SAMPLE_DISTANCE then
			local moveDirection = horizontalDisplacement.Unit
			if state.cameraLastBotMoveDirection then
				local directionDot = math.clamp(
					state.cameraLastBotMoveDirection:Dot(moveDirection),
					-1,
					1
				)
				local turnDegrees = math.deg(math.acos(directionDot))
				if turnDegrees >= CAMERA_FLICK_TURN_THRESHOLD_DEGREES
					and state.cameraFlickCooldown <= 0 then
					startCameraFlick(
						CAMERA_FLICK_TURN_MIN,
						CAMERA_FLICK_TURN_MAX
					)
				end
				if turnDegrees >= SHARP_TURN_THRESHOLD_DEGREES then
					startSharpTurnSpacing()
				end
			end
			state.cameraLastBotMoveDirection = moveDirection
			state.cameraLastBotSamplePosition = targetPosition
		end
	end

	state.cameraFlickRoutineElapsed = state.cameraFlickRoutineElapsed + deltaTime
	if state.cameraFlickRoutineElapsed >= state.cameraFlickRoutineInterval then
		state.cameraFlickRoutineElapsed = 0
		state.cameraFlickRoutineInterval = RandomGenerator:NextNumber(
			CAMERA_FLICK_ROUTINE_MIN,
			CAMERA_FLICK_ROUTINE_MAX
		)
		if state.cameraFlickCooldown <= 0 then
			startCameraFlick(
				CAMERA_FLICK_LIGHT_MIN,
				CAMERA_FLICK_LIGHT_MAX
			)
		end
	end

	state.cameraFlickElapsed = state.cameraFlickElapsed + deltaTime
	if state.cameraFlickElapsed < state.cameraFlickDuration then
		local progress = math.clamp(
			state.cameraFlickElapsed / state.cameraFlickDuration,
			0,
			1
		)
		local easedProgress = getSmoothStep(progress)
		state.cameraFlickOffsetDegrees = state.cameraFlickAmplitude
			* math.sin(math.pi * easedProgress)
	else
		state.cameraFlickOffsetDegrees = 0
	end

	local now = os.clock()
	local microOffset = math.sin(
		(now * CAMERA_MICRO_PRIMARY_SPEED) + state.cameraMicroPhaseA
	) * CAMERA_MICRO_PRIMARY_DEGREES
	microOffset = microOffset + (math.sin(
		(now * CAMERA_MICRO_SECONDARY_SPEED) + state.cameraMicroPhaseB
	) * CAMERA_MICRO_SECONDARY_DEGREES)

	return state.cameraBaseAppliedOffsetDegrees,
		state.cameraFlickOffsetDegrees,
		microOffset
end

local function updateCharacterFacing(humanoid, localRoot, aimPosition, deltaTime)
	local offset = aimPosition - localRoot.Position
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	if horizontalOffset.Magnitude <= 0.001 then
		return
	end

	enableCharacterFacing(humanoid)
	-- O boneco continua seguindo o bot, mas nao gira junto com o angulo manual
	-- da camera. Isso evita realimentacao e deixa o arraste mais natural.
	local desiredFacing = CFrame.lookAt(
		localRoot.Position,
		localRoot.Position + horizontalOffset.Unit,
		Vector3.new(0, 1, 0)
	)
	local alpha = getSmoothAlpha(CHARACTER_TURN_SMOOTH_SPEED, deltaTime)
	localRoot.CFrame = localRoot.CFrame:Lerp(desiredFacing, alpha)
end

local function updateTrackingCamera(localRoot, targetRoot, _aimPosition, deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- O angulo da camera usa o centro real do bot. A variacao de mira continua
	-- existindo apenas no movimento temporario e nao desloca este teste.
	local offset = targetRoot.Position - localRoot.Position
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	if horizontalOffset.Magnitude <= 0.001 then
		return
	end

	local towardTarget = horizontalOffset.Unit

	-- A CameraModule do Roblox roda antes deste passo. Comparamos a direcao que
	-- ela produziu com a nossa ultima saida para recuperar o arraste horizontal
	-- real, sem depender dos eventos TouchMoved/InputChanged do executor.
	local focus = camera.Focus.Position
	local defaultForward = getHorizontalUnit(focus - camera.CFrame.Position)
	if state.cameraLastOutputForward and defaultForward then
		local inputDeltaDegrees = getSignedHorizontalAngle(
			state.cameraLastOutputForward,
			defaultForward
		)
		if math.abs(inputDeltaDegrees)
			>= CAMERA_INPUT_NOISE_THRESHOLD_DEGREES then
			inputDeltaDegrees = math.clamp(
				inputDeltaDegrees,
				-CAMERA_INPUT_MAX_DELTA_DEGREES,
				CAMERA_INPUT_MAX_DELTA_DEGREES
			)
			state.cameraRequestedOffsetDegrees = math.clamp(
				(state.cameraRequestedOffsetDegrees or 0) + inputDeltaDegrees,
				CAMERA_MIN_MANUAL_OFFSET_DEGREES,
				CAMERA_MAX_MANUAL_OFFSET_DEGREES
			)
		end
	end

	local requestedOffset = math.clamp(
		state.cameraRequestedOffsetDegrees or 0,
		CAMERA_MIN_MANUAL_OFFSET_DEGREES,
		CAMERA_MAX_MANUAL_OFFSET_DEGREES
	)
	-- A CameraModule ja suaviza o movimento do dedo. Aplicar outro filtro aqui
	-- criava atraso; usar o valor diretamente deixa a resposta praticamente 1:1.
	local manualOffset = requestedOffset
	state.cameraAppliedOffsetDegrees = manualOffset

	local trackAngle = math.clamp(
		TRACK_HORIZONTAL_OFFSET_DEGREES + manualOffset,
		CAMERA_MIN_TRACK_ANGLE_DEGREES,
		CAMERA_MAX_TRACK_ANGLE_DEGREES
	)

	local limitedForward = rotateHorizontalLeft(
		towardTarget,
		trackAngle
	)

	-- Reaproveita distancia, zoom e inclinacao vertical da camera normal.
	-- Somente o angulo horizontal e recolocado dentro de -60 a 60 graus.
	local cameraOffset = camera.CFrame.Position - focus
	local verticalOffset = cameraOffset.Y
	local horizontalRadius = Vector3.new(cameraOffset.X, 0, cameraOffset.Z).Magnitude
	if horizontalRadius <= CAMERA_MIN_HORIZONTAL_RADIUS then
		return
	end

	local cameraPosition = focus
		- (limitedForward * horizontalRadius)
		+ Vector3.new(0, verticalOffset, 0)
	local desiredCameraCFrame = CFrame.lookAt(
		cameraPosition,
		focus,
		Vector3.new(0, 1, 0)
	)

	if state.cameraEngageActive then
		if not state.cameraEngageStartCFrame then
			state.cameraEngageStartCFrame = camera.CFrame
		end
		state.cameraEngageElapsed = state.cameraEngageElapsed + deltaTime
		local progress = state.cameraEngageElapsed
			/ math.max(state.cameraEngageDuration, 0.001)
		camera.CFrame = state.cameraEngageStartCFrame:Lerp(
			desiredCameraCFrame,
			getSmoothStep(progress)
		)
		if progress >= 1 then
			state.cameraEngageActive = false
			state.cameraEngageStartCFrame = nil
		end
	else
		camera.CFrame = desiredCameraCFrame
	end

	state.cameraLastOutputForward = getHorizontalUnit(
		focus - camera.CFrame.Position
	)
end

local function addManualMovementInfluence(
	movementVector,
	manualDirection,
	distance,
	fromTarget,
	isRecovering
)
	local horizontalManual = Vector3.new(
		manualDirection.X,
		0,
		manualDirection.Z
	)
	local manualMagnitude = math.min(horizontalManual.Magnitude, 1)
	if manualMagnitude <= 0.001 then
		return movementVector
	end

	-- Durante o recuo nao deixa o joystick empurrar de volta para dentro.
	local radialAmount = horizontalManual:Dot(fromTarget)
	if (isRecovering or distance <= MIN_STOP_DISTANCE) and radialAmount < 0 then
		horizontalManual = horizontalManual - (fromTarget * radialAmount)
	end

	-- Perto do limite externo ainda permite movimento lateral, mas nao afastar.
	radialAmount = horizontalManual:Dot(fromTarget)
	if distance >= MANUAL_OUTER_GUARD_DISTANCE and radialAmount > 0 then
		horizontalManual = horizontalManual - (fromTarget * radialAmount)
	end

	if horizontalManual.Magnitude <= 0.001 then
		return movementVector
	end

	local filteredMagnitude = math.min(horizontalManual.Magnitude, 1)
	local manualInfluence = horizontalManual.Unit
		* filteredMagnitude
		* MANUAL_MOVE_WEIGHT
	local combinedMovement = movementVector + manualInfluence
	if combinedMovement.Magnitude > 1 then
		return combinedMovement.Unit
	end

	return combinedMovement
end

local function targetTeleported(targetRoot, currentTime, deltaTime)
	if state.botSequenceRoot and state.botSequenceRoot ~= targetRoot then
		return true
	end

	local currentPosition = targetRoot.Position
	local currentPhysicsVelocity = targetRoot.AssemblyLinearVelocity
	if not state.botSequenceLastPosition then
		state.botSequenceRoot = targetRoot
		state.botSequenceLastPosition = currentPosition
		state.botSequenceLastSampleAt = currentTime
		state.botSequenceEstimatedVelocity = currentPhysicsVelocity
		state.botSequenceLastPhysicsVelocity = currentPhysicsVelocity
		return false
	end

	local positionDelta = currentPosition - state.botSequenceLastPosition
	local movedDistance = positionDelta.Magnitude
	if movedDistance <= BOT_SEQUENCE_MOTION_EPSILON then
		local decay = math.exp(
			-BOT_SEQUENCE_VELOCITY_DECAY * math.max(deltaTime or 0, 0)
		)
		state.botSequenceEstimatedVelocity = state.botSequenceEstimatedVelocity
			* decay
		state.botSequenceLastPhysicsVelocity = currentPhysicsVelocity
		return false
	end

	local sampleInterval = math.clamp(
		currentTime - (state.botSequenceLastSampleAt or currentTime),
		1 / 240,
		BOT_SEQUENCE_MAX_SAMPLE_INTERVAL
	)
	local previousPhysicsVelocity = state.botSequenceLastPhysicsVelocity
		or Vector3.zero
	local estimatedVelocity = state.botSequenceEstimatedVelocity
		or Vector3.zero
	local physicsPrediction = (
		previousPhysicsVelocity + currentPhysicsVelocity
	) * 0.5 * sampleInterval
	local learnedPrediction = estimatedVelocity * sampleInterval
	local physicsResidual = (positionDelta - physicsPrediction).Magnitude
	local learnedResidual = (positionDelta - learnedPrediction).Magnitude
	local bestResidual = math.min(physicsResidual, learnedResidual)

	local targetHumanoid = state.target
		and state.target:FindFirstChildOfClass("Humanoid")
	local walkingAllowance = 0
	if targetHumanoid and targetHumanoid.MoveDirection.Magnitude > 0.05 then
		walkingAllowance = targetHumanoid.WalkSpeed * sampleInterval * 1.4
	end

	local hardDistance = math.max(
		BOT_SEQUENCE_TELEPORT_HARD_DISTANCE,
		BOT_SEQUENCE_TELEPORT_HARD_SPEED * sampleInterval
	)
	local physicsVelocitySpike = currentPhysicsVelocity.Magnitude
		>= BOT_SEQUENCE_PHYSICS_VELOCITY_SPIKE
		or previousPhysicsVelocity.Magnitude
			>= BOT_SEQUENCE_PHYSICS_VELOCITY_SPIKE
	local residualTeleport = movedDistance
		>= BOT_SEQUENCE_TELEPORT_MIN_DISTANCE
		and bestResidual >= BOT_SEQUENCE_TELEPORT_MIN_RESIDUAL
		and movedDistance > walkingAllowance + 0.35
	local teleported = movedDistance >= hardDistance
		or (movedDistance >= BOT_SEQUENCE_TELEPORT_MIN_DISTANCE
			and physicsVelocitySpike)
		or residualTeleport

	if teleported then
		return true
	end

	local observedVelocity = positionDelta / sampleInterval
	state.botSequenceEstimatedVelocity = estimatedVelocity:Lerp(
		observedVelocity,
		BOT_SEQUENCE_VELOCITY_BLEND
	)
	state.botSequenceRoot = targetRoot
	state.botSequenceLastPosition = currentPosition
	state.botSequenceLastSampleAt = currentTime
	state.botSequenceLastPhysicsVelocity = currentPhysicsVelocity
	return false
end

local function movementStep(deltaTime)
	if not state.alive then
		return
	end

	if not state.enabled then
		releaseTrackingControl()
		return
	end

	if not state.target then
		releaseTrackingControl()
		return
	end

	local humanoid, localRoot = getLocalMover()
	if not humanoid or not localRoot then
		releaseTrackingControl()
		return
	end

	local targetRoot = inspectCandidate(state.target)
	if not targetRoot then
		releaseTrackingControl()
		state.target = nil
		resetBotSequenceState()
		updateTarget(true)
		return
	end

	-- Esta variante nunca sobrescreve Humanoid:Move nem AutoRotate. Assim, o
	-- joystick continua 100% livre e o movimento relativo a camera permanece o
	-- comportamento nativo do Roblox.
	releaseMovement()
	restoreCharacterFacing()

	if state.botAppearSequenceTarget ~= state.target
		or state.botSequencePhase == "idle" then
		beginBotSequence(state.target, targetRoot, false)
	end

	local currentTime = os.clock()
	if targetTeleported(targetRoot, currentTime, deltaTime) then
		beginBotSequence(state.target, targetRoot, true)
		return
	end

	if not state.hasBomb then
		releaseTrackingControl()
		return
	end

	if state.botSequencePhase == "waiting" then
		if currentTime < state.botAppearWaitUntil then
			state.cameraEngageActive = false
			state.cameraEngageElapsed = 0
			state.cameraEngageStartCFrame = nil
			state.cameraLastOutputForward = nil
			state.trackingActiveLastFrame = false
			return
		end

		state.botSequencePhase = "engaging"
		state.trackingActiveLastFrame = false
	end

	if not state.trackingActiveLastFrame then
		state.trackingActiveLastFrame = true
		state.cameraEngageActive = true
		state.cameraEngageElapsed = 0
		state.cameraEngageStartCFrame = nil
		state.cameraLastOutputForward = nil
		state.cameraEngageDuration = state.botSequencePhase == "engaging"
			and state.botAppearEngageDuration
			or getCameraEngageDuration()
	end

	updateTrackingCamera(
		localRoot,
		targetRoot,
		targetRoot.Position,
		deltaTime
	)

	if state.botSequencePhase == "engaging"
		and not state.cameraEngageActive then
		state.botSequencePhase = "tracking"
		state.botSequenceLastPosition = targetRoot.Position
		state.botSequenceLastSampleAt = os.clock()
		state.botSequenceEstimatedVelocity = targetRoot.AssemblyLinearVelocity
		state.botSequenceLastPhysicsVelocity = targetRoot.AssemblyLinearVelocity
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
		state.distanceElapsed = 0
		randomizeStopDistance()
		state.microSign = RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1
		state.microPhase = RandomGenerator:NextNumber(0, math.pi * 2)
		state.microFrequency = RandomGenerator:NextNumber(0.72, 1.08)
		state.innerRecoveryActive = false
		state.sharpTurnSpacingActive = false
		state.sharpTurnSpacingElapsed = 0
		state.sharpTurnSpacingSettled = 0
		state.sharpTurnSpacingCooldown = 0
		state.aimReturnFromEdge = false
		randomizeAimTarget()
		state.aimAppliedOffset = state.aimTargetOffset
		state.cameraRequestedOffsetDegrees = 0
		state.cameraAppliedOffsetDegrees = 0
		randomizeCameraBaseOffset()
		state.cameraBaseAppliedOffsetDegrees = 0
		state.cameraFlickElapsed = state.cameraFlickDuration
		state.cameraFlickOffsetDegrees = 0
		state.cameraFlickRoutineElapsed = 0
		state.cameraFlickRoutineInterval = RandomGenerator:NextNumber(
			CAMERA_FLICK_ROUTINE_MIN,
			CAMERA_FLICK_ROUTINE_MAX
		)
		state.cameraFlickCooldown = 0
		state.cameraMicroPhaseA = RandomGenerator:NextNumber(0, math.pi * 2)
		state.cameraMicroPhaseB = RandomGenerator:NextNumber(0, math.pi * 2)
		state.cameraLastBotSamplePosition = nil
		state.cameraLastBotMoveDirection = nil
		state.cameraEngageActive = false
		state.cameraEngageElapsed = 0
		state.cameraEngageStartCFrame = nil
		state.cameraLastOutputForward = nil
		state.trackingActiveLastFrame = false
		state.hasBomb = playerHasBomb()
		refreshCandidateCache()
		updateTarget(false)
	else
		state.hasBomb = false
		state.target = nil
		resetBotSequenceState()
		state.distanceElapsed = 0
		releaseTrackingControl()
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
	local screenSize = ScreenGui.AbsoluteSize
	if screenSize.X > 0 and screenSize.Y > 0 then
		viewport = screenSize
	end

	local x = math.clamp(
		position.X.Offset,
		0,
		math.max(0, viewport.X - MobileButton.AbsoluteSize.X)
	)
	local y = math.clamp(
		position.Y.Offset,
		0,
		math.max(0, viewport.Y - MobileButton.AbsoluteSize.Y)
	)
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
			resetBotSequenceState()
			releaseTrackingControl()
			task.defer(function()
				if state.alive and state.enabled and not state.target then
					updateTarget(true)
				end
			end)
		end
	end
end)

connect(LocalPlayer.CharacterAdded, function()
	state.hasBomb = false
	state.target = nil
	resetBotSequenceState()
	state.distanceElapsed = 0
	releaseTrackingControl()
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
		if hadBomb ~= state.hasBomb then
			if not state.hasBomb then
				releaseTrackingControl()
			end
		end
	end

	if cacheElapsed >= CACHE_REFRESH_INTERVAL then
		cacheElapsed = 0
		refreshCandidateCache()
	end

	if targetElapsed >= TARGET_UPDATE_INTERVAL then
		targetElapsed = 0
		updateTarget(true)
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
	resetBotSequenceState()
	state.distanceElapsed = 0
	releaseTrackingControl()

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
warn("[Camera Track] Carregado: movimento livre, horizontal entre -60 e 60 graus e padrao em 45 graus.")
