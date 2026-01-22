local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local table = require 'ext.table'
local range = require 'ext.range'
local assert = require 'ext.assert'
local stdio = require 'ffi.req' 'c.stdio'	-- use stdio instead of ffi.C for browser compat
local png = require 'image.ffi.png'


local voidp = ffi.typeof'void*'
local charp1 = ffi.typeof'char*[1]'
local int = ffi.typeof'int'
local int1 = ffi.typeof'int[1]'
local uint8_t = ffi.typeof'uint8_t'
local uint8_t_p = ffi.typeof'uint8_t*'
local uint8_t_arr = ffi.typeof'uint8_t[?]'
local uint8_t_p_arr = ffi.typeof'uint8_t*[?]'
local uint8_t_arr8 = ffi.typeof'uint8_t[8]'
local uint16_t = ffi.typeof'uint16_t'
local uint32_t_1 = ffi.typeof'uint32_t[1]'
local size_t = ffi.typeof'size_t'
local float = ffi.typeof'float'
local double = ffi.typeof'double'
local double1 = ffi.typeof'double[1]'
local double8 = ffi.typeof'double[8]'

local png_structp = ffi.typeof'png_structp'
local png_structp_1 = ffi.typeof'png_structp[1]'

local png_infop = ffi.typeof'png_infop'
local png_infop_1 = ffi.typeof'png_infop[1]'

local png_byte = ffi.typeof'png_byte'
local png_byte_arr = ffi.typeof'png_byte[?]'
local png_bytep = ffi.typeof'png_bytep'
local png_bytep_1 = ffi.typeof'png_bytep[1]'
local png_bytep_arr = ffi.typeof'png_bytep[?]'

local png_uint_16_p_1 = ffi.typeof'png_uint_16p[1]'
local png_uint_32_1 = ffi.typeof'png_uint_32[1]'

local png_color_arr = ffi.typeof'png_color[?]'
local png_colorp_1 = ffi.typeof'png_color*[1]'
local png_color_8p_1 = ffi.typeof'png_color_8*[1]'
local png_color_16_1 = ffi.typeof'png_color_16[1]'
local png_color_16p_1 = ffi.typeof'png_color_16p[1]'

local png_textp_1 = ffi.typeof'png_text*[1]'

local png_sPLT_t_p_1 = ffi.typeof'png_sPLT_t*[1]'
local png_time_p_1 = ffi.typeof'png_time*[1]'

local png_unknown_chunk_arr = ffi.typeof'png_unknown_chunk[?]'
local png_unknown_chunk_p_1 = ffi.typeof'png_unknown_chunk*[1]'

local png_error_ptr = ffi.typeof'png_error_ptr'
local png_rw_ptr = ffi.typeof'png_rw_ptr'


local PNGLoader = Loader:subclass()

PNGLoader.libpngVersion = png.PNG_LIBPNG_VER_STRING

--[[
http://www.libpng.org/pub/png/spec/1.2/PNG-Chunks.html
PNG options:

Color Type        Allowed Bit Depths  Interpretation
0 GRAY			  1,2,4,8,16          Each pixel is a grayscale sample.
2 RGB             8,16                Each pixel is an R,G,B triple.
3 PALETTE         1,2,4,8             Each pixel is a palette index; a PLTE chunk must appear.
4 GRAY_ALPHA/GA   8,16                Each pixel is a grayscale sample, followed by an alpha sample.
6 RGB_ALPHA/RGBA  8,16                Each pixel is an R,G,B triple, followed by an alpha sample.
-- replace the base loader which forced rgb
-- instead, allow for rgba
--]]
function PNGLoader:prepareImage(image)
	if not (
		image.channels == 1
		or image.channels == 3
		or image.channels == 4
	) then
		image = image:rgb()
	end

	assert.eq(ffi.typeof(image.format), image.format, "format is not a ctype")

	if image.format == float or image.format == double then
		image = image:clamp(0,1)
	end

	if image.palette then
		-- png 16bpp doesn't work on palette image types
		-- TODO if we do have to convert an indexed >8bpp image here then we should at least warn, if not error, because it will be destructive
		if ffi.sizeof(image.format) > 1 then
			print('WARNING: converting indexed texture from >8bpp to 8bpp, something bad will probably happen')
		end
	else
		-- all non-palette image types can be 1,2,4,8,16 bpp
		if ffi.sizeof(image.format) > 2 then
			image = image:setFormat'uint8_t'
		end
	end

	assert(
		image.channels == 1
		or image.channels == 3
		or image.channels == 4,
		"expected 1, 3 or 4 channels"
	)

	return image
