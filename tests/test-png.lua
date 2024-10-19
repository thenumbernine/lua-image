#!/usr/bin/env luajit
local assert = require 'ext.assert'
local Image = require 'image'
local image = Image(... or 'test.png')
print(require 'ext.tolua'(image))

image.unknown = image.unknown or {}
--[[
http://www.libpng.org/pub/png/spec/1.2/PNG-Encoders.html#E.Use-of-private-chunks
"Applications can use PNG private chunks to carry information that need not be understood by other applications.
	Such chunks must be given names with **lowercase second letters**, to ensure that they can never conflict with any future public chunk definition. "
"Use an ancillary chunk type (**lowercase first letter**), not a critical chunk type, for all private chunks that store information that is not absolutely essential to view the image. "
--]]
image.unknown.blEH = {
	data = 'Testing Testing',
}
print'saving'
image:save'test-save.png'
print'saved'
print'loading'
local image2 = Image'test-save.png'
print(require 'ext.tolua'(image2))
assert.eq(image2.unknown.blEH.data, 'Testing Testing')
