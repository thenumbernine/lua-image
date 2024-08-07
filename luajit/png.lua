local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
require 'ffi.req' 'c.string'	--memcpy
local stdio = require 'ffi.req' 'c.stdio'	-- use stdio instead of ffi.C for browser compat
local png = require 'ffi.req' 'png'
local gcmem = require 'ext.gcmem'

local PNGLoader = Loader:subclass()

-- TODO just pick a version and stick with it?
if ffi.os == 'Windows' then
	PNGLoader.libpngVersion = '1.6.37'
elseif ffi.os == 'OSX' then
	PNGLoader.libpngVersion = '1.5.13'
elseif ffi.os == 'Linux' then
	PNGLoader.libpngVersion = '1.6.39'
end

-- replace the base loader which forced rgb
-- instead, allow for rgba
function PNGLoader:prepareImage(image)
	if image.channels ~= 3 and image.channels ~= 4 then
		image = image:rgb()
	end
	if image.format == 'float' or image.format == 'double' then
		image = image:clamp(0,1)
	end
	if image.format ~= 'unsigned char' then
		image = image:setFormat'unsigned char'
	end
	assert(image.channels == 3 or image.channels == 4, "expected 3 or 4 channels")
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

		local info_ptr = png.png_create_info_struct(png_ptr)
		if info_ptr == nil then
			error("[read_png_file] png_create_info_struct failed")
		end

		png.png_init_io(png_ptr, fp)
		png.png_set_sig_bytes(png_ptr, 8)

		png.png_read_png(png_ptr, info_ptr, png.PNG_TRANSFORM_IDENTITY, nil)

		local width = png.png_get_image_width(png_ptr, info_ptr)
		local height = png.png_get_image_height(png_ptr, info_ptr)
		local colorType = png.png_get_color_type(png_ptr, info_ptr)
		local bit_depth = png.png_get_bit_depth(png_ptr, info_ptr)
		local colorTypePalette = png.PNG_COLOR_MASK_PALETTE + png.PNG_COLOR_MASK_COLOR
		if colorType ~= png.PNG_COLOR_TYPE_RGB
		and colorType ~= png.PNG_COLOR_TYPE_RGB_ALPHA
		and colorType ~= colorTypePalette
		then
			error("expected colorType to be PNG_COLOR_TYPE_RGB or PNG_COLOR_TYPE_RGB_ALPHA, got "..colorType)
		end
		assert(bit_depth == 8, "can only handle 8-bit images at the moment")

		local number_of_passes = png.png_set_interlace_handling(png_ptr)
		-- looks like png 1.5 needed this but png 1.6 doesn't
		--png.png_read_update_info(png_ptr, info_ptr)

		-- read file

		assert(ffi.sizeof('png_byte') == 1)
		local row_pointers = png.png_get_rows(png_ptr, info_ptr)
		local channels = ({
				[png.PNG_COLOR_TYPE_RGB] = 3,
				[png.PNG_COLOR_TYPE_RGB_ALPHA] = 4,
				[colorTypePalette] = 1,
			})[colorType] or error('got unknown colorType')
		local data = gcmem.new('unsigned char', width * height * channels)
		-- read data from rows directly
		for y=0,height-1 do
			ffi.C.memcpy(ffi.cast('unsigned char*', data) + channels*width*y, row_pointers[y], channels*width)
		end

		-- TODO free row_pointers?

		stdio.fclose(fp)

		return {
			data = data,
			width = width,
			height = height,
			channels = channels,
		}
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
	local data = assert(args.data, "expected data")

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
			8,
			({
				[3] = png.PNG_COLOR_TYPE_RGB,
				[4] = png.PNG_COLOR_TYPE_RGB_ALPHA,
			})[channels] or error("got unknown channels "..tostring(channels)),
			png.PNG_INTERLACE_NONE,
			png.PNG_COMPRESSION_TYPE_BASE,
			png.PNG_FILTER_TYPE_BASE)
		png.png_write_info(png_ptr, info_ptr)

		local rowptrs = gcmem.new('unsigned char *', height)
		for y=0,height-1 do
			-- [[ do I need to allocate these myself?
			rowptrs[y] = data + channels*width*y
			--]]
			--[[ or does png_write_end / png_destroy_write_struct free them?
			-- and why does the sample code allocate 2x its requirement?
			rowptrs[y] = ffi.C.malloc(2 * channels * width)
			--rowptrs[y] = ffi.C.malloc(channels * width)
			ffi.copy(rowptrs[y], data + channels*width*y, channels * width)
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
