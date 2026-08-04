---@alias InputCallback fun(x: integer, y: integer, tr: TraceResult)

---@type TraceResult
local traceOutput = {}
local lastCheck = RealTime()
hook.Remove("CreateMove", "RagdollPoser_MouseInput")
hook.Add("CreateMove", "RagdollPoser_MouseInput", function(cmd)
	local pl = LocalPlayer()
	local weap = pl:GetActiveWeapon()
	local tool = pl:GetTool()
	local equipped = IsValid(weap) and weap:GetClass() == "gmod_tool" and tool and tool:GetMode() == RagdollPoser.Mode
	if equipped then
		local eyePos = MainEyePos()
		util.TraceLine({
			start = eyePos,
			endpos = eyePos + pl:GetAimVector() * 16384,
			filter = { pl, pl:GetViewEntity() },
			ignoreworld = false, -- TODO: implement ignore world privileges
			output = traceOutput,
		})
		local tr = traceOutput

		local now = RealTime()
		local allowInput = now - lastCheck > RealFrameTime()
		local x, y = input.GetCursorPos()
		-- Get left-click and right-click events
		if (input.WasMousePressed(MOUSE_LEFT) or input.WasMouseDoublePressed(MOUSE_LEFT)) and allowInput then
			hook.Run("RagdollPoser_Input_LeftClickDown", x, y, tr)
			lastCheck = now
		end
		if input.WasMouseReleased(MOUSE_LEFT) and allowInput then
			hook.Run("RagdollPoser_Input_LeftClickUp", x, y, tr)
			lastCheck = now
		end
		if (input.WasMousePressed(MOUSE_RIGHT) or input.WasMouseDoublePressed(MOUSE_RIGHT)) and allowInput then
			hook.Run("RagdollPoser_Input_RightClickUp", x, y, tr)
			lastCheck = now
		end
		if input.WasMouseReleased(MOUSE_RIGHT) and allowInput then
			hook.Run("RagdollPoser_Input_RightClickUp", x, y, tr)
			lastCheck = now
		end
	end
end)
