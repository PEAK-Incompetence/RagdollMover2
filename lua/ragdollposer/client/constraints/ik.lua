-- Vibecoded the Jacobian IK Solver with GPT-6 Luna
-- It works surprisingly well

---@class IKConstraint: Constraint
---@field State IKConstraintState
local ik = include("base.lua")

local MAX_ITERATIONS = 64
local POSITION_EPSILON = 0.25
local DAMPING = 0.15
local MAX_STEP = math.rad(8)
local MAX_REACH_FRACTION = 0.98
local LINE_COLOR = Color(0, 220, 255, 255)
local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

ik.Properties = {
	type = "ik",
	category = "#tool.ragdollposer.constraint.category.tracking",
	name = "#tool.ragdollposer.constraint.ik.name",
	desc = "#tool.ragdollposer.constraint.ik.desc",
	help = "#tool.ragdollposer.constraint.ik.help",
}

---@class IKConstraintState: ConstraintState
---@field iterations integer
---@field length integer Number of parent links above the end effector
---@field offset Vector World-space end-effector offset
---@field weightPosition boolean
---@field weightPositionValue number
---@field weightRotation boolean
---@field weightRotationValue number
---@field weightRotationConfigured boolean?
ik.State = table.Merge(table.Copy(ik.State), {
	iterations = 32,
	length = 2,
	offset = Vector(),
	weightPosition = true,
	weightPositionValue = 1,
	weightRotation = true,
	weightRotationValue = 1,
})