end

local errorCallback = ffi.cast(png_error_ptr, function(struct, msg)
	print('png error:', ffi.string(msg))
end)

local warningCallback = ffi.cast(png_error_ptr, function(struct, msg)
	print('png warning:', ffi.string(msg))
end)

local headerSize = 8

local function pngLoadBody(args)

	-- initialize stuff
--DEBUG(@5):print('png_create_read_struct', PNGLoader.libpngVersion, nil, errorCallback, warningCallback)
	local png_ptr = png.png_create_read_struct(PNGLoader.libpngVersion, nil, errorCallback, warningCallback)
--DEBUG(@5):print('...got', png_ptr)
	if png_ptr == ffi.null then
		error'png_create_read_struct failed'
	end

	local png_pp = png_structp_1()
	png_pp[0] = png_ptr

--DEBUG(@5):print('png_create_info_struct', png_ptr)
	local info_ptr =  png.png_create_info_struct(png_ptr)
--DEBUG(@5):print('...got', info_ptr)
	if info_ptr == ffi.null then
		error'png_create_info_struct failed'
	end

	local info_pp = png_infop_1()
	info_pp[0] = info_ptr

	args.init(png_ptr)	-- init the png

--DEBUG(@5):print('png_set_sig_bytes', png_ptr, headerSize)
	png.png_set_sig_bytes(png_ptr, headerSize)

--DEBUG(@5):print('png_set_keep_unknown_chunks', png_ptr, png.PNG_HANDLE_CHUNK_ALWAYS, nil, 0)
	-- This seems to only work with the png_read_png pathway, but not with the png_read_info+png_read_image+png_read_end pathway
	-- With the png_read_info+... pathway, custom chunks are thrown out regardless.
	-- I'm suspicious they won't be if I add a custom chunk callback handler per-custom-chunk, but I want to just save all of them, and do it without callbacks.
	png.png_set_keep_unknown_chunks(png_ptr, png.PNG_HANDLE_CHUNK_ALWAYS, nil, 0)

	-- [[ using png_read_png
--DEBUG(@5):print('png_read_png', png_ptr, info_ptr, png.PNG_TRANSFORM_IDENTITY, nil)
	-- "This call is equivalent to png_read_info(), followed the set of transformations indicated by the transform mask, then png_read_image(), and finally png_read_end()."
	png.png_read_png(png_ptr, info_ptr, png.PNG_TRANSFORM_IDENTITY, nil)
	--]]
	--[[ using png_read_info+png_read_image+png_read_end:
--DEBUG(@5):print('png_read_info', png_ptr, info_ptr)
	png.png_read_info(png_ptr, info_ptr)
	--]]

--DEBUG(@5):print('png_get_image_width', png_ptr, info_ptr)
	local width = png.png_get_image_width(png_ptr, info_ptr)
--DEBUG(@5):print('png_get_image_height', png_ptr, info_ptr)
	local height = png.png_get_image_height(png_ptr, info_ptr)
--DEBUG(@5):print('png_get_color_type', png_ptr, info_ptr)
	local colorType = png.png_get_color_type(png_ptr, info_ptr)
