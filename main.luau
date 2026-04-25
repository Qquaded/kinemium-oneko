local Extension = {}

local KinemiumRaylib = game:GetService("KinemiumRaylib")
local UserInputService = game:GetService("UserInputService")
local KinemiumIconLoader = game:GetService("KinemiumIconLoader")

local renderer = KinemiumRaylib.GetRenderer()
local lib = KinemiumRaylib.GetLib()
local const = KinemiumRaylib.GetConst()

local SPRITE_SIZE = 32
local MOVE_SPEED = 220
local STOP_DISTANCE = 10
local CLAW_DISTANCE = 28
local WALK_FRAME_TIME = 0.12
local IDLE_FRAME_TIME = 0.35
local DRAW_PRIORITY = 1000

local WALK_TEXTURES = {
	up = { "up1", "up2" },
	down = { "down1", "down2" },
	left = { "left1", "left2" },
	right = { "right1", "right2" },
	upleft = { "upleft1", "upleft2" },
	upright = { "upright1", "upright2" },
	downleft = { "downleft1", "downleft2" },
	downright = { "downright1", "downright2" },
}

local IDLE_STATES = {
	{ start = 0, stop = 2, frames = { "awake" }, frameTime = IDLE_FRAME_TIME },
	{ start = 2, stop = 5, frames = { "scratch1", "scratch2" }, frameTime = IDLE_FRAME_TIME },
	{ start = 5, stop = 8, frames = { "wash1", "wash2" }, frameTime = IDLE_FRAME_TIME },
	{ start = 8, stop = 9, frames = { "yawn1", "yawn2" }, frameTime = IDLE_FRAME_TIME },
	{ start = 9, stop = math.huge, frames = { "sleep1", "sleep2" }, frameTime = 0.55 },
}

local state = {
	textures = {},
	renderId = nil,
	position = nil,
	direction = "down",
	frameIndex = 1,
	animationTimer = 0,
	idleTime = 0,
	currentSprite = "awake",
}

local function clearTextures()
	for _, texture in pairs(state.textures) do
		if texture and texture.id ~= 0 then
			lib.UnloadTexture(texture)
		end
	end

	table.clear(state.textures)
end

local function loadTexture(name)
	local contents = GetFileContents("assets/" .. name .. ".png")
	local texture = KinemiumIconLoader.ToTextureBuffer(contents)
	state.textures[name] = texture.texture
	return texture
end

local function loadTextures()
	clearTextures()

	local seen = {}
	local function ensureTexture(name)
		if not seen[name] then
			seen[name] = true
			loadTexture(name)
		end
	end

	for _, frames in pairs(WALK_TEXTURES) do
		for _, name in ipairs(frames) do
			ensureTexture(name)
		end
	end

	for _, idleState in ipairs(IDLE_STATES) do
		for _, name in ipairs(idleState.frames) do
			ensureTexture(name)
		end
	end

	for _, direction in ipairs({ "up", "down", "left", "right" }) do
		for i = 1, 2 do
			ensureTexture(direction .. "claw" .. i)
		end
	end
end

local function getMouseTarget()
	local mousePosition = UserInputService:GetMousePosition()
	return mousePosition - Vector2.new(SPRITE_SIZE / 2, SPRITE_SIZE / 2)
end

local function clampToWindow(position)
	local windowSize = UserInputService:GetWindowDimensions()
	local maxX = math.max(0, windowSize.X - SPRITE_SIZE)
	local maxY = math.max(0, windowSize.Y - SPRITE_SIZE)

	return Vector2.new(math.clamp(position.X, 0, maxX), math.clamp(position.Y, 0, maxY))
end

local function pickDirection(offset)
	local absX = math.abs(offset.X)
	local absY = math.abs(offset.Y)

	if absX > absY * 1.5 then
		return if offset.X >= 0 then "right" else "left"
	elseif absY > absX * 1.5 then
		return if offset.Y >= 0 then "down" else "up"
	elseif offset.X >= 0 then
		return if offset.Y >= 0 then "downright" else "upright"
	else
		return if offset.Y >= 0 then "downleft" else "upleft"
	end
end

local function advanceFrame(dt, frameTime)
	state.animationTimer += dt
	if state.animationTimer < frameTime then
		return
	end

	state.animationTimer -= frameTime
	state.frameIndex = if state.frameIndex == 1 then 2 else 1
end

local function updateIdleSprite(dt)
	state.idleTime += dt

	local selected = IDLE_STATES[#IDLE_STATES]
	for _, idleState in ipairs(IDLE_STATES) do
		if state.idleTime >= idleState.start and state.idleTime < idleState.stop then
			selected = idleState
			break
		end
	end

	local frames = selected.frames
	if #frames == 1 then
		state.frameIndex = 1
		state.animationTimer = 0
		state.currentSprite = frames[1]
		return
	end

	advanceFrame(dt, selected.frameTime)
	state.currentSprite = frames[state.frameIndex]
end

local function updateWalkingSprite(dt, distance)
	state.idleTime = 0
	advanceFrame(dt, WALK_FRAME_TIME)

	local clawSprite = state.direction .. "claw" .. state.frameIndex
	if distance <= CLAW_DISTANCE and state.textures[clawSprite] then
		state.currentSprite = clawSprite
		return
	end

	local frames = WALK_TEXTURES[state.direction] or WALK_TEXTURES.down
	state.currentSprite = frames[state.frameIndex]
end

local function updateCat(dt)
	if not state.position then
		return
	end

	local target = getMouseTarget()
	local offset = target - state.position
	local distance = offset:Magnitude()

	if distance > STOP_DISTANCE then
		state.direction = pickDirection(offset)
		local step = math.min(distance, MOVE_SPEED * dt)
		state.position = clampToWindow(state.position + offset:Unit() * step)
		updateWalkingSprite(dt, distance)
	else
		state.position = clampToWindow(target)
		updateIdleSprite(dt)
	end
end

local function drawCat()
	local texture = state.textures[state.currentSprite]
	if not texture then
		return
	end

	lib.DrawTexture(texture, math.floor(state.position.X + 0.5), math.floor(state.position.Y + 0.5), const.WHITE)
end

function Extension.activate()
	if state.renderId then
		Extension.deactivate()
	end

	loadTextures()

	state.direction = "down"
	state.frameIndex = 1
	state.animationTimer = 0
	state.idleTime = 0
	state.currentSprite = "awake"
	state.position = clampToWindow(getMouseTarget() + Vector2.new(-64, 32))

	state.renderId = renderer.Pool.new("2d", function()
		local dt = lib.GetFrameTime()
		updateCat(dt)
		drawCat()
	end, DRAW_PRIORITY)

	print("Oneko plugin loaded")
end

function Extension.deactivate()
	if state.renderId then
		renderer.Pool.Destroy(state.renderId)
		state.renderId = nil
	end

	clearTextures()
	state.position = nil
	state.currentSprite = "awake"
	state.direction = "down"
	state.frameIndex = 1
	state.animationTimer = 0
	state.idleTime = 0

	print("Oneko plugin unloaded")
end

return Extension
