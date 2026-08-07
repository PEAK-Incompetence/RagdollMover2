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

---[CLIENT]
---
---Gizmo transform
---
---@class RagdollPoser.Gizmo
local MGR = {
	---@class GizmoProps
	_gizmoProps = {
		pos = Vector(),
		ang = Angle(),
		scale = 30,
		width = 0.25,
		offset = Vector(),
		partial = false,
	},

	_linePositions = {
		Vector(0, 1, 1),
		Vector(0, -1, 1),
		Vector(0, -1, -1),
		Vector(0, 1, -1),
	},

	_moving = false,
	_enabled = true,

	---@type GizmoBase[]
	_directions = {},
	---@type GizmoOrientation
	_orientation = 0,
	---@type GizmoMode
	_mode = 0,
	---@type GizmoPivot
	_pivot = 0,

	_mirror = false,
	---@type integer
	_gizmoIndex = 0,
	---@type Vector[]
	_intersections = {},

	---All the matrices that we are interested in. We start at the selected bone as our matrix,
	---and then we go down the bone hierarchy and get all matrices to transform.
	---If we also have selected bone matrices as our descendants from the root bone, first transform
	---the root bone, then transform the descendant bones
	---@type VMatrix[]
	_matrices = {},
	---Matrices local to parent matrices. Useful for transforms
	---@type {[integer]: VMatrix}
	_localMatrices = {},
	---@type Vector[]
	_pivots = {},
}

---How the gizmo is rotated when selecting a bone
---@enum GizmoOrientation
MGR.Orientation = {
	World = 0, -- no orientation
	Local = 1, -- oriented to bone
}

---The point relative to where transforms occur; useful for multiple bones
---@enum GizmoPivot
MGR.Pivot = {
	Median = 0,
	Bounding = 1,
	Individual = 2,
}

---@enum GizmoMode
MGR.Mode = {
	Translation = 0,
	Rotation = 1,
	Scale = 2,
}

local numModes = table.Count(MGR.Mode)

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

function MGR:SetWidth(width)
	self._gizmoProps.width = width
end

function MGR:SetScale(scale)
	self._gizmoProps.scale = scale
end

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
	PrintTable(self._directions)
end

function MGR:CycleMode()
	self._mode = (self._mode + 1) % numModes
	return self._mode
end

---@param pos Vector
function MGR:SetPosition(pos)
	self._gizmoProps.pos = pos
end

---@param state boolean
function MGR:SetMoving(state)
	self._moving = state
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

-- Instead of creating a matrix with `GetMatrix`, copy the values
-- to this one, to reduce garbace collection cycles
local mat = Matrix()

local GREEN = Color(0, 255, 0, 255)
local YELLOW = Color(255, 255, 0, 255)

-- Make sure you are in the 2D rendering context
function MGR:DrawBones()
	local mouseHovered = {}

	if RagdollPoser.Selection:GetEnabled() then
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

	local props = self._gizmoProps

	-- print(self._pos)
	if props.pos then
		-- render.SetColorMaterialIgnoreZ()
		-- render.CullMode(MATERIAL_CULLMODE_NONE)
		-- render.DrawBox(props.pos, props.ang, tempMin, tempMax)
		local eyepos, eyevec, eyeang = RagdollPoser.View:GetView()

		if self:IsMoving() then
			local direction = self._directions[self._gizmoIndex]
			direction:Draw(props, self._orientation, true)
		else
			local selected = false
			for _, direction in ipairs(self._directions) do
				local hitPos = direction:Intersect(eyepos, eyevec, props)
				direction:Draw(props, self._orientation, not selected and hitPos ~= nil)
			end
		end
	end
end

function MGR:TestIntersect()
	-- Gizmos don't have a sense of depth, so we need to measure the depth after collecting depth interests
	local eyepos, eyevec, eyeang = RagdollPoser.View:GetView()
	local directions = self._directions
	local intersections = self._intersections
	for i, direction in ipairs(directions) do
		intersections[i] = direction:Intersect(eyepos, eyevec, self._gizmoProps)
	end

	local min = math.min
	local targetIndex, closestDistance = 0, math.huge
	for i = 1, #directions do
		local hitpos = intersections[i]
		if hitpos then
			local distance = hitpos:LengthSqr()
			if distance < closestDistance then
				closestDistance = distance
				targetIndex = i
			end
		end
	end

	if targetIndex > 0 then
		self._gizmoIndex = targetIndex
		return true
	end

	return false
end

local IDENTITY_MATRIX = Matrix():Identity()

