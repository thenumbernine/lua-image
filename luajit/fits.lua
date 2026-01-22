--[[
Notice about the FITS IO:

It loads and saves in planar mode.
Which means technically it shouldn't have 3 channels.
If you try to save a 3-channel image via FITS, you'll get interleaved garbage.
--]]
local Loader = require 'image.luajit.loader'
local path = require 'ext.path'
local assert = require 'ext.assert'
local ffi = require 'ffi'
require 'ffi.req' 'c.string'
local fits = require 'image.ffi.fitsio'

local void_p = ffi.typeof'void*'
local char = ffi.typeof'char'
local signed_char = ffi.typeof'signed char'
local unsigned_char = ffi.typeof'unsigned char'
local short = ffi.typeof'short'
local signed_short = ffi.typeof'signed short'
local unsigned_short = ffi.typeof'unsigned short'
local int = ffi.typeof'int'
local signed_int = ffi.typeof'signed int'
local unsigned_int = ffi.typeof'unsigned int'
local int1 = ffi.typeof'int[1]'
local long = ffi.typeof'long'
local signed_long = ffi.typeof'signed long'
local unsigned_long = ffi.typeof'unsigned long'
local long_int_3 = ffi.typeof'long int[3]'
local float = ffi.typeof'float'
local double = ffi.typeof'double'

local fitsfile_p_1 = ffi.typeof'fitsfile*[1]'


local FITSLoader = Loader:subclass()

-- overload the parent class functionality
-- don't clamp or change format
function FITSLoader:prepareImage(image)
	return image
end

function FITSLoader:load(filename)
	assert(filename, "expected filename")
	return select(2, assert(xpcall(function()
		local fitsFilePtr = fitsfile_p_1()
		local status = int1()
		status[0] = 0
		fits.ffopen(fitsFilePtr, filename, fits.READONLY, status)
		assert.eq(status[0], 0, "ffopen failed")

		local bitPixType = int1()
		fits.ffgidt(fitsFilePtr[0], bitPixType, status)
		assert.eq(status[0], 0, "ffgidt failed")

		local imgType = 0
		local format
		if bitPixType[0] == fits.BYTE_IMG then
			format = unsigned_char
			imgType = fits.TBYTE
		elseif bitPixType[0] == fits.SHORT_IMG then
			format = short
			imgType = fits.TSHORT
		elseif bitPixType[0] == fits.LONG_IMG then
			format = long
			imgType = fits.TLONG
		elseif bitPixType[0] == fits.FLOAT_IMG then
			format = float
			imgType = fits.TFLOAT
		elseif bitPixType[0] == fits.DOUBLE_IMG then
			format = double
			imgType = fits.TDOUBLE
		else
			error("image is an unsupported FITS type " .. bitPixType[0])
		end

		local format-arr = ffi.typeof('$[?]', format)

		local dim = int1()
		fits.ffgidm(fitsFilePtr[0], dim, status)
		assert.eq(status[0], 0, "ffgidm failed")
		assert.eq(dim[0], 0, "image is an unsupported dimension")

		local fpixel = long_int_3()
		for i=0,dim[0]-1 do
			fpixel[i] = 1
		end

		local sizes = long_int_3()
		fits.ffgisz(fitsFilePtr[0], 3, sizes, status)
		assert.eq(status[0], 0, "ffgisz failed")
		local width = tonumber(sizes[0])
		local height = tonumber(sizes[1])
		local channels = tonumber(sizes[2])

		local numPixels = width * height * channels
		local buffer = format_arr(numPixels)
		fits.ffgpxv(fitsFilePtr[0], imgType, fpixel, numPixels, nil, buffer, nil, status)
		assert.eq(status[0], 0, "ffgpxv failed")

		fits.ffclos(fitsFilePtr[0], status)
		assert.eq(status[0], 0, "ffclos failed")

		return {
			buffer = buffer,
			width = width,
			height = height,
			channels = channels,
			format = format,
		}
	end, function(err)
		return 'for filename '..filename..'\n'..err..'\n'..debug.traceback()
	end)))
end

local formatInfos = {
	[tostring(char)] = {bitPixType = fits.BYTE_IMG, imgType = fits.TBYTE},	-- default is unsigned? that's what they keep tellign us ...
	[tostring(signed_char)] = {bitPixType = fits.SBYTE_IMG, imgType = fits.TSBYTE},
	[tostring(unsigned_char)] = {bitPixType = fits.BYTE_IMG, imgType = fits.TBYTE},
	[tostring(short)] = {bitPixType = fits.SHORT_IMG, imgType = fits.TSHORT},
	[tostring(signed_short)] = {bitPixType = fits.SHORT_IMG, imgType = fits.TSHORT},
	[tostring(unsigned_short)] = {bitPixType = fits.USHORT_IMG, imgType = fits.TUSHORT},
	[tostring(int)] = {bitPixType = fits.LONG_IMG, imgType = fits.TINT},	-- 32bit ... right? technically 'long' isn't anymore 32bit ...
	[tostring(signed_int)] = {bitPixType = fits.LONG_IMG, imgType = fits.TINT},
	[tostring(unsigned_int)] = {bitPixType = fits.ULONG_IMG, imgType = fits.TUINT},
	[tostring(long)] = {bitPixType = fits.LONGLONG_IMG, imgType = fits.TLONGLONG},	-- 64bit... ? or is this TLONG vs TINT (since there is a distinct TULONG type ...)
	[tostring(signed_long)] = {bitPixType = fits.LONGLONG_IMG, imgType = fits.TLONGLONG},
	[tostring(unsigned_long)] = {bitPixType = fits.LONGLONG_IMG, imgType = fits.TLONGLONG},	-- FITS has no unsigned 64-bit long ...
	[tostring(float)] = {bitPixType = fits.FLOAT_IMG, imgType = fits.TFLOAT},
	[tostring(double)] = {bitPixType = fits.DOUBLE_IMG, imgType = fits.TDOUBLE},
}

function FITSLoader:save(args)
	-- args:
	local filename = assert.index(args, 'filename')
	local width = assert.index(args, 'width')
	local height = assert.index(args, 'height')
	local channels = assert.index(args, 'channels')
	local format = assert.index(args, 'format')
	local buffer = assert.index(args, 'buffer')

	assert.eq(format, ffi.typeof(format), "expected format to be a ctype")

	if path(filename):exists() then path(filename):remove() end

	local status = gcmem.new('int', 1)
	status[0] = 0

	local fitsFilePtr = gcmem.new('fitsfile *', 1)
	fitsFilePtr[0] = nil

	fits.ffinit(fitsFilePtr, filename, status)
	assert.eq(status[0], 0, "ffinit failed")

	local sizes = gcmem.new('long', 3)
	sizes[0] = width
	sizes[1] = height
	sizes[2] = channels

	local formatInfo = assert.index(formatInfos, tostring(format), "failed to find FITS type")
	local bitPixType = formatInfo.bitPixType

	status[0] = fits.ffphps(fitsFilePtr[0], bitPixType, 3, sizes, status)
	assert.eq(status[0], 0, "ffphps failed")

	local firstpix = gcmem.new('long int', 3)
	for i=0,2 do
		firstpix[i] = 1
	end

	local numPixels = width * height * channels

	local imgType = formatInfo.imgType

	fits.ffppx(fitsFilePtr[0], imgType, firstpix, numPixels, ffi.cast(void_p, buffer), status)
	assert.eq(status[0], 0, "ffppx failed")

	fits.ffclos(fitsFilePtr[0], status);
	assert.eq(status[0], 0, "ffclos failed")
end

return FITSLoader
