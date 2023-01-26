#!/usr/bin/env luajit
local ffi = require 'ffi'
for format,cond in pairs{
	bmp = true,
	fits = true,
	jpeg = ffi.os ~= 'Windows',
	png = true,
	tiff = ffi.os ~= 'Windows',
} do
	if cond then
		-- test writing
		if assert(loadfile('test.lua'))(format) then
			-- test reading
			assert(loadfile('test.lua'))(format)
		end
	end
end
