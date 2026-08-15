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
		sensitivity = 1,
		---@type GizmoOrientation
		orientation = 0,
	},

	_moving = false,
	_enabled = true,

	---@type GizmoBase[]
	_directions = {},
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

---@param selection table
local function setAngleFromSelection(selection)
	local count = #selection
	local bone, entity = selection[count - 1], selection[count]
	local matrix = entity:GetBoneMatrix(bone)
	if matrix then
		MGR:SetAngles(matrix:GetAngles())
	end
end

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

function MGR:UpdateOrientation()
	local props = self._gizmoProps
	local orientation = props.orientation
	for _, direction in ipairs(self._directions) do
		direction:UpdateOrientation(orientation, props)
	end
end

---@param mode GizmoMode
function MGR:OnModeChanged(mode)
	self._directions = {}

	for i = 1, 3 do
		local v = Vector()
		v[i] = 1
		local gizmoType = modeToInitializer[mode](v)

		self._directions[i] = gizmoType
	end
	if mode == self.Mode.Rotation then
		-- Big disc

		local disc, ball = disc(), ball()
		self._directions[4] = disc
		self._directions[5] = ball
	elseif mode == self.Mode.Scale or mode == self.Mode.Translation then
		for i = 4, 6 do
			local v = Vector()
			v[i - 3] = 1
			local gizmoType = modeToInitializerSide[mode](v)
			self._directions[i] = gizmoType
		end
	end
	self:UpdateOrientation()
end

function MGR:CycleMode()
	self._mode = (self._mode + 1) % numModes
	return self._mode
end

---@param pos Vector
function MGR:SetPosition(pos)
	self._gizmoProps.pos = pos
end

---@param ang Angle
function MGR:SetAngles(ang)
	self._gizmoProps.ang = ang
	self:UpdateOrientation()
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

local entityBuffer = {}

---@type NetReceiver
local function sendSubPoseResponse()
	for _, entity in ipairs(entityBuffer) do
		RagdollPoser.Entity.UpdateRenderBounds(entity)
	end
	entityBuffer = {}

	local selection = RagdollPoser.Selection:GetSelection()
	setPositionFromSelection(selection)
	setAngleFromSelection(selection)
end
RagdollPoser.Networking.DefineReceiver("SendSubPoseResponse", sendSubPoseResponse)

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
			direction:Draw(props, true)
		else
			local selected = false
			for _, direction in ipairs(self._directions) do
				local hitPos = direction:Intersect(eyepos, eyevec, props)
				direction:Draw(props, not selected and hitPos ~= nil)
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

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

