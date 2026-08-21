-- AutoTrackCam - Cerber W Mobile
-- Camera-only tracking for the nearest player while the local player holds the bomb.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Backpack = LocalPlayer:WaitForChild("Backpack")
local RandomGenerator = Random.new()

local GLOBAL_STATE_NAME = "__cerber_w_autocamera_main"
local SCREEN_GUI_NAME = "CerberWAutoCameraMobile"
local RENDER_BIND_NAME = "CerberW_AutoCamera_" .. tostring(LocalPlayer.UserId)

local TARGET_UPDATE_INTERVAL = 0.10
local BOMB_UPDATE_INTERVAL = 0.05
local DRAG_HOLD_TIME = 0.50

local TRACK_HORIZONTAL_OFFSET_DEGREES = 45
local CAMERA_MIN_TRACK_ANGLE_DEGREES = -60
local CAMERA_MAX_TRACK_ANGLE_DEGREES = 60
local CAMERA_MIN_MANUAL_OFFSET_DEGREES = CAMERA_MIN_TRACK_ANGLE_DEGREES
	- TRACK_HORIZONTAL_OFFSET_DEGREES
local CAMERA_MAX_MANUAL_OFFSET_DEGREES = CAMERA_MAX_TRACK_ANGLE_DEGREES
	- TRACK_HORIZONTAL_OFFSET_DEGREES
local CAMERA_INPUT_NOISE_THRESHOLD_DEGREES = 0.01
local CAMERA_INPUT_MAX_DELTA_DEGREES = 60
local CAMERA_MIN_HORIZONTAL_RADIUS = 0.08
local REACTION_SHARP_TURN_THRESHOLD_DEGREES = 50
local REACTION_TRIGGER_COOLDOWN = 0.16

-- 30% keeps the former response time. 70% reacts in 0.04-0.10 s,
-- with a bias toward the lower end of that range.
local CAMERA_ENGAGE_SLOW_CHANCE = 0.30
local CAMERA_ENGAGE_SLOW_MIN = 0.18
local CAMERA_ENGAGE_SLOW_MAX = 0.28
local CAMERA_ENGAGE_FAST_MIN = 0.04
local CAMERA_ENGAGE_FAST_MAX = 0.10
local CAMERA_ENGAGE_FAST_BIAS_POWER = 2.2

local AIM_MIN_ABSOLUTE_OFFSET = 0.14
local AIM_NEAR_MAX_OFFSET = 0.58
local AIM_MIDDLE_MAX_OFFSET = 0.98
local AIM_EDGE_MAX_OFFSET = 1.35
local AIM_NEAR_CHANCE = 0.55
local AIM_MIDDLE_CHANCE = 0.86
local AIM_CHANGE_MIN = 0.22
local AIM_CHANGE_MAX = 0.55
local AIM_EDGE_CHANGE_MIN = 0.10
local AIM_EDGE_CHANGE_MAX = 0.16
local AIM_RETURN_CHANGE_MIN = 0.16
local AIM_RETURN_CHANGE_MAX = 0.30
local AIM_SMOOTH_SPEED = 18

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

local environment = _G
pcall(function()
	if getgenv then
		environment = getgenv()
	end
end)

local function stopPreviousGlobal(name)
	local previous = environment[name]
	if type(previous) == "table" and type(previous.cleanup) == "function" then
		pcall(previous.cleanup)
	end
end

stopPreviousGlobal(GLOBAL_STATE_NAME)
stopPreviousGlobal("__nt_autocamera_game_scan")
stopPreviousGlobal("__nt_autotrack_bot_debug")

pcall(function()
	RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
end)

for _, guiName in ipairs({
	SCREEN_GUI_NAME,
	"AutoTrackBotDebugMobile",
	"AutoWallHopGuiMobile",
}) do
	local oldGui = PlayerGui:FindFirstChild(guiName)
	if oldGui then
		oldGui:Destroy()
	end
end

local state = {
	alive = true,
	enabled = false,
	teamCheckEnabled = true,
	buttonHidden = false,
	startTime = 10,
	reactionTimeMs = 0,
	connections = {},
	target = nil,
	bomb = nil,
	timerLabel = nil,
	timerLastText = nil,
	timerDisplayValue = nil,
	timerObservedAt = 0,
	timerStepDuration = 1,
	timerPrecise = false,
	remainingTime = nil,
	trackingActiveLastFrame = false,
	cameraRequestedOffsetDegrees = 0,
	cameraAppliedOffsetDegrees = 0,
	cameraLastOutputForward = nil,
	cameraEngageActive = false,
	cameraEngageElapsed = 0,
	cameraEngageDuration = CAMERA_ENGAGE_SLOW_MIN,
	cameraEngageStartCFrame = nil,
	aimTargetOffset = (RandomGenerator:NextInteger(0, 1) == 0 and -1 or 1)
		* RandomGenerator:NextNumber(0.2, 0.5),
	aimAppliedOffset = 0.24,
	aimElapsed = 0,
	aimChangeInterval = RandomGenerator:NextNumber(AIM_CHANGE_MIN, AIM_CHANGE_MAX),
	aimReturnFromEdge = false,
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
	cameraLastTargetSamplePosition = nil,
	cameraLastTargetMoveDirection = nil,
	cameraLastAppliedTargetDirection = nil,
	cameraReactionUntil = 0,
	cameraReactionCooldownUntil = 0,
	cameraReactionHeldDirection = nil,
	cameraPendingTurnFlick = false,
}
state.aimAppliedOffset = state.aimTargetOffset
environment[GLOBAL_STATE_NAME] = state

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local function getCameraEngageDuration()
	if RandomGenerator:NextNumber(0, 1) < CAMERA_ENGAGE_SLOW_CHANCE then
		return RandomGenerator:NextNumber(
			CAMERA_ENGAGE_SLOW_MIN,
			CAMERA_ENGAGE_SLOW_MAX
		)
	end

	local sample = RandomGenerator:NextNumber(0, 1)
	local biasedSample = sample ^ CAMERA_ENGAGE_FAST_BIAS_POWER
	return CAMERA_ENGAGE_FAST_MIN
		+ ((CAMERA_ENGAGE_FAST_MAX - CAMERA_ENGAGE_FAST_MIN) * biasedSample)
