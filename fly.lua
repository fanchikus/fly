local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FLY_SPEED = 50
local VERTICAL_SPEED = 40
local DEBUG = true

local player = Players.LocalPlayer
local flying = false
local noclip = false
local stateConn = nil
local animConn = nil
local savedWalkSpeed = 16

-- ============ UI ============
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 120, 0, 50)
button.Position = UDim2.new(0, 20, 0.5, -25)
button.Text = "FLY: OFF"
button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Font = Enum.Font.SourceSansBold
button.TextSize = 20
button.Parent = screenGui

-- Noclip toggle button (sits right below the fly button)
local noclipButton = Instance.new("TextButton")
noclipButton.Size = UDim2.new(0, 120, 0, 36)
noclipButton.Position = UDim2.new(0, 20, 0.5, 30)
noclipButton.Text = "NOCLIP: OFF"
noclipButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
noclipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
noclipButton.Font = Enum.Font.SourceSansBold
noclipButton.TextSize = 16
noclipButton.Parent = screenGui

-- Debug toggle button (sits right below the noclip button)
local debugButton = Instance.new("TextButton")
debugButton.Size = UDim2.new(0, 120, 0, 36)
debugButton.Position = UDim2.new(0, 20, 0.5, 70)
debugButton.Text = "DEBUG: ON"
debugButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
debugButton.TextColor3 = Color3.fromRGB(255, 255, 255)
debugButton.Font = Enum.Font.SourceSansBold
debugButton.TextSize = 16
debugButton.Parent = screenGui

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(0, 320, 0, 160)
debugLabel.Position = UDim2.new(0, 20, 0.5, 115)
debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
debugLabel.BackgroundTransparency = 0.4
debugLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
debugLabel.Font = Enum.Font.Code
debugLabel.TextSize = 16
debugLabel.TextXAlignment = Enum.TextXAlignment.Left
debugLabel.TextYAlignment = Enum.TextYAlignment.Top
debugLabel.Text = "Debug: waiting..."
debugLabel.Visible = DEBUG
debugLabel.Parent = screenGui

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 200, 0, 20)
speedLabel.Position = UDim2.new(0, 20, 0.5, 285)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.Font = Enum.Font.SourceSans
speedLabel.TextSize = 14
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Text = "Fly speed (press Enter):"
speedLabel.Parent = screenGui

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 120, 0, 36)
speedBox.Position = UDim2.new(0, 20, 0.5, 307)
speedBox.PlaceholderText = "Speed: " .. tostring(FLY_SPEED)
speedBox.Text = ""
speedBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.Font = Enum.Font.SourceSansBold
speedBox.TextSize = 18
speedBox.ClearTextOnFocus = false
speedBox.Parent = screenGui

speedBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		local num = tonumber(speedBox.Text)
		if num and num > 0 then
			FLY_SPEED = num
			speedBox.PlaceholderText = "Speed: " .. tostring(FLY_SPEED)
			if DEBUG then print("[Fly] Speed set to", FLY_SPEED) end
		else
			if DEBUG then print("[Fly] Invalid speed input:", speedBox.Text) end
		end
	end
	speedBox.Text = ""
end)

-- ============ Noclip toggle ============
-- Note: collision is driven continuously in the Heartbeat loop below so it
-- survives new limbs/accessories loading in and character respawns; this
-- function just flips the desired state and updates the button.
local function setNoclip(state)
	noclip = state
	noclipButton.Text = noclip and "NOCLIP: ON" or "NOCLIP: OFF"
	noclipButton.BackgroundColor3 = noclip and Color3.fromRGB(40, 160, 70) or Color3.fromRGB(60, 60, 60)

	-- Restore collision immediately when turning noclip off, unless flying
	-- is also active (flying manages collision itself).
	if not noclip and not flying and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end

	if DEBUG then print("[Fly] Noclip", noclip and "ON" or "OFF") end
end

noclipButton.MouseButton1Click:Connect(function()
	setNoclip(not noclip)
end)

-- ============ Debug toggle ============
local function setDebug(state)
	DEBUG = state
	debugLabel.Visible = DEBUG
	debugButton.Text = DEBUG and "DEBUG: ON" or "DEBUG: OFF"
	debugButton.BackgroundColor3 = DEBUG and Color3.fromRGB(40, 160, 70) or Color3.fromRGB(60, 60, 60)
end

debugButton.MouseButton1Click:Connect(function()
	setDebug(not DEBUG)
end)

-- initialize button state to match starting DEBUG value
setDebug(DEBUG)

-- ============ Helpers ============
local function setCollision(char, enabled)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = enabled
		end
	end
end

