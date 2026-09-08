---[CLIENT]
---
---Handle input events by sending them through one place for other systems to hook onto
---
---Requirements
--- - There shall only be one keybind per action
---
---@class RagdollPoser.Input
---@
local MGR = {
	xMove = 0,
	yMove = 0,
}

---@type {[BUTTON_CODE]: InputAction}
MGR.KeyBinds = MGR.KeyBinds or {}
---@type {[InputAction]: BUTTON_CODE}
MGR.BoundActions = MGR.BoundActions or table.Flip(MGR.KeyBinds)

---@type table<integer, BUTTON_CODE>
local activeKeybinds = {}

local function refreshKeyBinds()
	activeKeybinds = {}
	for key, _ in pairs(MGR.KeyBinds) do
		activeKeybinds[#activeKeybinds + 1] = key
	end
end

---@param action InputAction
---@param keycode BUTTON_CODE
function MGR:RegisterKey(action, keycode)
	MGR.KeyBinds[keycode] = action
	-- If we are reassigning an action to another key, we need to remove it from the keybinds
	-- TODO: Allow multiple actions to run for a single key
	if MGR.BoundActions[action] and MGR.BoundActions[action] ~= keycode then
		MGR.KeyBinds[MGR.BoundActions[action]] = nil
	end
	MGR.BoundActions[action] = keycode
	refreshKeyBinds()
	RagdollPoser.Log("Registered keybind ", input.GetKeyName(keycode), " for ", RagdollPoser.ActionName[action])
end

---@alias InputCallback fun(x: integer, y: integer, tr: TraceResult)

---@type TraceResult
local traceOutput = {
	HitPos = vector_origin,
	Normal = vector_origin,
	StartPos = vector_origin
}
local lastCheck = RealTime()

---@param cmd CUserCmd
local function mouseInput(cmd)
	local pl = LocalPlayer()
	local equipped = RagdollPoser.Helpers.Equipped()
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
end

hook.Remove("CreateMove", "RagdollPoser_MouseInput")
hook.Add("CreateMove", "RagdollPoser_MouseInput", mouseInput)

local keysDown = {}
local function keyboardInput()
	local equipped = RagdollPoser.Helpers.Equipped()
	if equipped then
		for _, key in ipairs(activeKeybinds) do
			if input.IsKeyDown(key) and not keysDown[key] then
				keysDown[key] = true
				hook.Run("RagdollPoser_Input_KeyPress", MGR.KeyBinds[key])
			elseif not input.IsKeyDown(key) and keysDown[key] then
				keysDown[key] = false
			end
		end
	end
end
hook.Remove("PlayerButtonDown", "RagdollPoser_KeyboardInput")
hook.Remove("KeyPress", "RagdollPoser_KeyboardInput")
hook.Remove("Think", "RagdollPoser_KeyboardInput")
hook.Add("Think", "RagdollPoser_KeyboardInput", keyboardInput)

local function mouseDelta(cmd, x, y, ang)
	MGR.xMove = x
	MGR.yMove = y
end
hook.Add("InputMouseApply", "RagdollPoser_MouseDelta", mouseDelta)

RagdollPoser.Input = MGR
