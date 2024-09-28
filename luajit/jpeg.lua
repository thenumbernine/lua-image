local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local stdio = require 'ffi.req' 'c.stdio'	-- fopen, fclose, FILE ... use stdio instead of ffi.C for browser compat
--[[ using longjmp like in the libjpeg example code
require 'ffi.req' 'c.setjmp'	-- jmp_buf ... hmm, can I use something else?  something that won't break Lua?
--]]
local jpeg = require 'ffi.req' 'jpeg'
local gcmem = require 'ext.gcmem'

--[[ debugging
local oldjpeg = jpeg
local jpeg = setmetatable({}, {
	__index = function(t,k)
		print(debug.traceback())
		return oldjpeg[k]
	end,
})
--]]

local JPEGLoader = Loader:subclass()

ffi.cdef[[
struct my_error_mgr {
	struct jpeg_error_mgr pub;	// "public" fields
/* using lua errors */
	FILE *file;
	int writing;	//0 = reading, 1 = writing
/**/
/* using longjmp like in the libjpeg example code * /
	jmp_buf setjmp_buffer;		// for return to caller
/**/
};
]]
local function handleError(cinfo)
	local myerr = ffi.cast('struct my_error_mgr*', cinfo[0].err)
-- [[ using lua errors
	stdio.fclose(myerr[0].file)
	if myerr[0].writing then
		jpeg.jpeg_destroy_compress(cinfo)
	else
		jpeg.jpeg_destroy_decompress(cinfo)
	end
	-- TODO get why it failed
	error('jpeg failed')
---]]
--[[ using longjmp like in the libjpeg example code
	ffi.C.longjmp(myerr[0].setjmp_buffer, 1)
--]]
end
local handleErrorCallback = ffi.cast('void(*)(j_common_ptr)', handleError)

function JPEGLoader:load(filename)
	local cinfo = gcmem.new('struct jpeg_decompress_struct', 1)
	local myerr = gcmem.new('struct my_error_mgr', 1)

	local infile = stdio.fopen(filename, 'rb')
	if infile == nil then
		error("can't open "..filename)
	end
-- [[ using lua errors
	myerr[0].file = infile	-- store here for closing in the error handler if something goes wrong
	myerr[0].writing = 0
--]]
	cinfo[0].err = jpeg.jpeg_std_error(ffi.cast('struct jpeg_error_mgr *', myerr))

	myerr[0].pub.error_exit = handleErrorCallback
--[[ using longjmp like in the libjpeg example code
	if ffi.C.setjmp(myerr[0].setjmp_buffer) ~= 0 then
		jpeg.jpeg_destroy_compress(cinfo)
		stdio.fclose(outfile)
		return
	end
--]]

	jpeg.jpeg_create_decompress(cinfo)
	jpeg.jpeg_stdio_src(cinfo, infile)

	jpeg.jpeg_read_header(cinfo, 1)
	jpeg.jpeg_start_decompress(cinfo)
-- TODO :
	local row_stride = cinfo[0].output_width * cinfo[0].output_components
	local tmpbuffer = cinfo[0].mem[0].alloc_sarray(ffi.cast('j_common_ptr', cinfo), jpeg.JPOOL_IMAGE, row_stride, 1)

	local width = cinfo[0].output_width
	local height = cinfo[0].output_height
	local channels = 3
	local buffer = gcmem.new('uint8_t', width * height * channels)

	local y = 0
	while cinfo[0].output_scanline < cinfo[0].output_height do
		jpeg.jpeg_read_scanlines(cinfo, tmpbuffer, 1)
		ffi.copy(buffer + channels * y * width, tmpbuffer[0], channels * width)
		y=y+1
	end
	jpeg.jpeg_finish_decompress(cinfo)
	jpeg.jpeg_destroy_decompress(cinfo)
	stdio.fclose(infile)

	return {
		buffer = buffer,
		width = width,
		height = height,
		channels = channels,
		format = 'uint8_t',
	}
end

function JPEGLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local buffer = assert(args.buffer, "expected buffer")
	local quality = args.quality or 90

	local cinfo = gcmem.new('struct jpeg_compress_struct', 1)

	local outfile = stdio.fopen(filename, 'wb')	-- target file
	if outfile == nil then
		error("can't open "..filename)
	end

	local myerr = gcmem.new('struct my_error_mgr', 1)
-- [[ using lua errors
	myerr[0].file = outfile
	myerr[0].writing = 1
	cinfo[0].err = jpeg.jpeg_std_error(ffi.cast('struct jpeg_error_mgr*' ,myerr))
	jpeg.jpeg_create_compress(cinfo)
--]]

	jpeg.jpeg_stdio_dest(cinfo, outfile)

	cinfo[0].image_width = width
	cinfo[0].image_height = height
	assert(channels == 3)
	cinfo[0].input_components = channels
	cinfo[0].in_color_space = jpeg.JCS_RGB

	jpeg.jpeg_set_defaults(cinfo)

	jpeg.jpeg_set_quality(cinfo, quality, 1)

	jpeg.jpeg_start_compress(cinfo, 1)

	local row_stride = width * 3	-- physical row width in image buffer

	local row_pointer = gcmem.new('JSAMPROW', 1)
	while cinfo[0].next_scanline < cinfo[0].image_height do
		row_pointer[0] = buffer + cinfo[0].next_scanline * row_stride
		jpeg.jpeg_write_scanlines(cinfo, row_pointer, 1)
	end

	jpeg.jpeg_finish_compress(cinfo)

	stdio.fclose(outfile)
	jpeg.jpeg_destroy_compress(cinfo)
end

return JPEGLoader
