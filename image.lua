-- png, jpeg, tiff, limited bmp and tga, ppm, fits 
-- requires a separate shared object to be built
return require 'image.luaimg.image'

-- png, jpeg
-- sdl has more read support but only bmp write support =(
--return require 'image.sdl_image.image'

-- bmp, png, tiff
-- pure luajit ffi
return require 'image.luajit.image'
