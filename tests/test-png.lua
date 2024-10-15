#!/usr/bin/env luajit
local asserteq = require 'ext.assert'.eq
local Image = require 'image'
local image = Image(... or 'test.png')
print(require 'ext.tolua'(image))

image.unknown = image.unknown or {}
image.unknown.BlEh = {
	data = 'Testing Testing',
}
print'saving'
image:save'test-save.png'
print'saved'
print'loading'
local image2 = Image'test-save.png'
print(require 'ext.tolua'(image2))
asserteq(image2.unknown.BlEh.data, 'Testing Testing')
