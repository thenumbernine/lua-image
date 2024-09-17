#!/usr/bin/env luajit
local fn = assert(..., "expected filename")
local image = Image(fn)
print('width', image.width)
print('height', image.height)
print('channels', image.channels)
print('format', image.format)