local function setFlying(state)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	local bodyVel = root:FindFirstChild("FlyForce")
	local bodyGyro = root:FindFirstChild("FlyGyro")
	local animator = hum:FindFirstChildOfClass("Animator")

	if state then
		if not bodyVel then
			bodyVel = Instance.new("BodyVelocity")
			bodyVel.Name = "FlyForce"
			bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bodyVel.Velocity = Vector3.new(0, 0, 0)
			bodyVel.P = 1250
			bodyVel.Parent = root
		end
		if not bodyGyro then
			bodyGyro = Instance.new("BodyGyro")
			bodyGyro.Name = "FlyGyro"
			bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
			bodyGyro.P = 3000
			bodyGyro.D = 100
			bodyGyro.CFrame = root.CFrame
			bodyGyro.Parent = root
		end

		savedWalkSpeed = hum.WalkSpeed
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		setCollision(char, false)

		hum:ChangeState(Enum.HumanoidStateType.Swimming)
		if stateConn then stateConn:Disconnect() end
		stateConn = hum.StateChanged:Connect(function(_, new)
			if flying and new ~= Enum.HumanoidStateType.Swimming then
				hum:ChangeState(Enum.HumanoidStateType.Swimming)
			end
		end)

		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
			if animConn then animConn:Disconnect() end
			animConn = animator.AnimationPlayed:Connect(function(track)
				if flying then
					track:Stop(0)
				end
			end)
		end

		flying = true
		button.Text = "FLY: ON"
		button.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		if DEBUG then print("[Fly] Flying ON") end
	else
		if bodyVel then bodyVel:Destroy() end
		if bodyGyro then bodyGyro:Destroy() end
		if stateConn then
			stateConn:Disconnect()
			stateConn = nil
		end
		if animConn then
			animConn:Disconnect()
			animConn = nil
		end
		hum.WalkSpeed = savedWalkSpeed
		hum.AutoRotate = true
		setCollision(char, true)
		hum:ChangeState(Enum.HumanoidStateType.Freefall)

		flying = false
		button.Text = "FLY: OFF"
		button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		if DEBUG then print("[Fly] Flying OFF") end
	end
end

button.MouseButton1Click:Connect(function()
	setFlying(not flying)
end)

player.CharacterAdded:Connect(function(newChar)
	flying = false
	setNoclip(false)
	if stateConn then
		stateConn:Disconnect()
		stateConn = nil
	end
	if animConn then
		animConn:Disconnect()
		animConn = nil
	end
	for _, part in ipairs(newChar:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
	if DEBUG then print("[Fly] Character respawned, flying/noclip reset") end
end)

-- ============ Input ============
local keysDown = {
	[Enum.KeyCode.W] = false,
	[Enum.KeyCode.S] = false,
	[Enum.KeyCode.A] = false,
	[Enum.KeyCode.D] = false,
	[Enum.KeyCode.Q] = false,
	[Enum.KeyCode.E] = false,
}

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if keysDown[input.KeyCode] ~= nil then
		keysDown[input.KeyCode] = true
	end
	if input.KeyCode == Enum.KeyCode.F9 then
		setDebug(not DEBUG)
	elseif input.KeyCode == Enum.KeyCode.F10 then
		setNoclip(not noclip)
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if keysDown[input.KeyCode] ~= nil then
		keysDown[input.KeyCode] = false
	end
end)

local function activeKeysString()
	local active = {}
	for key, down in pairs(keysDown) do
		if down then table.insert(active, key.Name) end
	end
	return #active > 0 and table.concat(active, ",") or "none"
end

-- ============ Main loop ============
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local bodyVel = root and root:FindFirstChild("FlyForce")
	local bodyGyro = root and root:FindFirstChild("FlyGyro")

	-- Keep noclip enforced every frame so newly-added parts (accessories,
	-- tools, etc.) don't silently re-enable collision. Flying already
	-- disables collision on its own, so skip redundant work while flying.
	if noclip and not flying and char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				part.CanCollide = false
			end
		end
	end

	if not flying or not root or not bodyVel or not bodyGyro then
		if DEBUG and debugLabel.Visible then
			debugLabel.Text = string.format("Flying: %s\nNoclip: %s\nKeys: %s", tostring(flying), tostring(noclip), activeKeysString())
		end
		return
	end

	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector

	local dir = Vector3.new()
	if keysDown[Enum.KeyCode.W] then dir += look end
	if keysDown[Enum.KeyCode.S] then dir -= look end
	if keysDown[Enum.KeyCode.D] then dir += right end
	if keysDown[Enum.KeyCode.A] then dir -= right end

	if dir.Magnitude > 0 then
		dir = dir.Unit
	end

	local velocity = dir * FLY_SPEED

	local vertical = 0
	if keysDown[Enum.KeyCode.E] then vertical += VERTICAL_SPEED end
	if keysDown[Enum.KeyCode.Q] then vertical -= VERTICAL_SPEED end
	velocity = Vector3.new(velocity.X, velocity.Y + vertical, velocity.Z)

	bodyVel.Velocity = velocity
	bodyGyro.CFrame = CFrame.new(root.Position, root.Position + look)

	if DEBUG and debugLabel.Visible then
		debugLabel.Text = string.format(
			"Flying: true\nPos: %.1f, %.1f, %.1f\nVelocity: %.1f, %.1f, %.1f\nSpeed: %.1f studs/s\nKeys: %s",
			root.Position.X, root.Position.Y, root.Position.Z,
			velocity.X, velocity.Y, velocity.Z,
			velocity.Magnitude,
			activeKeysString()
		)
	end
end)
