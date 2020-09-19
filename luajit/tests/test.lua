#!/usr/bin/env luajit
require 'ext'
local format = ...
local Image = require 'image'
local filename = 'test.'..format
local writeFilename = 'test-write.'..format
if not os.fileexists(filename) then
	-- test writing only 
	-- ... by reading a file format that we assume is working
	filename = 'test.bmp'
	writeFilename = 'test.'..format
end
print('reading '..filename)
local image = assert(Image(filename), "failed to open image "..filename)
print('writing '..writeFilename)
assert(image:save(writeFilename), "failed to save image "..writeFilename)
