local ffi = require 'ffi'
local sdl = require 'sdl'
local img = require 'sdl.ffi.sdl_image'
local class = require 'ext.class'
local path = require 'ext.path'

local uint8_t_p = ffi.typeof'uint8_t*'

local rgbaPixelFormat
if ffi.os == 'Windows' then
	rgbaPixelFormat = ffi.new('SDL_PixelFormat[1]')
	rgbaPixelFormat[0].palette = nil
	rgbaPixelFormat[0].BitsPerPixel = 32
	rgbaPixelFormat[0].BytesPerPixel = 4
	rgbaPixelFormat[0].Rmask = 0x000000ff	rgbaPixelFormat[0].Rshift = 0	rgbaPixelFormat[0].Rloss = 0
	rgbaPixelFormat[0].Gmask = 0x0000ff00	rgbaPixelFormat[0].Gshift = 8	rgbaPixelFormat[0].Gloss = 0
	rgbaPixelFormat[0].Bmask = 0x00ff0000 	rgbaPixelFormat[0].Bshift = 16	rgbaPixelFormat[0].Bloss = 0
	rgbaPixelFormat[0].Amask = 0xff000000	rgbaPixelFormat[0].Ashift = 24	rgbaPixelFormat[0].Aloss = 0
	rgbaPixelFormat[0].colorkey = 0
	rgbaPixelFormat[0].alpha = 0
end

local Image = class()

function Image:init(w, h, ch, format, generator)
	if ch ~= 4 then error("only supporting 4bpp for now") end
	if format then error("haven't got format support yet") end
	if generator then error("haven't got image source support yet") end
	if type(w) == 'string' then
		local filename = w
		if not path(filename):exists() then error('file not found: '..filename) end

		local loadSurface = img.IMG_Load(filename)
		if loadSurface == nil then error("failed to load filename "..tostring(filename)) end

		local surface
		if ffi.os == 'Windows' then
			surface = sdl.SDL_ConvertSurface(loadSurface, rgbaPixelFormat, sdl.SDL_SWSURFACE)
		else
			surface = sdl.SDL_DisplayFormatAlpha(loadSurface)
		end
		sdl.SDL_FreeSurface(loadSurface)
		if surface == nil then error("failed to convert image to displayable format") end

		self.surfaceRef = surface
		self.surface = surface[0]
		local data = self:data()
		-- TODO init data with generator here
		ffi.gc(self.surfaceRef, sdl.SDL_FreeSurface)
	else
		self.surface = sdl.SDL_CreateRGBSurface(sdl.SDL_SWSURFACE, w, h, bit.lshift(ch, 3), 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)
	end
end

function Image:size()
	return self.surface.w, self.surface.h, 4
end

function Image:data()
	return ffi.cast(uint8_t_p, self.surface.pixels)
end

-- TODO verify rgba order
function Image:__call(x,y,r,g,b,a)
	local i = 4 * (x + self.surface.w * y)
	local pixels = ffi.cast(uint8_t_p, self.surface.pixels)
	local _r = pixels[i+0] / 255
	local _g = pixels[i+1] / 255
	local _b = pixels[i+2] / 255
	local _a = pixels[i+3] / 255
	if r ~= nil then pixels[i+0] = math.floor(r * 255) end
	if g ~= nil then pixels[i+1] = math.floor(g * 255) end
	if b ~= nil then pixels[i+2] = math.floor(b * 255) end
	if a ~= nil then pixels[i+3] = math.floor(a * 255) end
	return _r, _g, _b, _a
end

return Image
