#!/usr/bin/env luajit
local fn = assert(..., "expected filename")
local table = require 'ext.table'
local string = require 'ext.string'
local tolua = require 'ext.tolua'
local Image = require 'image'
local image = Image(fn)

print(tolua(image))

print('PALETTE LEN:', image.palette and #image.palette)
for i,c in ipairs(image.palette or {}) do
	io.write((i..'=%06x\t'):format(bit.bor(
		bit.lshift(c[1], 16),
		bit.lshift(c[2], 8),
		c[3]
	)))
end

local hist = image:getHistogram()
for _,key in ipairs(table.keys(hist):sort(function(a,b)
	return hist[a] > hist[b]
end)) do
	print(string.hex(key)..' has '..hist[key])
end

--image:save'tmp.png'