end

local function getSmoothAlpha(speed, deltaTime)
	return 1 - math.exp(-speed * math.max(deltaTime, 0))
end

local function getSmoothStep(value)
	local clamped = math.clamp(value, 0, 1)
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

local function getCharacterRoot(character)
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local root = humanoid.RootPart
	if not root or not root:IsA("BasePart") then
		root = character:FindFirstChild("HumanoidRootPart")
	end
	if not root or not root:IsA("BasePart") then
		root = character.PrimaryPart
	end

	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local BOMB_NAME_HINTS = {
	"bomb",
	"bomba",
	"tnt",
	"explosive",
}

local function nameLooksLikeBomb(name)
	local lowerName = string.lower(tostring(name or ""))
	for _, hint in ipairs(BOMB_NAME_HINTS) do
		if string.find(lowerName, hint, 1, true) then
			return true
		end
	end
	return false
end

local function findBombIn(root)
	if not root then
		return nil
	end

	local exact = root:FindFirstChild("Bomb")
	if exact then
		return exact
	end

	for _, child in ipairs(root:GetChildren()) do
		if nameLooksLikeBomb(child.Name) then
			return child
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if nameLooksLikeBomb(descendant.Name)
			and (descendant:IsA("Tool") or descendant:FindFirstChild("BombHandle")) then
			return descendant
		end
	end

	return nil
end

local function findOwnedBomb()
	-- Exact structure found by the scan:
	-- Workspace.Characters.<local player>.Bomb
	local characterBomb = findBombIn(LocalPlayer.Character)
	if characterBomb then
		return characterBomb
	end

	return findBombIn(Backpack)
end

local function findTimerLabel(bomb)
	if not bomb then
		return nil
	end

	-- Exact structure found by the scan:
	-- Bomb.BombHandle.UIAttachment.UI.TimeLeft
	local handle = bomb:FindFirstChild("BombHandle")
	local attachment = handle and handle:FindFirstChild("UIAttachment")
	local ui = attachment and attachment:FindFirstChild("UI")
	local exact = ui and ui:FindFirstChild("TimeLeft")
	if exact and (exact:IsA("TextLabel")
		or exact:IsA("TextButton")
		or exact:IsA("TextBox")) then
		return exact
	end

	local fallback = bomb:FindFirstChild("TimeLeft", true)
	if fallback and (fallback:IsA("TextLabel")
		or fallback:IsA("TextButton")
		or fallback:IsA("TextBox")) then
		return fallback
	end

	return nil
end

local function parseTimerText(text)
	local normalized = tostring(text or ""):gsub(",", ".")
	local minutes, seconds = normalized:match("(%d+)%s*:%s*(%d+%.?%d*)")
	if minutes and seconds then
		return (tonumber(minutes) * 60) + tonumber(seconds), true
	end

	local numericText = normalized:match("%d+%.?%d*")
	if not numericText then
		return nil, false
	end

	return tonumber(numericText), numericText:find("%.", 1, false) ~= nil
end

local function resetTimerState(bomb, label)
	state.bomb = bomb
	state.timerLabel = label
	state.timerLastText = nil
	state.timerDisplayValue = nil
	state.timerObservedAt = os.clock()
	state.timerStepDuration = 1
	state.timerPrecise = false
	state.remainingTime = nil
end

local function updateRemainingTime()
	local bomb = findOwnedBomb()
	local label = findTimerLabel(bomb)
	if bomb ~= state.bomb or label ~= state.timerLabel then
		resetTimerState(bomb, label)
	end

	if not bomb then
		state.remainingTime = nil
		return nil
	end

	if not label then
		-- With the default 10-second setting, possession itself is sufficient.
		-- Lower custom thresholds wait for a readable countdown.
		state.remainingTime = state.startTime >= 9.999 and 10 or nil
		return state.remainingTime
	end

	local now = os.clock()
	local currentText = tostring(label.Text or "")
	if currentText ~= state.timerLastText then
		local parsed, precise = parseTimerText(currentText)
		if parsed ~= nil then
			if state.timerDisplayValue ~= nil and parsed < state.timerDisplayValue then
				local observedStep = now - state.timerObservedAt
				if observedStep >= 0.35 and observedStep <= 1.75 then
					state.timerStepDuration = math.clamp(
						(state.timerStepDuration * 0.65) + (observedStep * 0.35),
						0.70,
						1.30
					)
				end
			end
			state.timerDisplayValue = parsed
			state.timerObservedAt = now
			state.timerPrecise = precise
		end
		state.timerLastText = currentText
	end

	if state.timerDisplayValue == nil then
		state.remainingTime = nil
		return nil
	end

	if state.timerPrecise then
		state.remainingTime = math.max(0, state.timerDisplayValue)
	else
		local elapsed = math.max(0, now - state.timerObservedAt)
		local estimated = state.timerDisplayValue
			- (elapsed / math.max(state.timerStepDuration, 0.01))
		state.remainingTime = math.max(0, estimated)
	end

	return state.remainingTime
end

local function playersAreTeammates(otherPlayer)
	if not state.teamCheckEnabled then
		return false
	end

	local localTeam = LocalPlayer.Team
	local otherTeam = otherPlayer.Team
	if localTeam and otherTeam then
		return localTeam == otherTeam
	end

	if not LocalPlayer.Neutral and not otherPlayer.Neutral then
		return LocalPlayer.TeamColor == otherPlayer.TeamColor
	end

	return false
end

