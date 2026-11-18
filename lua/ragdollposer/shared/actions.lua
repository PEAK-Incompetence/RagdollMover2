---[SERVER AND CLIENT]
---
---For every action
---
---@alias InputAction integer
RagdollPoser.Actions = {
	CycleGizmo = 0, -- Change gizmo types
	SelectBone = 1, -- Bone Select Mode
	ToggleConstraint = 2, -- Turn constraint on and off
	SelectRoot = 3, -- Select root bone
	AttachSurface = 4, -- Places held entity onto the world geometry
	DoPrecision = 5, -- Increase the precision of gizmo movement
}

RagdollPoser.ActionName = table.Flip(RagdollPoser.Actions)
