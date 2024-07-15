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

-- TIFF can handle any format, no need to convert
function TIFFLoader:prepareImage(image)
	return image
end

-- assumes RGB data
function TIFFLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local data = assert(args.data, "expected data")
	local format = assert(args.format, "expected format")	-- or unsigned char?
	local channels = assert(args.channels, "expected channels")

	local bytesPerSample = ffi.sizeof(format)
	local bitsPerSample = bytesPerSample * 8

--print('tiff version '..ffi.string(tiff.TIFFGetVersion()))

	local sampleFormat = assert(tiff.SAMPLEFORMAT_UINT)	-- default
	-- TODO what about typedef'd ffi types?  any way to query ffi to find the original type? or find if it is a float type or not?
	if format == 'int8_t'
	or format == 'int16_t'
	or format == 'int32_t'
	or format == 'char'
	or format == 'short'
	or format == 'int'
	or format == 'long'
	then
		sampleFormat = tiff.SAMPLEFORMAT_INT
	elseif format == 'float'
	or format == 'double'
	then
		sampleFormat = tiff.SAMPLEFORMAT_IEEEFP
	elseif format == 'complex char'
	or format == 'complex short'
	or format == 'complex int'
	then
		sampleFormat = tiff.SAMPLEFORMAT_COMPLEXINT
	elseif format == 'complex float'
	or format == 'complex double'
	then
		sampleFormat = tiff.SAMPLEFORMAT_COMPLEXIEEEFP
	else
		-- assume it's uint?
		-- TODO support for SAMPLEFORMAT_VOID somehow?
	end

-- TODO capture errors and use lua errors?
--	tiff.TIFFSetWarningHandler(nil)
--	tiff.TIFFSetErrorHandler(nil)

	local fp = tiff.TIFFOpen(filename, 'w')
	if fp == nil then error("failed to open file "..filename.." for writing") end

	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_IMAGEWIDTH), ffi.cast('uint32_t', width))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_IMAGELENGTH), ffi.cast('uint32_t', height))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_BITSPERSAMPLE), ffi.cast('uint16_t', bitsPerSample))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_SAMPLESPERPIXEL), ffi.cast('uint16_t', channels))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_PLANARCONFIG), ffi.cast('uint16_t', assert(tiff.PLANARCONFIG_CONTIG)))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_COMPRESSION), ffi.cast('uint16_t', assert(tiff.COMPRESSION_NONE)))
	if bitsPerSample == 8 and channels == 3 then
		tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_PHOTOMETRIC), ffi.cast('uint16_t', assert(tiff.PHOTOMETRIC_RGB)))
	else
		tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_PHOTOMETRIC), ffi.cast('uint16_t', assert(tiff.PHOTOMETRIC_MINISBLACK)))
	end
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_ORIENTATION), ffi.cast('uint16_t', assert(tiff.ORIENTATION_TOPLEFT)))
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_SAMPLEFORMAT), ffi.cast('uint16_t', sampleFormat))

	local stripSize = bytesPerSample * channels * width
	stripSize = tiff.TIFFDefaultStripSize(fp, stripSize)
	tiff.TIFFSetField(fp, assert(tiff.TIFFTAG_ROWSPERSTRIP), ffi.cast('uint32_t', stripSize))

	local ptr = ffi.cast('unsigned char*', data)
	for y=0,height-1 do
		--tiff.TIFFWriteEncodedStrip(fp, 0, ptr, stripSize)
		tiff.TIFFWriteScanline(fp, ptr, y, 0)
		ptr = ptr + stripSize
	end

	tiff.TIFFClose(fp)
end

return TIFFLoader
