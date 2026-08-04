---Handle rendering and collision of gizmo

local RGPFontSize = math.max(math.Round(14 * ScrH() / 1080), 10)

surface.CreateFont("RagdollPoserFont", {
	font = "Verdana",
	size = RGPFontSize,
	weight = 700,
	antialias = true,
})

surface.CreateFont("RagdollPoserHeaderFont", {
	font = "Verdana",
	size = RGPFontSize + 4,
	weight = 700,
	antialias = true,
})

---@module "disc"
local disc = include("gizmos/disc.lua")
---@module "arrow"
local arrow = include("gizmos/arrow.lua")
---@module "scale"
local scale = include("gizmos/scale.lua")
---@module "ball"
local ball = include("gizmos/ball.lua")
---@module "sidemove"
local sidemove = include("gizmos/sidemove.lua")
---@module "sidescale"
local sidescale = include("gizmos/sidescale.lua")

local MAX_BONE_SIZE = RagdollPoser.Constants.MAX_BONE_SIZE
local OUTLINE_WIDTH = 1
local BLACK = Color(0, 0, 0, 255)
local FLOAT_1DIVIDE540 = 0.00185185185

---@class RagdollPoser.Gizmo
local MGR = {
	_pos = Vector(),
	_ang = Angle(),
	_scale = 30,
	_width = 0.25,
	_offset = Vector(),

	_linePositions = {
		Vector(0, 1, 1),
		Vector(0, -1, 1),
		Vector(0, -1, -1),
		Vector(0, 1, -1),
	},

	_moving = false,
	_enabled = true,

	_directions = {},
}

---@enum GizmoMode
MGR.Mode = {
	Translation = 0,
	Rotation = 1,
	Scale = 2,
}

---@type {[GizmoMode]: fun(): GizmoBase}
local modeToInitializer = {
	[MGR.Mode.Translation] = arrow,
	[MGR.Mode.Rotation] = disc,
	[MGR.Mode.Scale] = scale,
}

---@type {[GizmoMode]: fun(): GizmoBase}
local modeToInitializerSide = {
	[MGR.Mode.Translation] = sidemove,
	[MGR.Mode.Scale] = sidescale,
}

---@param mode GizmoMode
function MGR:OnModeChanged(mode)
	self._directions = {}
	for i = 1, 3 do
		local v = Vector()
		v[i] = 1
		self._directions[i] = modeToInitializer[mode](v)
	end
	if mode == self.Mode.Rotation then
		-- Big disc
		self._directions[4] = disc()
		self._directions[5] = ball()
	elseif mode == self.Mode.Scale or mode == self.Mode.Translation then
		for i = 4, 6 do
			local v = Vector()
			v[i - 3] = 1
			self._directions[i] = modeToInitializerSide[mode](v)
		end
	end
end

---@param pos Vector
function MGR:SetPosition(pos)
	self._pos = pos
end

function MGR:IsMoving()
	return self._moving
end

function MGR:IsEnabled()
	return self._enabled
end

function MGR:SetEnabled(enabled)
	self._enabled = enabled
end

RagdollPoser.Networking.SendSubPose = RagdollPoser.Networking.DefineSender("SendSubPose")
RagdollPoser.Networking.SendSubPose2 = RagdollPoser.Networking.DefineSender("SendSubPose2")

local mat = Matrix()

local GREEN = Color(0, 255, 0, 255)
local YELLOW = Color(255, 255, 0, 255)

local showBones = false
-- Make sure you are in the 2D rendering context
function MGR:DrawBones()
	-- Add key pressed hook in input function
	if LocalPlayer():KeyPressed(IN_WALK) then
		showBones = not showBones
		self:SetEnabled(not showBones)
		RagdollPoser.Selection:SetEnabled(showBones)
	end

	local mouseHovered = {}

	if showBones then
		local ents = RagdollPoser.Entity.GetClientEntities()
		for _, ent in ipairs(ents) do
			if not IsValid(ent) then
				continue
			end

			table.insert(mouseHovered, ent)
			for b = 0, ent:GetBoneCount() - 1 do
				local name = ent:GetBoneName(b)
				-- TODO: Get invisible bones (e.g. weapon_bone)
				if name == "__INVALIDBONE__" then
					continue
				end

				ent:CopyBoneMatrix(b, mat)
				local p = mat:GetTranslation()
				local data = p:ToScreen()
				if not data.visible then
					continue
				end
				local tx, ty = data.x, data.y
				local x, y = input.GetCursorPos()
				local color = GREEN
				if RagdollPoser.Selection:RaycastBone(x, y, tx, ty) then
					color = YELLOW
					table.insert(mouseHovered, b)
				end

				-- TODO: Categorize based on bone type
				surface.DrawCircle(tx, ty, MAX_BONE_SIZE, color)
			end
		end
	end

	return mouseHovered
end

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)

-- Make sure you are in the 3D rendering context
function MGR:Draw()
	if not self:IsEnabled() then
		return
	end

	-- print(self._pos)
	if self._pos then
		render.SetColorMaterialIgnoreZ()
		render.CullMode(MATERIAL_CULLMODE_NONE)
		render.DrawBox(self._pos, self._ang, tempMin, tempMax)
		-- drawQuad(linepos, mat, RED, self._pos, self._ang:Forward(), self._scale, self._width)
		-- drawQuad(linepos, mat, GREEN, self._pos, -self._ang:Right(), self._scale, self._width)
		-- drawQuad(linepos, mat, BLUE, self._pos, self._ang:Up(), self._scale, self._width)
		render.CullMode(MATERIAL_CULLMODE_CCW)
	end
end