--DEBUG(@5):print('png_get_bit_depth', png_ptr, info_ptr)
	local bitDepth = png.png_get_bit_depth(png_ptr, info_ptr)
	if colorType ~= png.PNG_COLOR_TYPE_GRAY
	and colorType ~= png.PNG_COLOR_TYPE_RGB
	and colorType ~= png.PNG_COLOR_TYPE_PALETTE
	and colorType ~= png.PNG_COLOR_TYPE_GRAY_ALPHA
	and colorType ~= png.PNG_COLOR_TYPE_RGB_ALPHA
	then
		error("got unknown colorType: "..tostring(colorType))
	end

	if not (bitDepth == 1
		or bitDepth == 2
		or bitDepth == 4
		or bitDepth % 8 == 0
	) then
		error("got unknown bit depth: "..tostring(bitDepth))
	end

	--local number_of_passes = png.png_set_interlace_handling(png_ptr)
	-- looks like png 1.5 needed this but png 1.6 doesn't
	--png.png_read_update_info(png_ptr, info_ptr)

	-- read file

	local channels = ({
		[png.PNG_COLOR_TYPE_GRAY] = 1,
		[png.PNG_COLOR_TYPE_PALETTE] = 1,
		[png.PNG_COLOR_TYPE_GRAY_ALPHA] = 2,
		[png.PNG_COLOR_TYPE_RGB] = 3,
		[png.PNG_COLOR_TYPE_RGB_ALPHA] = 4,
	})[colorType] or error('got unknown colorType')
	local format
	if bitDepth <= 8 then
		format = uint8_t
	elseif bitDepth == 16 then
		format = uint16_t
	else
		error("got unknown bit depth: "..tostring(bitDepth))
	end
	local formatp = ffi.typeof('$*', format)
	local format_arr = ffi.typeof('$[?]', format)
	local buffer = format_arr(width * height * channels)

	-- [[ using png_read_png
--DEBUG(@5):print('png_get_rows', png_ptr, info_ptr)
	local rowPointer = png.png_get_rows(png_ptr, info_ptr)
	--]]
	--[[ used with png_read_info / png_read_image / png_read_end
--DEBUG(@5):print('allocating rowPointer...')
	local rowPointer = png_bytep_arr(height)
	local rowBytes = png.png_get_rowbytes(png_ptr, info_ptr)
	local rowPtrData = range(0,height-1):mapi(function(i)
		local ptr = uint8_t_arr(rowBytes)
		rowPointer[i] = ptr
		return ptr	-- save so it doesn't gc
	end)
--DEBUG(@5):print('png_read_image', png_ptr, rowPointer)
	png.png_read_image(png_ptr, rowPointer)
	--]]

	-- read buffer from rows directly
	if bitDepth < 8 then
		assert.eq(channels, 1, "I don't support channels>1 for bitDepth<8")
		local bitMask = assert.index({
			[1] = 1,
			[2] = 3,
			[4] = 0xf,
			[8] = 0xff,
		}, bitDepth)
		local dst = buffer
		for y=0,height-1 do
			local src = ffi.cast(png_bytep, rowPointer[y])
			local bitOfs = 0
			for x=0,width-1 do
				dst[0] = bit.band(bitMask, bit.rshift(src[0], 8 - bitOfs - bitDepth))
				dst = dst + 1
				bitOfs = bitOfs + bitDepth
				if bitOfs >= 8 then
					bitOfs = bitOfs - 8
					src = src + 1
				end
			end
		end
	else
		local rowSize = channels * width * ffi.sizeof(format)
		for y=0,height-1 do
			ffi.copy(ffi.cast(formatp, buffer) + y * rowSize, rowPointer[y], rowSize)
		end
	end

	local palette
	if colorType == png.PNG_COLOR_TYPE_PALETTE then
		-- get the rgb entries
		local pal_pp = png_colorp_1()
		local numPal = int1()