function MGR:PreTransform()
	-- Get an initial copy of the entity matrices

	print("pretransform")

	local selection = RagdollPoser.Selection:GetSelection()
	---@param entity Entity
	---@param matrices VMatrix[]
	---@param bone integer
	---@param store VMatrix[]
	---@param storeLocal {[integer]: VMatrix}
	---@param indexer integer[]
	---@param parents {[integer]: integer}
	local function recursiveMatrixCopy(entity, matrices, bone, store, storeLocal, indexer, parents)
		local m = matrices[bone + 1]
		if m then
			-- copy the matrix
			indexer[bone] = table.insert(store, m * IDENTITY_MATRIX)
		end
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			recursiveMatrixCopy(entity, matrices, childBone, store, storeLocal, indexer, parents)
			local childMatrix = matrices[childBone + 1]
			if childMatrix and m then
				storeLocal[childBone] = m:GetInverse() * childMatrix
				parents[childBone] = bone
			end
		end
	end
	-- TODO: Maybe simplify the tables used below for doing transforms?
	-- There could be a simpler, possibly more performant way to doing things
	self._matrices = {}
	self._matrixIndex = {}
	self._localMatrices = {}
	self._parents = {}
	self._accumulations = {}

	-- Collection of bones per entity, starting from the selected root bone index to the selected descendant bone index
	local entityBones = {}
	---@type {[Entity]: {[integer]: integer}}
	local entityBoneSet = {}

	-- First, we need to select all bones and do our iteration with the root first, and then the descendants, for each entity
	-- After we do that, then we can copy our matrices over. Then what will happen is that we process the root matrices first,
	-- and then the descendant matrices
	-- Problem, bone selections are not ordered. We need to figure out the order using the client bone hierarchy
	for i = 1, #selection - 1, 2 do
		local bone, client = selection[i], selection[i + 1]
		---@cast bone integer
		---@cast client ClientEntity
		entityBones[client] = entityBones[client] or {}
		entityBoneSet[client] = entityBoneSet[client] or {}
		entityBoneSet[client][bone] = 0
	end

	for i = 1, #selection - 1, 2 do
		local bone, client = selection[i], selection[i + 1]
		local tree = RagdollPoser.Entity.GetDefaultPoseTreeFor(client)

		local count = 0
		local walk = bone
		while tree[walk + 1] do
			if entityBoneSet[client][walk] then
				count = count + 1
			end
			walk = tree[walk + 1][5]
		end
		entityBoneSet[client][bone] = count
	end
	-- sort entity bone set per client by number of bones
	for client, bones in pairs(entityBoneSet) do
		for bone, count in SortedPairsByValue(bones) do
			table.insert(entityBones[client], bone)
		end
		-- PrintTable(entityBones[client])
	end

	-- iterate over every selected bone in order from root bone to descendant bone
	-- and get their matrices
	for client, bones in pairs(entityBones) do
		local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
		if matrices then
			self._matrices[client] = self._matrices[client] or {}
			self._matrixIndex[client] = self._matrixIndex[client] or {}
			self._localMatrices[client] = self._localMatrices[client] or {}
			self._parents[client] = self._parents[client] or {}
			for _, bone in ipairs(bones) do
				self._matrices[client][bone] = self._matrices[client][bone] or {}
				self._matrixIndex[client][bone] = self._matrixIndex[client][bone] or {}
				self._localMatrices[client][bone] = self._localMatrices[client][bone] or {}
				recursiveMatrixCopy(
					client,
					matrices,
					bone,
					self._matrices[client][bone],
					self._localMatrices[client][bone],
					self._matrixIndex[client][bone],
					self._parents[client]
				)
				self._matrixIndex[client][bone] = table.Flip(self._matrixIndex[client][bone])
			end
		end
	end

	local gizmo = self._directions[self._gizmoIndex]
	local props = self._gizmoProps

	-- After getting our entity matrices, we need to calculate the directions which we do the transform
	self._pivots = { gizmo:GetDirection(props) }

	-- Check gizmo pivot
	if self._pivot == self.Pivot.Individual then
		if props.orientation == self.Orientation.Local then
			-- We need to get a bunch of direction vectors, using the direction we passed to move bones individually on their own axes
			-- or to rotate them on their own axes
			-- So iterate over all selected bones to get their local, individual directions
		end
	else
		if props.orientation == self.Orientation.World then
		end
	end

	for i, pivot in ipairs(self._pivots) do
		self._pivots[i] = gizmo:PreTransform(pivot)
		self._accumulations[i] = 0
	end

	-- Also operate with entity matrices for the mirrored bones, using the same settings for the above, except
	-- these must be relative to where the entity is facing
	-- The desired mirror plane might not be the same for all models, so we'll give the option to change the mirror plane so we get proper
	-- mirroring for every model
	if self._mirror then
		-- TODO: add mirror operations
	end

	local x, y = input.GetCursorPos()
	self.start = gui.ScreenToVector(x, y)
end

function MGR:Transform()
	local x, y = input.GetCursorPos()
	local newPoint = gui.ScreenToVector(x, y)
	self.delta = newPoint - self.start

	local gizmo = self._directions[self._gizmoIndex]
	if gizmo then
		local selection = RagdollPoser.Selection:GetSelection()
		for i = 1, #selection - 1, 2 do
			local bone, client = selection[i], selection[i + 1]
			gizmo:Transform(
				self._pivots,
				self.start,
				newPoint,
				self._matrices[client][bone],
				self._accumulations,
				self._gizmoProps
			)
			gizmo:PostTransform(
				self._matrices[client][bone],
				self._localMatrices[client][bone],
				self._matrixIndex[client][bone],
				self._parents[client]
			)

			local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)

			if matrices then
				for b, indices in pairs(self._matrixIndex[client]) do
					for index, bb in ipairs(indices) do
						local targetMatrix = matrices[bb + 1]
						if targetMatrix then
							targetMatrix:Set(self._matrices[client][b][index])
						end
					end
				end
			end
		end
	end

	-- PrintTable(self._localMatrices)
	-- After caching our directions,
	-- Do transform to initial copy, and apply new transform to
	-- entity matrices so that we see the effect on the ghost client entity
	self.start = newPoint
end

