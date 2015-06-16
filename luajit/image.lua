--[[
TODO all the loaders are currently designed to work for RGB,
whereas the other options (luaimg, sdl_image) are designed to work for RGBA
so this needs to be changed to work with RGBA too
--]]
local ffi = require 'ffi'
local class = require 'ext.class'

local Image = class()

Image.loaders = {
	png = require 'image.luajit.png',
	bmp = require 'image.luajit.bmp',
	tif = require 'image.luajit.tiff',
	tiff = require 'image.luajit.tiff',
}

function Image:init(w,h,ch)
	ch = ch or 4
	if type(w) == 'string' then
		local ext = w:match'.*%.(.-)$'
		local loader = ext and self.loaders[ext:lower()]
		if not loader then
			error("I don't know how to load a file with ext "..tostring(ext))
		end
		local result = loader.load(w)
		self.buffer = result.data
		self.width = result.width
		self.height = result.height
		self.channels = 3
	else
		self.buffer = ffi.new('unsigned char[?]', w*h*ch)
		self.width = w
		self.height = h
		self.channels = ch
	end
end

function Image:save(filename, ...)
	assert(self.channels == 3, "expected only 3 channels")
	local ext = filename:match'.*%.(.-)$'
	local loader = ext and self.loaders[ext:lower()]
	if not loader then
		error("I don't know how to load a file with ext "..tostring(ext))
	end
	loader.save{
		filename = filename,
		width = self.width,
		height = self.height,
		data = self.buffer,
	}
end

function Image:size()
	return self.width, self.height, self.channels
end

function Image:__call(x,y,r,g,b,a)
	local i = self.channels * (x + self.width * y)
	local pixels = self.buffer
	local _r = pixels[i+0] / 255
	local _g = self.channels > 1 and pixels[i+1] / 255
	local _b = self.channels > 2 and pixels[i+2] / 255
	local _a = self.channels > 3 and pixels[i+3] / 255
	if r ~= nil then pixels[i+0] = math.floor(r * 255) end
	if self.channels > 1 and g ~= nil then pixels[i+1] = math.floor(g * 255) end
	if self.channels > 2 and b ~= nil then pixels[i+2] = math.floor(b * 255) end
	if self.channels > 3 and a ~= nil then pixels[i+3] = math.floor(a * 255) end
	return _r, _g, _b, _a
end

function Image:data()
	return self.buffer
end

return Image