local function findNearestPlayer()
	local localRoot = getCharacterRoot(LocalPlayer.Character)
	if not localRoot then
		return nil
	end

	local nearestPlayer = nil
	local nearestDistance = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local root = getCharacterRoot(player.Character)
			if root then
				local distance = (root.Position - localRoot.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearestPlayer = player
				end
			end
		end
	end

	-- Team Check remains outside target selection until its game-specific
	-- signal is mapped, preventing it from blocking every nearby player.
	return nearestPlayer
end

local function randomizeAimTarget()
	local previousTarget = state.aimTargetOffset or AIM_MIN_ABSOLUTE_OFFSET
	local previousSign = getDirectionSign(previousTarget)
	local nextSign = previousSign
	local magnitude = AIM_MIN_ABSOLUTE_OFFSET

	if state.aimReturnFromEdge then
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
		nextTarget = -previousSign * math.max(AIM_MIN_ABSOLUTE_OFFSET, magnitude)
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

	local horizontalRight = getHorizontalUnit(targetRoot.CFrame.RightVector)
	if not horizontalRight then
		return targetRoot.Position
	end

	return targetRoot.Position + (horizontalRight * appliedOffset)
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
		nextOffset = getDirectionSign(nextOffset) * CAMERA_BASE_MIN_ABSOLUTE_DEGREES
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

local function startSharpTurnReaction()
	local delaySeconds = math.clamp(state.reactionTimeMs or 0, 0, 99) / 1000
	local now = os.clock()
	if delaySeconds <= 0
		or now < state.cameraReactionCooldownUntil
		or not state.cameraLastAppliedTargetDirection then
		return false
	end

	state.cameraReactionHeldDirection = state.cameraLastAppliedTargetDirection
	state.cameraReactionUntil = now + delaySeconds
	state.cameraReactionCooldownUntil = now
		+ delaySeconds
		+ REACTION_TRIGGER_COOLDOWN
	return true
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

	state.cameraFlickCooldown = math.max(0, state.cameraFlickCooldown - deltaTime)
	local targetPosition = targetRoot.Position
	if not state.cameraLastTargetSamplePosition then
		state.cameraLastTargetSamplePosition = targetPosition
	else
		local displacement = targetPosition - state.cameraLastTargetSamplePosition
		local horizontalDisplacement = Vector3.new(
			displacement.X,
			0,
			displacement.Z
		)
		if horizontalDisplacement.Magnitude >= CAMERA_FLICK_SAMPLE_DISTANCE then
			local moveDirection = horizontalDisplacement.Unit
			if state.cameraLastTargetMoveDirection then
				local directionDot = math.clamp(
					state.cameraLastTargetMoveDirection:Dot(moveDirection),
					-1,
					1
				)
				local turnDegrees = math.deg(math.acos(directionDot))
				local reactionStarted = false
				if turnDegrees >= REACTION_SHARP_TURN_THRESHOLD_DEGREES then
					reactionStarted = startSharpTurnReaction()
				end
				if turnDegrees >= CAMERA_FLICK_TURN_THRESHOLD_DEGREES
					and state.cameraFlickCooldown <= 0 then
					if reactionStarted then
						state.cameraPendingTurnFlick = true
					else
						startCameraFlick(
							CAMERA_FLICK_TURN_MIN,
							CAMERA_FLICK_TURN_MAX
						)
					end
				end
			end
			state.cameraLastTargetMoveDirection = moveDirection
			state.cameraLastTargetSamplePosition = targetPosition
		end
	end

	if state.cameraPendingTurnFlick
		and os.clock() >= state.cameraReactionUntil then
		state.cameraPendingTurnFlick = false
		if state.cameraFlickCooldown <= 0 then
			startCameraFlick(CAMERA_FLICK_TURN_MIN, CAMERA_FLICK_TURN_MAX)
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
			startCameraFlick(CAMERA_FLICK_LIGHT_MIN, CAMERA_FLICK_LIGHT_MAX)
		end
	end

	state.cameraFlickElapsed = state.cameraFlickElapsed + deltaTime
	if state.cameraFlickElapsed < state.cameraFlickDuration then
		local progress = math.clamp(
			state.cameraFlickElapsed / state.cameraFlickDuration,
			0,
			1
		)
		state.cameraFlickOffsetDegrees = state.cameraFlickAmplitude
			* math.sin(math.pi * getSmoothStep(progress))
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

local function resetCameraTrackingState(resetManualOffset)
	state.trackingActiveLastFrame = false
	state.cameraEngageActive = false
	state.cameraEngageElapsed = 0
	state.cameraEngageStartCFrame = nil
	state.cameraLastOutputForward = nil
	state.cameraLastTargetSamplePosition = nil
	state.cameraLastTargetMoveDirection = nil
	state.cameraLastAppliedTargetDirection = nil
	state.cameraReactionUntil = 0
	state.cameraReactionCooldownUntil = 0
	state.cameraReactionHeldDirection = nil
	state.cameraPendingTurnFlick = false
	state.cameraFlickOffsetDegrees = 0
	state.cameraFlickElapsed = state.cameraFlickDuration
	if resetManualOffset then
		state.cameraRequestedOffsetDegrees = 0
		state.cameraAppliedOffsetDegrees = 0
	end
end

local function beginCameraTracking()
	state.trackingActiveLastFrame = true
	state.cameraEngageActive = true
	state.cameraEngageElapsed = 0
	state.cameraEngageDuration = getCameraEngageDuration()
	state.cameraEngageStartCFrame = nil
	state.cameraLastOutputForward = nil
	state.cameraLastTargetSamplePosition = nil
	state.cameraLastTargetMoveDirection = nil
	state.cameraLastAppliedTargetDirection = nil
	state.cameraReactionUntil = 0
	state.cameraReactionHeldDirection = nil
	state.cameraPendingTurnFlick = false
	state.cameraMicroPhaseA = RandomGenerator:NextNumber(0, math.pi * 2)
	state.cameraMicroPhaseB = RandomGenerator:NextNumber(0, math.pi * 2)
	randomizeAimTarget()
	randomizeCameraBaseOffset()
end

local function updateTrackingCamera(localRoot, targetRoot, deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local aimPosition = updateAimPosition(targetRoot, deltaTime)
	local rawTargetDirection = getHorizontalUnit(aimPosition - localRoot.Position)
	if not rawTargetDirection then
		return
	end

	local focus = camera.Focus.Position
	local defaultForward = getHorizontalUnit(focus - camera.CFrame.Position)
	if state.cameraLastOutputForward and defaultForward then
		-- Original first-ZIP behavior: CameraModule runs before this step. The
		-- difference it produced is applied directly as the native drag input.
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

	local manualOffset = math.clamp(
		state.cameraRequestedOffsetDegrees or 0,
		CAMERA_MIN_MANUAL_OFFSET_DEGREES,
		CAMERA_MAX_MANUAL_OFFSET_DEGREES
	)
	state.cameraAppliedOffsetDegrees = manualOffset

	local baseError, flickError, microError = updateCameraVariation(
		targetRoot,
		deltaTime
	)

	local targetDirection = rawTargetDirection
	if os.clock() < state.cameraReactionUntil
		and state.cameraReactionHeldDirection then
		targetDirection = state.cameraReactionHeldDirection
	else
		state.cameraReactionHeldDirection = nil
		state.cameraLastAppliedTargetDirection = rawTargetDirection
	end

	local trackAngle = math.clamp(
		TRACK_HORIZONTAL_OFFSET_DEGREES
			+ manualOffset
			+ baseError
			+ flickError
			+ microError,
		CAMERA_MIN_TRACK_ANGLE_DEGREES,
		CAMERA_MAX_TRACK_ANGLE_DEGREES
	)
	local limitedForward = rotateHorizontalLeft(targetDirection, trackAngle)

	-- Keep the native zoom and vertical pitch. Only the horizontal direction
	-- is guided, so the player can still move the camera vertically and zoom.
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

local function noTextStroke(textObject)
	textObject.TextStrokeTransparency = 1
end

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
		shadow:SetAttribute("ShownTransparency", config.transparency)
		shadow.BorderSizePixel = 0
		shadow.ZIndex = math.max(parent.ZIndex - 1, 0)
		shadow.Active = false
		shadow.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(
			0,
			cornerRadius + math.floor(config.grow / 2.1)
		)
		corner.Parent = shadow
	end
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

local inset = GuiService:GetGuiInset()
local initialY = math.max(6, inset.Y - 6)

local MobileButton = Instance.new("TextButton")
MobileButton.Name = "AutoCameraButton"
MobileButton.Size = UDim2.new(0, 140, 0, 50)
MobileButton.Position = UDim2.new(0, 150, 0, initialY)
MobileButton.BackgroundColor3 = Color3.fromRGB(180, 38, 45)
MobileButton.BorderSizePixel = 0
MobileButton.Text = "Auto Camera Off"
MobileButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileButton.Font = Enum.Font.GothamBold
MobileButton.TextScaled = true
MobileButton.AutoButtonColor = false
MobileButton.ZIndex = 10
MobileButton.Active = true
MobileButton.Parent = ScreenGui
MobileButton:SetAttribute("LastDragTime", 0)
Instance.new("UICorner", MobileButton).CornerRadius = UDim.new(0, 12)
noTextStroke(MobileButton)
addTrueRoundedShadow(MobileButton, 14, 1.15, Color3.fromRGB(0, 0, 0))

local buttonTextLimit = Instance.new("UITextSizeConstraint")
buttonTextLimit.MinTextSize = 10
buttonTextLimit.MaxTextSize = 17
buttonTextLimit.Parent = MobileButton

local buttonScale = Instance.new("UIScale")
buttonScale.Scale = 1
buttonScale.Parent = MobileButton

local MobileMenuButton = Instance.new("TextButton")
MobileMenuButton.Name = "MenuButton"
MobileMenuButton.Size = UDim2.new(0, 54, 0, 54)
MobileMenuButton.Position = UDim2.new(0, 86, 0, initialY)
MobileMenuButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
MobileMenuButton.BorderSizePixel = 0
MobileMenuButton.Text = "≡"
MobileMenuButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileMenuButton.Font = Enum.Font.GothamBold
MobileMenuButton.TextSize = 22
MobileMenuButton.AutoButtonColor = false
MobileMenuButton.ZIndex = 10
MobileMenuButton.Active = true
MobileMenuButton.Parent = ScreenGui
MobileMenuButton:SetAttribute("LastDragTime", 0)
Instance.new("UICorner", MobileMenuButton).CornerRadius = UDim.new(1, 0)
noTextStroke(MobileMenuButton)
addTrueRoundedShadow(MobileMenuButton, 999, 1.05, Color3.fromRGB(0, 0, 0))

local menuScale = Instance.new("UIScale")
menuScale.Scale = 1
menuScale.Parent = MobileMenuButton

local MobilePanel = Instance.new("Frame")
MobilePanel.Name = "Panel"
MobilePanel.Size = UDim2.new(0, 232, 0, 324)
MobilePanel.Position = UDim2.new(0, 8, 0, 72)
MobilePanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
MobilePanel.BorderSizePixel = 0
MobilePanel.Visible = false
MobilePanel.ZIndex = 30
MobilePanel.Parent = ScreenGui
MobilePanel:SetAttribute("CustomMoved", false)
Instance.new("UICorner", MobilePanel).CornerRadius = UDim.new(0, 14)
addTrueRoundedShadow(MobilePanel, 14, 1.15, Color3.fromRGB(0, 0, 0))

local panelScale = Instance.new("UIScale")
panelScale.Scale = 1
panelScale.Parent = MobilePanel

local mobileDragHandle = Instance.new("Frame")
mobileDragHandle.Name = "DragHandle"
mobileDragHandle.Size = UDim2.new(1, -16, 0, 14)
mobileDragHandle.Position = UDim2.new(0, 8, 0, 5)
mobileDragHandle.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
mobileDragHandle.BorderSizePixel = 0
mobileDragHandle.Active = true
mobileDragHandle.ZIndex = 35
mobileDragHandle.Parent = MobilePanel
Instance.new("UICorner", mobileDragHandle).CornerRadius = UDim.new(1, 0)

local function createTab(text, position, width)
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0, width, 0, 26)
	tab.Position = position
	tab.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
	tab.BorderSizePixel = 0
	tab.Text = text
	tab.TextColor3 = Color3.fromRGB(255, 255, 255)
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 11
	tab.AutoButtonColor = false
	tab.ZIndex = 35
	tab.Parent = MobilePanel
	Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 10)
	noTextStroke(tab)
	return tab
