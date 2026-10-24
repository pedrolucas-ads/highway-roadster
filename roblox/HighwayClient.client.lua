-- HIGHWAY ROADSTER · Cliente (o jogo inteiro)
-- Onde colar: StarterPlayer > StarterPlayerScripts > LocalScript (nome: HighwayClient)
-- Cada jogador corre na própria pista (tudo é criado localmente), o ranking é global via servidor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local K = 3.2 -- studs por metro (a lógica roda em metros, igual à versão web)
local ORIGIN = Vector3.new(0, 400, 0) -- pista flutuando longe do spawn
local LANES = { -5.4, -1.8, 1.8, 5.4 }
local COMBO_TIME = 3.6
local SEG, NSEG = 60, 12
local HEAT_PER_STAR, MAX_STARS = 3, 5
-- celular/tablet: menos peças no cenário, névoa mais densa e controles de toque
local MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled

-- Sons: cole aqui os IDs do Creator Store (ex.: "rbxassetid://123456"). Vazio = sem som.
local SOUND_IDS = {
	engine = "rbxassetid://74570409322232", -- Electric Car Engine (loop)
	siren = "rbxassetid://1081285613", -- American Police Siren Loop
	jump = "rbxassetid://128991711954402", -- swoosh 2
	trick = "rbxassetid://126029734510141", -- coin ding
	land = "rbxassetid://90390915247200", -- Impact Metal Hit
	near = "rbxassetid://138890894929151", -- Whoosh2
	smash = "rbxassetid://8125594257", -- Car Crash Sound
	crash = "rbxassetid://138307089384990", -- Car crash sound effect
	beep = "rbxassetid://117751546358455", -- Countdown beep
}

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local rng = Random.new()
local function rand(a, b)
	return a + rng:NextNumber() * (b - a)
end
local function clamp(v, a, b)
	return math.clamp(v, a, b)
end
local function smooth(t)
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function ease(t)
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - ((-2 * t + 2) ^ 2) / 2
end
local function W(x, y, z)
	return ORIGIN + Vector3.new(x * K, y * K, z * K)
end
local function fmt(n)
	local s = tostring(math.floor(n + 0.5))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if r:sub(1, 1) == "," then
		r = r:sub(2)
	end
	return r
end
local function fmtT(s)
	return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local world = Instance.new("Folder")
world.Name = "HighwayWorld_Local"
world.Parent = workspace

-- cria uma peça em coordenadas locais (metros); cf opcional de rotação
local function piece(parent, cls, size, pos, color, material, rot)
	local p = Instance.new(cls)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size * K
	p.CFrame = CFrame.new(pos * K) * (rot or CFrame.identity)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end
local function cyl(parent, length, diameter, pos, color, material, rot)
	-- cilindro do Roblox tem o eixo em X
	local p = piece(parent, "Part", Vector3.new(length, diameter, diameter), pos, color, material, rot)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local VERT = CFrame.Angles(0, 0, math.pi / 2) -- deixa um cilindro em pé

