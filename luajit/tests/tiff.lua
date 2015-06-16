local ffi = require 'ffi'
local tiff = require 'image.luajit.tiff'


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
tiff.save{
	filename = 'test.tiff',
	width = width, 
	height = height, 
	data = data
}