--DEBUG(@5):print('png_get_PLTE', png_ptr, info_ptr, pal_pp, numPal)
		if 0 == png.png_get_PLTE(png_ptr, info_ptr, pal_pp, numPal) then
			error'png_get_PLTE failed'
		end
		-- see if there are alpha components as well
		local transparencyAlpha = png_bytep_1(nil)
		local numTransparent = int1(0)
		local transparencyColor = png_color_16p_1(nil)
		-- ... why would transparencyColor return content when it has no value or purpose here, and the spec says it isn't even stored?
--DEBUG(@5):print('png_get_tRNS', png_ptr, info_ptr, transparencyAlpha, numTransparent, transparencyColor)
		if 0 == png.png_get_tRNS(png_ptr, info_ptr, transparencyAlpha, numTransparent, transparencyColor) then
			-- then there's no transparency info ...
--DEBUG:assert.eq(transparencyAlpha[0],nil)	-- ... so this should be initialized to nil, right?
			transparencyAlpha[0] = nil	-- but I don't trust it
		end
		palette = {}
		for i=0,numPal[0]-1 do
			-- for now palettes are tables of entries of {r,g,b} from 0-255
			local entry = {
				pal_pp[0][i].red,
				pal_pp[0][i].green,
				pal_pp[0][i].blue,
			}
			palette[i+1] = entry
			if transparencyAlpha[0] ~= ffi.null then
				entry[4] = i < numTransparent[0]
					and transparencyAlpha[0][i]
					or 255
			end
		end
	else
		-- https://refspecs.linuxbase.org/LSB_3.1.0/LSB-Desktop-generic/LSB-Desktop-generic/libpng12.png.get.trns.1.html
		-- "*numTransparent shall be set to the number of transparency values *trans_values shall be set to the single color value specified for non-paletted images."
		-- hmm
		local transparencyAlpha = png_bytep_1(nil)
		local numTransparent = int1(0)
		local transparencyColor = png_color_16p_1(nil)	-- why would this return content when it has no value or purpose here, and the spec says it isn't even stored?
--DEBUG(@5):print('png_get_tRNS', png_ptr, info_ptr, transparencyAlpha, numTransparent, transparencyColor)
		if 0 == png.png_get_tRNS(png_ptr, info_ptr, transparencyAlpha, numTransparent, transparencyColor) then
--DEBUG(@5):print('...failed, assigning to nil')
			transparencyColor[0] = ffi.null
		end
--DEBUG(@5):if transparencyColor[0] ~= ffi.null then
--DEBUG(@5):	print('transparencyColor', transparencyColor[0].index, transparencyColor[0].red, transparencyColor[0].green, transparencyColor[0].blue, transparencyColor[0].gray)
--DEBUG(@5):end
		-- TODO HERE only for the single color set in transparencyColor
	end

	local result = {
		buffer = buffer,
		width = width,
		height = height,
		channels = channels,
		format = format,
		palette = palette,
	}
	--[[
	see if we can't load any other tags ...
	TODO save them too? maybe not, idk.
	what are all our chunks?
	http://www.libpng.org/pub/png/spec/1.2/PNG-Chunks.html
	IHDR - header - check
	PLTE - palette - check
	IDAT - image data - check
	IEND - ending - check
	tRNS - transparency - check i guess, for RGBA images i guess
	gAMA ...
	sRGB ...
	iCCP ...
	iTXt, tEXt, zTXt ...
	bKGD
	pHYs
	sCAL
	sBIT
	sPLT
	hIST
	png_uint_32 png_get_pCAL(png_const_structrp png_ptr, png_inforp info_ptr, png_charp *purpose, png_int_32 *X0, png_int_32 *X1, int * png_uint_32, int *nparams, png_charp *units, png_charpp *params);
	png_uint_32 png_get_oFFs(png_const_structrp png_ptr, png_const_inforp info_ptr, png_int_32 *offset_x, png_int_32 *offset_y, int *unit_type);
	png_uint_32 png_get_eXIf(png_const_structrp png_ptr, png_inforp info_ptr, png_bytep *exif);

	TODO TODO seems the png functions are groupe dbetween getters of chunk info directly, and lots of helper functions
	how about spearating these ot make sure we get all info
	btw htere's "get unknown chunks" but is there "get known chunks" ?
	--]]