local function newModel(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or world
	return m
end
local function finish(m)
	m.WorldPivot = CFrame.new()
	return m
end

---------------------------------------------------------------------
-- LUZ / CÉU SYNTHWAVE (só no cliente)
---------------------------------------------------------------------
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("Atmosphere") or c:IsA("PostEffect") then
		c:Destroy()
	end
end
Lighting.ClockTime = 17.7
Lighting.Brightness = 2.2
Lighting.Ambient = rgb(120, 80, 135)
Lighting.OutdoorAmbient = rgb(205, 150, 200)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8
local atmo = Instance.new("Atmosphere")
atmo.Density = MOBILE and 0.46 or 0.36
atmo.Offset = 0.15
atmo.Color = rgb(244, 172, 204)
atmo.Decay = rgb(178, 98, 168)
atmo.Glare = 0.6
atmo.Haze = 2.2
atmo.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.TintColor = rgb(255, 228, 244)
cc.Saturation = 0.15
cc.Contrast = 0.05
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.8
bloom.Size = 30
bloom.Threshold = 1.6
bloom.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

local sun = piece(world, "Part", Vector3.new(90, 90, 90), Vector3.zero, rgb(255, 226, 196), Enum.Material.Neon)
sun.Shape = Enum.PartType.Ball
local SUN_DIR = Vector3.new(-0.3, 0.05, -1).Unit

---------------------------------------------------------------------
-- PISTA (segmentos reciclados)
---------------------------------------------------------------------
local C_ROAD = rgb(78, 72, 89)
local C_LINE = rgb(244, 238, 248)
local C_STEEL = rgb(74, 59, 82)
local PALM = rgb(38, 22, 48)
local B_COLORS = { rgb(217, 180, 216), rgb(196, 163, 217), rgb(240, 194, 201), rgb(183, 156, 204), rgb(230, 207, 224), rgb(169, 143, 192) }

local function buildPalm(parent, x, z)
	local h = rand(8, 14)
	local segs = 6
	local lean = rand(0.25, 0.7) * (rng:NextNumber() < 0.5 and -1 or 1)
	local px, py = 0, 0
	local yaw = rand(0, math.pi * 2)
	local base = CFrame.new(x, -1.6, z) * CFrame.Angles(0, yaw, 0)
	for i = 0, segs - 1 do
		local sh = h / segs
		local ang = lean * (i / segs) * 0.7
		local mid = base * CFrame.new(px + math.sin(ang) * sh / 2, py + math.cos(ang) * sh / 2, 0) * CFrame.Angles(0, 0, -ang)
		cyl(parent, sh * 1.06, 0.5 - i * 0.03, mid.Position, PALM, nil, (mid - mid.Position) * VERT)
		px += math.sin(ang) * sh
		py += math.cos(ang) * sh
	end
	local top = base * CFrame.new(px, py, 0)
	local leaves = MOBILE and 6 or 9
	for i = 0, leaves - 1 do
		local a = i / leaves * math.pi * 2 + rand(-0.2, 0.2)
		local leaf = top * CFrame.Angles(0, a, 0) * CFrame.Angles(-rand(0.3, 0.6), 0, 0) * CFrame.new(0, 0, -2.1)
		piece(parent, "Part", Vector3.new(0.9, 0.08, 4.4), leaf.Position, PALM, nil, leaf - leaf.Position)
	end
end

local segments = {}
local function buildSegment(i)
	local m = newModel("Seg" .. i)
	piece(m, "Part", Vector3.new(16, 0.4, 60), Vector3.new(0, -0.2, 0), C_ROAD, Enum.Material.Asphalt)
	piece(m, "Part", Vector3.new(16.6, 2, 60), Vector3.new(0, -1.4, 0), rgb(109, 90, 120))
	for _, sx in ipairs({ -7.25, 7.25 }) do
		piece(m, "Part", Vector3.new(0.22, 0.04, 60), Vector3.new(sx, 0.02, 0), C_LINE)
	end
	for _, lx in ipairs({ -3.6, 0, 3.6 }) do
		for k = 0, 4 do
			piece(m, "Part", Vector3.new(0.18, 0.04, 5), Vector3.new(lx, 0.02, -30 + 2.5 + k * 12), C_LINE)
		end
	end
	piece(m, "Part", Vector3.new(0.55, 1.05, 60), Vector3.new(-8.15, 0.52, 0), rgb(194, 175, 200), Enum.Material.Concrete)
	local rail = rgb(210, 200, 220)
	piece(m, "Part", Vector3.new(0.1, 0.32, 60), Vector3.new(8.05, 0.85, 0), rail, Enum.Material.Metal)
	piece(m, "Part", Vector3.new(0.1, 0.12, 60), Vector3.new(8.05, 1.32, 0), rail, Enum.Material.Metal)
	for k = 0, 9 do
		piece(m, "Part", Vector3.new(0.14, 1.4, 0.14), Vector3.new(8.05, 0.7, -30 + 3 + k * 6), rail, Enum.Material.Metal)
	end
	piece(m, "Part", Vector3.new(40, 0.3, 60), Vector3.new(-28.5, -1.6, 0), rgb(220, 170, 176), Enum.Material.Sand)
	piece(m, "Part", Vector3.new(300, 0.3, 60), Vector3.new(158, -0.7, 0), rgb(128, 100, 128))
	-- poste
	cyl(m, 10, 0.3, Vector3.new(8.7, 5, 0), C_STEEL, nil, VERT)
	piece(m, "Part", Vector3.new(2.8, 0.12, 0.12), Vector3.new(7.35, 9.9, 0), C_STEEL)
	piece(m, "Part", Vector3.new(1, 0.16, 0.42), Vector3.new(6.1, 9.8, 0), rgb(255, 236, 205), Enum.Material.Neon)
	-- palmeiras e prédios
	buildPalm(m, rand(-34, -11), rand(-28, -2))
	if not MOBILE then
		buildPalm(m, rand(-34, -11), rand(2, 28))
	end
	local nb = rng:NextNumber() < 0.5 and 2 or 1
	for b = 1, nb do
		local w, h, d = rand(14, 34), rand(18, 95), rand(14, 26)
		piece(m, "Part", Vector3.new(w, h, d), Vector3.new(rand(32, 190), h / 2 - 0.7, (b == 1 and -15 or 15) + rand(-6, 6)), B_COLORS[rng:NextInteger(1, #B_COLORS)])
	end
	finish(m)
	return { model = m, z = 0 }
end

local ocean = piece(world, "Part", Vector3.new(640, 1, 640), Vector3.zero, rgb(176, 120, 182), Enum.Material.SmoothPlastic)
ocean.Reflectance = MOBILE and 0 or 0.25
ocean.Transparency = 0

---------------------------------------------------------------------
-- RAMPA DE LARGADA (treliça + trilhos de luz)
---------------------------------------------------------------------
local RAMP = { z0 = 16, zTop = -6, z1 = -72, h = 7, halfW = 4.3 }
local function rampH(z)
	if z > RAMP.z0 or z < RAMP.z1 then
		return 0
	end
	if z > RAMP.zTop then
		return RAMP.h
	end
	return RAMP.h * (1 - smooth((RAMP.zTop - z) / (RAMP.zTop - RAMP.z1)))
end
local function groundAt(x, z)
	if math.abs(x) <= RAMP.halfW then
		return rampH(z)
	end
	return 0
end

local function beam(parent, a, b, t, color, material)
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	piece(parent, "Part", Vector3.new(t, t, len), cf.Position, color, material, cf - cf.Position)
end

do
	local m = newModel("Ramp")
	local N = 32
	local len = RAMP.z0 - RAMP.z1
	for i = 0, N - 1 do
		local za = RAMP.z0 - i / N * len
		local zb = RAMP.z0 - (i + 1) / N * len
		local a = Vector3.new(0, rampH(za) - 0.15, za)
		local b = Vector3.new(0, rampH(zb) - 0.15, zb)
		local cf = CFrame.lookAt((a + b) / 2, b)
		piece(m, "Part", Vector3.new(RAMP.halfW * 2, 0.3, (b - a).Magnitude + 0.05), cf.Position, rgb(95, 86, 108), Enum.Material.Concrete, cf - cf.Position)
		for _, sx in ipairs({ -1, 1 }) do
			local ga = Vector3.new(sx * (RAMP.halfW + 0.1), rampH(za) + 0.35, za)
			local gb = Vector3.new(sx * (RAMP.halfW + 0.1), rampH(zb) + 0.35, zb)
			beam(m, ga, gb, 0.18, rgb(255, 246, 255), Enum.Material.Neon)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local prev, prevZ
		for z = RAMP.z0, RAMP.zTop - 34, -8 do
			local top = Vector3.new(sx * (RAMP.halfW + 0.4), rampH(z) + 4.4, z)
			beam(m, Vector3.new(sx * (RAMP.halfW + 0.4), -1, z), top, 0.35, C_STEEL)
			if prev then
				beam(m, prev, top, 0.3, C_STEEL)
				beam(m, Vector3.new(sx * (RAMP.halfW + 0.4), rampH(prevZ), prevZ), top, 0.18, C_STEEL)
			end
			prev, prevZ = top, z
		end
	end
	for z = RAMP.z0, RAMP.zTop - 34, -8 do
		local h = rampH(z) + 4.4
		beam(m, Vector3.new(-RAMP.halfW - 0.4, h, z), Vector3.new(RAMP.halfW + 0.4, h, z), 0.32, C_STEEL)
		beam(m, Vector3.new(-RAMP.halfW - 0.4, h - 1.1, z), Vector3.new(0, h, z), 0.14, C_STEEL)
		beam(m, Vector3.new(RAMP.halfW + 0.4, h - 1.1, z), Vector3.new(0, h, z), 0.14, C_STEEL)
	end
	piece(m, "Part", Vector3.new(RAMP.halfW * 2 + 1, 0.12, 0.25), Vector3.new(0, RAMP.h + 4.1, RAMP.zTop), rgb(255, 246, 255), Enum.Material.Neon)
	finish(m)
	m:PivotTo(CFrame.new(ORIGIN))
end

---------------------------------------------------------------------
-- CARRO DO JOGADOR (frente = -Z)
---------------------------------------------------------------------
local carModel, flames
do
	local m = newModel("Roadster")
	local steel = rgb(214, 213, 224)
	local glass = rgb(21, 18, 28)
	piece(m, "Part", Vector3.new(2.02, 0.32, 5.5), Vector3.new(0, 0.48, 0), rgb(35, 32, 41))
	piece(m, "Part", Vector3.new(2, 0.65, 5.7), Vector3.new(0, 0.9, -0.05), steel, Enum.Material.Metal)
	-- capô: WedgePart sobe em direção ao +Z (traseira)
	piece(m, "WedgePart", Vector3.new(2, 0.655, 2.87), Vector3.new(0, 1.5525, -1.285), steel, Enum.Material.Metal)
	piece(m, "Part", Vector3.new(2, 0.115, 2.65), Vector3.new(0, 1.2825, 1.475), steel, Enum.Material.Metal)
	piece(m, "WedgePart", Vector3.new(2, 0.54, 2.65), Vector3.new(0, 1.61, 1.475), steel, Enum.Material.Metal, CFrame.Angles(0, math.pi, 0))
	piece(m, "WedgePart", Vector3.new(2.04, 0.331, 1.45), Vector3.new(0, 1.735, -0.575), glass, Enum.Material.Glass)
	piece(m, "WedgePart", Vector3.new(2.04, 0.316, 1.55), Vector3.new(0, 1.742, 0.925), glass, Enum.Material.Glass, CFrame.Angles(0, math.pi, 0))
	piece(m, "Part", Vector3.new(1.95, 0.06, 0.06), Vector3.new(0, 1.0, -2.76), rgb(255, 255, 255), Enum.Material.Neon)
	local tail = piece(m, "Part", Vector3.new(1.98, 0.07, 0.06), Vector3.new(0, 1.28, 2.83), rgb(255, 42, 80), Enum.Material.Neon)
	local tl = Instance.new("PointLight")
	tl.Color = rgb(255, 40, 80)
	tl.Range = 10
	tl.Brightness = 2
	tl.Parent = tail
	for _, x in ipairs({ -0.94, 0.94 }) do
		for _, z in ipairs({ -1.85, 1.9 }) do
			cyl(m, 0.34, 0.92, Vector3.new(x, 0.46, z), rgb(20, 18, 24))
			cyl(m, 0.36, 0.54, Vector3.new(x, 0.46, z), rgb(140, 138, 150), Enum.Material.Metal)
		end
	end
	flames = {}
	for _, x in ipairs({ -0.55, 0.55 }) do
		local f = piece(m, "Part", Vector3.new(0.35, 0.35, 0.8), Vector3.new(x, 0.62, 3.2), rgb(130, 235, 255), Enum.Material.Neon)
		f.Transparency = 1
		table.insert(flames, f)
	end
	finish(m)
	carModel = m
end
local shadow = piece(world, "Part", Vector3.new(2.6, 0.02, 6), Vector3.zero, rgb(0, 0, 0))
shadow.Transparency = 0.55

---------------------------------------------------------------------
-- TRÁFEGO E POLÍCIA
---------------------------------------------------------------------
local CAR_COLORS = { rgb(236, 232, 242), rgb(42, 42, 52), rgb(194, 59, 77), rgb(60, 92, 168), rgb(156, 162, 173), rgb(232, 216, 198), rgb(74, 122, 106), rgb(29, 29, 34) }
local RED_LIGHT = rgb(255, 42, 64)
local function wheelsOn(m, hw, zs)
	for _, x in ipairs({ -hw, hw }) do
		for _, z in ipairs(zs) do
			cyl(m, 0.28, 0.72, Vector3.new(x, 0.36, z), rgb(17, 17, 17))
		end
	end
end
local function makeCar(kind)
	local m = newModel("Car")
	local w, l, h
	local cabin = rgb(36, 31, 44)
	if kind == "bus" then
		w, l, h = 2.6, 11, 3.1
		piece(m, "Part", Vector3.new(2.6, 2.6, 11), Vector3.new(0, 1.75, 0), rgb(242, 193, 46))
		piece(m, "Part", Vector3.new(2.64, 0.8, 9.6), Vector3.new(0, 2.3, -0.3), cabin, Enum.Material.Glass)
		piece(m, "Part", Vector3.new(2.64, 0.14, 11.02), Vector3.new(0, 1.25, 0), rgb(27, 27, 27))
		piece(m, "Part", Vector3.new(0.5, 0.2, 0.05), Vector3.new(-1, 1.1, 5.52), RED_LIGHT, Enum.Material.Neon)
		piece(m, "Part", Vector3.new(0.5, 0.2, 0.05), Vector3.new(1, 1.1, 5.52), RED_LIGHT, Enum.Material.Neon)
		wheelsOn(m, 1.15, { -3.6, 3.6 })
	elseif kind == "truck" then
		w, l, h = 2.5, 8.5, 3.4
		piece(m, "Part", Vector3.new(2.5, 3.0, 6.2), Vector3.new(0, 2.0, 1.1), rgb(239, 234, 242))
		piece(m, "Part", Vector3.new(2.3, 2.0, 2.2), Vector3.new(0, 1.45, -3.1), CAR_COLORS[rng:NextInteger(1, 4)])
		piece(m, "Part", Vector3.new(2.32, 0.7, 0.05), Vector3.new(0, 1.9, -4.2), cabin, Enum.Material.Glass)
		piece(m, "Part", Vector3.new(2.4, 0.16, 0.05), Vector3.new(0, 0.8, 4.22), RED_LIGHT, Enum.Material.Neon)
		wheelsOn(m, 1.1, { -3, 2.6 })
	elseif kind == "suv" then
		w, l, h = 2.05, 4.8, 1.85
		piece(m, "Part", Vector3.new(2.05, 0.95, 4.8), Vector3.new(0, 0.85, 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
		piece(m, "Part", Vector3.new(1.9, 0.72, 3.0), Vector3.new(0, 1.66, 0.3), cabin, Enum.Material.Glass)
		piece(m, "Part", Vector3.new(1.9, 0.1, 0.05), Vector3.new(0, 1.05, 2.42), RED_LIGHT, Enum.Material.Neon)
		wheelsOn(m, 0.92, { -1.55, 1.55 })
	elseif kind == "cop" then
		w, l, h = 1.95, 4.7, 1.6
		piece(m, "Part", Vector3.new(1.95, 0.64, 4.7), Vector3.new(0, 0.66, 0), rgb(21, 21, 27))
		piece(m, "Part", Vector3.new(1.97, 0.3, 2.1), Vector3.new(0, 0.8, 0.1), rgb(244, 244, 248))
		piece(m, "Part", Vector3.new(1.66, 0.54, 2.3), Vector3.new(0, 1.24, 0.2), cabin, Enum.Material.Glass)
		piece(m, "Part", Vector3.new(1.75, 0.1, 0.05), Vector3.new(0, 0.82, 2.37), RED_LIGHT, Enum.Material.Neon)
		local red = piece(m, "Part", Vector3.new(0.62, 0.16, 0.36), Vector3.new(-0.36, 1.58, 0.2), rgb(255, 16, 48), Enum.Material.Neon)
		local blue = piece(m, "Part", Vector3.new(0.62, 0.16, 0.36), Vector3.new(0.36, 1.58, 0.2), rgb(16, 80, 255), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 4
		light.Parent = red
		wheelsOn(m, 0.9, { -1.5, 1.5 })
		finish(m)
		return m, w, l, h, { red = red, blue = blue, light = light }
	else
		w, l, h = 1.9, 4.5, 1.45
		piece(m, "Part", Vector3.new(1.9, 0.62, 4.5), Vector3.new(0, 0.65, 0), CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)])
		piece(m, "Part", Vector3.new(1.62, 0.52, 2.2), Vector3.new(0, 1.2, 0.25), cabin, Enum.Material.Glass)
		piece(m, "Part", Vector3.new(1.7, 0.1, 0.05), Vector3.new(0, 0.8, 2.27), RED_LIGHT, Enum.Material.Neon)
		wheelsOn(m, 0.88, { -1.45, 1.45 })
	end
	finish(m)
	return m, w, l, h
end

---------------------------------------------------------------------
-- PARTÍCULAS (pool de bolinhas)
---------------------------------------------------------------------
local particles = {}
local pIdx = 1
local HIDDEN = CFrame.new(ORIGIN + Vector3.new(0, -150, 0)) -- longe da câmera, acima do limite de queda do mapa
for i = 1, MOBILE and 60 or 110 do
	local p = piece(world, "Part", Vector3.new(1, 1, 1), Vector3.zero, rgb(255, 255, 255))
	p.CFrame = HIDDEN
	p.Shape = Enum.PartType.Ball
	p.Transparency = 1
	particles[i] = { p = p, life = 0, max = 1, v = Vector3.zero, pos = Vector3.zero, size = 1, grow = 1, op = 1 }
end
local function emit(pos, vel, life, size, grow, color, neon, op)
	local q = particles[pIdx]
	pIdx = pIdx % #particles + 1
	q.pos, q.v, q.life, q.max, q.size, q.grow, q.op = pos, vel, life, life, size, grow, op or 0.8
	q.p.Color = color
	q.p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
end
local function updateParticles(dt)
	for _, q in ipairs(particles) do
		if q.life > 0 then
			q.life -= dt
			if q.life <= 0 then
				q.p.Transparency = 1
				q.p.CFrame = HIDDEN
			else
				local k = 1 - q.life / q.max
				q.pos += q.v * dt
				q.v *= (1 - math.min(1, dt * 1.6))
				local s = q.size * (1 + k * q.grow) * K
				q.p.Size = Vector3.new(s, s, s)
				q.p.CFrame = CFrame.new(W(q.pos.X, q.pos.Y, q.pos.Z))
				q.p.Transparency = 1 - q.op * (1 - k)
			end
		end
	end
end

---------------------------------------------------------------------
-- SONS (opcionais)
---------------------------------------------------------------------
local function sfx(name, vol, pitch)
	local id = SOUND_IDS[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.6
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end
local function loopSound(name)
	local id = SOUND_IDS[name]
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end
local engineSound = loopSound("engine")
local sirenSound = loopSound("siren")

---------------------------------------------------------------------
-- HUD (ScreenGui criado por código)
---------------------------------------------------------------------
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end
local function stroke(o, t, c)
	new("UIStroke", { Thickness = t or 1, Color = c or Color3.new(1, 1, 1), Transparency = 0.65, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function text(parent, props)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		RichText = true,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function button(parent, label, props)
	local base = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		Text = label,
		AutoButtonColor = true,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 8)
	stroke(b, 1)
	return b
end
local PINK, YELLOW, CYAN = rgb(255, 126, 182), rgb(255, 211, 77), rgb(56, 232, 255)

local gui = new("ScreenGui", { Name = "HighwayGui", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
-- a interface foi desenhada para 1100x680; em telas menores (celular) tudo encolhe junto
local uiScale = new("UIScale", {}, gui)
local function rescale()
	local vp = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 680), 0.42, 1)
end
rescale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

local hud = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local copWarn = new("Frame", { Size = UDim2.new(1, 0, 0.35, 0), Position = UDim2.fromScale(0, 0.65), BackgroundColor3 = rgb(255, 20, 60), BackgroundTransparency = 1, BorderSizePixel = 0 }, hud)
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, copWarn)

local scoreLbl = text(hud, { Size = UDim2.new(0, 420, 0, 48), Position = UDim2.new(0.5, -210, 0, 14), TextSize = 42, Text = "0" })
local streakLbl = text(hud, { Size = UDim2.new(0, 420, 0, 18), Position = UDim2.new(0.5, -210, 0, 62), TextSize = 13, TextColor3 = PINK })
local comboBg = new("Frame", { Size = UDim2.new(0, 290, 0, 4), Position = UDim2.new(0.5, -145, 0, 84), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, hud)
local comboFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(255, 80, 70), BorderSizePixel = 0 }, comboBg)
local gainLbl = text(hud, { Size = UDim2.new(0, 300, 0, 20), Position = UDim2.new(0.5, -150, 0, 92), TextSize = 16, TextColor3 = YELLOW, TextTransparency = 1 })
local distLbl = text(hud, { Size = UDim2.new(0, 200, 0, 30), Position = UDim2.new(0, 16, 0, 64), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, Text = "0 m" })
local wantedLbl = text(hud, { Size = UDim2.new(0, 200, 0, 22), Position = UDim2.new(0, 16, 0, 96), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold })
-- distância/estrelas ficam sempre abaixo da barra do Roblox (≈60px reais), qualquer que seja a escala
local function placeTopLeft()
	local s = uiScale.Scale
	distLbl.Position = UDim2.new(0, 16, 0, 64 / s)
	wantedLbl.Position = UDim2.new(0, 16, 0, 64 / s + 32)
end
placeTopLeft()
uiScale:GetPropertyChangedSignal("Scale"):Connect(placeTopLeft)
local pops = new("Frame", { Size = UDim2.new(0, 600, 0, 140), Position = UDim2.new(0.5, -300, 0.2, 0), BackgroundTransparency = 1 }, hud)
new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, pops)
local countLbl = text(gui, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.3), TextSize = 140, TextTransparency = 1, TextStrokeTransparency = 1, TextStrokeColor3 = PINK })

local bottom = new("Frame", { Size = UDim2.new(0, 640, 0, 44), Position = UDim2.new(0.5, -320, 1, -54), BackgroundTransparency = 1 }, hud)
text(bottom, { Size = UDim2.new(0, 60, 0, 12), TextSize = 11, Text = "NITRO", TextXAlignment = Enum.TextXAlignment.Left })
local meterBg = new("Frame", { Size = UDim2.new(1, -120, 0, 9), Position = UDim2.new(0, 62, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, BorderSizePixel = 0 }, bottom)
corner(meterBg, 5)
local meterFill = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, meterBg)
corner(meterFill, 5)
local meterPct = text(bottom, { Size = UDim2.new(0, 50, 0, 12), Position = UDim2.new(1, -50, 0, 0), TextSize = 11, Text = "50%", TextXAlignment = Enum.TextXAlignment.Right })
local hints = text(bottom, {
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 0, 22),
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextTransparency = 0.25,
	Text = "A / D  Lane   ·   W / SPACE  Jump · hold to fly   ·   S  Slam   ·   SHIFT  Nitro   ·   no ar: A / D Barrel roll · W Front flip   (setas também)",
})

-- botões de toque (celular)
-- botões de toque: ScreenGui próprio (fora do UIScale), tamanho proporcional à altura da tela
local touchGui = new("ScreenGui", { Name = "HighwayTouch", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, DisplayOrder = 2 }, player:WaitForChild("PlayerGui"))
local function tbtn(label, pos, size, color)
	local b = new("TextButton", {
		Size = UDim2.fromScale(size, size),
		Position = pos,
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		Text = label,
		AutoButtonColor = false,
	}, touchGui)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, b)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	new("UIPadding", { PaddingTop = UDim.new(0.32, 0), PaddingBottom = UDim.new(0.32, 0), PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0) }, b)
	new("UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1), Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end
local bLeft = tbtn("<", UDim2.fromScale(0.025, 0.96), 0.24)
local bRight = tbtn(">", UDim2.fromScale(0.16, 0.96), 0.24)
local bSlam = tbtn("SLAM", UDim2.fromScale(0.69, 0.96), 0.2)
local bJump = tbtn("JUMP", UDim2.fromScale(0.83, 0.96), 0.3, PINK)
local bNitro = tbtn("NITRO", UDim2.fromScale(0.85, 0.6), 0.22, CYAN)

-- menu
local menu = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(20, 5, 30), BackgroundTransparency = 0.55 }, gui)
text(menu, { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0.12, 0), TextSize = 64, Text = "HIGHWAY", TextStrokeColor3 = PINK, TextStrokeTransparency = 0.4 })
text(menu, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.12, 74), TextSize = 26, Text = "R O A D S T E R", TextColor3 = PINK })
local ctrl = new("Frame", { Size = UDim2.new(0, 320, 0, 150), Position = UDim2.new(0.5, -160, 0.12, 124), BackgroundColor3 = rgb(10, 6, 20), BackgroundTransparency = 0.35 }, menu)
corner(ctrl, 10)
stroke(ctrl, 1)
text(ctrl, {
	Size = UDim2.new(1, -24, 1, -16),
	Position = UDim2.new(0, 12, 0, 8),
	TextSize = 13,
	Font = Enum.Font.GothamMedium,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextXAlignment = Enum.TextXAlignment.Left,
	LineHeight = 1.25,
	Text = '<font color="#aaaaaa" size="10">CONTROLS</font>\nA / D  (setas)   Change lane\nW / Space   Jump · hold to fly\nS   Slam\nShift   Nitro boost\nNo ar: A / D Barrel roll · W Front flip',
})
local playBtn = button(menu, "PLAY", { Size = UDim2.new(0, 200, 0, 52), Position = UDim2.new(0.5, -100, 0.12, 292), BackgroundTransparency = 0, TextColor3 = rgb(26, 15, 36), TextSize = 20 })
local menuRankBtn = button(menu, "Ranking", { Size = UDim2.new(0, 200, 0, 36), Position = UDim2.new(0.5, -100, 0.12, 352) })
local bestLbl = text(menu, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0.12, 398), TextSize = 13, Font = Enum.Font.GothamBold, TextTransparency = 0.3 })

