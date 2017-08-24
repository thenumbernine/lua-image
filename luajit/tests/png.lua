#!/usr/bin/env luajit
local Image = require 'image'
local image = Image'test.png'
image:save'test-write.png'
