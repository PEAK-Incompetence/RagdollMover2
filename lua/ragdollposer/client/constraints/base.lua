---@class Constraint
---@field _target any
---@field _bone integer
---@field _targetSpace integer
---@field _ownerSpace integer
---@field _influence number
local Base = {}
Base.__index = Base

function Base:Init()
	local base = setmetatable({}, Base)
	return base
end

function Base:Evaluate() end

return Base