function MGR:PreTransform()
	-- Get an initial copy of the entity matrices
	print("pretransform")

	local selection = RagdollPoser.Selection:GetSelection()
	---@param entity Entity
	---@param matrices VMatrix[]
	---@param bone integer
	---@param store VMatrix[]
	---@param storeLocal {[integer]: VMatrix}
	local function recursiveMatrixCopy(entity, matrices, bone, store, storeLocal)
		local m = matrices[bone + 1]
		if m then
			-- copy the matrix
			table.insert(store, m * IDENTITY_MATRIX)
		end
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			recursiveMatrixCopy(entity, matrices, childBone, store, storeLocal)
			local childMatrix = matrices[childBone + 1]
			if childMatrix and m then
				storeLocal[childBone] = m:GetInverse() * childMatrix
			end
		end
	end

	---@param entity Entity
	---@param bone integer
	---@param bones integer[]
	local function recursiveBoneCopy(entity, bone, bones)
		table.insert(bones, bone)
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			recursiveBoneCopy(entity, childBone, bones)
		end
	end

	self._matrices = {}
	self._localMatrices = {}

	-- Collection of bones per entity, starting from the selected root bone index to the selected descendant bone index
	---@type {[Entity]: integer[]}
	local entityBones = {}
	---@type {[Entity]: {[integer]: true}}
	local entityBoneSet = {}

	-- First, we need to select all bones and do our iteration with the root first, and then the descendants, for each entity
	-- After we do that, then we can copy our matrices over. Then what will happen is that we process the root matrices first,
	-- and then the descendant matrices
	for i = 1, #selection - 1, 2 do
		local bone, client = selection[i], selection[i + 1]
		entityBones[client] = entityBones[client] or {}
		entityBoneSet[client] = entityBoneSet[client] or {}
		local walk = bone

		local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
		if matrices then
			recursiveMatrixCopy(client, matrices, bone, self._matrices, self._localMatrices)
		end
	end

	-- After getting our entity matrices, we need to calculate the directions which we do the transform
	self._pivots = { self._directions[self._gizmoIndex]:GetDirection() }

	-- Check gizmo pivot
	if self._pivot == self.Pivot.Individual then
		if self._orientation == self.Orientation.Local then
			-- We need to get a bunch of direction vectors, using the direction we passed to move bones individually on their own axes
			-- or to rotate them on their own axes
			-- So iterate over all selected bones to get their local, individual directions
		end
	end

	-- Also operate with entity matrices for the mirrored bones, using the same settings for the above, except
	-- these must be relative to where the entity is facing
	-- The desired mirror plane might not be the same for all models, so we'll give the option to change the mirror plane so we get proper
	-- mirroring for every model
	if self._mirror then
		-- TODO: add mirror operations
	end
end

function MGR:Transform()
	local gizmo = self._directions[self._gizmoIndex]
	if gizmo then
		gizmo:Transform(self._pivots, delta, self._matrices, locals)
	end

	PrintTable(self._localMatrices)
	-- After caching our directions,
	-- Do transform to initial copy, and apply new transform to
	-- entity matrices so that we see the effect on the ghost client entity
	print("transform!")
end

local function doTransform()
	if MGR:IsMoving() then
		MGR:Transform()
	end
end
hook.Add("Think", "RagdollPoser_Gizmo_Transform", doTransform)

function MGR:PostTransform()
	-- Set entity matrices
	print("post transform!")
end

---@type InputCallback
local function onLeftClickDown(x, y, tr)
	-- If we're not accepting drag selections, then don't do anything
	if not MGR:IsMoving() and MGR:TestIntersect() then
		-- Click on gizmo and do stuff
		MGR:SetMoving(true)
		MGR:PreTransform()
	end
end
local function onLeftClickUp(x, y, tr)
	if MGR:IsMoving() then
		-- After doing stuff, apply final transforms, send to server
		MGR:SetMoving(false)
		MGR:PostTransform()
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
	hovered = {}
end)

hook.Add("RagdollPoser_Entity_PostRefresh", "Gizmo", function()
	-- FIXME: I would like to have this run after I get the new client entities. Just doing things these way is really hacky
	-- unless we have hook priorities
	timer.Simple(0, function()
		setPositionFromSelection(RagdollPoser.Selection:GetSelection())
	end)
end)

local function onKeyPress(action)
	if action == RagdollPoser.Actions.CycleGizmo then
		MGR:OnModeChanged(MGR:CycleMode())
	elseif action == RagdollPoser.Actions.SelectBone then
		MGR:SetEnabled(not MGR:IsEnabled())
		RagdollPoser.Selection:SetEnabled(not MGR:IsEnabled())
	end
end
hook.Add("RagdollPoser_Input_KeyPress", "Gizmo", onKeyPress)

local function initializeGizmo()
	MGR._gizmoProps.scale = GetConVar("ragdollposer_scale"):GetFloat()
	MGR._gizmoProps.width = GetConVar("ragdollposer_width"):GetFloat()
	MGR._gizmoProps.partial = GetConVar("ragdollposer_partial"):GetBool()
	hook.Remove("CreateMove", "RagdollPoser_InitializeGizmo")
end
hook.Remove("CreateMove", "RagdollPoser_InitializeGizmo")
hook.Add("CreateMove", "RagdollPoser_InitializeGizmo", initializeGizmo)

local function updateWidth(_, old, new)
	local result = tonumber(new)
	if result then
		MGR:SetWidth(result)
	end
end
cvars.RemoveChangeCallback("ragdollposer_width", "ragdollposer_width_callback")
cvars.AddChangeCallback("ragdollposer_width", updateWidth, "ragdollposer_width_callback")
local function updateScale(_, old, new)
	local result = tonumber(new)
	if result then
		MGR:SetScale(result)
	end
end
cvars.RemoveChangeCallback("ragdollposer_scale", "ragdollposer_scale_callback")
cvars.AddChangeCallback("ragdollposer_scale", updateScale, "ragdollposer_scale_callback")

RagdollPoser.Gizmo = MGR