-- game over
local over = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
local card = new("Frame", { Size = UDim2.new(0, 360, 0, 330), Position = UDim2.new(0.5, -180, 0.5, -165), BackgroundColor3 = rgb(12, 10, 16), BackgroundTransparency = 0.15 }, over)
corner(card, 12)
stroke(card, 1)
local newRec = text(card, { Size = UDim2.new(0, 120, 0, 20), Position = UDim2.new(0.5, -60, 0, 14), TextSize = 11, Text = "NEW RECORD", TextColor3 = rgb(36, 20, 0), BackgroundTransparency = 0, BackgroundColor3 = YELLOW })
corner(newRec, 3)
local endTitle = text(card, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 40), TextSize = 12, Font = Enum.Font.GothamBold, TextTransparency = 0.35, Text = "FINAL SCORE" })
local endScore = text(card, { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 56), TextSize = 52, Text = "0" })
local statsLbl = text(card, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 116), TextSize = 16, Font = Enum.Font.GothamBold })
local rankLbl = text(card, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 160), TextSize = 17 })
local toNextLbl = text(card, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 184), TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = YELLOW })
local retryBtn = button(card, "Retry", { Size = UDim2.new(0, 100, 0, 40), Position = UDim2.new(0, 20, 0, 214), BackgroundTransparency = 0, TextColor3 = rgb(26, 15, 36) })
local rankBtn = button(card, "Ranking", { Size = UDim2.new(0, 100, 0, 40), Position = UDim2.new(0, 130, 0, 214) })
local menuBtn = button(card, "Menu", { Size = UDim2.new(0, 100, 0, 40), Position = UDim2.new(0, 240, 0, 214) })
text(card, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 268), TextSize = 12, Font = Enum.Font.GothamMedium, TextTransparency = 0.4, Text = "R = retry  ·  ranking global do jogo" })