end

local MobileTabFunctions = createTab(
	"Functions",
	UDim2.new(0, 8, 0, 24),
	102
)
local MobileTabSettings = createTab(
	"Settings",
	UDim2.new(0, 122, 0, 24),
	102
)
MobileTabFunctions.BackgroundColor3 = Color3.fromRGB(20, 20, 20)

local MobileFunctionsPage = Instance.new("Frame")
MobileFunctionsPage.Name = "FunctionsPage"
MobileFunctionsPage.Size = UDim2.new(1, 0, 1, -58)
MobileFunctionsPage.Position = UDim2.new(0, 0, 0, 58)
MobileFunctionsPage.BackgroundTransparency = 1
MobileFunctionsPage.ZIndex = 31
MobileFunctionsPage.Parent = MobilePanel

local MobileSettingsPage = Instance.new("Frame")
MobileSettingsPage.Name = "SettingsPage"
MobileSettingsPage.Size = UDim2.new(1, 0, 1, -58)
MobileSettingsPage.Position = UDim2.new(0, 0, 0, 58)
MobileSettingsPage.BackgroundTransparency = 1
MobileSettingsPage.Visible = false
MobileSettingsPage.ZIndex = 31
MobileSettingsPage.Parent = MobilePanel

local functionsTitle = Instance.new("TextLabel")
functionsTitle.Size = UDim2.new(1, -14, 0, 22)
functionsTitle.Position = UDim2.new(0, 7, 0, 4)
functionsTitle.BackgroundTransparency = 1
functionsTitle.Text = "All Functions"
functionsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
functionsTitle.Font = Enum.Font.GothamBold
functionsTitle.TextSize = 13
functionsTitle.TextXAlignment = Enum.TextXAlignment.Left
functionsTitle.ZIndex = 36
functionsTitle.Parent = MobileFunctionsPage
noTextStroke(functionsTitle)