---@type InputCallback
local function onLeftClickDown(x, y, tr)
	-- If we're not accepting drag selections, then don't do anything
	if not MGR:IsMoving() and checkGizmo then
		-- Click on gizmo and do stuff
	end
end
local function onLeftClickUp(x, y, tr)
	if MGR:IsMoving() and checkGizmo then
		-- After doing stuff, apply final transforms, send to server
	end
end
hook.Add("RagdollPoser_Input_LeftClickDown", "Gizmo", onLeftClickDown)
hook.Add("RagdollPoser_Input_LeftClickUp", "Gizmo", onLeftClickUp)

local hovered = {}
hook.Add("RagdollPoser_Selection_Hover", "Gizmo", function(bone, entity)
	hovered = {}
	hovered[entity] = bone
end)

local BLUE = Color(0, 0, 255, 255)
local hoverMat = Matrix()
function MGR:DrawHovered()
	for entity, bone in pairs(hovered) do
		entity:CopyBoneMatrix(bone, hoverMat)
		local p = hoverMat:GetTranslation()
		local data = p:ToScreen()
		if not data.visible then
			continue
		end
		local tx, ty = data.x, data.y
		local color = BLUE

		-- TODO: Categorize based on bone type
		surface.DrawCircle(tx, ty, MAX_BONE_SIZE, color)
	end
end

function MGR:DrawSelected()
	local selection = RagdollPoser.Selection:GetSelection()
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]
		local matrix = entity:GetBoneMatrix(bone)
		local data = matrix:GetTranslation():ToScreen()
		if not data.visible then
			continue
		end
		surface.DrawCircle(data.x, data.y, MAX_BONE_SIZE, YELLOW)
	end
end

---@param mouseHovered Entity[]|integer[]
function MGR:DrawBoneNames(mouseHovered)
	local targetEntity = NULL
	local mx, my = input.GetCursorPos()

	local maxItemsPerColumn = 257 * (RGPFontSize + 3)
	local scrH = ScrH() - 100 -- Some padding to keep the bones centered
	local columns = 0

	local midw, midh = ScrW() / 2, ScrH() / 2
	local meanNameLength = 0
	-- Assume default font is about this wide
	local fontWidth = 7.5 * FLOAT_1DIVIDE540 * midh
	if fontWidth < 6.5 then
		fontWidth = 6.5
	end
	for i = 1, #mouseHovered do
		local entry = mouseHovered[i]
		if isentity(entry) then
			targetEntity = entry
		elseif IsValid(targetEntity) then
			---@cast entry integer
			meanNameLength = meanNameLength + #targetEntity:GetBoneName(entry) * fontWidth
		end
	end

	local j = 0
	for i = 1, #mouseHovered do
		local entry = mouseHovered[i]
		local nextEntry = mouseHovered[i + 1]
		local shouldIncrement = isnumber(entry) or isnumber(nextEntry)

		if shouldIncrement then
			j = j + 1
		end

		-- List the selected bones. If they attempt to overflow through the screen, add the items to another column.
		local yPos = my + (j % maxItemsPerColumn) * (RGPFontSize + 3)
		local xPos = mx + 5 + meanNameLength * columns
		if yPos > scrH then
			maxItemsPerColumn = j + 1
		end
		if j > 1 and j % maxItemsPerColumn == 0 then
			columns = columns + 1
			xPos = mx + 5 + meanNameLength * columns
		end

		if isentity(entry) then
			targetEntity = mouseHovered[i]
			if isnumber(mouseHovered[i + 1]) then
				draw.SimpleTextOutlined(
					targetEntity:GetModel(),
					"RagdollPoserHeaderFont",
					xPos,
					yPos,
					GREEN,
					TEXT_ALIGN_LEFT,
					TEXT_ALIGN_BOTTOM,
					OUTLINE_WIDTH,
					BLACK
				)
			end
		elseif IsValid(targetEntity) then
			---@cast entry integer
			local boneName = targetEntity:GetBoneName(entry)

			draw.SimpleTextOutlined(
				boneName,
				"RagdollPoserFont",
				xPos,
				yPos,
				GREEN,
				TEXT_ALIGN_LEFT,
				TEXT_ALIGN_BOTTOM,
				OUTLINE_WIDTH,
				BLACK
			)
		end
	end
end

function MGR:Render()
	cam.Start2D()
	local mouseHovered = self:DrawBones()
	self:DrawBoneNames(mouseHovered)
	self:DrawSelected()
	self:DrawHovered()
	cam.End2D()

	cam.Start3D()
	self:Draw()
	cam.End3D()

	-- Draw selected bone
end

---@param selection table
local function setPositionFromSelection(selection)
	local pos = Vector()

	PrintTable(selection)
	local count = #selection * 0.5
	for i = 1, #selection - 1, 2 do
		local bone = selection[i]
		local entity = selection[i + 1]
		---@cast bone integer
		---@cast entity Entity
		local matrix = entity:GetBoneMatrix(bone)

		if matrix then
			pos:Add(matrix:GetTranslation())
		end
	end
	pos:Div(count)
	MGR:SetPosition(pos)
end

hook.Add("RagdollPoser_Selection_Selected", "Gizmo", function(selection)
	setPositionFromSelection(selection)
	MGR:SetEnabled(true)
	RagdollPoser.Selection:SetEnabled(false)
	showBones = false
	hovered = {}
end)

hook.Add("RagdollPoser_Entity_PostRefresh", "Gizmo", function()
	-- FIXME: I would like to have this run after I get the new client entities. Just doing things these way is really hacky
	-- unless we have hook priorities
	timer.Simple(0, function()
		setPositionFromSelection(RagdollPoser.Selection:GetSelection())
	end)
end)

RagdollPoser.Gizmo = MGR
