local ffi = require 'ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'

local uint8_t = ffi.typeof'uint8_t'
local float = ffi.typeof'float'
local double = ffi.typeof'double'

local Loader = class()

-- convert to a valid format, complain if it can't be converted
function Loader:prepareImage(image)
	image = image:rgb()
	if image.format == float or image.format == double then
		image = image:clamp(0,1)
	end
	if image.format ~= uint8_t then
		image = image:setFormat(uint8_t)
	end
	assert.eq(image.channels, 3, "expected only 3 channels")
	return image
end

return Loader
