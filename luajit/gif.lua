local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local gif = require 'image.ffi.gif'

local int1 = ffi.typeof'int[1]'
local uint8_t = ffi.typeof'uint8_t'
local uint8_t_arr = ffi.typeof'uint8_t[?]'

local GIFLoader = Loader:subclass()

function GIFLoader:load(filename, imageIndex)
	assert(filename, "expected filename")
	imageIndex = imageIndex or 0

	local err = int1(0)
	local --[[GifFileType*]] gifFile = gif.DGifOpenFileName(filename, err)
	--if (err != D_GIF_SUCCEEDED) {
	if gifFile == nil then
		error("DGifOpenFileName failed with error " .. err[0])
	end

	--Common::Finally fileFinally([&](){ DGifCloseFile(gifFile, &err); });

	-- what does this even do?
	if gif.DGifSlurp(gifFile) == gif.GIF_ERROR then
		gif.DGifCloseFile(gifFile, err)
		error("DGifSlurp failed with error " .. gifFile[0].Error)
	end

	local --[[ColorMapObject const * const]] commonMap = gifFile[0].SColorMap

	imageIndex = imageIndex % gifFile[0].ImageCount

	local --[[SavedImage const &]] saved = gifFile[0].SavedImages[imageIndex]
	local --[[GifImageDesc const &]] desc = saved.ImageDesc
	local --[[ColorMapObject const * const]] colorMap = desc.ColorMap ~= nil and desc.ColorMap or commonMap

	local palette = range(0,colorMap.ColorCount-1):mapi(function(i)
		local c = colorMap.Colors[i]
		return {c.Red, c.Green, c.Blue}
	end)

	local width = desc.Width
	local height = desc.Height
	local buffer = uint8_t_arr(width * height)
	ffi.copy(buffer, saved.RasterBits, width * height)

	return {
		buffer = buffer,
		width = width,
		height = height,
		channels = 1,
		format = uint8_t,
		palette = palette,
	}
end

-- used for saving, which I haven't implemented yet
function GIFLoader:prepareImage(image)
	return image
end

-- because discretizing palette ...
function GIFLoader:save(args)
	error"save GIF not working yet"
end

return GIFLoader