local function createSwitchRow(parent, yOffset, labelText)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -14, 0, 40)
	row.Position = UDim2.new(0, 7, 0, yOffset)
	row.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.ZIndex = 35
	row.Active = true
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 130, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 36
	label.Active = false
	label.Parent = row
	noTextStroke(label)

	local switch = Instance.new("Frame")
	switch.Name = "Switch"
	switch.Size = UDim2.new(0, 54, 0, 28)
	switch.Position = UDim2.new(1, -66, 0.5, -14)
	switch.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	switch.BorderSizePixel = 0
	switch.ZIndex = 36
	switch.Active = false
	switch.Parent = row
	Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, 26, 0, 26)
	knob.Position = UDim2.new(0, 3, 0.5, -13)
	knob.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	knob.BorderSizePixel = 0
	knob.ZIndex = 37
	knob.Active = false
	knob.Parent = switch
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	return row, switch, knob
end

local HideButtonRow, hideButtonSwitch, hideButtonKnob = createSwitchRow(
	MobileFunctionsPage,
	30,
	"Hide Button"
)
local TeamCheckRow, teamCheckSwitch, teamCheckKnob = createSwitchRow(
	MobileFunctionsPage,
	72,
	"Team Check"
)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -14, 0, 22)
settingsTitle.Position = UDim2.new(0, 7, 0, 4)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Minimal Settings"
settingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextSize = 13
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.ZIndex = 36
settingsTitle.Parent = MobileSettingsPage
noTextStroke(settingsTitle)

local timeRow = Instance.new("Frame")
timeRow.Size = UDim2.new(1, -14, 0, 48)
timeRow.Position = UDim2.new(0, 7, 0, 30)
timeRow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
timeRow.BorderSizePixel = 0
timeRow.ZIndex = 35
timeRow.Parent = MobileSettingsPage
Instance.new("UICorner", timeRow).CornerRadius = UDim.new(0, 12)

local timeLabel = Instance.new("TextLabel")
timeLabel.Size = UDim2.new(1, -86, 1, 0)
timeLabel.Position = UDim2.new(0, 12, 0, 0)
timeLabel.BackgroundTransparency = 1
timeLabel.Text = "Start Time"
timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timeLabel.Font = Enum.Font.GothamBold
timeLabel.TextSize = 15
timeLabel.TextXAlignment = Enum.TextXAlignment.Left
timeLabel.ZIndex = 36
timeLabel.Parent = timeRow
noTextStroke(timeLabel)

local StartTimeBox = Instance.new("TextBox")
StartTimeBox.Name = "StartTime"
StartTimeBox.Size = UDim2.new(0, 64, 0, 30)
StartTimeBox.Position = UDim2.new(1, -74, 0.5, -15)
StartTimeBox.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
StartTimeBox.BorderSizePixel = 0
StartTimeBox.Text = "10s"
StartTimeBox.PlaceholderText = "10"
StartTimeBox.TextColor3 = Color3.fromRGB(255, 255, 255)
StartTimeBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
StartTimeBox.Font = Enum.Font.GothamBold
StartTimeBox.TextSize = 14
StartTimeBox.ClearTextOnFocus = false
StartTimeBox.ZIndex = 37
StartTimeBox.Parent = timeRow
Instance.new("UICorner", StartTimeBox).CornerRadius = UDim.new(0, 10)
noTextStroke(StartTimeBox)

