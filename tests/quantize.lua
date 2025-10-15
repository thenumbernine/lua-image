#!/usr/bin/env luajit
local Image = require 'image'

local srcfn, dstfn = ...
assert(srcfn and dstfn, "expected [quantize.lua] srcfn dstfn")

assert(Image(srcfn):toIndexed():save(dstfn))