-- ranking
local rankUI = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.2, Visible = false, ZIndex = 5 }, gui)
local rcard = new("Frame", { Size = UDim2.new(0, 360, 0, 420), Position = UDim2.new(0.5, -180, 0.5, -210), BackgroundColor3 = rgb(12, 10, 16), BackgroundTransparency = 0, ZIndex = 5 }, rankUI)
corner(rcard, 12)
stroke(rcard, 1)
text(rcard, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 10), TextSize = 14, Text = "RANKING GLOBAL", ZIndex = 5 })
local rankRows = {}
for i = 1, 10 do
	rankRows[i] = text(rcard, { Size = UDim2.new(1, -40, 0, 28), Position = UDim2.new(0, 20, 0, 40 + (i - 1) * 30), TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
end
local rankClose = button(rcard, "Voltar", { Size = UDim2.new(0, 160, 0, 38), Position = UDim2.new(0.5, -80, 1, -52), BackgroundTransparency = 0, TextColor3 = rgb(26, 15, 36), ZIndex = 5 })

local popOrder = 0
local function popup(label, gain, color)
	popOrder += 1
	local t = text(pops, {
		LayoutOrder = popOrder,
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = 22,
		TextColor3 = color or Color3.new(1, 1, 1),
		Text = label .. (gain and gain > 0 and ('  <font color="#ffd34d">+' .. fmt(gain) .. "</font>") or ""),
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = rgb(60, 0, 50),
	})
	local kids = {}
	for _, c in ipairs(pops:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids > 4 then
		kids[1]:Destroy()
	end
	task.delay(0.9, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(t, 1.5)
end

---------------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------------
local state = "menu"
local P = {}
local cars, cops = {}, {}
local score, streak, maxStreak, comboT, playTime = 0, 0, 0, 0, 0
local nextSpawn, timeScale, slowT, shake = -180, 1, 0, 0
local heat, heatIdle, copCooldown = 0, 0, 0
local countT, countN, lastGainT, menuT = 0, -1, 0, 0
local overShown = false
local held = {}
local touchJump, touchNitro = false, false
local camPos, camLook = W(0, 12, 30), W(0, 0, 0)

local function mult()
	return math.min(10, 1 + math.floor(streak / 2))
end
local function wantedStars()
	return math.min(MAX_STARS, math.floor(heat / HEAT_PER_STAR))
end
local function addHeat(n)
	local before = wantedStars()
	heat = math.min(HEAT_PER_STAR * MAX_STARS + 2, heat + n)
	heatIdle = 0
	if wantedStars() > before then
		popup(string.rep("★", wantedStars()) .. " WANTED", 0, rgb(255, 128, 128))
	end
end

local function award(label, pts, color, meterAdd)
	if not P.alive then
		return 0
	end
	local gain = math.floor(pts * mult() + 0.5)
	score += gain
	streak += 1
	maxStreak = math.max(maxStreak, streak)
	comboT = COMBO_TIME
	P.meter = math.min(1, P.meter + (meterAdd or 0.1))
	popup(label, gain, color)
	gainLbl.Text = "+" .. fmt(gain)
	gainLbl.TextTransparency = 0
	lastGainT = 1.2
	return gain
end

local function burst(pos, n, speed, color, neon, life, size)
	for _ = 1, n do
		emit(pos, Vector3.new(rand(-1, 1) * speed, rand(0, 1) * speed, rand(-1, 1) * speed - (P.speed or 0) * 0.3), life * rand(0.6, 1.2), size, 2.5, color, neon, 0.9)
	end
end

local function smashCar(c, label, byPlayer, fromX, fromSpeed)
	if c.smashed then
		return
	end
	if byPlayer == nil then
		byPlayer = true
	end
	fromX = fromX or P.x
	fromSpeed = fromSpeed or P.speed
	c.smashed = true
	c.t = 0
	local side = math.sign(c.x - fromX)
	if side == 0 then
		side = rng:NextNumber() < 0.5 and -1 or 1
	end
	c.vel = Vector3.new(side * rand(4, 9), rand(10, 17), -(fromSpeed + rand(8, 20)))
	c.spin = Vector3.new(rand(-4, 4), rand(-3, 3), side * rand(3, 7))
	c.rot = CFrame.identity
	burst(Vector3.new(c.x, c.h * 0.6, c.z), 12, 9, rgb(255, 176, 112), true, 0.5, 0.5)
	burst(Vector3.new(c.x, 1, c.z), 8, 5, rgb(255, 226, 239), false, 1.1, 1.2)
	if math.abs(c.z - P.z) < 120 then
		sfx("smash", 0.7)
		shake = math.max(shake, byPlayer and 0.7 or 0.25)
	end
	if not byPlayer then
		return
	end
	if c.cop then
		award("COP DOWN", 500, rgb(255, 176, 176), 0.2)
		addHeat(1)
	else
		local big = c.kind == "bus" or c.kind == "truck"
		award(label or "SMASH", big and 260 or 150, rgb(255, 176, 176), 0.12)
		addHeat(big and 1.5 or 1)
	end
end

local function flyDebris(c, dt)
	c.t += dt
	c.vel = c.vel + Vector3.new(0, -28 * dt, 0)
	c.x += c.vel.X * dt
	c.y += c.vel.Y * dt
	c.z += c.vel.Z * dt
	if c.y < 0 then
		c.y = 0
		c.vel = Vector3.new(c.vel.X * 0.7, math.abs(c.vel.Y) * 0.3, c.vel.Z * 0.8)
	end
	c.rot = c.rot * CFrame.Angles(c.spin.X * dt, c.spin.Y * dt, c.spin.Z * dt)
	c.model:PivotTo(CFrame.new(W(c.x, c.y, c.z)) * c.rot)
end

local function startTrick(kind, dir)
	if P.trick or not P.air or P.slam then
		return
	end
	P.trick = { kind = kind, dir = dir or 1, t = 0, dur = kind == "roll" and 0.55 or 0.62 }
end
local function completeTrick()
	local t = P.trick
	if not t then
		return
	end
	P.trick = nil
	P.roll, P.pitch = 0, 0
	P.tricks += 1
	sfx("trick", 0.6)
	award(t.kind == "roll" and "Barrel roll" or "Front flip", (t.kind == "roll" and 200 or 250) + math.floor(P.airTime * 25), nil, 0.14)
end

local function crash(busted)
	if not P.alive then
		return
	end
	P.alive = false
	P.crashT = 0
	P.trick = nil
	P.busted = busted
	if busted then
		popup("BUSTED", 0, rgb(122, 168, 255))
	end
	P.cv = Vector3.new(rand(-6, 6), 11, -P.speed * 0.55)
	P.cspin = Vector3.new(rand(-5, 5), rand(-3, 3), rand(-7, 7))
	P.crot = CFrame.identity
	P.air = true
	timeScale, slowT, shake = 0.3, 1.1, 1.2
	burst(Vector3.new(P.x, 1, P.z), 20, 12, rgb(255, 160, 96), true, 0.7, 0.6)
	burst(Vector3.new(P.x, 1, P.z), 12, 6, rgb(216, 200, 216), false, 1.6, 1.4)
	sfx("crash", 0.9)
end

local function jump()
	if not P.alive or P.air then
		return
	end
	P.air = true
	P.vy = 15.5
	P.tricks = 0
	P.airTime = 0
	sfx("jump", 0.5)
	for _ = 1, 5 do
		emit(Vector3.new(P.x + rand(-1, 1), 0.4, P.z + 2), Vector3.new(rand(-2, 2), rand(1, 3), 4), 0.8, 0.8, 2, rgb(255, 230, 242), false, 0.6)
	end
end

local function shockwave()
	sfx("crash", 0.8, 0.7)
	shake = 1
	for i = 0, 19 do
		local a = i / 20 * math.pi * 2
		emit(Vector3.new(P.x, 0.5, P.z), Vector3.new(math.cos(a) * 18, rand(0.5, 2), math.sin(a) * 18), 0.8, 1.1, 2, rgb(255, 214, 236), false, 0.8)
	end
	local n = 0
	for _, list in ipairs({ cars, cops }) do
		for _, c in ipairs(list) do
			if not c.smashed and math.abs(c.z - P.z) < 16 and math.abs(c.x - P.x) < 6.5 then
				smashCar(c, c.cop and "COP DOWN" or "SLAM")
				n += 1
			end
		end
	end
	if n == 0 then
		award("Slam", 60, rgb(255, 208, 230), 0.03)
	end
end

local function land()
	local impact = -P.vy
	P.air = false
	P.vy = 0
	P.flying = false
	local slammed = P.slam
	P.slam = false
	if P.trick then
		local k = P.trick.t / P.trick.dur
		if k > 0.8 then
			completeTrick()
		elseif k > 0.2 then
			crash(false)
			return
		else
			P.trick = nil
			P.roll, P.pitch = 0, 0
		end
	end
	P.roll, P.pitch = 0, 0
	if P.tricks > 0 then
		award("PERFECT LANDING", 90 + P.tricks * 30, rgb(255, 208, 230), 0.06)
	end
	if slammed then
		shockwave()
	end
	sfx("land", 0.5)
	for _ = 1, 8 do
		emit(Vector3.new(P.x + rand(-1.4, 1.4), 0.3, P.z + rand(-2, 2.5)), Vector3.new(rand(-5, 5), rand(0.5, 2.5), rand(-2, 4)), 1, 1, 2.5, rgb(255, 230, 242), false, 0.65)
	end
	shake = math.max(shake, clamp(impact / 40, 0.1, 0.8))
	P.tricks = 0
	P.airTime = 0
end

local function spawnCar(z)
	local lane = rng:NextInteger(1, 4)
	local near = {}
	local count = 0
	for _, c in ipairs(cars) do
		if not c.smashed and math.abs(c.z - z) < 18 and not near[c.lane] then
			near[c.lane] = true
			count += 1
		end
	end
	if near[lane] or count >= 3 then
		return
	end
	local r = rng:NextNumber()
	local kind = r < 0.1 and "bus" or r < 0.2 and "truck" or r < 0.45 and "suv" or "sedan"
	local m, w, l, h = makeCar(kind)
	local slow = kind == "bus" or kind == "truck"
	local c = { model = m, kind = kind, lane = lane, x = LANES[lane], y = 0, z = z, speed = slow and rand(17, 22) or rand(21, 30), w = w, l = l, h = h, passed = false, smashed = false, t = 0 }
	m:PivotTo(CFrame.new(W(c.x, 0, z)))
	table.insert(cars, c)
end

local function spawnCop()
	local lane = rng:NextInteger(1, 4)
	local m, w, l, h, lights = makeCar("cop")
	local c = { model = m, cop = true, kind = "cop", lane = lane, x = LANES[lane], y = 0, z = P.z + rand(40, 60), speed = P.speed + 10, w = w, l = l, h = h, smashed = false, t = 0, laneT = rand(0.3, 1), flash = rand(0, 6), leaving = false, lights = lights }
	m:PivotTo(CFrame.new(W(c.x, 0, c.z)))
	table.insert(cops, c)
	popup("POLICE!", 0, rgb(255, 128, 128))
end

local function clearList(list)
	for _, c in ipairs(list) do
		c.model:Destroy()
	end
	table.clear(list)
end

local function resetGame()
	clearList(cars)
	clearList(cops)
	-- os segmentos foram reciclados para a frente na corrida anterior: volta todos para a largada
	for i, s in ipairs(segments) do
		s.z = 20 - (i - 1) * SEG
		s.model:PivotTo(CFrame.new(W(0, 0, s.z)))
	end
	P.x, P.y, P.z, P.lane = LANES[2], RAMP.h, 8, 2
	P.vy, P.air, P.speed, P.roll, P.pitch, P.trick = 0, false, 0, 0, 0, nil
	P.tricks, P.slam, P.flying, P.nitro, P.meter, P.airTime = 0, false, false, false, 0.5, 0
	P.alive, P.crashT, P.busted, P.lean, P.visPitch = true, 0, false, 0, 0
	score, streak, maxStreak, comboT, playTime = 0, 0, 0, 0, 0
	nextSpawn, timeScale, slowT, shake = -180, 1, 0, 0
	heat, heatIdle, copCooldown = 0, 0, 0
	overShown = false
	for _, c in ipairs(pops:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	cc.Saturation, cc.Brightness, blur.Size = 0.15, 0, 0
end

---------------------------------------------------------------------
-- RANKING / TELAS
---------------------------------------------------------------------
local remotes = ReplicatedStorage:WaitForChild("HighwayRemotes", 15)
local localBest = 0

local function showRanking()
	rankUI.Visible = true
	for i = 1, 10 do
		rankRows[i].Text = i == 1 and "Carregando..." or ""
		rankRows[i].TextColor3 = Color3.new(1, 1, 1)
	end
	task.spawn(function()
		local ok, list = false, nil
		if remotes then
			ok, list = pcall(function()
				return remotes.GetTop:InvokeServer()
			end)
		end
		if not ok or not list or #list == 0 then
			rankRows[1].Text = "Ranking indisponível (publique o jogo / ative API Services)"
			rankRows[1].TextSize = 11
			return
		end
		rankRows[1].TextSize = 14
		for i = 1, 10 do
			local e = list[i]
			rankRows[i].Text = e and string.format("#%d   %s   <font color=\"#ffd34d\">%s</font>", i, e.name, fmt(e.score)) or ""
			rankRows[i].TextColor3 = (e and e.me) and YELLOW or Color3.new(1, 1, 1)
		end
	end)
end

local function setHudVisible(v)
	hud.Visible = v
	touchGui.Enabled = v and UIS.TouchEnabled
end

local function toMenu()
	state = "menu"
	over.Visible = false
	rankUI.Visible = false
	menu.Visible = true
	setHudVisible(false)
	resetGame()
	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Best") then
		localBest = math.max(localBest, stats.Best.Value)
	end
	bestLbl.Text = localBest > 0 and ("BEST " .. fmt(localBest)) or ""
end

local function startGame()
	menu.Visible = false
	over.Visible = false
	rankUI.Visible = false
	resetGame()
	setHudVisible(true)
	hints.Visible = not MOBILE
	state = "count"
	countT, countN = 0, -1
end

local function gameOver()
	state = "over"
	setHudVisible(false)
	local dist = math.max(0, math.floor(8 - P.z))
	local final = math.floor(score)
	local wasBest = final > localBest
	localBest = math.max(localBest, final)
	newRec.Visible = wasBest
	endTitle.Text = P.busted and "BUSTED · FINAL SCORE" or "FINAL SCORE"
	endTitle.TextColor3 = P.busted and rgb(122, 168, 255) or Color3.new(1, 1, 1)
	endScore.Text = fmt(final)
	statsLbl.Text = string.format('<font size="10" color="#999999">DISTANCE        MAX COMBO        TIME</font>\n%s m          %d          %s', fmt(dist), maxStreak, fmtT(playTime))
	rankLbl.Text = "Rank ..."
	toNextLbl.Text = ""
	cc.Saturation, cc.Brightness = -1, -0.25
	blur.Size = 10
	over.Visible = true
	task.spawn(function()
		if not remotes then
			rankLbl.Text = "Rank offline"
			return
		end
		local ok, res = pcall(function()
			return remotes.SubmitScore:InvokeServer(final, dist, maxStreak, playTime)
		end)
		if not ok or not res then
			rankLbl.Text = "Rank offline"
			return
		end
		localBest = math.max(localBest, res.best or 0)
		newRec.Visible = res.newRecord == true
		if res.rank then
			local pct = math.max(1, math.floor(res.rank / math.max(1, res.total) * 100 + 0.5))
			rankLbl.Text = string.format('Rank #%d <font size="12" color="#aaaaaa">Top %d%%</font>', res.rank, math.min(100, pct))
			if res.toNext then
				toNextLbl.Text = fmt(res.toNext) .. " pts to #" .. (res.rank - 1)
			end
		else
			rankLbl.Text = "Fora do Top 100"
		end
	end)
end

---------------------------------------------------------------------
-- INPUT
---------------------------------------------------------------------
local function jumpHeld()
	return held[Enum.KeyCode.Space] or held[Enum.KeyCode.Up] or held[Enum.KeyCode.W] or held[Enum.KeyCode.ButtonA] or touchJump
end
local function nitroHeld()
	return held[Enum.KeyCode.LeftShift] or held[Enum.KeyCode.RightShift] or held[Enum.KeyCode.ButtonR2] or held[Enum.KeyCode.ButtonX] or touchNitro
end
local function laneChange(d)
	if not P.alive then
		return
	end
	local nl = clamp(P.lane + d, 1, 4)
	if nl == P.lane then
		return
	end
	P.lane = nl
	if P.air and P.y > 1.2 then
		startTrick("roll", -d)
	else
		for _ = 1, 3 do
			emit(Vector3.new(P.x + rand(-0.8, 0.8), 0.3, P.z + 2.4), Vector3.new(-d * 3, rand(0.3, 1.2), 5), 0.7, 0.6, 2, rgb(255, 230, 242), false, 0.45)
		end
	end
end
local function upPress()
	if P.air then
		startTrick("flip")
	else
		jump()
	end
end
local function downPress()
	if not P.alive or not P.air or P.slam then
		return
	end
	P.slam = true
	P.vy = -48
	P.flying = false
	P.trick = nil
	P.roll, P.pitch = 0, 0
end

local KEY_LEFT = { [Enum.KeyCode.Left] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.DPadLeft] = true }
local KEY_RIGHT = { [Enum.KeyCode.Right] = true, [Enum.KeyCode.D] = true, [Enum.KeyCode.DPadRight] = true }
local KEY_UP = { [Enum.KeyCode.Up] = true, [Enum.KeyCode.W] = true, [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true }
local KEY_DOWN = { [Enum.KeyCode.Down] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.ButtonB] = true }

UIS.InputBegan:Connect(function(input, processed)
	local kc = input.KeyCode
	if kc == Enum.KeyCode.Unknown then
		return
	end
	local first = not held[kc]
	held[kc] = true
	if processed or not first then
		return
	end
	if state == "menu" then
		if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA then
			startGame()
		end
		return
	end
	if state == "over" then
		if kc == Enum.KeyCode.R or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA then
			startGame()
		end
		return
	end
	if state ~= "play" then
		return
	end
	if KEY_LEFT[kc] then
		laneChange(-1)
	elseif KEY_RIGHT[kc] then
		laneChange(1)
	elseif KEY_UP[kc] then
		upPress()
	elseif KEY_DOWN[kc] then
		downPress()
	end
end)
UIS.InputEnded:Connect(function(input)
	held[input.KeyCode] = false
end)

-- cada dedo é um InputObject próprio: dá para segurar NITRO e trocar de faixa ao mesmo tempo
local activeTouches = {}
local function hold(btn, onDown, onUp)
	btn.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			activeTouches[input] = { btn = btn, up = onUp }
			btn.BackgroundTransparency = 0.25
			onDown()
		end
	end)
end
local function releaseTouch(input)
	local a = activeTouches[input]
	if a then
		activeTouches[input] = nil
		a.btn.BackgroundTransparency = 0.6
		if a.up then
			a.up()
		end
	end
end
UIS.InputEnded:Connect(releaseTouch)
UIS.TouchEnded:Connect(releaseTouch)
-- deslizar o dedo na tela também controla (estilo Subway Surfers)
UIS.TouchSwipe:Connect(function(direction, _, processed)
	if processed or state ~= "play" then
		return
	end
	if direction == Enum.SwipeDirection.Left then
		laneChange(-1)
	elseif direction == Enum.SwipeDirection.Right then
		laneChange(1)
	elseif direction == Enum.SwipeDirection.Up then
		upPress()
	elseif direction == Enum.SwipeDirection.Down then
		downPress()
	end
end)
hold(bLeft, function()
	if state == "play" then
		laneChange(-1)
	end
end)
hold(bRight, function()
	if state == "play" then
		laneChange(1)
	end
end)
hold(bJump, function()
	touchJump = true
	if state == "play" then
		upPress()
	end
end, function()
	touchJump = false
end)
hold(bSlam, function()
	if state == "play" then
		downPress()
	end
end)
hold(bNitro, function()
	touchNitro = true
end, function()
	touchNitro = false
end)

playBtn.Activated:Connect(startGame)
retryBtn.Activated:Connect(startGame)
menuBtn.Activated:Connect(toMenu)
rankBtn.Activated:Connect(showRanking)
menuRankBtn.Activated:Connect(showRanking)
rankClose.Activated:Connect(function()
	rankUI.Visible = false
end)

-- trava o personagem padrão (a corrida é controlada por este script)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)
task.spawn(function()
	local ok, controls = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 30)):GetControls()
	end)
	if ok and controls then
		controls:Disable()
	end
	-- esconde o analógico e o botão de pulo padrão do Roblox no celular
	UIS.ModalEnabled = true
