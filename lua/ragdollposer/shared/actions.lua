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
}

RagdollPoser.ActionName = table.Flip(RagdollPoser.Actions)
