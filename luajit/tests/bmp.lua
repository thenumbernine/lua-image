local bmp = require 'image.luajit.bmp'
local img = bmp.load('test.bmp')
bmp.save{
	filename='test-write.bmp',
	width=img.width, 
	height=img.height, 
	data=img.data
}
