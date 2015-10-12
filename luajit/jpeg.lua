local Loader = require 'image.luajit.loader'
local class = require 'ext.class'
local ffi = require 'ffi'
require 'ffi.c.stdio'	-- fopen
local jpeg = require 'ffi.jpeg'
local gcmem = require 'ext.gcmem'

local JPEGLoader = class(Loader)

ffi.cdef[[
struct my_error_mgr {
	struct jpeg_error_mgr pub;	/* "public" fields */
	jmp_buf setjmp_buffer;	/* for return to caller */
};
]]
local errorExt = function(cinfo)
	-- nothing? return?
	local myerr = ffi.cast('my_error_ptr', cinfo[0].err)
	ffi.C.longjmp(myerr[0].setjmp_buffer, 1)
end
local errorExitPtr = ffi.cast('void(*)(j_common_ptr)', errorExit)

function JPEGLoader:load(filename)
	local cinfo = gcmem.new('struct jpeg_decompress_struct', 1)
	local jerr = gcmem.new('struct my_error_mgr', 1)

	local infile = ffi.C.fopen(filename, 'rb')
	if infile == nil then
		error("can't open "..filename)
	end

	cinfo[0].err = jpeg.jpeg_std_error( ffi.cast('struct jpeg_error_mgr*',jerr))
	jerr[0].pub.error_exit = errorExitPtr
	if ffi.C.setjmp(jerr[0].setjmp_buffer) ~= 0 then
		jpeg.jpeg_destroy_decompress(cinfo)
		ffi.C.fclose(infile)
		return
	end

	jpeg.jpeg_create_decompress(cinfo)
	jpeg.jpeg_stdio_src(cinfo, infile)

	jpeg.jpeg_read_header(cinfo, 1)
	jpeg.jpeg_start_decompress(cinfo)
-- TODO :
	local row_stride = cinfo[0].output_width * cinfo[0].output_components
	local buffer = cinfo[0].mem[0].alloc_sarray(ffi.cast('j_common_ptr', cinfo), jpeg.JPOOL_IMAGE, row_stride, 1)

	local width = cinfo[0].output_width
	local height = cinfo[0].output_height
	local channels = 3
	local data = gcmem.new('unsigned char', width * height * channels)

	local y = 0
	while cinfo[0].output_scanline < cinfo[0].output_height do
		jpeg.jpeg_read_scanlines(cinfo, buffer, 1)
		ffi.copy(data + channels * y * width, buffer[0], channels * width)
		y=y+1
	end
	jpeg.jpeg_finish_decompress(cinfo)
	jpeg.jpeg_destroy_decompress(cinfo)
	ffi.C.fclose(infile)

	return {
		data = data,
		width = width,
		height = height,
		channels = channels,
	}
end

function JPEGLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local data = assert(args.data, "expected data")
	local quality = args.quality or 90

	local cinfo = gcmem.new('struct jpeg_compress_struct', 1)
	local jerr = gcmem.new('struct jpeg_error_mgr', 1)
	--FILE * outfile;		/* target file */
	--int row_stride;		/* physical row width in image buffer */

	cinfo[0].err = jpeg.jpeg_std_error(jerr)
	jpeg.jpeg_create_compress(cinfo)

	local outfile = ffi.C.fopen(filename, 'wb')
	if outfile == nil then
  		error("can't open "..filename)
	end
	jpeg.jpeg_stdio_dest(cinfo, outfile)

	cinfo[0].image_width = width
	cinfo[0].image_height = height
	assert(channels == 3)
	cinfo[0].input_components = channels
	cinfo[0].in_color_space = jpeg.JCS_RGB
  
	jpeg.jpeg_set_defaults(cinfo)
  
  	jpeg.jpeg_set_quality(cinfo, quality, 1)

  	jpeg.jpeg_start_compress(cinfo, 1)

  	local row_stride = width * 3

	local row_pointer = gcmem.new('JSAMPROW', 1)
	while cinfo[0].next_scanline < cinfo[0].image_height do
		row_pointer[0] = data + cinfo[0].next_scanline * row_stride
		jpeg.jpeg_write_scanlines(cinfo, row_pointer, 1)
	end

	jpeg.jpeg_finish_compress(cinfo)

	ffi.C.fclose(outfile)

  	jpeg.jpeg_destroy_compress(cinfo)
end

return JPEGLoader
