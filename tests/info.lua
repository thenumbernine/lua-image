#!/usr/bin/env luajit
local fn = assert(..., "expected filename")
local Image = require 'image'
local image = Image(fn)
print('width', image.width)
print('height', image.height)
print('channels', image.channels)
print('format', image.format)
print('palette', image.palette and #image.palette)
for i,c in ipairs(image.palette or {}) do
	io.write((i..'=%06x\t'):format(bit.bor(
		bit.lshift(c[1], 16),
		bit.lshift(c[2], 8),
		c[3]
	)))
end

--image:save'tmp.png'