local reactionRow = Instance.new("Frame")
reactionRow.Size = UDim2.new(1, -14, 0, 48)
reactionRow.Position = UDim2.new(0, 7, 0, 84)
reactionRow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
reactionRow.BorderSizePixel = 0
reactionRow.ZIndex = 35
reactionRow.Parent = MobileSettingsPage
Instance.new("UICorner", reactionRow).CornerRadius = UDim.new(0, 12)

local reactionLabel = Instance.new("TextLabel")
reactionLabel.Size = UDim2.new(1, -86, 1, 0)
reactionLabel.Position = UDim2.new(0, 12, 0, 0)
reactionLabel.BackgroundTransparency = 1
reactionLabel.Text = "Reaction Time"
reactionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
reactionLabel.Font = Enum.Font.GothamBold
reactionLabel.TextSize = 15
reactionLabel.TextXAlignment = Enum.TextXAlignment.Left
reactionLabel.ZIndex = 36
reactionLabel.Parent = reactionRow
noTextStroke(reactionLabel)

local ReactionTimeBox = Instance.new("TextBox")
ReactionTimeBox.Name = "ReactionTime"
ReactionTimeBox.Size = UDim2.new(0, 64, 0, 30)
ReactionTimeBox.Position = UDim2.new(1, -74, 0.5, -15)
ReactionTimeBox.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
ReactionTimeBox.BorderSizePixel = 0
ReactionTimeBox.Text = "0ms"
ReactionTimeBox.PlaceholderText = "0"
ReactionTimeBox.TextColor3 = Color3.fromRGB(255, 255, 255)
ReactionTimeBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
ReactionTimeBox.Font = Enum.Font.GothamBold
ReactionTimeBox.TextSize = 14
ReactionTimeBox.ClearTextOnFocus = false
ReactionTimeBox.ZIndex = 37
ReactionTimeBox.Parent = reactionRow
Instance.new("UICorner", ReactionTimeBox).CornerRadius = UDim.new(0, 10)
noTextStroke(ReactionTimeBox)

local settingsNote = Instance.new("TextLabel")
settingsNote.Size = UDim2.new(1, -24, 0, 36)
settingsNote.Position = UDim2.new(0, 12, 0, 142)
settingsNote.BackgroundTransparency = 1
settingsNote.Text = "Start: 0-10s • Reaction: 0-99ms"
settingsNote.TextColor3 = Color3.fromRGB(95, 95, 95)
settingsNote.Font = Enum.Font.Gotham
settingsNote.TextSize = 11
settingsNote.TextWrapped = true
settingsNote.TextXAlignment = Enum.TextXAlignment.Left
settingsNote.TextYAlignment = Enum.TextYAlignment.Top
settingsNote.ZIndex = 36
settingsNote.Parent = MobileSettingsPage
noTextStroke(settingsNote)

local noticeLabel = Instance.new("TextLabel")
noticeLabel.Size = UDim2.new(1, -24, 0, 28)
noticeLabel.Position = UDim2.new(0, 12, 1, -38)
noticeLabel.BackgroundTransparency = 1
noticeLabel.Text = ""
noticeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
noticeLabel.Font = Enum.Font.Gotham
noticeLabel.TextSize = 11
noticeLabel.TextWrapped = true
noticeLabel.ZIndex = 36
noticeLabel.Parent = MobilePanel
noTextStroke(noticeLabel)

local noticeToken = 0
local function showNotice(text)
	noticeToken = noticeToken + 1
	local myToken = noticeToken
	noticeLabel.Text = text
	noticeLabel.TextTransparency = 1
	TweenService:Create(
		noticeLabel,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 0}
	):Play()
	task.delay(1.6, function()
		if state.alive and myToken == noticeToken then
			TweenService:Create(
				noticeLabel,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{TextTransparency = 1}
			):Play()
		end
	end)
end

local function updateSwitchVisual(switchFrame, knob, enabled, instant)
	local offPosition = UDim2.new(0, 3, 0.5, -13)
	local onPosition = UDim2.new(1, -29, 0.5, -13)
	local switchColor = enabled
		and Color3.fromRGB(190, 190, 190)
		or Color3.fromRGB(20, 20, 24)
	local knobColor = enabled
		and Color3.fromRGB(255, 255, 255)
		or Color3.fromRGB(0, 0, 0)

	if instant then
		switchFrame.BackgroundColor3 = switchColor
		knob.Position = enabled and onPosition or offPosition
		knob.BackgroundColor3 = knobColor
		return
	end

	TweenService:Create(
		switchFrame,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = switchColor}
	):Play()
	TweenService:Create(
		knob,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = enabled and onPosition or offPosition,
			BackgroundColor3 = knobColor,
		}
	):Play()
end

local function clampGuiToScreen(guiObject)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local width = guiObject.AbsoluteSize.X
	local height = guiObject.AbsoluteSize.Y
	if width <= 0 then
		width = guiObject.Size.X.Offset
	end
	if height <= 0 then
		height = guiObject.Size.Y.Offset
	end

	local x = math.clamp(guiObject.Position.X.Offset, 0, math.max(0, viewport.X - width))
	local y = math.clamp(guiObject.Position.Y.Offset, 0, math.max(0, viewport.Y - height))
	guiObject.Position = UDim2.new(0, x, 0, y)
end

local function canUseTap(guiObject)
	local lastDragTime = guiObject:GetAttribute("LastDragTime") or 0
	return (os.clock() - lastDragTime) > 0.32
end

