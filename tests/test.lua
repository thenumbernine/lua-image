#!/usr/bin/env luajit
local path = require 'ext.path'
local format, writeFilename = ...
assert(format)
local Image = require 'image'
local filename = 'test.'..format
writeFilename = writeFilename or ('test-write.'..format)
if not path(filename):exists() then
	-- test writing only
	-- ... by reading a file format that we assume is working
	filename = 'test.bmp'
	writeFilename = 'test.'..format
end
print('reading '..filename)
local image = assert(Image(filename), "failed to open image "..filename)
print('writing '..writeFilename)
assert(image:save(writeFilename), "failed to save image "..writeFilename)
