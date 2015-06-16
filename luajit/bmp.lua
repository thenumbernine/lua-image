--[[
NOTICE the BMP save/load operates as BGR
I'm also saving images upside-down ... but I'm working with flipped buffers so it's okay?
--]]
local ffi = require 'ffi'
local gc = require 'gcmem.gcmem'
require 'ffi.c.stdio'

ffi.cdef[[

//wtypes.h
typedef unsigned short WORD;
typedef unsigned long DWORD;
typedef long LONG;

//wingdi.h
#pragma pack(1)
struct tagBITMAPFILEHEADER {
        WORD    bfType;
        DWORD   bfSize;
        WORD    bfReserved1;
        WORD    bfReserved2;
        DWORD   bfOffBits;
};
typedef struct tagBITMAPFILEHEADER BITMAPFILEHEADER;

struct tagBITMAPINFOHEADER{
        DWORD      biSize;
        LONG       biWidth;
        LONG       biHeight;
        WORD       biPlanes;
        WORD       biBitCount;
        DWORD      biCompression;
        DWORD      biSizeImage;
        LONG       biXPelsPerMeter;
        LONG       biYPelsPerMeter;
        DWORD      biClrUsed;
        DWORD      biClrImportant;
};
typedef struct tagBITMAPINFOHEADER BITMAPINFOHEADER;

//I don't trust MS semantics ... if you get any weird memory behavior, switch to using GCC's __attribute__ ((packed))
#pragma pack(0)
]]

local exports = {}

exports.load = function(filename)
	local file = ffi.C.fopen(filename, 'rb')
	if not file then error("failed to open file "..filename.." for reading") end

	local fileHeader = gc.new('BITMAPFILEHEADER', 1)
	ffi.C.fread(fileHeader, ffi.sizeof(fileHeader[0]), 1, file)

--[[
	print('file header:')	
	print('type', ('%x'):format(fileHeader[0].bfType))
	print('size', fileHeader[0].bfSize)
	print('reserved1', fileHeader[0].bfReserved1)
	print('reserved2', fileHeader[0].bfReserved2)
	print('offset', fileHeader[0].bfOffBits)
--]]
	
	assert(fileHeader[0].bfType == 0x4d42, "image has bad signature")
	-- assert that the reserved are zero?
	
	local infoHeader = gc.new('BITMAPINFOHEADER', 1)
	ffi.C.fread(infoHeader, ffi.sizeof(infoHeader[0]), 1, file)

--[[
	print('info header:')
	print('size', infoHeader[0].biSize)
	print('width', infoHeader[0].biWidth)
	print('height', infoHeader[0].biHeight)
	print('planes', infoHeader[0].biPlanes)
	print('bitcount', infoHeader[0].biBitCount)
	print('compression', infoHeader[0].biCompression)
	print('size of image', infoHeader[0].biSizeImage)
	print('biXPelsPerMeter', infoHeader[0].biXPelsPerMeter)
	print('biYPelsPerMeter', infoHeader[0].biYPelsPerMeter)
	print('colors used', infoHeader[0].biClrUsed)
	print('colors important', infoHeader[0].biClrImportant)
--]]

	assert(infoHeader[0].biBitCount == 24, "only supports 24-bpp images")
	assert(infoHeader[0].biCompression == 0, "only supports uncompressed images")

	ffi.C.fseek(file, fileHeader[0].bfOffBits, ffi.C.SEEK_SET)

	local width = infoHeader[0].biWidth
	local height = infoHeader[0].biHeight
	assert(height >= 0, "currently doesn't support flipped images")

	local data = gc.new('char', width * height * 3)

	local padding = (4-(3 * width))%4

	for y=height-1,0,-1 do
		-- read it out as BGR	
		ffi.C.fread(data + 3 * width * y, 3 * width, 1, file)

		if padding ~= 0 then 
			ffi.C.fseek(file, padding, ffi.C.SEEK_SET)
		end
	end

	ffi.C.fclose(file)

	return {
		data = data,
		width = width,
		height = height,
		xdpi = infoHeader[0].biXPelsPerMeter,
		ydpi = infoHeader[0].biYPelsPerMeter,
	}
end

exports.save = function(args)
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local data = assert(args.data, "expected data")

	local padding = (4-(3*width))%4
	local rowsize = width * 3 + padding

	local fileHeader = gc.new('BITMAPFILEHEADER', 1)
	local infoHeader = gc.new('BITMAPINFOHEADER', 1)
	local offset = ffi.sizeof(fileHeader[0]) + ffi.sizeof(infoHeader[0])
	
	local file = ffi.C.fopen(filename, 'wb')
	if not file then error("failed to open file "..filename.." for writing") end

	fileHeader[0].bfType = 0x4d42
	fileHeader[0].bfSize = rowsize * height + offset
	fileHeader[0].bfReserved1 = 0
	fileHeader[0].bfReserved2 = 0
	fileHeader[0].bfOffBits = offset
	ffi.C.fwrite(fileHeader, ffi.sizeof(fileHeader[0]), 1, file)

	infoHeader[0].biSize = ffi.sizeof(infoHeader[0])
	infoHeader[0].biWidth = width
	infoHeader[0].biHeight = height
	infoHeader[0].biPlanes = 1
	infoHeader[0].biBitCount = 24
	infoHeader[0].biCompression = 0
	infoHeader[0].biSizeImage = 0	-- rowsize * height?  the source has zero here
	infoHeader[0].biXPelsPerMeter = args.xdpi or 300
	infoHeader[0].biYPelsPerMeter = args.ydpi or 300
	ffi.C.fwrite(infoHeader, ffi.sizeof(infoHeader[0]), 1, file)

	local zero = gc.new('int', 1)
	zero[0] = 0

	local row = gc.new('unsigned char', 3 * width)
	for y=height-1,0,-1 do
		ffi.copy(row, data + 3 * width * y, 3 * width)
		for x=0,width-1 do
			row[0+3*x], row[2+3*x] = row[2+3*x], row[0+3*x]
		end
		ffi.C.fwrite(row, 3 * width, 1, file)
		if padding ~= 0 then 
			ffi.C.fwrite(zero, padding, 1, file) 
		end
	end

	gc.free(zero)
	gc.free(row)
	gc.free(fileHeader)
	gc.free(infoHeader)

	ffi.C.fclose(file)
end

return exports