local function bindFreeDrag(handle, target, holdTime, onMoved)
	local activeInput = nil
	local dragStart = nil
	local startPosition = nil
	local holdSatisfied = false
	local holdCanceled = false
	local holdId = 0
	holdTime = holdTime or 0

	connect(handle.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		activeInput = input
		dragStart = input.Position
		startPosition = target.Position
		holdSatisfied = holdTime <= 0
		holdCanceled = false
		holdId = holdId + 1
		local thisHold = holdId

		if not holdSatisfied then
			task.delay(holdTime, function()
				if state.alive
					and activeInput == input
					and not holdCanceled
					and holdId == thisHold then
					holdSatisfied = true
					handle:SetAttribute("LastDragTime", os.clock())
				end
			end)
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if not activeInput or not dragStart or not startPosition then
			return
		end
		local matches = input == activeInput
			or (activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement)
		if not matches then
			return
		end

		local delta = input.Position - dragStart
		if not holdSatisfied then
			if delta.Magnitude >= 10 then
				holdCanceled = true
				handle:SetAttribute("LastDragTime", os.clock())
			end
			return
		end

		if delta.Magnitude >= 3 then
			handle:SetAttribute("LastDragTime", os.clock())
			target.Position = UDim2.new(
				0,
				startPosition.X.Offset + delta.X,
				0,
				startPosition.Y.Offset + delta.Y
			)
			clampGuiToScreen(target)
			if onMoved then
				onMoved()
			end
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input == activeInput then
			activeInput = nil
			dragStart = nil
			startPosition = nil
			holdSatisfied = false
			holdCanceled = false
		end
	end)
end

local function animatePress(scaleObject, pressed)
	TweenService:Create(
		scaleObject,
		TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = pressed and 0.95 or 1}
	):Play()
end

local function bindPressAnimation(button, scaleObject)
	connect(button.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			animatePress(scaleObject, true)
		end
	end)
	connect(button.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			animatePress(scaleObject, false)
		end
	end)
end

local function setMainButtonVisualHidden(hidden, instant)
	state.buttonHidden = hidden
	-- Keep the GuiButton alive and Active. Only its pixels disappear, so the
	-- exact same area still accepts taps and the 0.5 s drag gesture.
	MobileButton.Visible = true
	local duration = instant and 0 or 0.16
	TweenService:Create(
		MobileButton,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = hidden and 1 or 0,
			TextTransparency = hidden and 1 or 0,
		}
	):Play()

	for _, descendant in ipairs(MobileButton:GetDescendants()) do
		if descendant.Name == "TrueShadow" and descendant:IsA("Frame") then
			local shownTransparency = descendant:GetAttribute("ShownTransparency")
			if type(shownTransparency) ~= "number" then
				shownTransparency = 0.9
			end
			TweenService:Create(
				descendant,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundTransparency = hidden and 1 or shownTransparency}
			):Play()
		end
	end
end

local function updateButtonText()
	MobileButton.Text = state.enabled and "Auto Camera On" or "Auto Camera Off"
	TweenService:Create(
		MobileButton,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundColor3 = state.enabled
				and Color3.fromRGB(34, 177, 76)
				or Color3.fromRGB(180, 38, 45),
		}
	):Play()
end

local function toggleAutoCamera()
	state.enabled = not state.enabled
	updateButtonText()
	resetCameraTrackingState(true)
	if state.enabled then
		updateRemainingTime()
		state.target = findNearestPlayer()
		showNotice("Auto Camera enabled")
	else
		state.target = nil
		showNotice("Auto Camera disabled")
	end
end

local panelOpen = false
local function placePanelNearMenu()
	if MobilePanel:GetAttribute("CustomMoved") then
		clampGuiToScreen(MobilePanel)
		return
	end

	local x = MobileMenuButton.Position.X.Offset + MobileMenuButton.Size.X.Offset + 10
	local y = MobileMenuButton.Position.Y.Offset
	MobilePanel.Position = UDim2.new(0, x, 0, y)
	clampGuiToScreen(MobilePanel)
end

local function setPanelOpen(open)
	panelOpen = open
	if open then
		placePanelNearMenu()
		MobilePanel.Visible = true
		panelScale.Scale = 0.88
		MobilePanel.BackgroundTransparency = 0.18
		TweenService:Create(
			panelScale,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{Scale = 1}
		):Play()
		TweenService:Create(
			MobilePanel,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0}
		):Play()
	else
		TweenService:Create(
			panelScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Scale = 0.94}
		):Play()
		TweenService:Create(
			MobilePanel,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{BackgroundTransparency = 0.24}
		):Play()
		task.delay(0.17, function()
			if state.alive and not panelOpen then
				MobilePanel.Visible = false
				panelScale.Scale = 1
				MobilePanel.BackgroundTransparency = 0
			end
		end)
	end
end

local function selectTab(name)
	local functionsSelected = name == "Functions"
	MobileFunctionsPage.Visible = functionsSelected
	MobileSettingsPage.Visible = not functionsSelected
	TweenService:Create(
		MobileTabFunctions,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = functionsSelected
			and Color3.fromRGB(20, 20, 20)
			or Color3.fromRGB(8, 8, 8)}
	):Play()
	TweenService:Create(
		MobileTabSettings,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = not functionsSelected
			and Color3.fromRGB(20, 20, 20)
			or Color3.fromRGB(8, 8, 8)}
	):Play()
end

local function formatSeconds(value)
	local rounded = math.floor((value * 100) + 0.5) / 100
	if math.abs(rounded - math.floor(rounded)) < 0.0001 then
		return tostring(math.floor(rounded)) .. "s"
	end
	local text = string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
	return text .. "s"
end

local function applyStartTimeText()
	local normalized = tostring(StartTimeBox.Text or "")
		:gsub(",", ".")
	local numericText = normalized:match("%-?%d+%.?%d*")
	local value = numericText and tonumber(numericText) or nil
	if value == nil then
		StartTimeBox.Text = formatSeconds(state.startTime)
		showNotice("Use a value from 0 to 10")
		return
	end

	state.startTime = math.clamp(value, 0, 10)
	StartTimeBox.Text = formatSeconds(state.startTime)
	showNotice("Start time: " .. StartTimeBox.Text)
