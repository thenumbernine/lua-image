package = "image"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/lua-image"
}
description = {
	summary = "LuaJIT image library",
	detailed = "LuaJIT image library",
	homepage = "https://github.com/thenumbernine/lua-image",
	license = "MIT",
}
dependencies = {
	"lua >= 5.1",
}
build = {
	type = "builtin",
	modules = {
		["image"] = "image.lua",
		["image.luaimg.image"] = "luaimg/image.lua",
		["image.luajit.bmp"] = "luajit/bmp.lua",
		["image.luajit.fits"] = "luajit/fits.lua",
		["image.luajit.gif"] = "luajit/gif.lua",
		["image.luajit.image"] = "luajit/image.lua",
		["image.luajit.jpeg"] = "luajit/jpeg.lua",
		["image.luajit.loader"] = "luajit/loader.lua",
		["image.luajit.png"] = "luajit/png.lua",
		["image.luajit.tests.test"] = "luajit/tests/test.lua",
		["image.luajit.tests.test-all"] = "luajit/tests/test-all.lua",
		["image.luajit.tiff"] = "luajit/tiff.lua",
		["image.sdl_image.image"] = "sdl_image/image.lua"
	}
}