--DEBUG(@5):print'reading gAMA'
	local gamma = double1()		-- TODO can I just pass a double into a double* and luajit will figure out to & it?
	if 0 ~= png.png_get_gAMA(png_ptr, info_ptr, gamma) then
		result.gamma = gamma[0]
	end

--DEBUG(@5):print'reading cHRM'
	local chromatics = double8()
	if 0 ~= png.png_get_cHRM(png_ptr, info_ptr, chromatics+0, chromatics+1, chromatics+2, chromatics+3, chromatics+4, chromatics+5, chromatics+6, chromatics+7) then
		result.chromatics = {
			whiteX = chromatics[0],
			whiteY = chromatics[1],
			redX = chromatics[2],
			redY = chromatics[3],
			greenX = chromatics[4],
			greenY = chromatics[5],
			blueX = chromatics[6],
			blueY = chromatics[7],
		}
	end

--DEBUG(@5):print'reading sRGB'
	local srgb = int1()
	if 0 ~= png.png_get_sRGB(png_ptr, info_ptr, srgb) then
		--[[
		0: Perceptual
		1: Relative colorimetric
		2: Saturation
		3: Absolute colorimetric
		--]]
		result.srgbIntent = srgb[0]
	end

--DEBUG(@5):print'reading iCCP'
	local name = charp1()
	local compressionType = int1()
	local profile = charp1()
	local profileLen = uint32_t_1()
	if 0 ~= png.png_get_iCCP(png_ptr, info_ptr, name, compressionType, profile, profileLen) then
		result.iccProfile = {
			name = name[0] ~= ffi.null and ffi.string(name[0]) or nil,
			-- "must always be set to PNG_COMPRESSION_TYPE_BASE"
			compressionType = compressionType[0],
			-- "International Color Consortium color profile"
			profile = profile[0] ~= ffi.null and ffi.string(profile[0], profileLen[0]) or nil,
		}
	end

--DEBUG(@5):print'reading text'
	local numText = png.png_get_text(png_ptr, info_ptr, nil, nil)
	if numText > 0 then
		local textPtr = png_textp_1()
		png.png_get_text(png_ptr, info_ptr, textPtr, nil)
		result.text = range(0,numText-1):mapi(function(i)
			local text = textPtr[0][i]
			return {
				compression = text.compression,
				key = text.key ~= ffi.null and ffi.string(text.key) or nil,
				text = text.text ~= ffi.null and ffi.string(text.text) or nil,--, text.text_length),
				text_length = text.text_length,	-- why is this needed? is our string null-term?
				itxt_length = text.itxt_length,	-- how about this? just to show compression size? or for reading compressed data?
				lang = text.lang ~= ffi.null and ffi.string(text.lang) or nil,
				lang_key = text.lang_key ~= ffi.null and ffi.string(text.lang_key) or nil,
			}
		end)
	end

--DEBUG(@5):print'reading bKGD'
	local background = png_color_16p_1()
	if 0 ~= png.png_get_bKGD(png_ptr, info_ptr, background) then
		result.background = {
			index = background[0].index,
			red = background[0].red,
			green = background[0].green,
			blue = background[0].blue,
			gray = background[0].gray,
		}
	end

--DEBUG(@5):print'reading pHYs'
	local resX = png_uint_32_1()
	local resY = png_uint_32_1()
	local unitType = int1()
	if 0 ~= png.png_get_pHYs(png_ptr, info_ptr, resX, resY, unitType) then
		result.physical = {
			resX = resX[0],
			resY = resY[0],
			unitType = unitType[0],
		}
	end

--DEBUG(@5):print'reading sCAL'
	local unit = int1()
	local width = double1()
	local height = double1()
	if 0 ~= png.png_get_sCAL(png_ptr, info_ptr, unit, width, height) then
		result.scale = {
			unit = unit[0],
			width = width[0],
			height = height[0],
		}
	end

