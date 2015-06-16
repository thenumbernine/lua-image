local ffi = require 'ffi'
local png = require 'image.luajit.png'

-- load example
local img = png.load{filename='tmp1.png'}
local data = assert(img.data)
local width = assert(img.width)
local height = assert(img.height)

--[[
-- generate our own texture? 
local width = 256
local height = 256
local data = ffi.new('char[?]', width * height * 3)
for y=0,height-1 do
	for x=0,width-1 do
		data[0+3*(x+width*y)] = 255*x/(width-1)
		data[1+3*(x+width*y)] = 255*y/(height-1)
		data[2+3*(x+width*y)] = 127
	end
end
--]]

png.save{
	filename = 'test-output.png',
	width = width, 
	height = height, 
	data = data
}
