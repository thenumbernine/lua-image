-- png, jpeg, tiff, limited bmp and tga, ppm, fits
-- requires a separate shared object to be built
--return require 'image.luaimg.image'

-- png, jpeg
-- sdl has more read support but only bmp write support =(
--return require 'image.sdl_image.image'

-- bmp, png, tiff
-- pure luajit ffi
local Image = require 'image.luajit.image'

function Image.iterfunc(s, var)
	s.x = s.x + 1
	local sizex, sizey = s.img.width, s.img.height
	if s.x >= sizex then
		s.x = 0
		s.y = s.y + 1
		if s.y >= sizey then
			s.y = 0
			return nil
		end
	end
	return s.x, s.y
end

function Image:iter()
	return Image.iterfunc, {x=-1,y=0,img=self}, nil
end

-- only override if the providing impementation doesn't have its own
if not Image.clone then
	function Image:clone()
		local dst = Image(self.width, self.height, self.channels)
		for x,y in dst:iter() do
			dst(x,y,self(x,y))
		end
		return dst
	end
end

return Image

