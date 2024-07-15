local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local gif = require 'ffi.req' 'gif'

local GIFLoader = Loader:subclass()

function GIFLoader:load(filename, imageIndex)
	assert(filename, "expected filename")
	imageIndex = imageIndex or 0

	local err = ffi.new('int[1]', 0)
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

	local --[[SavedImage const &]] saved = gifFile[0].SavedImages[imageIndex];
	local --[[GifImageDesc const &]] desc = saved.ImageDesc
	local --[[ColorMapObject const * const]] colorMap = desc.ColorMap ~= nil and desc.ColorMap or commonMap

	local width = desc.Width
	local height = desc.Height
	local channels = 3
	local data = ffi.new('unsigned char[?]', width * height * channels)

	for v=0,height-1 do
		for u=0,width-1 do
			local c = saved.RasterBits[v * width + u]
			if colorMap ~= nil then
				local --[[GifColorType]] rgb = colorMap[0].Colors[c]
				local dstindex = channels * (u + width * v)
				data[0 + dstindex] = rgb.Red
				data[1 + dstindex] = rgb.Green
				data[2 + dstindex] = rgb.Blue
			else
				error("Can't decode this gif")	--truecolor gif? greyscale? no color map...
			end
		end
	end

	return {
		data = data,
		width = width,
		height = height,
		channels = channels,
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