local function doTransform()
	-- FIXME: Make this not run while we are holstering
	-- We can also just disable the input system when we are holstering, to prevent the left-click event altogether
	local equipped = RagdollPoser.Helpers.Equipped()
	if equipped and MGR:IsMoving() then
		MGR:Transform()
	end
end

-- HACK: using 2 hooks to get mouse input from locked and unlocked cursor states
hook.Remove("Think", "RagdollPoser_Gizmo_Transform")
hook.Add("Think", "RagdollPoser_Gizmo_Transform", doTransform)
hook.Remove("InputMouseApply", "RagdollPoser_Gizmo_Transform")
hook.Add("InputMouseApply", "RagdollPoser_Gizmo_Transform", doTransform)

local boneMatrix = Matrix()

-- TODO: Do a server acknowledge step so that the server only accepts poses that we send from here, not from
-- anywhere else
local function sendSubPose(selection)
	-- Selection structure
	-- Entity A
	-- Bones
	-- Matrix
	-- Entity B
	-- ...

	---@type Entity[]
	local entities = entityBuffer
	---@type {[Entity]: integer[]}
	local bones = {}
	---@type {[Entity]: {[integer]: true}}
	local boneSet = {}

	---@param entity Entity
	---@param bone integer
	local function addChildBones(entity, bone, arr, set)
		table.insert(arr, bone)
		set[bone] = true
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			if not set[childBone] then
				addChildBones(entity, childBone, arr, set)
			end
		end
	end

	for i = 1, #selection - 1, 2 do
		local bone = selection[i]
		local client = selection[i + 1]
		local entity = RagdollPoser.Entity.GetEntityFromClient(client)

		local arr = bones[entity]
		local set = boneSet[entity]
		if not bones[entity] then
			arr = {}
			set = {}
			bones[entity] = arr
			boneSet[entity] = set
			table.insert(entities, entity)
		end

		if not set[bone] then
			addChildBones(entity, bone, arr, set)
		end
	end

	RagdollPoser.Networking.SendSubPose()
	net.WriteUInt(#entities, 13)
	for _, entity in ipairs(entities) do
		net.WriteEntity(entity)
		local matrices = RagdollPoser.Entity.GetMatrices(entity)
		local bs = bones[entity]
		local count = #bs
		net.WriteUInt(count, 8)
		for _, b in ipairs(bs) do
			net.WriteUInt(b, 8)
			local matrix = matrices[b + 1]

			local physbone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
			if physbone >= 0 then
				-- Send world transforms and everything
				net.WriteMatrix(matrix)
			else
				RagdollPoser.Helpers.GetNonPhysicalBonePose(
					RagdollPoser.Entity.GetClientFromEntity(entity),
					b,
					boneMatrix
				)
				boneMatrix:SetScale(matrix:GetScale())
				net.WriteMatrix(boneMatrix)
			end
		end
	end
	net.SendToServer()
end

function MGR:PostTransform()
	local gizmo = self._directions[self._gizmoIndex]
	if gizmo then
		gizmo:FinishTransform()
	end

	local selection = RagdollPoser.Selection:GetSelection()

	sendSubPose(selection)
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

hook.Add("RagdollPoser_Selection_Selected", "Gizmo", function(selection)
	setPositionFromSelection(selection)
	setAngleFromSelection(selection)
	MGR:SetEnabled(true)
	RagdollPoser.Selection:SetEnabled(false)
	hovered = {}
end)

hook.Add("RagdollPoser_Entity_PostRefresh", "Gizmo", function()
	-- FIXME: I would like to have this run after I get the new client entities. Just doing things these way is really hacky
	-- unless we have hook priorities
	timer.Simple(0, function()
		local selection = RagdollPoser.Selection:GetSelection()
		setPositionFromSelection(selection)
		setAngleFromSelection(selection)
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
	MGR._gizmoProps.orientation = GetConVar("ragdollposer_local"):GetBool() and MGR.Orientation.Local
		or MGR.Orientation.World
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

local function updateOrientation(_, old, new)
	local newOrientation = tobool(new) and MGR.Orientation.Local or MGR.Orientation.World
	MGR._gizmoProps.orientation = newOrientation
	MGR:UpdateOrientation()
end
cvars.RemoveChangeCallback("ragdollposer_local", "ragdollposer_scale_callback")
cvars.AddChangeCallback("ragdollposer_local", updateOrientation, "ragdollposer_scale_callback")

RagdollPoser.Gizmo = MGR
