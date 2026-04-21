local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local assert = require 'ext.assert'
local table = require 'ext.table'
local range = require 'ext.range'
local gif = require 'image.ffi.gif'


local int_1 = ffi.typeof'int[1]'
local uint8_t = ffi.typeof'uint8_t'
local uint8_t_arr = ffi.typeof'uint8_t[?]'
local GraphicsControlBlock = ffi.typeof'GraphicsControlBlock'


local GIFLoader = Loader:subclass()

function GIFLoader:load(filename, imageIndex)
	assert(filename, "expected filename")
	imageIndex = imageIndex or 0

	local err = int_1(0)
	local --[[GifFileType*]] gifFile = gif.DGifOpenFileName(filename, err)
	--if (err != D_GIF_SUCCEEDED) {
	if gifFile == nil then
		error("DGifOpenFileName failed with error " .. err[0])
	end

	--Common::Finally fileFinally([&](){ DGifCloseFile(gifFile, &err) })

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

	local bitsPerPixel = colorMap.BitsPerPixel
	assert.eq(bit.band(bitsPerPixel, 7), 0)
	local bytesPerPixel = bit.rshift(bitsPerPixel, 3)

	local palette = range(0,colorMap.ColorCount-1):mapi(function(i)
		local c = colorMap.Colors[i]
		return {c.Red, c.Green, c.Blue}
	end)

	local width = desc.Width
	local height = desc.Height
	local size = width * height * bytesPerPixel
	local buffer = uint8_t_arr(size)
	ffi.copy(buffer, saved.RasterBits, size)

	-- TODO mechanism for loading *all* instead of cycling the frame and reloading every time ...
	return {
		buffer = buffer,
		width = width,
		height = height,
		channels = 1,
		format = uint8_t,
		palette = palette,
	}
end

-- TODO get rid of Loader:prepareImage and just pass in the image ... and let the loader manipulate it ...
function GIFLoader:prepareImage(image)
	return image
end

--[[
args[1] is Image but with .filename
	and optionally .frameDelay
args[2..] are successive framed images
--]]
function GIFLoader:save(...)
	local Image = require 'image'
	local images = table{...}:mapi(function(o) return setmetatable(o, Image) end)
	local numFrames = #images
	local args = ...	-- i.e first image, but with .filename set ...
	local filename = assert.type(assert.index(args, 'filename'), 'string')

	local width = args.width
	local height = args.height
	for i,image in ipairs(images) do
		assert.eq(image.width, width)
		assert.eq(image.height, height)
	end

	local indexedMasterImg
	if numFrames == 1 then
		-- if using 1 frame then use its palette, or quantize if no palette
		indexedMasterImg = images[1]
		if not indexedMasterImg.palette then
			indexedMasterImg = rgbMasterImg:toIndexed()
		end
	else
		--if not all palettes are identical then ...]
		for i=1,numFrames do
			images[i] = images[i]:rgb()
		end
		local rgbMasterImg = Image(width, numFrames * height, images[1].channels, images[1].format)
		local rgbImageSize = images[1]:getBufferSize()
		for i,image in ipairs(images) do
			assert.eq(image:getBufferSize(), rgbImageSize)
			ffi.copy(rgbMasterImg.buffer + rgbImageSize * (i-1), image.buffer, rgbImageSize)
		end
		indexedMasterImg = rgbMasterImg:toIndexed()
	end
	assert.eq(indexedMasterImg.channels, 1)
	assert.eq(indexedMasterImg.format, uint8_t)
	local rowsize = indexedMasterImg.width * indexedMasterImg.channels * ffi.sizeof(indexedMasterImg.format)

	local palette = assert.index(indexedMasterImg, 'palette')
	local bitsPerPixel = 8
	assert.le(#palette, bit.lshift(1, bitsPerPixel), "I've hard-coded the bpp at 8, and your palette uses more than 8, so you will have to increase the limit and verify that it works properly")

	assert.eq(indexedMasterImg:getBufferSize() % numFrames, 0)
	local indexedImageSize = indexedMasterImg:getBufferSize() / numFrames


	local err = int_1()
	local fp = gif.EGifOpenFileName(filename, false, err)
	if err[0] ~= gif.E_GIF_SUCCEEDED then
		error("GIFLoader:save EGifOpenFileName failed with error "..tostring(err[0]))
	end
	assert(fp ~= nil, "got no error and no file pointer")

	local numColors = bit.lshift(1, math.floor(math.log(#palette, 2)))
	assert.le(numColors, bit.lshift(1, bitsPerPixel))
	-- meh, gif is restrictive enough that I don't trust it to work for anything except 8bpp indexed
	numColors = bit.lshift(1, bitsPerPixel)

	local gifPal = gif.GifMakeMapObject(numColors , nil)
	ffi.fill(gifPal[0].Colors, ffi.sizeof'GifColorType' * numColors)
	if gifPal == nil then
		error("GifMakeMapObject: either #palette is non-power-of-two or your memory is full")
	end
	for i,p in ipairs(palette) do
		local c = gifPal[0].Colors + (i-1)
		c.Red = p[1]
		c.Green = p[2]
		c.Blue = p[3]
	end

	-- "bitsPerPixel" is "GifColorRes" in the API ... hmmm
	gif.EGifPutScreenDesc(fp, width, height, bitsPerPixel, 0, gifPal)

	gif.EGifPutExtensionLeader(fp, gif.APPLICATION_EXT_FUNC_CODE)
	local loopBlock = 'NETSCAPE2.0'
	gif.EGifPutExtensionBlock(fp, #loopBlock, loopBlock)
	local loopData = string.char(1, 0, 0)	-- 1 = loop-count sub-block, 0,0 = infinite
	gif.EGifPutExtensionBlock(fp, #loopData, loopData)
	gif.EGifPutExtensionTrailer(fp)

	local srcp = indexedMasterImg.buffer + 0
	for frame=1,numFrames do
		local gcb = GraphicsControlBlock()
		gcb.DisposalMode = gif.DISPOSE_DO_NOT	-- gif.DISPOSAL_UNSPECIFIED,
		gcb.UserInputFlag = false
		gcb.DelayTime = 83	-- ms
		gcb.TransparentColor = gif.NO_TRANSPARENT_COLOR
		gif.EGifGCBToSavedExtension(gcb, fp, frame-1)
		gif.EGifPutImageDesc(fp, 0, 0, width, height, false, nil)
		for i=0,height-1 do
			gif.EGifPutLine(fp, srcp, rowsize)
			srcp = srcp + rowsize
		end
	end
	assert.eq(srcp, indexedMasterImg.buffer + indexedMasterImg:getBufferSize())

	gif.EGifCloseFile(fp, err)
	if err[0] ~= gif.E_GIF_SUCCEEDED then
		error("GIFLoader:save EGifCloseFile failed with error "..tostring(err[0]))
	end
	gif.GifFreeMapObject(gifPal)
end

return GIFLoader
