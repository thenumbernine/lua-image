local Loader = require 'image.luajit.loader'
local ffi = require 'ffi'
local tiff = require 'ffi.req' 'tiff'
local gcmem = require 'ext.gcmem'

local TIFFLoader = Loader:subclass()

function TIFFLoader:load(filename)
	assert(filename, "expected filename")

	tiff.TIFFSetWarningHandler(nil)
	tiff.TIFFSetErrorHandler(nil)

	local fp = tiff.TIFFOpen(filename, 'r')
	if fp == nil then error("failed to open file "..filename.." for reading") end

	local function readtag(tagname, ctype, default)
		local result = gcmem.new(ctype, 1)
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
	local pixelSize = bit.rshift(bitsPerSample * samplesPerPixel, 3)
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
	elseif sampleFormat == tiff.SAMPLEFORMAT_IEEEFP then
		format = ({
			[32] = 'float',
			[64] = 'double',
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_VOID then
		format = 'uint8_t'
		-- TODO multiply channels by bitsPerSample?  or cdef a new type based on bitsPerSample?
		print("something will go wrong I bet")
	elseif sampleFormat == tiff.SAMPLEFORMAT_COMPLEXINT then
		format = ({
			[16] = 'complex char',
			[32] = 'complex short',
			[64] = 'complex int',
		})[bitsPerSample]
	elseif sampleFormat == tiff.SAMPLEFORMAT_COMPLEXIEEEFP then
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

	local buffer = gcmem.new(format, width * height * pixelSize)

	local ptr = ffi.cast('uint8_t*', buffer)
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
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local buffer = assert(args.buffer, "expected buffer")
	local format = assert(args.format, "expected format")
	local channels = assert(args.channels, "expected channels")

	local bytesPerSample = ffi.sizeof(format)
	local bitsPerSample = bit.lshift(bytesPerSample, 3)

--DEBUG:print('tiff saving image format', format)
--DEBUG:print('bytes/sample', bytesPerSample)
--DEBUG:print('bits/sample', bitsPerSample)
--DEBUG:print('tiff version '..ffi.string(tiff.TIFFGetVersion()))

	local sampleFormat
	if ffi.typeof(format) == ffi.typeof'int8_t'
	or ffi.typeof(format) == ffi.typeof'int16_t'
	or ffi.typeof(format) == ffi.typeof'int32_t'
	or ffi.typeof(format) == ffi.typeof'char'
	or ffi.typeof(format) == ffi.typeof'short'
	or ffi.typeof(format) == ffi.typeof'int'
	or ffi.typeof(format) == ffi.typeof'long'
	then
		sampleFormat = tiff.SAMPLEFORMAT_INT
	elseif ffi.typeof(format) == ffi.typeof'uint8_t'
	or ffi.typeof(format) == ffi.typeof'uint16_t'
	or ffi.typeof(format) == ffi.typeof'uint32_t'
	or ffi.typeof(format) == ffi.typeof'unsigned char'
	or ffi.typeof(format) == ffi.typeof'unsigned short'
	or ffi.typeof(format) == ffi.typeof'unsigned int'
	or ffi.typeof(format) == ffi.typeof'unsigned long'
	then
		sampleFormat = tiff.SAMPLEFORMAT_UINT
	elseif ffi.typeof(format) == ffi.typeof'float'
	or ffi.typeof(format) == ffi.typeof'double'
	then
		sampleFormat = tiff.SAMPLEFORMAT_IEEEFP
	elseif ffi.typeof(format) == ffi.typeof'complex char'
	or ffi.typeof(format) == ffi.typeof'complex short'
	or ffi.typeof(format) == ffi.typeof'complex int'
	then
		sampleFormat = tiff.SAMPLEFORMAT_COMPLEXINT
	elseif ffi.typeof(format) == ffi.typeof'complex float'
	or ffi.typeof(format) == ffi.typeof'complex double'
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
		local tagvalue = assert(tiff[tagname])
		if 0 == tiff.TIFFSetField(fp, tagvalue, ffi.cast(ctype, value)) then
			error("TIFFSetField failed for "..tostring(tagname).." "..tostring(ctype).." "..tostring(value))
		end
	end

	writetag('TIFFTAG_IMAGEWIDTH', 'uint32_t', width)
	writetag('TIFFTAG_IMAGELENGTH', 'uint32_t', height)
	writetag('TIFFTAG_BITSPERSAMPLE', 'uint16_t', bitsPerSample)
	writetag('TIFFTAG_SAMPLESPERPIXEL', 'uint16_t', channels)
	writetag('TIFFTAG_PLANARCONFIG', 'uint16_t', assert(tiff.PLANARCONFIG_CONTIG))
	writetag('TIFFTAG_COMPRESSION', 'uint16_t', 
		ffi.sizeof(format) == 1 
		and assert(tiff.COMPRESSION_LZW) 
		or assert(tiff.COMPRESSION_ZSTD)
	)
	if channels == 3 then
		writetag('TIFFTAG_PHOTOMETRIC', 'uint16_t', assert(tiff.PHOTOMETRIC_RGB))
	else
		writetag('TIFFTAG_PHOTOMETRIC', 'uint16_t', assert(tiff.PHOTOMETRIC_MINISBLACK))
	end
	writetag('TIFFTAG_ORIENTATION', 'uint16_t', assert(tiff.ORIENTATION_TOPLEFT))
	writetag('TIFFTAG_SAMPLEFORMAT', 'uint16_t', sampleFormat)

	local stripSize = bytesPerSample * channels * width
	stripSize = tiff.TIFFDefaultStripSize(fp, stripSize)
	writetag('TIFFTAG_ROWSPERSTRIP', 'uint32_t', stripSize)

	local ptr = ffi.cast('uint8_t*', buffer)
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
