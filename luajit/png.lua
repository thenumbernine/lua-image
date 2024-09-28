local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local range = require 'ext.range'
local asserteq = require 'ext.assert'.eq
local assertle = require 'ext.assert'.le
local assertindex = require 'ext.assert'.index
local stdio = require 'ffi.req' 'c.stdio'	-- use stdio instead of ffi.C for browser compat
local png = require 'ffi.req' 'png'
local gcmem = require 'ext.gcmem'

local PNGLoader = Loader:subclass()

-- TODO just pick a version and stick with it?
if ffi.os == 'Windows' then
	PNGLoader.libpngVersion = '1.6.37'
elseif ffi.os == 'OSX' then
	PNGLoader.libpngVersion = '1.6.43'
elseif ffi.os == 'Linux' then
	PNGLoader.libpngVersion = '1.6.39'
end

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
	if image.format == 'float' or image.format == 'double' then
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

local errorCallback = ffi.cast('png_error_ptr', function(struct, msg)
	print('png error:', ffi.string(msg))
end)

local warningCallback = ffi.cast('png_error_ptr', function(struct, msg)
	print('png warning:', ffi.string(msg))
end)

function PNGLoader:load(filename)
	assert(filename, "expected filename")
	return select(2, assert(xpcall(function()

		local header = gcmem.new('char',8)	-- 8 is the maximum size that can be checked

		-- open file and test for it being a png
		local fp = stdio.fopen(filename, 'rb')
		if fp == nil then
			error(string.format("[read_png_file] File %s could not be opened for reading", filename))
		end

		stdio.fread(header, 1, 8, fp)
		if png.png_sig_cmp(header, 0, 8) ~= 0 then
			error(string.format("[read_png_file] File %s is not recognized as a PNGLoader file", filename))
		end

		-- initialize stuff
		local png_ptr = png.png_create_read_struct(self.libpngVersion, nil, errorCallback, warningCallback)
		if png_ptr == nil then
			error("[read_png_file] png_create_read_struct failed")
		end

		local png_pp = ffi.new'png_structp[1]'
		png_pp[0] = png_ptr

		local info_ptr =  png.png_create_info_struct(png_ptr)
		if info_ptr == nil then
			error("[read_png_file] png_create_info_struct failed")
		end

		local info_pp = ffi.new'png_infop[1]'
		info_pp[0] = info_ptr

		png.png_init_io(png_ptr, fp)
		png.png_set_sig_bytes(png_ptr, 8)

		png.png_read_png(png_ptr, info_ptr, png.PNG_TRANSFORM_IDENTITY, nil)

		local width = png.png_get_image_width(png_ptr, info_ptr)
		local height = png.png_get_image_height(png_ptr, info_ptr)
		local colorType = png.png_get_color_type(png_ptr, info_ptr)
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

		-- TODO replace png_byte etc in the header, lighten the load on luajit ffi
		assert(ffi.sizeof('png_byte') == 1)
		local rowPointer = png.png_get_rows(png_ptr, info_ptr)
		local channels = ({
			[png.PNG_COLOR_TYPE_GRAY] = 1,
			[png.PNG_COLOR_TYPE_PALETTE] = 1,
			[png.PNG_COLOR_TYPE_GRAY_ALPHA] = 2,
			[png.PNG_COLOR_TYPE_RGB] = 3,
			[png.PNG_COLOR_TYPE_RGB_ALPHA] = 4,
		})[colorType] or error('got unknown colorType')
		local format
		if bitDepth <= 8 then
			format = 'uint8_t'
		elseif bitDepth == 16 then
			format = 'uint16_t'
		else
			error("got unknown bit depth: "..tostring(bitDepth))
		end
		local buffer = gcmem.new(format, width * height * channels)
		-- read buffer from rows directly
		if bitDepth < 8 then
			asserteq(channels, 1, "I don't support channels>1 for bitDepth<8")
			local bitMask = assertindex({
				[1] = 1,
				[2] = 3,
				[4] = 0xf,
				[8] = 0xff,
			}, bitDepth)
			local dst = buffer
			for y=0,height-1 do
				local src = ffi.cast('png_byte*', rowPointer[y])
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
			local rowSize = channels*width*ffi.sizeof(format)
			for y=0,height-1 do
				ffi.copy(ffi.cast(format..'*', buffer) + y * rowSize, rowPointer[y], rowSize)
			end
		end

		local palette
		if colorType == png.PNG_COLOR_TYPE_PALETTE then
			local pal_pp = ffi.new'png_color*[1]'
			local numPal = ffi.new'int[1]'
			if 0 == png.png_get_PLTE(png_ptr, info_ptr, pal_pp, numPal) then
				error("[read_png_file] png_get_PLTE failed")
			end
			palette = {}
			for i=1,numPal[0] do
				-- for now palettes are tables of entries of {r,g,b} from 0-255
				palette[i] = {
					pal_pp[0][i-1].red,
					pal_pp[0][i-1].green,
					pal_pp[0][i-1].blue,
				}
			end
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
--DEBUG:print'reading gAMA'
		local gamma = ffi.new'double[1]'
		if 0 ~= png.png_get_gAMA(png_ptr, info_ptr, gamma) then
			result.gamma = gamma[0]
		end

--DEBUG:print'reading cHRM'
		local chromatics = ffi.new'double[8]'
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

--DEBUG:print'reading sRGB'
		local srgb = ffi.new'int[1]'
		if 0 ~= png.png_get_sRGB(png_ptr, info_ptr, srgb) then
			--[[
			0: Perceptual
			1: Relative colorimetric
			2: Saturation
			3: Absolute colorimetric
			--]]
			result.srgbIntent = srgb[0]
		end

--DEBUG:print'reading iCCP'
		local name = ffi.new'char*[1]'
		local compressionType = ffi.new'int[1]'
		local profile = ffi.new'char*[1]'
		local profileLen = ffi.new'uint32_t[1]'
		if 0 ~= png.png_get_iCCP(png_ptr, info_ptr, name, compressionType, profile, profileLen) then
			result.iccProfile = {
				name = name[0] ~= nil and ffi.string(name[0]) or nil,
				-- "must always be set to PNG_COMPRESSION_TYPE_BASE"
				compressionType = compressionType[0],
				-- "International Color Consortium color profile"
				profile = profile[0] ~= nil and ffi.string(profile[0], profileLen[0]) or nil,
			}
		end

--DEBUG:print'reading text'
		local numText = png.png_get_text(png_ptr, info_ptr, nil, nil)
		if numText > 0 then
			local textPtr = ffi.new('png_text*[1]')
			png.png_get_text(png_ptr, info_ptr, textPtr, nil)
			result.text = range(0,numText-1):mapi(function(i)
				local text = textPtr[0][i]
				return {
					compression = text.compression,
					key = text.key ~= nil and ffi.string(text.key) or nil,
					text = text.text ~= nil and ffi.string(text.text) or nil,--, text.text_length),
					text_length = text.text_length,	-- why is this needed? is our string null-term?
					itxt_length = text.itxt_length,	-- how about this? just to show compression size? or for reading compressed data?
					lang = text.lang ~= nil and ffi.string(text.lang) or nil,
					lang_key = text.lang_key ~= nil and ffi.string(text.lang_key) or nil,
				}
			end)
		end

--DEBUG:print'reading bKGD'
		local background = ffi.new'png_color_16*[1]'
		if 0 ~= png.png_get_bKGD(png_ptr, info_ptr, background) then
			result.background = {
				index = background[0].index,
				red = background[0].red,
				green = background[0].green,
				blue = background[0].blue,
				gray = background[0].gray,
			}
		end

--DEBUG:print'reading pHYs'
		local resX = ffi.new'png_uint_32[1]'
		local resY = ffi.new'png_uint_32[1]'
		local unitType = ffi.new'int[1]'
		if 0 ~= png.png_get_pHYs(png_ptr, info_ptr, resX, resY, unitType) then
			result.physical = {
				resX = resX[0],
				resY = resY[0],
				unitType = unitType[0],
			}
		end

--DEBUG:print'reading sCAL'
		local unit = ffi.new'int[1]'
		local width = ffi.new'double[1]'
		local height = ffi.new'double[1]'
		if 0 ~= png.png_get_sCAL(png_ptr, info_ptr, unit, width, height) then
			result.scale = {
				unit = unit[0],
				width = width[0],
				height = height[0],
			}
		end

--DEBUG:print'reading sBIT'
		local sigBit = ffi.new'png_color_8*[1]'
		if 0 ~= png.png_get_sBIT(png_ptr, info_ptr, sigBit) then
			result.significant = {
				red = sigBit[0].red,
				green = sigBit[0].green,
				blue = sigBit[0].blue,
				gray = sigBit[0].gray,
				alpha = sigBit[0].alpha,
			}
		end

--DEBUG:print'reading sPLT'
		local spltEntries = ffi.new'png_sPLT_t*[1]'
		local numSuggestedPalettes = png.png_get_sPLT(png_ptr, info_ptr, spltEntries)
		if numSuggestedPalettes > 0 then
			result.suggestedPalettes = range(0,numSuggestedPalettes-1):mapi(function(i)
				local splt = spltEntries[0][i]
				return {
					name = splt.name ~= nil and ffi.string(splt.name) or nil,
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

--DEBUG:print'reading hIST'
		local hist = ffi.new'png_uint_16p[1]'
		if 0 ~= png.png_get_hIST(png_ptr, info_ptr, hist)
		-- hist .. what is the size? the docs and no examples show.
		and result.palette then	-- TODO if not then something is wrong ...histogram is only supposed ot appear when there is a palette....
			-- TODO this and .palette, keep them cdata maybe?
			result.histogram = range(0,#result.palette-1):mapi(function(i)
				return hist[0][i]
			end)
		end

		local modTime = ffi.new'png_time*[1]'
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

		--png_get_unknown_chunks = [[int png_get_unknown_chunks(png_const_structrp png_ptr, png_inforp info_ptr, png_unknown_chunkpp entries);]],

		-- http://www.libpng.org/pub/png/libpng-1.2.5-manual.html
		-- "If you are not interested, you can pass NULL."
		-- Why is this still crashing, and what am I missing?
		--local end_pp = ffi.new'png_infop[1]'
		--end_pp[0] = ffi.cast('void*', 0)
		--png.png_read_end(png_ptr, nil) -- ffi.cast('void*', 0)) -- end_pp[0]) -- 0)
		png.png_destroy_read_struct(png_pp, info_pp, nil)	--end_pp)
		stdio.fclose(fp)

		return result
	end, function(err)
		return 'for filename '..filename..'\n'..err..'\n'..debug.traceback()
	end)))
