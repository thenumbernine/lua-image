#!/usr/bin/env luajit
local ffi = require 'ffi'
local Image = require 'image'
for format,_ in 
	--pairs(Image.loaders) 
	pairs(
		(
			Windows = {	
				bmp = true,
				fits = true,
				--jpeg = true,
				png = true,
				--tiff = true,
			}
		)[ffi.os]
	)
do
	-- test writing
	if assert(loadfile('test.lua'))(format) then
		-- test reading
		assert(loadfile('test.lua'))(format)
	end
end