local function makeChain(entity, effector, parentLinks)
	local chain = {}
	local bone = effector

	for _ = 0, parentLinks do
		if bone < 0 then
			break
		end
		chain[#chain + 1] = bone
		bone = entity:GetBoneParent(bone)
	end

	return chain
end

local function isDescendant(entity, bone, ancestor)
	local walk = bone
	while walk and walk >= 0 do
		if walk == ancestor then
			return true
		end
		walk = entity:GetBoneParent(walk)
	end
	return false
end

local function applyJointRotation(transforms, subtree, jointBone, axis, degrees)
	if math.abs(degrees) < 1e-5 then
		return
	end

	local jointMatrix = transforms[jointBone + 1]
	if not jointMatrix then
		return
	end

	axis:Normalize()
	local pivot = jointMatrix:GetTranslation()
	local rotation = Angle(0, 0, 0)
	rotation:RotateAroundAxis(axis, degrees)

	for _, matrixIndex in ipairs(subtree) do
		local matrix = transforms[matrixIndex]
		if matrix then
			local position = matrix:GetTranslation()
			local relative = position - pivot
			relative:Rotate(rotation)
			matrix:SetTranslation(pivot + relative)

			local angles = matrix:GetAngles()
			angles:RotateAroundAxis(axis, degrees)
			matrix:SetAngles(angles)
		end
	end
end

local function solveSymmetric3(a, b, c, rhs)
	local crossBC = b:Cross(c)
	local determinant = a:Dot(crossBC)
	if math.abs(determinant) < 1e-10 then
		return nil
	end

	return Vector(rhs:Dot(crossBC) / determinant, rhs:Dot(c:Cross(a)) / determinant, rhs:Dot(a:Cross(b)) / determinant)
end

local function solvePosition(entity, transforms, chain, goal, iterations, influence)
	local endEffector = chain[1]
	local effectorMatrix = transforms[endEffector + 1]
	if not effectorMatrix then
		return
	end

	local maxReach = 0
	for chainIndex = 1, #chain - 1 do
		local child = transforms[chain[chainIndex] + 1]
		local parent = transforms[chain[chainIndex + 1] + 1]
		if child and parent then
			maxReach = maxReach + child:GetTranslation():Distance(parent:GetTranslation())
		end
	end
	local rootMatrix = transforms[chain[#chain] + 1]
	if maxReach > 0 then
		local rootPosition = rootMatrix:GetTranslation()
		local goalOffset = goal - rootPosition
		local goalDistance = goalOffset:Length()
		local reachableDistance = maxReach * MAX_REACH_FRACTION
		if goalDistance > reachableDistance then
			goal = rootPosition + goalOffset * (reachableDistance / goalDistance)
		end
	end

	local subtrees = {}
	for chainIndex = 2, #chain do
		local joint = chain[chainIndex]
		local subtree = {}
		for bone = 0, entity:GetBoneCount() - 1 do
			local matrixIndex = bone + 1
			if isDescendant(entity, bone, joint) then
				subtree[#subtree + 1] = matrixIndex
			end
		end
		subtrees[joint] = subtree
	end

	for _ = 1, iterations do
		effectorMatrix = transforms[endEffector + 1]
		local error = goal - effectorMatrix:GetTranslation()
		if error:LengthSqr() <= POSITION_EPSILON * POSITION_EPSILON then
			break
		end

		local columns = {}
		local xx, xy, xz, yy, yz, zz = 0, 0, 0, 0, 0, 0

		for chainIndex = 2, #chain do
			local joint = chain[chainIndex]
			local jointMatrix = transforms[joint + 1]
			if jointMatrix then
				local pivot = jointMatrix:GetTranslation()
				local offset = effectorMatrix:GetTranslation() - pivot
				local axes = {
					jointMatrix:GetForward(),
					jointMatrix:GetRight(),
					jointMatrix:GetUp(),
				}

				for _, axis in ipairs(axes) do
					axis:Normalize()
					local column = axis:Cross(offset)
					columns[#columns + 1] = {
						bone = joint,
						axis = axis,
						column = column,
					}
					xx = xx + column.x * column.x
					xy = xy + column.x * column.y
					xz = xz + column.x * column.z
					yy = yy + column.y * column.y
					yz = yz + column.y * column.z
					zz = zz + column.z * column.z
				end
			end
		end

		if #columns == 0 then
			break
		end

		local dampingSquared = DAMPING * DAMPING
		local response = solveSymmetric3(
			Vector(xx + dampingSquared, xy, xz),
			Vector(xy, yy + dampingSquared, yz),
			Vector(xz, yz, zz + dampingSquared),
			error
		)
		if not response then
			break
		end

		local updates, jointOrder = {}, {}
		for _, column in ipairs(columns) do
			local radians = column.column:Dot(response) * influence
			local update = updates[column.bone]
			if not update then
				update = { axis = Vector() }
				updates[column.bone] = update
				jointOrder[#jointOrder + 1] = column.bone
			end
			update.axis:Add(column.axis * radians)
		end

		for _, joint in ipairs(jointOrder) do
			local update = updates[joint]
			local radians = update.axis:Length()
			if radians > MAX_STEP then
				update.axis:Mul(MAX_STEP / radians)
				radians = MAX_STEP
			end
			if radians > 1e-5 then
				applyJointRotation(transforms, subtrees[joint], joint, update.axis, math.deg(radians))
			end
		end
	end
end

function ik:ConstructUI(entry, props, state)
	self.State.target = self.Owner
	entry.Header:SetTooltip("#tool.ragdollposer.constraint.ik.help")

	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, self.State)
	header()
	ui.target:SetEnabled(false)
	ui.target:SetTooltip("#tool.ragdollposer.constraint.ik.owner")

	ui.length = entry:NumSlider("#tool.ragdollposer.constraint.ik.length", "", 1, 16, 0)
	ui.length:SetValue(self.State.length)
	function ui.length.OnValueChanged(_, value)
		self.State.length = math.Clamp(math.Round(value), 1, 16)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	ui.iterations = entry:NumSlider("#tool.ragdollposer.constraint.ik.iterations", "", 1, MAX_ITERATIONS, 0)
	ui.iterations:SetValue(self.State.iterations)
	function ui.iterations.OnValueChanged(_, value)
		self.State.iterations = math.Clamp(math.Round(value), 1, MAX_ITERATIONS)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	self.State.offset = self.State.offset or Vector()
	for axis, label in ipairs({
		"#tool.ragdollposer.constraint.ik.offset.x",
		"#tool.ragdollposer.constraint.ik.offset.y",
		"#tool.ragdollposer.constraint.ik.offset.z",
	}) do
		local control = entry:NumSlider(label, "", -32, 32, 1)
		control:SetValue(self.State.offset[axis])
		control.OnValueChanged = function(_, value)
			self.State.offset[axis] = value
			RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
		end
		ui["offset" .. axis] = control
	end

	ui.weightPosition = entry:NumSlider("#tool.ragdollposer.constraint.ik.positionweight", "", 0, 1, 2)
	ui.weightPosition:SetValue(self.State.weightPositionValue or 1)
	function ui.weightPosition.OnValueChanged(_, value)
		self.State.weightPositionValue = value
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	ui.weightRotation = vgui.Create("DCheckBoxLabel", entry)
	ui.weightRotation:SetText(language.GetPhrase("#tool.ragdollposer.constraint.ik.rotationweight"))
	ui.weightRotation:SetChecked(self.State.weightRotation ~= false)
	ui.weightRotation:SizeToContents()
	function ui.weightRotation.OnChange(_, enabled)
		self.State.weightRotation = enabled
		self.State.weightRotationConfigured = true
		ui.rotationWeight:SetEnabled(enabled)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end
	entry:AddItem(ui.weightRotation)

	ui.rotationWeight = entry:NumSlider("#tool.ragdollposer.constraint.ik.rotationweight.value", "", 0, 1, 2)
	ui.rotationWeight:SetValue(self.State.weightRotationValue or 1)
	ui.rotationWeight:SetEnabled(self.State.weightRotation ~= false)
	function ui.rotationWeight.OnValueChanged(_, value)
		self.State.weightRotationValue = value
		self.State.weightRotationConfigured = true
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	footer()
end

function ik:PreEvaluate(entity, transforms, indices, locals, parents)
	self._goal = nil
	self._poseLocals = nil
	self._effectorLocal = nil
	self._effectorAngles = nil

	if
		self.State.enabled == false
		or entity ~= self.Owner
		or self.State.target ~= self.Owner
		or self.State.weightPosition == false
		or not IsValid(entity)
	then
		return
	end

	local effector = self.State.bone
	local client = RagdollPoser.Entity.GetClientFromEntity(entity)
	if not IsValid(client) or not isnumber(effector) or effector < 0 or effector >= client:GetBoneCount() then
		return
	end

	RagdollPoser.Entity.ExposeBones(client)
	local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
	local matrix = matrices and matrices[effector + 1]
	if not matrix then
		return
	end

	local offset = self.State.offset or vector_origin
	self._goal = matrix:GetTranslation() + offset
	self._effectorAngles = matrix:GetAngles()
	self._poseLocals = {}
	for bone = 0, client:GetBoneCount() - 1 do
		local parent = client:GetBoneParent(bone)
		local childMatrix = matrices[bone + 1]
		local parentMatrix = parent >= 0 and matrices[parent + 1]
		if childMatrix and parentMatrix then
			self._poseLocals[bone] = parentMatrix:GetInverse() * childMatrix
		end
	end
	if client:GetBoneParent(effector) >= 0 then
		self._effectorLocal = self._poseLocals[effector]
	else
		self._effectorLocal = matrix * IDENTITY_MATRIX
	end
end

function ik:EvaluatePose(entity, controlledBones, transforms)
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or entity ~= self.Owner
		or self.State.target ~= self.Owner
		or not self._goal
		or not self._poseLocals
		or not self._effectorLocal
		or not transforms
	then
		return
	end

	local client = RagdollPoser.Entity.GetClientFromEntity(entity)
	if not IsValid(client) then
		return
	end

	local effector = self.State.bone
	local effectorMatrix = transforms[effector + 1]
	if not effectorMatrix then
		return
	end

	-- TODO: Add support for moving locked bones with IKs and doing the IK stuff all at once
	local selectedEffector = false
	for _, bone in ipairs(controlledBones) do
		if bone == effector then
			selectedEffector = true
			break
		end
	end

	local offset = self.State.offset or vector_origin
	local goal = selectedEffector and (effectorMatrix:GetTranslation() + offset) or self._goal
	local chain = makeChain(client, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	if #chain < 2 then
		return
	end

	local influence = math.Clamp(self.State.influence or 1, 0, 1)
	influence = influence * math.Clamp(self.State.weightPositionValue or 1, 0, 1)
	if influence == 0 then
		return
	end

	local parent = client:GetBoneParent(effector)
	local effectorAngles = selectedEffector and effectorMatrix:GetAngles() or self._effectorAngles
	if parent >= 0 then
		local parentMatrix = transforms[parent + 1]
		if parentMatrix then
			local restored = parentMatrix * self._effectorLocal
			restored:SetAngles(effectorAngles)
			transforms[effector + 1] = restored
		end
	else
		local restored = self._effectorLocal * IDENTITY_MATRIX
		restored:SetAngles(effectorAngles)
		transforms[effector + 1] = restored
	end

	local function propagate(bone)
		local parentMatrix = transforms[bone + 1]
		if not parentMatrix then
			return
		end
		---@cast parentMatrix VMatrix
		for _, child in ipairs(client:GetChildBones(bone)) do
			local localMatrix = self._poseLocals[child]
			if localMatrix and transforms[child + 1] then
				transforms[child + 1] = parentMatrix * localMatrix
				propagate(child)
			end
		end
	end
	propagate(effector)

	local iterations = math.Clamp(math.floor(self.State.iterations or 32), 1, MAX_ITERATIONS)
	solvePosition(client, transforms, chain, goal, iterations, influence)

	local rotationInfluence = 0
	if self.State.weightRotation ~= false then
		rotationInfluence = math.Clamp(self.State.influence or 1, 0, 1)
			* math.Clamp(self.State.weightRotationValue or 1, 0, 1)
	end
	if rotationInfluence > 0 then
		effectorMatrix = transforms[effector + 1]
		if effectorMatrix then
			effectorMatrix:SetAngles(LerpAngle(rotationInfluence, effectorMatrix:GetAngles(), effectorAngles))
			propagate(effector)
		end
	end
end

function ik:GetOutputRoot()
	local effector = self.State.bone
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or self.State.target ~= self.Owner
		or not IsValid(self.Owner)
		or not isnumber(effector)
		or effector < 0
		or effector >= self.Owner:GetBoneCount()
	then
		return nil
	end

	local chain = makeChain(self.Owner, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	return chain[#chain]
end

function ik:Draw()
	local effector = self.State.bone
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or self.State.target ~= self.Owner
		or not IsValid(self.Owner)
		or not isnumber(effector)
		or effector < 0
	then
		return
	end

	local client = RagdollPoser.Entity.GetClientFromEntity(self.Owner)
	if not IsValid(client) or effector >= client:GetBoneCount() then
		return
	end

	local chain = makeChain(client, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	if #chain < 2 then
		return
	end

	local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
	if not matrices then
		return
	end

	render.SetColorMaterialIgnoreZ()
	for index = 1, #chain - 1 do
		local child = matrices[chain[index] + 1]
		local parent = matrices[chain[index + 1] + 1]
		if child and parent then
			render.DrawLine(child:GetTranslation(), parent:GetTranslation(), LINE_COLOR, false)
		end
	end
end

local function createConstraint(entity, state, name)
	local base = ik:Init(entity, state, name)
	---@cast base IKConstraint
	base.State.target = base.Owner
	if not base.State.weightRotationConfigured then
		base.State.weightRotation = true
		base.State.weightRotationConfigured = true
	end
	return base
end

return createConstraint