--DEBUG(@5):print'reading sBIT'
	local sigBit = png_color_8p_1()
	if 0 ~= png.png_get_sBIT(png_ptr, info_ptr, sigBit) then
		result.significant = {
			red = sigBit[0].red,
			green = sigBit[0].green,
			blue = sigBit[0].blue,
			gray = sigBit[0].gray,
			alpha = sigBit[0].alpha,
		}
	end

--DEBUG(@5):print'reading sPLT'
	local spltEntries = png_sPLT_t_p_1 ()
	local numSuggestedPalettes = png.png_get_sPLT(png_ptr, info_ptr, spltEntries)
	if numSuggestedPalettes > 0 then
		result.suggestedPalettes = range(0,numSuggestedPalettes-1):mapi(function(i)
			local splt = spltEntries[0][i]
			return {
				name = splt.name ~= ffi.null and ffi.string(splt.name) or nil,
				depth = splt.depth,
				entries = range(0,splt.nentries-1):mapi(function(j)
					local entry = splt.entries[j]
					return {
						red = entry.red,
						green = entry.green,
						blue = entry.blue,
						alpha = entry.alpha,
						frequency = entry.frequency,
					}
				end),
			}
		end)
	end

--DEBUG(@5):print'reading hIST'
	local hist = png_uint_16_p_1()
	if 0 ~= png.png_get_hIST(png_ptr, info_ptr, hist)
	-- hist .. what is the size? the docs and no examples show.
	and result.palette then	-- TODO if not then something is wrong ...histogram is only supposed ot appear when there is a palette....
		-- TODO this and .palette, keep them cdata maybe?
		result.histogram = range(0,#result.palette-1):mapi(function(i)
			return hist[0][i]
		end)
	end

	local modTime = png_time_p_1 ()
	if 0 ~= png.png_get_tIME(png_ptr, info_ptr, modTime) then
		result.modTime = {
			year = modTime[0].year,
			month = modTime[0].month,
			day = modTime[0].day,
			hour = modTime[0].hour,
			minute = modTime[0].minute,
			second = modTime[0].second,
		}
	end

	-- TODO call this '.unknown' or just call this '.chunks' ?
	local chunks = png_unknown_chunk_p_1()
	local numChunks = png.png_get_unknown_chunks(png_ptr, info_ptr, chunks)
--DEBUG(@5):print('loading', numChunks, 'unknown chunks')
	if numChunks ~= 0 then
		result.unknown = {}
		for i=0,numChunks-1 do
			local chunk = chunks[i]
			local name = ffi.string(chunk.name)
			result.unknown[name] = {
				name = name,
				data = ffi.string(chunk.data, chunk.size),
				location = chunk.location,
			}
		end
	end

	-- http://www.libpng.org/pub/png/libpng-1.2.5-manual.html
	-- "If you are not interested, you can pass NULL."
	-- Why is this still crashing, and what am I missing?
	--local end_pp = png_infop_1()
	--end_pp[0] = ffi.cast(voidp, 0)

	-- using png_read_png ... not needed
	--[[ using png_read_info+png_read_image+png_read_end
--DEBUG(@5):print('png_read_end', png_ptr, nil)
	png.png_read_end(png_ptr, nil) -- ffi.cast(voidp, 0)) -- end_pp[0]) -- 0)
	--]]

	png.png_destroy_read_struct(png_pp, info_pp, nil)	--end_pp)

	return result
end

