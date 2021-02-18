local Loader = require 'image.luajit.loader'
local class = require 'ext.class'
local ffi = require 'ffi'
local tiff = require 'ffi.tiff'
local gcmem = require 'ext.gcmem'

local TIFFLoader = class(Loader)

function TIFFLoader:load(filename)
	assert(filename, "expected filename")

	tiff.TIFFSetWarningHandler(nil)
	tiff.TIFFSetErrorHandler(nil)

	local fp = tiff.TIFFOpen(filename, 'r')
	if not fp then error("failed to open file "..filename.." for reading") end

	local function readtag(tagname, type, default)
		local result = gcmem.new(type, 1)
		if tiff.TIFFGetField(fp, assert(tiff[tagname]), result) ~= 1 then 
			if default ~= nil then return default end
			error("failed to read tag "..tagname) 
		end
		return result[0]
	end
	local width = readtag('TIFFTAG_IMAGEWIDTH', 'uint32_t')
	local height = readtag('TIFFTAG_IMAGELENGTH', 'uint32_t')
	
	local bitsPerSample = readtag('TIFFTAG_BITSPERSAMPLE', 'uint16_t')	-- default = 1 ... but seems like it's always there
	
	local samplesPerPixel = readtag('TIFFTAG_SAMPLESPERPIXEL', 'uint16_t')	-- default = 1 ... but seems like it's always there

	local sampleFormat = readtag('TIFFTAG_SAMPLEFORMAT', 'uint16_t', tiff.SAMPLEFORMAT_UINT)

	local pixelSize = math.floor(bitsPerSample / 8 * samplesPerPixel)
	if pixelSize == 0 then 
		error("unsupported bitsPerSample="..bitsPerSample)--.." sampleFormat="..sampleFormat) 
	end


	local format
	if sampleFormat == tiff.SAMPLEFORMAT_UINT then
		format = ({
			[8] = 'uint8_t',
			[16] = 'uint16_t',
			[32] = 'uint32_t',
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_INT then
		format = ({
			[8] = 'int8_t',
			[16] = 'int16_t',
			[32] = 'int32_t',
		})[bitsPerSample]
	elseif sampleFormat == SAMPLEFORMAT_IEEEFP then
		format = ({
			[32] = 'float',
			[64] = 'double',
		})[bitsPerSample]
	elseif sampleFormat == SAMPLEFORMAT_VOID then
		format = 'uint8_t'
		-- TODO multiply channels by bitsPerSample?  or cdef a new type based on bitsPerSample?
		print("something will go wrong I bet")
	elseif sampleFormat == SAMPLEFORMAT_COMPLEXINT then
		format = ({
			[16] = 'complex char',
			[32] = 'complex short',
			[64] = 'complex int',
		})[bitsPerSample]
	elseif sampleFormat == SAMPLEFORMAT_COMPLEXIEEEFP then
		format = ({
			[64] = 'complex float',
			[128] = 'complex double',
		})[bitsPerSample]
	else
		-- TODO specify if we were using the default value, or if the TIFFTAG_SAMPLEFORMAT did exist
		error("unknown sampleFormat "..sampleFormat)
	end
	if not format then
		error("couldn't deduce format from bitsPerSample="..bitsPerSample.." sampleFormat="..sampleFormat)
	end

	local data = gcmem.new(format, width * height * pixelSize)
	
	local ptr = ffi.cast('unsigned char*', data)
	for strip=0,tiff.TIFFNumberOfStrips(fp)-1 do
		tiff.TIFFReadEncodedStrip(fp, strip, ptr, -1)
		local stripSize = tiff.TIFFStripSize(fp)
		ptr = ptr + stripSize
	end
	tiff.TIFFClose(fp)

	return {
		data = data,
		width = width,
		height = height,
		channels = samplesPerPixel,
		format = format,
	}
end

-- assumes RGB data
function TIFFLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local data = assert(args.data, "expected data")

--print('tiff version '..ffi.string(tiff.TIFFGetVersion()))

	tiff.TIFFSetWarningHandler(nil)
	tiff.TIFFSetErrorHandler(nil)
	
	local fp = tiff.TIFFOpen(filename, 'w')
	if not fp then error("failed to open file "..filename.." for writing") end

	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_IMAGEWIDTH), width)
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_IMAGELENGTH), height)
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_BITSPERSAMPLE), 8)	-- 8 bits per byte
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_COMPRESSION), assert(tiff.COMPRESSION_NONE))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_PHOTOMETRIC), assert(tiff.PHOTOMETRIC_RGB))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_ORIENTATION), assert(tiff.ORIENTATION_TOPLEFT))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_SAMPLESPERPIXEL), 3)	-- rgb
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_ROWSPERSTRIP), 1)
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_PLANARCONFIG), assert(tiff.PLANARCONFIG_CONTIG))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_SAMPLEFORMAT), assert(tiff.SAMPLEFORMAT_UINT))

	for y=0,height-1 do
		tiff.TIFFWriteEncodedStrip(fp, y, data + 3 * width * y, 3 * width)
	end

	tiff.TIFFClose(fp)
end

return TIFFLoader

