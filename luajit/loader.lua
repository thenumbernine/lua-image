local class = require 'ext.class'

local Loader = class()

-- convert to a valid format, complain if it can't be converted
function Loader:prepareImage(image)
	image = image:rgb():clamp(0,1):setFormat'unsigned char'
	assert(image.channels == 3, "expected only 3 channels")
	return image
end

return Loader