function PNGLoader:load(filename)
--DEBUG(@5):print('PNGLoader:load', filename)
	assert(filename, "expected filename")
	return select(2, assert(xpcall(function()

		local header = uint8_t_arr8()	-- 8 is the maximum size that can be checked
--DEBUG(@5):print('...header', header)

		-- open file and test for it being a png
--DEBUG(@5):print('fopen', filename, 'rb')
		local fp = stdio.fopen(filename, 'rb')
--DEBUG(@5):print('...got', fp)
		if fp == ffi.null then
			error'failed to open file for reading'
		end

--DEBUG(@5):print('fread', header, 1, 8, fp)
		stdio.fread(header, 1, 8, fp)
		if png.png_sig_cmp(header, 0, 8) ~= 0 then
			error'file is not recognized as a PNG'
		end

		local result = pngLoadBody{
			init = function(png_ptr)
--DEBUG(@5):print('png_init_io', png_ptr, fp)
				png.png_init_io(png_ptr, fp)
			end,
		}

		-- TODO this outside xpcall
		stdio.fclose(fp)

--DEBUG(@5):print('PNGLoader return', result)
		return result
	end, function(err)
--DEBUG(@5):print('PNGLoader got err', err) print(debug.traceback())
		return 'for filename '..filename..'\n'..err..'\n'..debug.traceback()
	end)))
end