end

-- https://cplusplus.com/forum/general/125209/
function PNGLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local format = assert(args.format, "expected format")
	local buffer = assert(args.buffer, "expected buffer")
	local palette = args.palette	 -- optional, table of N tables of 3 values for RGB constrained to 0-255 for now

	local fp
	local png_pp = ffi.new'png_structp[1]'
	local info_pp = ffi.new'png_infop[1]'
	local res, err = xpcall(function()
		fp = stdio.fopen(filename, 'wb')
		if fp == nil then error("failed to open file "..filename.." for writing") end

		-- initialize stuff
		local png_ptr = png.png_create_write_struct(self.libpngVersion, nil, nil, nil)
		if png_ptr == nil then
			error "[write_png_file] png_create_write_struct failed"
		end
		png_pp[0] = png_ptr

		local info_ptr = png.png_create_info_struct(png_ptr)
		if info_ptr == nil then
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
			assertle(numPal, png.PNG_MAX_PALETTE_LENGTH, 'palette size exceeded')
			local pngpal = gcmem.new('png_color', numPal)
			for i,c in ipairs(palette) do
				pngpal[i-1].red = c[1]
				pngpal[i-1].green = c[2]
				pngpal[i-1].blue = c[3]
			end
			png.png_set_PLTE(png_ptr, info_ptr, pngpal, numPal)
		end

		png.png_write_info(png_ptr, info_ptr)

		local rowptrs = gcmem.new('uint8_t *', height)
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
		png.png_write_end(png_ptr, info_ptr)
	end, function(err)
		return err..'\n'..debug.traceback()
	end)

	-- cleanup
	if png_pp[0] ~= nil then
		-- TODO if info_pp[0] == null then do I have to pass nil instead of info_pp ?
		png.png_destroy_write_struct(png_pp, info_pp)
	end
	if fp ~= nil then
		stdio.fclose(fp)
	end

	-- rethrow?
	if err then error(err) end
end

return PNGLoader
