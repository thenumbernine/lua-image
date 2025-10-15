-- Image is my more-compatible wrapper class
-- img is my old sucky class, global namespace, bleh

local ffi = require 'ffi'
local class = require 'ext.class'
local img = require 'img'	-- working on 'libImageLua', but too many libpaths searched through

local uint8_t_p = ffi.typeof'uint8_t*'
local uint8_t_arr = ffi.typeof'uint8_t[?]'

local Image = class()

local function oldimgloader(image, fn)
	image.img = img.load(fn)
end

Image.loaders = {
	png = oldimgloader,
	bmp = oldimgloader,
	tiff = oldimgloader,
	tif = oldimgloader,
	jpg = oldimgloader,
	jpeg = oldimgloader,
}

function Image:init(w,h,ch)
	if type(w) == 'string' then
		local ext = w:match'.*%.(.-)$'
		local loader = ext and self.loaders[ext:lower()]
		if not loader then
			error("I don't know how to load a file with ext "..tostring(ext))
		else
			loader(self, w)
		end
	else
		if not ch then ch = 4 end	--to match the sdl loader ...
		self.img = img.new{width=w, height=h, channels=ch}
	end
end

function Image:size(...)
	return self.img:size(...)
end

function Image:__call(...)
	return self.img:__call(...)
end

function Image:data(...)
	--[[ pushes a copy
	local w, h, ch = self:size()
	local datasize = w * h * ch
	local data = ffi.new(uint8_t_arr, datasize)
	ffi.copy(data, self.img:dataptr(), datasize)	-- userdata to uint8_t[]
	return data
	--]]
	return ffi.cast(uint8_t_p,self.img:dataptr())
end

function Image:save(...)
	return self.img:save(...)
end

return Image