end

local function applyReactionTimeText()
	local normalized = tostring(ReactionTimeBox.Text or "")
		:gsub(",", ".")
	local numericText = normalized:match("%-?%d+%.?%d*")
	local value = numericText and tonumber(numericText) or nil
	if value == nil then
		ReactionTimeBox.Text = tostring(state.reactionTimeMs) .. "ms"
		showNotice("Use a value from 0 to 99ms")
		return
	end

	state.reactionTimeMs = math.floor(math.clamp(value, 0, 99) + 0.5)
	ReactionTimeBox.Text = tostring(state.reactionTimeMs) .. "ms"
	if state.reactionTimeMs == 0 then
		state.cameraReactionUntil = 0
		state.cameraReactionHeldDirection = nil
		state.cameraPendingTurnFlick = false
	end
	showNotice("Reaction time: " .. ReactionTimeBox.Text)
end

updateSwitchVisual(hideButtonSwitch, hideButtonKnob, state.buttonHidden, true)
updateSwitchVisual(teamCheckSwitch, teamCheckKnob, state.teamCheckEnabled, true)

bindFreeDrag(MobileButton, MobileButton, DRAG_HOLD_TIME)
bindFreeDrag(MobileMenuButton, MobileMenuButton, 0)
bindFreeDrag(mobileDragHandle, MobilePanel, 0, function()
	MobilePanel:SetAttribute("CustomMoved", true)
end)
bindPressAnimation(MobileButton, buttonScale)
bindPressAnimation(MobileMenuButton, menuScale)

connect(MobileButton.Activated, function()
	if canUseTap(MobileButton) then
		toggleAutoCamera()
	end
end)

connect(MobileMenuButton.Activated, function()
	if canUseTap(MobileMenuButton) then
		setPanelOpen(not panelOpen)
	end
end)

connect(MobileTabFunctions.Activated, function()
	selectTab("Functions")
end)

connect(MobileTabSettings.Activated, function()
	selectTab("Settings")
end)

connect(HideButtonRow.Activated, function()
	local nextHidden = not state.buttonHidden
	setMainButtonVisualHidden(nextHidden, false)
	updateSwitchVisual(hideButtonSwitch, hideButtonKnob, state.buttonHidden, false)
	showNotice(state.buttonHidden and "Button hidden" or "Button shown")
end)

connect(TeamCheckRow.Activated, function()
	state.teamCheckEnabled = not state.teamCheckEnabled
	state.target = nil
	resetCameraTrackingState(false)
	updateSwitchVisual(teamCheckSwitch, teamCheckKnob, state.teamCheckEnabled, false)
	showNotice(state.teamCheckEnabled and "Team Check enabled" or "Team Check disabled")
end)

connect(StartTimeBox.FocusLost, function()
	applyStartTimeText()
end)

connect(ReactionTimeBox.FocusLost, function()
	applyReactionTimeText()
end)

local bombAccumulator = BOMB_UPDATE_INTERVAL
local targetAccumulator = TARGET_UPDATE_INTERVAL

connect(RunService.Heartbeat, function(deltaTime)
	if not state.alive then
		return
	end

	bombAccumulator = bombAccumulator + deltaTime
	if bombAccumulator >= BOMB_UPDATE_INTERVAL then
		bombAccumulator = bombAccumulator % BOMB_UPDATE_INTERVAL
		updateRemainingTime()
	end

	targetAccumulator = targetAccumulator + deltaTime
	if targetAccumulator >= TARGET_UPDATE_INTERVAL then
		targetAccumulator = targetAccumulator % TARGET_UPDATE_INTERVAL
		local nextTarget = nil
		if state.enabled and state.bomb then
			nextTarget = findNearestPlayer()
		end
		if nextTarget ~= state.target then
			state.target = nextTarget
			resetCameraTrackingState(false)
		end
	end
end)

RunService:BindToRenderStep(
	RENDER_BIND_NAME,
	Enum.RenderPriority.Last.Value,
	function(deltaTime)
		if not state.alive then
			return
		end

		local canTrack = state.enabled
			and state.bomb ~= nil
			and state.remainingTime ~= nil
			and state.remainingTime <= (state.startTime + 0.015)
			and state.target ~= nil
		if not canTrack then
			if state.trackingActiveLastFrame then
				resetCameraTrackingState(false)
			end
			return
		end

		local localRoot = getCharacterRoot(LocalPlayer.Character)
		local targetRoot = getCharacterRoot(state.target.Character)
		if not localRoot or not targetRoot then
			resetCameraTrackingState(false)
			return
		end

		if not state.trackingActiveLastFrame then
			beginCameraTracking()
		end
		updateTrackingCamera(localRoot, targetRoot, deltaTime)
	end
)

connect(LocalPlayer.CharacterAdded, function()
	resetTimerState(nil, nil)
	state.target = nil
	resetCameraTrackingState(true)
end)

connect(Players.PlayerRemoving, function(player)
	if player == state.target then
		state.target = nil
		resetCameraTrackingState(false)
	end
end)

task.defer(function()
	if not state.alive then
		return
	end
	clampGuiToScreen(MobileButton)
	clampGuiToScreen(MobileMenuButton)
	clampGuiToScreen(MobilePanel)
end)

state.cleanup = function()
	if not state.alive then
		return
	end
	state.alive = false

	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
	end)
	for _, connection in ipairs(state.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	state.connections = {}
	if ScreenGui and ScreenGui.Parent then
		ScreenGui:Destroy()
	end
	if environment[GLOBAL_STATE_NAME] == state then
		environment[GLOBAL_STATE_NAME] = nil
	end
end

updateButtonText()
setMainButtonVisualHidden(state.buttonHidden, true)
updateRemainingTime()
state.target = findNearestPlayer()
print("[Cerber W Auto Camera] loaded")
