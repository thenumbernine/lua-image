#!/usr/bin/env luajit
require 'ext'
local file = require 'ext.file'
local format, writeFilename = ...
local Image = require 'image'
local filename = 'test.'..format
writeFilename = writeFilename or ('test-write.'..format)
if not file(filename):exists() then
	-- test writing only
	-- ... by reading a file format that we assume is working
	filename = 'test.bmp'
	writeFilename = 'test.'..format
end
print('reading '..filename)
local image = assert(Image(filename), "failed to open image "..filename)
print('writing '..writeFilename)
assert(image:save(writeFilename), "failed to save image "..writeFilename)
