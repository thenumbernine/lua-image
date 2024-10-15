#!/usr/bin/env luajit
local path = require 'ext.path'
local readFilename, writeFilename = ...
local Image = require 'image'
assert(readFilename, "expected test.lua <infile> [<outfile>]")
print('reading '..readFilename)
local image = assert(Image(readFilename), "failed to open image "..readFilename)
print(require 'ext.tolua'(image))

if writeFilename then
	print('writing '..writeFilename)
	assert(image:save(writeFilename), "failed to save image "..writeFilename)
end
