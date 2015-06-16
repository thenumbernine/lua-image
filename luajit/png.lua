local ffi = require 'ffi'
require 'ffi.c.string'	--memcpy
local png = require 'ffi.png'
local exports = {}

local libpngVersion = "1.5.13"

exports.load = function(filename)
	assert(filename, "expected filename")

	local header = ffi.new('char[8]')	-- 8 is the maximum size that can be checked

	-- open file and test for it being a png */
	local fp = ffi.C.fopen(filename, 'rb')
	if not fp then
		error(string.format("[read_png_file] File %s could not be opened for reading", filename))
	end
	
	ffi.C.fread(header, 1, 8, fp)
	if png.png_sig_cmp(header, 0, 8) ~= 0 then
		error(string.format("[read_png_file] File %s is not recognized as a PNG file", filename))
	end

	-- initialize stuff */
	local png_ptr = png.png_create_read_struct(libpngVersion, nil, nil, nil)

	if not png_ptr then
		error("[read_png_file] png_create_read_struct failed")
	end

	local info_ptr = png.png_create_info_struct(png_ptr)
	if not info_ptr then
		error("[read_png_file] png_create_info_struct failed")
	end

	png.png_init_io(png_ptr, fp)
	png.png_set_sig_bytes(png_ptr, 8)

	png.png_read_png(png_ptr, info_ptr, png.PNG_TRANSFORM_IDENTITY, nil)

	local width = png.png_get_image_width(png_ptr, info_ptr)
	local height = png.png_get_image_height(png_ptr, info_ptr)
	local colorType = png.png_get_color_type(png_ptr, info_ptr)
	local bit_depth = png.png_get_bit_depth(png_ptr, info_ptr)
	if colorType ~= png.PNG_COLOR_TYPE_RGB then
		error("expected colorType PNG_COLOR_TYPE_RGB, got "..colorType)
	end
	assert(bit_depth == 8, "can only handle 8-bit images at the moment")

	local number_of_passes = png.png_set_interlace_handling(png_ptr)
	png.png_read_update_info(png_ptr, info_ptr)

	-- read file */

	assert(ffi.sizeof('png_byte') == 1)
	local row_pointers = png.png_get_rows(png_ptr, info_ptr)
	
	local data = ffi.new('unsigned char[?]', width * height * 3)
	for y=0,height-1 do
		ffi.C.memcpy(ffi.cast('char*', data) + 3*width*(height-1-y), row_pointers[y], 3 * width)
	end

	-- TODO free row_pointers?	

	ffi.C.fclose(fp)

	return {data=data, width=width, height=height}
end

exports.save = function(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local data = assert(args.data, "expected data")
	
	local fp = ffi.C.fopen(filename, 'wb')
	if not fp then error("failed to open file "..filename.." for writing") end

	-- initialize stuff */
	local png_ptr = png.png_create_write_struct(libpngVersion, nil, nil, nil)

	if not png_ptr then
		error "[write_png_file] png_create_write_struct failed"
	end

	local info_ptr = png.png_create_info_struct(png_ptr)
	if not info_ptr then
		error("[write_png_file] png_create_info_struct failed")
	end

	png.png_init_io(png_ptr, fp)

	png.png_set_IHDR(png_ptr, info_ptr, width, height,
		8, png.PNG_COLOR_TYPE_RGB, png.PNG_INTERLACE_NONE,
		png.PNG_COMPRESSION_TYPE_BASE, png.PNG_FILTER_TYPE_BASE)

	png.png_write_info(png_ptr, info_ptr)

	local rowptrs = ffi.new('unsigned char *[?]', height)
	for y=0,height-1 do
		rowptrs[y] = data + 3*width*(height-1-y)
	end
	png.png_write_image(png_ptr, rowptrs)

	png.png_write_end(png_ptr, nil)

	-- close file
	ffi.C.fclose(fp)
end

return exports

