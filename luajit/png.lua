local Loader = require 'image.luajit.loader'
local class = require 'ext.class'
local ffi = require 'ffi'
require 'ffi.c.string'	--memcpy
local png = require 'ffi.png'
local gcmem = require 'ext.gcmem'

local PNG = class(Loader)

-- TODO something that adapts better
if ffi.os == 'Windows' then
	-- the malkia ufo header says 1.4.19 beta 
	-- but 1.5.13 works ...
	PNG.libpngVersion = "1.5.13"
	-- but I'm going to upgrade to 1.6.25
	--PNG.libpngVersion = "1.6.25"
elseif ffi.os == 'OSX' then
	-- this is the malkia ufo libpng.dylib version on osx:
	PNG.libpngVersion = "1.7.0beta66"
elseif ffi.os == 'Linux' then
	PNG.libpngVersion = "1.6.20"
end

-- replace the base loader which forced rgb
-- instead, allow for rgba
function PNG:prepareImage(image)
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

function PNG:load(filename)
	assert(filename, "expected filename")
	return select(2, assert(xpcall(function()
		local header = gcmem.new('char',8)	-- 8 is the maximum size that can be checked

		-- open file and test for it being a png
		local fp = ffi.C.fopen(filename, 'rb')
		if fp == nil then
			error(string.format("[read_png_file] File %s could not be opened for reading", filename))
		end

		ffi.C.fread(header, 1, 8, fp)
		if png.png_sig_cmp(header, 0, 8) ~= 0 then
			error(string.format("[read_png_file] File %s is not recognized as a PNG file", filename))
		end

		-- initialize stuff
		local png_ptr = png.png_create_read_struct(self.libpngVersion, nil, nil, nil)

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
		if colorType ~= png.PNG_COLOR_TYPE_RGB
		and colorType ~= png.PNG_COLOR_TYPE_RGB_ALPHA
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
			})[colorType] or error('got unknown colorType')
		local data = gcmem.new('unsigned char', width * height * channels)
		-- read data from rows directly
		for y=0,height-1 do
			ffi.C.memcpy(ffi.cast('unsigned char*', data) + channels*width*y, row_pointers[y], channels*width)
		end

		-- TODO free row_pointers?

		ffi.C.fclose(fp)

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

function PNG:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local data = assert(args.data, "expected data")

	local fp = ffi.C.fopen(filename, 'wb')
	if fp == nil then error("failed to open file "..filename.." for writing") end

	-- initialize stuff
	local png_ptr = png.png_create_write_struct(self.libpngVersion, nil, nil, nil)

	if png_ptr == nil then
		error "[write_png_file] png_create_write_struct failed"
	end

	local info_ptr = png.png_create_info_struct(png_ptr)
	if info_ptr == nil then
		error("[write_png_file] png_create_info_struct failed")
	end

	png.png_init_io(png_ptr, fp)

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
		rowptrs[y] = data + channels*width*y
	end
	png.png_write_image(png_ptr, rowptrs)

	png.png_write_end(png_ptr, nil)

	-- close file
	ffi.C.fclose(fp)
end

return PNG
