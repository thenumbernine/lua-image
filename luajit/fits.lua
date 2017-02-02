--[[
Notice about the FITS IO:

It loads and saves in planar mode.
Which means technically it shouldn't have 3 channels.
If you try to save a 3-channel image via FITS, you'll get interleaved garbage.
--]]
local Loader = require 'image.luajit.loader'
local class = require 'ext.class'
local io = require 'ext.io'
local gcmem = require 'ext.gcmem'
local ffi = require 'ffi'
require 'ffi.c.string'
local fits = require 'ffi.fitsio'

local FITSLoader = class(Loader)

-- overload the parent class functionality
-- don't clamp or change format
function FITSLoader:prepareImage(image)
	return image
end

function FITSLoader:load(filename)
	assert(filename, "expected filename")
	return select(2, assert(xpcall(function()
		local fitsFilePtr = gcmem.new('fitsfile *', 1)
		local status = gcmem.new('int', 1)
		status[0] = 0
		fits.ffopen(fitsFilePtr, filename, fits.READONLY, status)
		assert(status[0] == 0, "ffopen failed with " .. status[0])
		
		local bitPixType = gcmem.new('int', 1)
		fits.ffgidt(fitsFilePtr[0], bitPixType, status)
		assert(status[0] == 0, "ffgidt failed with " .. status[0])

		local imgType = 0
		local format 
		if bitPixType[0] == fits.BYTE_IMG then
			format = 'unsigned char'
			imgType = fits.TBYTE
		elseif bitPixType[0] == fits.SHORT_IMG then
			format = 'short'
			imgType = fits.TSHORT
		elseif bitPixType[0] == fits.LONG_IMG then
			format = 'long'
			imgType = fits.TLONG
		elseif bitPixType[0] == fits.FLOAT_IMG then
			format = 'float'
			imgType = fits.TFLOAT
		elseif bitPixType[0] == fits.DOUBLE_IMG then
			format = 'double'
			imgType = fits.TDOUBLE
		else
			error("image is an unsupported FITS type " .. bitPixType[0])
		end
		
		local dim = gcmem.new('int',1)
		fits.ffgidm(fitsFilePtr[0], dim, status)
		assert(status[0] == 0, "ffgidm failed with " .. status[0])
		assert(dim[0] == 3, "image is an unsupported dimension " .. dim[0])

		local fpixel = gcmem.new('long int', 3)
		for i=0,dim[0]-1 do
			fpixel[i] = 1
		end

		local sizes = gcmem.new('long int', 3)
		fits.ffgisz(fitsFilePtr[0], 3, sizes, status)
		assert(status[0] == 0, "ffgisz failed with " .. status[0])
		local width = tonumber(sizes[0])
		local height = tonumber(sizes[1])
		local channels = tonumber(sizes[2])
		
		local numPixels = width * height * channels
		local data = gcmem.new(format, numPixels)
		fits.ffgpxv(fitsFilePtr[0], imgType, fpixel, numPixels, nil, data, nil, status)
		assert(status[0] == 0, "ffgpxv failed with " .. status[0])

		fits.ffclos(fitsFilePtr[0], status)
		assert(status[0] == 0, "ffclos failed with " .. status[0])
		
		return {
			data = data,
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
	['char'] = {bitPixType=fits.BYTE_IMG, imgType=fits.TBYTE},	-- default is unsigned? that's what they keep tellign us ...
	['unsigned char'] = {bitPixType=fits.BYTE_IMG, imgType=fits.TBYTE},
	['signed char'] = {bitPixType=fits.SBYTE_IMG, imgType=fits.TSBYTE},
	['short'] = {bitPixType=fits.SHORT_IMG, imgType=fits.TSHORT},
	['signed short'] = {bitPixType=fits.SHORT_IMG, imgType=fits.TSHORT},
	['unsigned short'] = {bitPixType=fits.USHORT_IMG, imgType=fits.TUSHORT},
	['int'] = {bitPixType=fits.LONG_IMG, imgType=fits.TINT},	-- 32bit ... right? technically 'long' isn't anymore 32bit ...
	['signed int'] = {bitPixType=fits.LONG_IMG, imgType=fits.TINT},
	['unsigned int'] = {bitPixType=fits.ULONG_IMG, imgType=fits.TUINT},
	['long'] = {bitPixType=fits.LONGLONG_IMG, imgType=fits.TLONGLONG},	-- 64bit... ? or is this TLONG vs TINT (since there is a distinct TULONG type ...)
	['signed long'] = {bitPixType=fits.LONGLONG_IMG, imgType=fits.TLONGLONG},
	['unsigned long'] = {bitPixType=fits.LONGLONG_IMG, imgType=fits.TLONGLONG},	-- FITS has no unsigned 64-bit long ...
	['float'] = {bitPixType=fits.FLOAT_IMG, imgType=fits.TFLOAT},
	['double'] = {bitPixType=fits.DOUBLE_IMG, imgType=fits.TDOUBLE},
}

function FITSLoader:save(args)
	-- args:
	local filename = assert(args.filename, "expected filename")
	local width = assert(args.width, "expected width")
	local height = assert(args.height, "expected height")
	local channels = assert(args.channels, "expected channels")
	local format = assert(args.format, "expected format")
	local data = assert(args.data, "expected data")

	if io.fileexists(filename) then os.remove(filename) end

	local status = gcmem.new('int', 1)
	status[0] = 0

	local fitsFilePtr = gcmem.new('fitsfile *', 1)
	fitsFilePtr[0] = nil
	
	fits.ffinit(fitsFilePtr, filename, status)
	assert(status[0] == 0, "ffinit failed with " .. status[0])

	local sizes = gcmem.new('long', 3)
	sizes[0] = width
	sizes[1] = height
	sizes[2] = channels

	local formatInfo = assert(formatInfos[format], "failed to find FITS type for format "..format)
	local bitPixType = formatInfo.bitPixType
	
	status[0] = fits.ffphps(fitsFilePtr[0], bitPixType, 3, sizes, status)
	assert(status[0] == 0, "ffphps failed with " .. status[0])
	
	local firstpix = gcmem.new('long int', 3)
	for i=0,2 do
		firstpix[i] = 1
	end
	
	local numPixels = width * height * channels
	
	local imgType = formatInfo.imgType 

	fits.ffppx(fitsFilePtr[0], imgType, firstpix, numPixels, ffi.cast('void*', data), status)
	assert(status[0] == 0, "ffppx failed with " .. status[0])
	
	fits.ffclos(fitsFilePtr[0], status);
	assert(status[0] == 0, "ffclos failed with " .. status[0])
end

return FITSLoader