end)
local function lockCharacter(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.Anchored = true
	end
end
if player.Character then
	task.spawn(lockCharacter, player.Character)
end
player.CharacterAdded:Connect(lockCharacter)

---------------------------------------------------------------------
-- MUNDO: segmentos
---------------------------------------------------------------------
for i = 0, NSEG - 1 do
	local s = buildSegment(i)
	s.z = 20 - i * SEG
	s.model:PivotTo(CFrame.new(W(0, 0, s.z)))
	segments[i + 1] = s
end
local function updateWorld()
	for _, s in ipairs(segments) do
		if s.z - SEG / 2 > P.z + 40 then
			s.z -= NSEG * SEG
			s.model:PivotTo(CFrame.new(W(0, 0, s.z)))
		end
	end
	ocean.CFrame = CFrame.new(W(-328, -5, P.z - 200))
	sun.CFrame = CFrame.new(camera.CFrame.Position + SUN_DIR * 2600)
end

---------------------------------------------------------------------
-- UPDATE: jogador
---------------------------------------------------------------------
local function updatePlayer(dt)
	local dist = math.max(0, 8 - P.z)
	if not P.alive then
		P.crashT += dt
		P.cv = P.cv + Vector3.new(0, -30 * dt, 0)
		P.x += P.cv.X * dt
		P.y += P.cv.Y * dt
		P.z += P.cv.Z * dt
		if P.y < 0 then
			P.y = 0
			P.cv = Vector3.new(P.cv.X * 0.6, math.abs(P.cv.Y) * 0.35, P.cv.Z * 0.7)
			P.cspin *= 0.6
		end
		P.cv = Vector3.new(P.cv.X, P.cv.Y, P.cv.Z * (1 - dt * 0.4))
		P.crot = P.crot * CFrame.Angles(P.cspin.X * dt, P.cspin.Y * dt, P.cspin.Z * dt)
		if rng:NextNumber() < 0.4 then
			emit(Vector3.new(P.x, P.y + 1, P.z), Vector3.new(rand(-1, 1), 3, 0), 1.4, 0.9, 3, rgb(106, 90, 112), false, 0.6)
		end
		carModel:PivotTo(CFrame.new(W(P.x, P.y, P.z)) * CFrame.new(0, 0.95 * K, 0) * P.crot * CFrame.new(0, -0.95 * K, 0))
		P.speed = math.max(0, P.speed - 40 * dt)
		return
	end

	P.nitro = nitroHeld() and P.meter > 0.01
	if P.nitro then
		P.meter = math.max(0, P.meter - 0.3 * dt)
	end
	local baseSpeed = math.min(36 + dist * 0.011, 68)
	local target = baseSpeed * (P.nitro and 1.5 or 1)
	P.speed += (target - P.speed) * math.min(1, dt * (P.speed < baseSpeed and 0.9 or 2.2))
	P.z -= P.speed * dt

	local lx = LANES[P.lane]
	P.x += (lx - P.x) * math.min(1, dt * 11)
	P.lean += ((lx - P.x) * -0.07 - P.lean) * math.min(1, dt * 10)

	if P.air then
		P.airTime += dt
		P.flying = (not P.slam) and jumpHeld() and P.meter > 0.01 and P.vy < 3
		if P.flying then
			local tvy = P.y < 11 and 1.2 or 0
			P.vy += (tvy - P.vy) * math.min(1, dt * 4)
			P.meter = math.max(0, P.meter - 0.32 * dt)
		else
			P.vy += (P.slam and -95 or -36) * dt
		end
		P.y += P.vy * dt
		local g = groundAt(P.x, P.z)
		if P.y <= g then
			P.y = g
			land()
			if not P.alive then
				return
			end
		end
	else
		local g = groundAt(P.x, P.z)
		if g < P.y - 0.35 then
			P.air = true
			P.vy = 0
			P.tricks = 0
			P.airTime = 0
		else
			P.y = g
		end
	end

	if P.trick then
		P.trick.t += dt
		local k = math.min(1, P.trick.t / P.trick.dur)
		local a = ease(k) * math.pi * 2
		if P.trick.kind == "roll" then
			P.roll = a * P.trick.dir
		else
			P.pitch = -a
		end
		if k >= 1 then
			completeTrick()
		end
	end

	local tp
	if P.air then
		tp = math.atan2(P.vy, P.speed) * 0.6
	else
		tp = math.atan(groundAt(P.x, P.z - 0.5) - groundAt(P.x, P.z + 0.5))
	end
	P.visPitch += (tp - P.visPitch) * math.min(1, dt * 8)
	carModel:PivotTo(CFrame.new(W(P.x, P.y, P.z)) * CFrame.new(0, 0.95 * K, 0) * CFrame.Angles(P.visPitch + P.pitch, 0, P.roll + P.lean) * CFrame.new(0, -0.95 * K, 0))

	for _, f in ipairs(flames) do
		f.Transparency = P.nitro and rand(0, 0.35) or 1
	end
	if P.nitro and not P.air and rng:NextNumber() < 0.6 then
		emit(Vector3.new(P.x + rand(-1, 1), 0.35, P.z + 2.6), Vector3.new(rand(-2, 2), rand(0.5, 2), 6), rand(0.7, 1.2), 0.7, 3, rgb(255, 230, 242), false, 0.55)
	end
	if P.flying and rng:NextNumber() < 0.5 then
		emit(Vector3.new(P.x + rand(-0.6, 0.6), P.y + 0.5, P.z + 2.8), Vector3.new(0, -1, 8), 0.5, 0.45, 1.5, rgb(168, 244, 255), true, 0.7)
	end
end

---------------------------------------------------------------------
-- UPDATE: tráfego e polícia
---------------------------------------------------------------------
local function hitPlayer(c, label)
	local dx, dz = math.abs(c.x - P.x), math.abs(c.z - P.z)
	if dx < c.w / 2 + 0.82 and dz < c.l / 2 + 2.5 then
		if P.y > c.h - 0.35 then
			if P.vy <= 0 and P.y < c.h + 0.6 then
				smashCar(c, c.cop and "COP DOWN" or "Stomp")
				P.vy = 12
				P.slam = false
				P.air = true
			end
		elseif P.nitro or P.slam then
			smashCar(c, label)
		else
			crash(c.cop == true)
		end
	end
	return dx
end

local function updateCars(dt)
	if state == "play" and P.alive then
		while nextSpawn > P.z - 330 do
			spawnCar(nextSpawn)
			local dist = math.max(0, 8 - P.z)
			nextSpawn -= math.max(7, rand(14, 30) - dist * 0.0035)
		end
	end
	for _, c in ipairs(cars) do
		if c.smashed then
			flyDebris(c, dt)
		else
			local sp = c.speed
			for _, o in ipairs(cars) do
				if o ~= c and not o.smashed and o.lane == c.lane and o.z < c.z and c.z - o.z < (c.l + o.l) / 2 + 6 then
					sp = math.min(sp, o.speed)
				end
			end
			c.speed = sp
			c.z -= sp * dt
			c.model:PivotTo(CFrame.new(W(c.x, 0, c.z)))
			if P.alive and state == "play" then
				local dx = hitPlayer(c, "SMASH")
				if not c.passed and c.z > P.z + c.l / 2 then
					c.passed = true
					if not c.smashed and dx < c.w / 2 + 3 and P.y < 2.5 and P.alive then
						sfx("near", 0.5)
						award("NEAR MISS", 50 + math.floor(P.speed), rgb(255, 208, 230), 0.07)
					end
				end
			end
		end
	end
	for i = #cars, 1, -1 do
		local c = cars[i]
		if c.z > P.z + 40 or c.z < P.z - 700 or (c.smashed and c.t > 4) then
			c.model:Destroy()
			table.remove(cars, i)
		end
	end
end

local function updateCops(dt)
	if state == "play" and P.alive then
		heatIdle += dt
		if heatIdle > 12 and heat > 0 then
			heat = math.max(0, heat - dt / 3)
		end
		copCooldown -= dt
		local live = 0
		for _, c in ipairs(cops) do
			if not c.smashed and not c.leaving then
				live += 1
			end
		end
		if live < math.min(4, wantedStars()) and copCooldown <= 0 then
			spawnCop()
			copCooldown = rand(3, 5)
		end
	end
	local stars = wantedStars()
	local nearest, behindNear = math.huge, math.huge
	for _, c in ipairs(cops) do
		if c.smashed then
			flyDebris(c, dt)
		else
			if stars == 0 or not P.alive then
				c.leaving = true
			end
			local behind = c.z > P.z + 3
			local gap = P.z - c.z
			local target
			if c.leaving then
				target = P.speed - 18
			elseif behind then
				target = P.speed + 9 + math.min(8, (c.z - P.z) * 0.15)
			else
				target = gap > 50 and (P.speed - 12) or math.max(18, P.speed - 5)
			end
			c.speed += (target - c.speed) * math.min(1, dt * 2)
			c.z -= c.speed * dt
			c.laneT -= dt
			if c.laneT <= 0 and not c.leaving then
				if P.lane ~= c.lane then
					c.lane += math.sign(P.lane - c.lane)
				end
				c.laneT = rand(0.7, 1.2)
			end
			c.x += (LANES[c.lane] - c.x) * math.min(1, dt * 4)
			c.model:PivotTo(CFrame.new(W(c.x, 0, c.z)) * CFrame.Angles(0, 0, (LANES[c.lane] - c.x) * -0.04))
			c.flash += dt * 9
			local on = math.sin(c.flash) > 0
			c.lights.red.Color = on and rgb(255, 16, 48) or rgb(51, 0, 8)
			c.lights.blue.Color = on and rgb(8, 16, 58) or rgb(16, 80, 255)
			c.lights.light.Color = on and rgb(255, 30, 60) or rgb(40, 90, 255)
			-- abre caminho no tráfego
			for _, o in ipairs(cars) do
				if not o.smashed and math.abs(o.x - c.x) < (o.w + c.w) / 2 - 0.2 and math.abs(o.z - c.z) < (o.l + c.l) / 2 then
					smashCar(o, nil, false, c.x, c.speed)
				end
			end
			if P.alive and state == "play" and not c.leaving then
				nearest = math.min(nearest, math.abs(c.z - P.z))
				if c.z > P.z + 2 and c.lane == P.lane then
					behindNear = math.min(behindNear, c.z - P.z)
				end
				hitPlayer(c, "COP DOWN")
			end
		end
	end
	for i = #cops, 1, -1 do
		local c = cops[i]
		if (c.smashed and c.t > 4) or c.z > P.z + 90 or c.z < P.z - 700 then
			c.model:Destroy()
			table.remove(cops, i)
		end
	end
	-- aviso: viatura colada atrás na sua faixa
	if behindNear < 45 then
		local blink = math.sin(os.clock() * 28) > 0
		copWarn.BackgroundColor3 = blink and rgb(255, 20, 60) or rgb(40, 90, 255)
		copWarn.BackgroundTransparency = 1 - ((1 - behindNear / 45) * 0.8 + 0.15)
	else
		copWarn.BackgroundTransparency = 1
	end
	if sirenSound then
		sirenSound.Volume = (state == "play" and P.alive and nearest < 140) and (0.6 * (1 - nearest / 140) + 0.1) or 0
	end
end

---------------------------------------------------------------------
-- UPDATE: câmera e HUD
---------------------------------------------------------------------
local function updateCamera(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	local pos, look
	if state == "menu" then
		menuT += dt
		local a = menuT * 0.25
		pos = Vector3.new(P.x + math.sin(a) * 11, P.y + 3.2, P.z + math.cos(a) * 11)
		look = Vector3.new(P.x, P.y + 1, P.z)
		camPos, camLook = pos, look
	elseif state == "count" then
		local k = smooth(countT / 3.2)
		local a = (1 - k) * 2.2
		local r = 9 - k * 0.5
		pos = Vector3.new(P.x + math.sin(a) * r, P.y + 2.4 + k * 1.1, P.z + math.cos(a) * r)
		look = Vector3.new(P.x, P.y + 1, P.z - k * 10)
		camPos, camLook = pos, look
	else
		local yf = P.alive and P.y or P.y * 0.4
		local f = math.min(1, dt * 7)
		local tz = P.z + 8.6
		camPos = Vector3.new(
			camPos.X + (P.x * 0.75 - camPos.X) * f,
			camPos.Y + (yf * 0.7 + 3.3 - camPos.Y) * f,
			tz + (camPos.Z - tz) * (1 - math.min(1, dt * 14))
		)
		camLook = Vector3.new(camLook.X + (P.x * 0.85 - camLook.X) * f, camLook.Y + (yf * 0.75 + 1.2 - camLook.Y) * f, P.z - 12)
	end
	local p = W(camPos.X, camPos.Y, camPos.Z)
	if shake > 0 then
		p += Vector3.new(rand(-1, 1) * shake * 0.35 * K, rand(-1, 1) * shake * 0.25 * K, 0)
		shake = math.max(0, shake - dt * 2.2)
	end
	camera.CFrame = CFrame.lookAt(p, W(camLook.X, camLook.Y, camLook.Z))
	local tf = (state == "play" and P.nitro) and 76 or (62 + math.min(8, (P.speed or 0) * 0.08))
	camera.FieldOfView += (tf - camera.FieldOfView) * math.min(1, dt * 3)
end

local function updateHud()
	scoreLbl.Text = fmt(score)
	distLbl.Text = fmt(math.max(0, 8 - P.z)) .. ' <font size="15">m</font>'
	local m = mult()
	if streak > 0 then
		streakLbl.Text = m > 1 and ('<font color="#ffd34d">x' .. m .. "</font> STREAK ACTIVE") or ("STREAK " .. streak)
	else
		streakLbl.Text = ""
	end
	comboFill.Size = UDim2.fromScale(comboT / COMBO_TIME, 1)
	meterFill.Size = UDim2.fromScale(P.meter, 1)
	meterFill.BackgroundColor3 = P.meter < 0.05 and rgb(255, 91, 122) or CYAN
	meterPct.Text = math.floor(P.meter * 100 + 0.5) .. "%"
	local st = wantedStars()
	wantedLbl.Text = '<font color="#ffd34d">' .. string.rep("★", st) .. '</font><font transparency="0.75">' .. string.rep("★", MAX_STARS - st) .. "</font>"
end

---------------------------------------------------------------------
-- LOOP PRINCIPAL
---------------------------------------------------------------------
toMenu()
RunService.RenderStepped:Connect(function(raw)
	raw = math.min(raw, 0.05)
	if slowT > 0 then
		slowT -= raw
		if slowT <= 0 then
			timeScale = 1
		end
	end
	local dt = raw * timeScale

	if state == "count" then
		countT += raw
		local n = math.floor(countT)
		if n ~= countN and n <= 3 then
			countN = n
			countLbl.Text = n < 3 and tostring(3 - n) or "GO!"
			countLbl.TextTransparency = 0
			countLbl.TextStrokeTransparency = 0.3
			TweenService:Create(countLbl, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			sfx("beep", 0.5, n == 3 and 2 or 1)
			if n == 3 then
				state = "play"
			end
		end
	end

	if state == "play" then
		if P.alive then
			playTime += dt
			comboT = math.max(0, comboT - dt)
			if comboT == 0 and streak > 0 then
				streak = 0
			end
			score += P.speed * dt * 0.5 * mult()
		end
		updatePlayer(dt)
		if not P.alive and P.crashT > 1.6 and not overShown then
			overShown = true
			gameOver()
		end
	elseif state == "over" then
		updatePlayer(dt)
	else
		carModel:PivotTo(CFrame.new(W(P.x, P.y, P.z)))
	end

	updateCars(dt)
	updateCops(dt)
	updateParticles(dt)
	updateCamera(raw)
	updateWorld()

	local g = groundAt(P.x, P.z)
	local hs = clamp(1 - (P.y - g) / 14, 0.25, 1)
	shadow.Size = Vector3.new(2.6 * hs * K, 0.02 * K, 6 * hs * K)
	shadow.CFrame = CFrame.new(W(P.x, g + 0.03, P.z))
	shadow.Transparency = 1 - 0.45 * hs

	if lastGainT > 0 then
		lastGainT -= raw
		if lastGainT <= 0 then
			gainLbl.TextTransparency = 1
		end
	end
	if state == "play" or state == "count" then
		updateHud()
	end
	if engineSound then
		local on = (state == "play" and P.alive) and 1 or (state == "count" and 0.4 or 0)
		engineSound.Volume = 0.35 * on
		engineSound.PlaybackSpeed = 0.8 + (P.speed or 0) / 60 + (P.nitro and 0.25 or 0)
	end
end)
