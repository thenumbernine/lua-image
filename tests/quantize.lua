#!/usr/bin/env luajit
local table = require 'ext.table'
local Image = require 'image'
local Quantize = require 'image.quantize_mediancut'

local srcfn, dstfn = ...
assert(srcfn and dstfn, "expected [quantize.lua] srcfn dstfn")

local srcimg = Image(srcfn)


local histogram = Quantize.buildHistogram(srcimg)
local numColors = #table.keys(histogram)

local dstimg = assert(Quantize.reduceColorsMedianCut{
	image = srcimg,
	targetSize = math.min(256, numColors),
	hist = histogram,
})

assert(dstimg:save(dstfn))
