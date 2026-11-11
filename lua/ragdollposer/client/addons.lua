-- Addon compatibility

local empty = {}

-- Stop Motion Helper 4 compatibiilty
hook.Remove("SMH_PostSetFrame", "rgm2_updateEntity")
hook.Add("SMH_PostSetFrame", "rgm2_updateEntity", function(frame)
	local entities = SMH and SMH.State and SMH.State.Entity or empty
	for entity, _ in pairs(entities) do
		RagdollPoser.Entity.UpdateEntity(entity)
	end
	local selection = RagdollPoser.Selection:GetSelection()
	if next(entities) and selection[1] then
		RagdollPoser.Gizmo:SetTransformFromSelection(selection)
	end
end)