function PNGLoader:loadMem(data)
--DEBUG(@5): print('PNGLoader:loadMem') --, data)
	assert(data, 'expected filename')
	local result

	-- is there a point to assert(xpcall) really? unless you're going to cleanup anything ...
	-- TODO proper cleanup
	assert(xpcall(function()
		local dataPtr = ffi.cast(uint8_t_p, data)
		local header = uint8_t_arr(headerSize)
		ffi.copy(header, dataPtr, headerSize)
		if png.png_sig_cmp(header, 0, headerSize) ~= 0 then
			error'file is not recognized as a PNG'
		end

		local i = ffi.cast(size_t, headerSize)
		local readCallback = ffi.cast(png_rw_ptr, function(
			png_ptr,	-- png_structp
			dst,		-- png_bytep
			size		-- size_t
		)
--DEBUG(@5): print('readCallback copy from', i)
			local dataPtr = ffi.cast(uint8_t_p, png.png_get_io_ptr(png_ptr))
--DEBUG: assert.ne(dataPtr, ffi.null)
--DEBUG: assert.le(i+size, #data)
			ffi.copy(dst, dataPtr+i, size)
			i = i + size
		end)

		local result = pngLoadBody{
			init = function(png_ptr)
--DEBUG(@5): print('png_set_read_fn', pngPtr, dataPtr, readCallback)
				png.png_set_read_fn(pngPtr, dataPtr, readCallback)
			end,
		}

		readCallback:free()	-- or don't, and just cast it once and cache it

	end, function(err)
		return 'PNGLoader:loadMem:\n'..err..'\n'..debug.traceback()
	end))

	-- same as in Image:load(filename)
	-- consider consolidating or not idk
	return setmetatable(result, require 'image')
end

-- https://cplusplus.com/forum/general/125209/
function PNGLoader:save(args)
	-- args:
	local filename = assert.index(args, 'filename')
	local width = assert.index(args, 'width')
	local height = assert.index(args, 'height')
	local channels = assert.index(args, 'channels')
	local format = assert.index(args, 'format')
	local buffer = assert.index(args, 'buffer')
	local palette = args.palette	 -- optional, table of N tables of 3 values for RGB constrained to 0-255 for now

	assert.eq(ffi.typeof(format), format, "format is not a ctype")

	local fp
	local png_pp = png_structp_1()
	local info_pp = png_infop_1()
	local res, err = xpcall(function()
		fp = stdio.fopen(filename, 'wb')
		if fp == ffi.null then
			fp = nil
			error("failed to open file "..filename.." for writing")
		end

		-- initialize stuff
		local png_ptr = png.png_create_write_struct(self.libpngVersion, nil, nil, nil)
		if png_ptr == ffi.null then
			error "[write_png_file] png_create_write_struct failed"
		end
		png_pp[0] = png_ptr

		local info_ptr = png.png_create_info_struct(png_ptr)
		if info_ptr == ffi.null then
			error("[write_png_file] png_create_info_struct failed")
		end
		info_pp[0] = info_ptr

		png.png_init_io(png_ptr, fp)

		--png.png_set_compression_level(png_ptr, png.Z_BEST_COMPRESSION)

		png.png_set_IHDR(
			png_ptr,
			info_ptr,
			width,
			height,
			bit.lshift(ffi.sizeof(format), 3),
			({
				[1] = palette
					and png.PNG_COLOR_TYPE_PALETTE
					or png.PNG_COLOR_TYPE_GRAY,
				[2] = png.PNG_COLOR_TYPE_GRAY_ALPHA,
				[3] = png.PNG_COLOR_TYPE_RGB,
				[4] = png.PNG_COLOR_TYPE_RGB_ALPHA,
			})[channels] or error("got unknown channels "..tostring(channels)),
			png.PNG_INTERLACE_NONE,
			png.PNG_COMPRESSION_TYPE_BASE,
			png.PNG_FILTER_TYPE_BASE)

		if palette then
			local numPal = #palette
			assert.le(numPal, png.PNG_MAX_PALETTE_LENGTH, 'palette size exceeded')
			local pngpal = png_color_arr(numPal)
			local hasPalAlpha
			for i,c in ipairs(palette) do
				pngpal[i-1].red = c[1]
				pngpal[i-1].green = c[2]
				pngpal[i-1].blue = c[3]
				if c[4] ~= nil and c[4] ~= 255 then
					hasPalAlpha = true
				end
			end
			png.png_set_PLTE(png_ptr, info_ptr, pngpal, numPal)

			if hasPalAlpha then
				local numTransparent = numPal
				local transparencyAlpha = png_byte_arr(numPal)
				for i,c in ipairs(palette) do
					transparencyAlpha[i-1] = c[4] or 255
				end
				-- can this be nil?
				--local transparencyColor = png_color_16_1(nil)
				local transparencyColor
				png.png_set_tRNS(png_ptr, info_ptr, transparencyAlpha, numTransparent, transparencyColor);
			end
		end

		png.png_write_info(png_ptr, info_ptr)

		local rowptrs = uint8_t_p_arr(height)
		for y=0,height-1 do
			-- [[ do I need to allocate these myself?
			rowptrs[y] = buffer + channels*width*y
			--]]
			--[[ or does png_write_end / png_destroy_write_struct free them?
			-- and why does the sample code allocate 2x its requirement?
			rowptrs[y] = ffi.C.malloc(2 * channels * width)
			--rowptrs[y] = ffi.C.malloc(channels * width)
			ffi.copy(rowptrs[y], buffer + channels*width*y, channels * width)
			--]]
		end
		png.png_write_image(png_ptr, rowptrs)

		if args.unknown then
			local names = table.keys(args.unknown)
			local numChunks = #names
			local chunks = png_unknown_chunk_arr(numChunks)
			for i,name in ipairs(names) do	-- does order matter?
				local src = args.unknown[name]
				local chunk = chunks[i-1]
				ffi.fill(chunk.name, 5)
				ffi.copy(chunk.name, name, math.min(#name, 5))
				chunk.data = ffi.cast(png_bytep, src.data)
				chunk.size = #src.data
				chunk.location = png.PNG_AFTER_IDAT
			end
			png.png_set_keep_unknown_chunks(png_ptr, png.PNG_HANDLE_CHUNK_ALWAYS, nil, 0)
			png.png_set_unknown_chunks(png_ptr, info_ptr, chunks, numChunks)
			for i=0,numChunks-1 do
				png.png_set_unknown_chunk_location(png_ptr, info_ptr, i, png.PNG_AFTER_IDAT)
			end
		end

		png.png_write_end(png_ptr, info_ptr)
	end, function(err)
		return err..'\n'..debug.traceback()
	end)

	-- cleanup
	if png_pp[0] ~= ffi.null then
		-- TODO if info_pp[0] == null then do I have to pass nil instead of info_pp ?
		png.png_destroy_write_struct(png_pp, info_pp)
	end
	if fp then
		stdio.fclose(fp)
	end

	-- rethrow?
	if err then error(err) end
end

return PNGLoader
