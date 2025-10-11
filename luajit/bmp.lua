--[[
NOTICE the BMP save/load operates as BGR
I'm also saving images upside-down ... but I'm working with flipped buffers so it's okay?
--]]
local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local stdio = require 'ffi.req' 'c.stdio'	-- use stdio instead of ffi.C for browser compat

local uint8_t_arr = ffi.typeof'uint8_t[?]'
local int1 = ffi.typeof'int[1]'

ffi.cdef[[

//wtypes.h
typedef unsigned short WORD;
typedef unsigned int DWORD;
typedef int LONG;

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

local BITMAPFILEHEADER_1 = ffi.typeof'BITMAPFILEHEADER[1]'
local BITMAPINFOHEADER_1 = ffi.typeof'BITMAPINFOHEADER[1]'

local BMPLoader = Loader:subclass()

function BMPLoader:load(filename)
	local file = stdio.fopen(filename, 'rb')
	if file == nil then error("failed to open file "..filename.." for reading") end

	local fileHeader = BITMAPFILEHEADER_1()
	stdio.fread(fileHeader, ffi.sizeof(fileHeader[0]), 1, file)

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

	local infoHeader = BITMAPINFOHEADER_1()
	stdio.fread(infoHeader, ffi.sizeof(infoHeader[0]), 1, file)

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

	assert(infoHeader[0].biBitCount == 24 or infoHeader[0].biBitCount == 32, "only supports 24-bpp or 32-bpp images")
	local channels = infoHeader[0].biBitCount/8
	assert(infoHeader[0].biCompression == 0, "only supports uncompressed images, found compression method "..infoHeader[0].biCompression)

	stdio.fseek(file, fileHeader[0].bfOffBits, stdio.SEEK_SET)

	local width = infoHeader[0].biWidth
	local height = infoHeader[0].biHeight
	assert(height >= 0, "currently doesn't support flipped images")

	local buffer = uint8_t_arr(width * height * channels)

	local padding = (4-(channels * width))%4

	for y=height-1,0,-1 do
		-- write it out as BGR
		stdio.fread(buffer + channels * width * y, channels * width, 1, file)

		for x=0,width-1 do
			local offset = channels*(x+width*y)
			buffer[0+offset], buffer[1+offset], buffer[2+offset] = buffer[2+offset], buffer[1+offset], buffer[0+offset]
		end

		if padding ~= 0 then
			stdio.fseek(file, padding, stdio.SEEK_SET)
		end
	end

	stdio.fclose(file)

	return {
		buffer = buffer,
		width = width,
		height = height,
		channels = channels,
		format = 'uint8_t',
		xdpi = infoHeader[0].biXPelsPerMeter,
		ydpi = infoHeader[0].biYPelsPerMeter,
	}
end

function BMPLoader:save(args)
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local buffer = assert(args.buffer, "expected buffer")

	local padding = (4-(channels*width))%4
	local rowsize = width * channels + padding

	local fileHeader = BITMAPFILEHEADER_1()
	local infoHeader = BITMAPINFOHEADER_1()
	local headerOffset = ffi.sizeof(fileHeader[0]) + ffi.sizeof(infoHeader[0])

	local file = stdio.fopen(filename, 'wb')
	if file == nil then error("failed to open file "..filename.." for writing") end

	fileHeader[0].bfType = 0x4d42
	fileHeader[0].bfSize = rowsize * height + headerOffset
	fileHeader[0].bfReserved1 = 0
	fileHeader[0].bfReserved2 = 0
	fileHeader[0].bfOffBits = headerOffset
	stdio.fwrite(fileHeader, ffi.sizeof(fileHeader[0]), 1, file)

	infoHeader[0].biSize = ffi.sizeof(infoHeader[0])
	infoHeader[0].biWidth = width
	infoHeader[0].biHeight = height
	infoHeader[0].biPlanes = 1
	infoHeader[0].biBitCount = channels*8
	infoHeader[0].biCompression = 0
	infoHeader[0].biSizeImage = 0	-- rowsize * height?  the source has zero here
	infoHeader[0].biXPelsPerMeter = args.xdpi or 300
	infoHeader[0].biYPelsPerMeter = args.ydpi or 300
	stdio.fwrite(infoHeader, ffi.sizeof(infoHeader[0]), 1, file)

	local zero = int1()
	zero[0] = 0

	local row = uint8_t_arr(channels * width)
	for y=height-1,0,-1 do
		ffi.copy(row, buffer + channels * width * y, channels * width)
		for x=0,width-1 do
			local rowOffset = channels * x
			row[0+rowOffset], row[2+rowOffset] = row[2+rowOffset], row[0+rowOffset]
		end
		stdio.fwrite(row, channels * width, 1, file)
		if padding ~= 0 then
			stdio.fwrite(zero, padding, 1, file)
		end
	end

	stdio.fclose(file)
end

return BMPLoader
