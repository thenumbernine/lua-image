local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local assert = require 'ext.assert'
local tiff = require 'image.ffi.tiff'


local char = ffi.typeof'char'
local short = ffi.typeof'short'
local int = ffi.typeof'int'
local long = ffi.typeof'long'
local int8_t = ffi.typeof'int8_t'
local int16_t = ffi.typeof'int16_t'
local int32_t = ffi.typeof'int32_t'

local unsigned_char = ffi.typeof'unsigned char'
local unsigned_short = ffi.typeof'unsigned short'
local unsigned_int = ffi.typeof'unsigned int'
local unsigned_long = ffi.typeof'unsigned long'
local uint8_t = ffi.typeof'uint8_t'
local uint8_t_p = ffi.typeof'uint8_t*'
local uint16_t = ffi.typeof'uint16_t'
local uint32_t = ffi.typeof'uint32_t'

local float = ffi.typeof'float'
local double = ffi.typeof'double'

local complex_char = ffi.typeof'complex char'
local complex_short = ffi.typeof'complex short'
local complex_int = ffi.typeof'complex int'
local complex_float = ffi.typeof'complex float'
local complex_double = ffi.typeof'complex double'


local TIFFLoader = Loader:subclass()

function TIFFLoader:load(filename)
	assert(filename, "expected filename")

	tiff.TIFFSetWarningHandler(nil)
	tiff.TIFFSetErrorHandler(nil)

	local fp = tiff.TIFFOpen(filename, 'r')
	if fp == nil then error("failed to open file "..filename.." for reading") end

	local function readtag(tagname, ctype, default)
		local arrtype = ffi.typeof('$[1]', ctype)
		local result = arrtype()
		if tiff.TIFFGetField(fp, assert.index(tiff, tagname), result) ~= 1 then
			if default ~= nil then return default end
			error("failed to read tag "..tagname)
		end
		return result[0]
	end
	local width = readtag('TIFFTAG_IMAGEWIDTH', uint32_t)
	local height = readtag('TIFFTAG_IMAGELENGTH', uint32_t)
	local bitsPerSample = readtag('TIFFTAG_BITSPERSAMPLE', uint16_t)	-- default = 1 ... but seems like it's always there
	local samplesPerPixel = readtag('TIFFTAG_SAMPLESPERPIXEL', uint16_t)	-- default = 1 ... but seems like it's always there
	local sampleFormat = readtag('TIFFTAG_SAMPLEFORMAT', uint16_t, tiff.SAMPLEFORMAT_UINT)
	local pixelSize = bit.rshift(bitsPerSample * samplesPerPixel, 3)
	if pixelSize == 0 then
		error("unsupported bitsPerSample="..bitsPerSample)--.." sampleFormat="..sampleFormat)
	end

	local format
	if sampleFormat == tiff.SAMPLEFORMAT_UINT then
		format = ({
			[8] = uint8_t,
			[16] = uint16_t,
			[32] = uint32_t,
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_INT then
		format = ({
			[8] = int8_t,
			[16] = int16_t,
			[32] = int32_t,
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_IEEEFP then
		format = ({
			[32] = float,
			[64] = double,
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_VOID then
		format = uint8_t
		-- TODO multiply channels by bitsPerSample?  or cdef a new type based on bitsPerSample?
		print("something will go wrong I bet")
	elseif sampleFormat == tiff.SAMPLEFORMAT_COMPLEXINT then
		format = ({
			[16] = complex_char,
			[32] = complex_short,
			[64] = complex_int,
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_COMPLEXIEEEFP then
		format = ({
			[64] = complex_float,
			[128] = complex_double,
		})[bitsPerSample]
	else
		-- TODO specify if we were using the default value, or if the TIFFTAG_SAMPLEFORMAT did exist
		error("unknown sampleFormat "..sampleFormat)
	end
	if not format then
		error("couldn't deduce format from bitsPerSample="..bitsPerSample.." sampleFormat="..sampleFormat)
	end

	local format_arr = ffi.typeof('$[?]', format)

	local buffer = format_arr(width * height * pixelSize)

	local ptr = ffi.cast(uint8_t_p, buffer)
	for strip=0,tiff.TIFFNumberOfStrips(fp)-1 do
		tiff.TIFFReadEncodedStrip(fp, strip, ptr, -1)
		local stripSize = tiff.TIFFStripSize(fp)
		ptr = ptr + stripSize
	end
	tiff.TIFFClose(fp)

	return {
		buffer = buffer,
		width = width,
		height = height,
		channels = samplesPerPixel,
		format = format,
	}
end

-- TIFF can handle any format, no need to convert
function TIFFLoader:prepareImage(image)
	return image
end

-- assumes RGB buffer
function TIFFLoader:save(args)
	-- args:
	local filename = assert.index(args, 'filename')
	local width = assert.index(args, 'width')
	local height = assert.index(args, 'height')
	local buffer = assert.index(args, 'buffer')
	local format = assert.index(args, 'format')
	local channels = assert.index(args, 'channels')

	assert.eq(format, ffi.typeof(format), "format is not a ctype")

	local bytesPerSample = ffi.sizeof(format)
	local bitsPerSample = bit.lshift(bytesPerSample, 3)

--DEBUG(image.luajit.tiff):print('tiff saving image format', format)
--DEBUG(image.luajit.tiff):print('bytes/sample', bytesPerSample)
--DEBUG(image.luajit.tiff):print('bits/sample', bitsPerSample)
--DEBUG(image.luajit.tiff):print('tiff version '..ffi.string(tiff.TIFFGetVersion()))

	local sampleFormat
	if format == int8_t
	or format == int16_t
	or format == int32_t
	or format == char
	or format == short
	or format == int
	or format == long
	then
		sampleFormat = tiff.SAMPLEFORMAT_INT
	elseif format == uint8_t
	or format == uint16_t
	or format == uint32_t
	or format == unsigned_char
	or format == unsigned_short
	or format == unsigned_int
	or format == unsigned_long
	then
		sampleFormat = tiff.SAMPLEFORMAT_UINT
	elseif format == float
	or format == double
	then
		sampleFormat = tiff.SAMPLEFORMAT_IEEEFP
	elseif format == complex_char
	or format == complex_short
	or format == complex_int
	then
		sampleFormat = tiff.SAMPLEFORMAT_COMPLEXINT
	elseif format == complex_float
	or format == complex_double
	then
		sampleFormat = tiff.SAMPLEFORMAT_COMPLEXIEEEFP
	else
		-- assume it's uint?
		-- TODO support for SAMPLEFORMAT_VOID somehow?
	end
	if not sampleFormat then
		error("couldn't deduce format for type "..tostring(format))
	end

-- TODO capture errors and use lua errors?
--	tiff.TIFFSetWarningHandler(nil)
--	tiff.TIFFSetErrorHandler(nil)

	local fp = tiff.TIFFOpen(filename, 'w')
	if fp == nil then error("failed to open file "..filename.." for writing") end

	local function writetag(tagname, ctype, value)
		local tagvalue = assert.index(tiff, tagname)
		if 0 == tiff.TIFFSetField(fp, tagvalue, ffi.cast(ctype, value)) then
			error("TIFFSetField failed for "..tostring(tagname).." "..tostring(ctype).." "..tostring(value))
		end
	end

	writetag('TIFFTAG_IMAGEWIDTH', uint32_t, width)
	writetag('TIFFTAG_IMAGELENGTH', uint32_t, height)
	writetag('TIFFTAG_BITSPERSAMPLE', uint16_t, bitsPerSample)
	writetag('TIFFTAG_SAMPLESPERPIXEL', uint16_t, channels)
	writetag('TIFFTAG_PLANARCONFIG', uint16_t, assert.index(tiff, 'PLANARCONFIG_CONTIG'))
	writetag('TIFFTAG_COMPRESSION', uint16_t,
		args.compression or
		--assert.index(tiff, 'COMPRESSION_NONE') -- I don't like this one
		assert.index(tiff, 'COMPRESSION_LZW')
		--assert.index(tiff, 'COMPRESSION_ZSTD') -- GIMP doesn't like this one
	)
	if channels == 3 then
		writetag('TIFFTAG_PHOTOMETRIC', uint16_t, assert.index(tiff, 'PHOTOMETRIC_RGB'))
	else
		writetag('TIFFTAG_PHOTOMETRIC', uint16_t, assert.index(tiff, 'PHOTOMETRIC_MINISBLACK'))
	end
	writetag('TIFFTAG_ORIENTATION', uint16_t, assert.index(tiff, 'ORIENTATION_TOPLEFT'))
	writetag('TIFFTAG_SAMPLEFORMAT', uint16_t, sampleFormat)

	local stripSize = bytesPerSample * channels * width
	stripSize = tiff.TIFFDefaultStripSize(fp, stripSize)
	if stripSize == -1 then
		error("TIFFDefaultStripSize failed")
	end
	writetag('TIFFTAG_ROWSPERSTRIP', uint32_t, stripSize)

	local ptr = ffi.cast(uint8_t_p, buffer)
	for y=0,height-1 do
		--tiff.TIFFWriteEncodedStrip(fp, 0, ptr, stripSize)
		if tiff.TIFFWriteScanline(fp, ptr, y, 0) == -1 then
			error("TIFFWriteScanline failed")
		end
		ptr = ptr + stripSize
	end

	tiff.TIFFClose(fp)
end

return TIFFLoader
