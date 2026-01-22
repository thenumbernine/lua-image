#!/usr/bin/env luajit
local path = require 'ext.path'
local Image = require 'image'
local tiff = require 'image.ffi.tiff'

local uncompressedSize
local image = Image'test.tiff'
local dir = path'test-tiff-compression'
dir:mkdir()
assert(dir:isdir())
for _,compression in ipairs{
	'COMPRESSION_NONE',
	'COMPRESSION_CCITTRLE',
	'COMPRESSION_CCITTFAX3',
	'COMPRESSION_CCITT_T4',
	'COMPRESSION_CCITTFAX4',
	'COMPRESSION_CCITT_T6',
	'COMPRESSION_LZW',
	'COMPRESSION_OJPEG',
	'COMPRESSION_JPEG',
	'COMPRESSION_T85',
	'COMPRESSION_T43',
	'COMPRESSION_NEXT',
	'COMPRESSION_CCITTRLEW',
	'COMPRESSION_PACKBITS',
	'COMPRESSION_THUNDERSCAN',
	'COMPRESSION_IT8CTPAD',
	'COMPRESSION_IT8LW',
	'COMPRESSION_IT8MP',
	'COMPRESSION_IT8BL',
	'COMPRESSION_PIXARFILM',
	'COMPRESSION_PIXARLOG',
	'COMPRESSION_DEFLATE',
	'COMPRESSION_ADOBE_DEFLATE',
	'COMPRESSION_DCS',
	'COMPRESSION_JBIG',
	'COMPRESSION_SGILOG',
	'COMPRESSION_SGILOG24',
	'COMPRESSION_JP2000',
	'COMPRESSION_LERC',
	'COMPRESSION_LZMA',
	'COMPRESSION_ZSTD',
	'COMPRESSION_WEBP',
	'COMPRESSION_JXL',
} do
	local dstfn = dir(compression..'.tiff')
	print('saving', dstfn)
	xpcall(function()
		image.compression = assert(tiff[compression])
		image:save(dstfn.path)
		local size = dstfn:attr().size
		-- make sure COMPRESSION_NONE is first
		if compression == 'COMPRESSION_NONE' then
			uncompressedSize = size
		end
		print('size', size, ('%d%%'):format(100 * size / uncompressedSize ))
	end, function(err)
		print(err)
	end)
end
