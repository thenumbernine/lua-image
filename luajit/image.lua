--[[
TODO all the loaders are currently designed to work for RGB,
whereas the other options (luaimg, sdl_image) are designed to work for RGBA
so this needs to be changed to work with RGBA too
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local gcmem = require 'ext.gcmem'

local Image = class()

Image.loaders = {
	png = require 'image.luajit.png',
	bmp = require 'image.luajit.bmp',
	tif = require 'image.luajit.tiff',
	tiff = require 'image.luajit.tiff',
	jpg = require 'image.luajit.jpeg',
	jpeg = require 'image.luajit.jpeg',
}

function Image:init(width,height,channels,format,generator)
	channels = channels or 4
	format = format or 'double'
	if type(width) == 'string' then
		local filename = width
		local ext = filename:match'.*%.(.-)$'
		local loader = ext and self.loaders[ext:lower()]
		if not loader then
			error("I don't know how to load a file with ext "..tostring(ext))
		end
		local result = loader.load(filename)
		self.buffer = result.data
		self.width = result.width
		self.height = result.height
		self.format = result.format or 'unsigned char'	-- the typical result
		self.channels = result.channels or 3
	else
		self.buffer = gcmem.new(format, width * height * channels)
		self.width = width
		self.height = height
		self.channels = channels
		self.format = format
		if type(generator) == 'function' then
			for y=0,self.height-1 do
				for x=0,self.width-1 do
					local values = {generator(x,y)}
					for ch=0,self.channels-1 do
						self.buffer[ch + self.channels * (x + self.width * y)] = values[ch+1] or 0
					end
				end
			end
		elseif type(generator) == 'table' then
			for i=0,self.width*self.height*self.channels-1 do
				self.buffer[i] = generator[i+1]
			end
		end
	end
end

function Image:setChannels(newChannels)
	local dst = Image(self.width, self.height, newChannels, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			local index = i + self.width * j
			for ch=0,math.min(self.channels,newChannels)-1 do
				dst.buffer[ch+newChannels*index] = self.buffer[ch+self.channels*index]
			end
		end
	end
	return dst
end

local formatInfo = {
	['char'] = {bias=128, scale=255},
	['signed char'] = {bias=128, scale=255},
	['unsigned char'] = {scale=255},
	['short'] = {bias=32768, scale=65536},
	['signed short'] = {bias=32768, scale=65536},
	['unsigned short'] = {scale=65536},
	['int'] = {bias=2^31, scale=2^32},
	['signed int'] = {bias=2^31, scale=2^32},
	['unsigned int'] = {scale=2^32},
}

function Image:setFormat(newFormat)
	local newData = gcmem.new(newFormat, self.width * self.height * self.channels)
	local dst = Image(self.width, self.height, self.channels, newFormat)
	local fromFormatInfo = formatInfo[self.format]
	local toFormatInfo = formatInfo[newFormat]
	for index=0,self.width*self.height*self.channels-1 do
		local value = tonumber(self.buffer[index])
		if fromFormatInfo then
			if fromFormatInfo.bias then
				value = value + fromFormatInfo.bias
			end
			value = value / fromFormatInfo.scale
		end
		if toFormatInfo then
			value = value * toFormatInfo.scale
			if toFormatInfo.bias then
				value = value - toFormatInfo.bias
			end
		end
		dst.buffer[index] = ffi.cast(newFormat, value)
	end
	return dst
end

function Image:rgb()
	local dst = Image(self.width, self.height, 3, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			if self.channels == 1 then
				local grey = self.buffer[i + self.width * j]
				dst.buffer[0 + 3 * (i + dst.width * j)] = grey
				dst.buffer[1 + 3 * (i + dst.width * j)] = grey
				dst.buffer[2 + 3 * (i + dst.width * j)] = grey
			else
				local index = self.channels * (i + self.width * j)
				local r,g,b = self.buffer[0 + index], self.buffer[1 + index], self.buffer[2 + index]
				dst.buffer[0 + 3 * (i + self.width * j)] = r or 0
				dst.buffer[1 + 3 * (i + self.width * j)] = g or 0
				dst.buffer[2 + 3 * (i + self.width * j)] = b or 0
			end
		end
	end
	return dst
end

function Image:save(filename, ...)
	local original = self
	self = self:rgb():setFormat'unsigned char'
	assert(self.channels == 3, "expected only 3 channels")
	local ext = filename:match'.*%.(.-)$'
	local loader = ext and self.loaders[ext:lower()]
	if not loader then
		error("I don't know how to load a file with ext "..tostring(ext))
	end
	loader.save{
		filename = filename,
		width = self.width,
		height = self.height,
		channels = self.channels,
		data = self.buffer,
	}
	return original
end

function Image:size()
	return self.width, self.height, self.channels
end

function Image:__call(x,y,r,g,b,a)
	local i = self.channels * (x + self.width * y)
	local pixels = self.buffer
	local _r = pixels[i+0] / 255
	local _g = self.channels > 1 and pixels[i+1] / 255
	local _b = self.channels > 2 and pixels[i+2] / 255
	local _a = self.channels > 3 and pixels[i+3] / 255
	if r ~= nil then pixels[i+0] = math.floor(r * 255) end
	if self.channels > 1 and g ~= nil then pixels[i+1] = math.floor(g * 255) end
	if self.channels > 2 and b ~= nil then pixels[i+2] = math.floor(b * 255) end
	if self.channels > 3 and a ~= nil then pixels[i+3] = math.floor(a * 255) end
	return _r, _g, _b, _a
end

function Image:data()
	return self.buffer
end

for _,info in ipairs{
	{op='__add', func=function(a,b) return a + b end},
	{op='__sub', func=function(a,b) return a - b end},
	{op='__mul', func=function(a,b) return a * b end},
	{op='__div', func=function(a,b) return a / b end},
	{op='__pow', func=function(a,b) return a ^ b end},
	{op='__mod', func=function(a,b) return a % b end},
} do
	Image[info.op] = function(a,b)
		local aIsImage = type(a) == 'table' and a.isa and a:isa(Image)
		local bIsImage = type(b) == 'table' and b.isa and b:isa(Image)
		if aIsImage and bIsImage then 
			assert(a.width == b.width)
			assert(a.height == b.height)
			assert(a.channels == b.channels)
		end
		local width = aIsImage and a.width or b.width
		local height = aIsImage and a.height or b.height
		local channels = aIsImage and a.channels or b.channels
		local c = Image(width, height, channels, aIsImage and a.format or b.format)
		for index=0,width*height*channels-1 do
			local va = type(a) == 'number' and a or a.buffer[index]
			local vb = type(b) == 'number' and b or b.buffer[index]
			c.buffer[index] = info.func(va, vb)
		end
		return c
	end
end

function Image:split()
	local dsts = {}
	for i=1,self.channels do
		dsts[i] = Image(self.width, self.height, 1, self.format)
	end
	for index=0,self.width*self.height-1 do
		for ch=0,self.channels-1 do
			dsts[ch+1].buffer[index] = self.buffer[ch + self.channels * index]
		end
	end
	return unpack(dsts)
end

function Image:greyscale()
	assert(self.channels >= 3)
	local dst = Image(self.width, self.height, 1, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			local index = self.channels * (i + self.width * j)
			local r,g,b = self.buffer[0 + index], self.buffer[1 + index], self.buffer[2 + index]
			local grey = .3*r + .59*g + .11*b
			dst.buffer[i + self.width * j] = grey
		end
	end
	return dst
end

function Image:gradient()
	assert(self.channels == 1)
	local dst = Image(self.width, self.height, 2, self.format)
	for j=0,self.height-1 do
		local jm = (j-1+self.height)%self.height
		local jp = (j+1)%self.height
		for i=0,self.width-1 do
			local im = (i-1+self.width)%self.width
			local ip = (i+1)%self.width
			local dx = (self.buffer[ip + self.width * j] - self.buffer[im + self.width * j])/2
			local dy = (self.buffer[i + self.width * jp] - self.buffer[i + self.width * jm])/2
			dst.buffer[0 + 2 * (i + dst.width * j)] = dx
			dst.buffer[1 + 2 * (i + dst.width * j)] = dy
		end
	end
	return dst
end

function Image:divergence()
	assert(self.channels == 1)
	local gradX, gradY = self:gradient():split()
	local gradXX = gradX:gradient():split()
	local _, gradYY = gradY:gradient():split()
	return gradXX + gradYY
end

function Image:curvature()
	assert(self.channels == 1)
	local gradX, gradY = self:gradient():split()
	local gradXX, gradXY = gradX:gradient():split()
	local gradYX, gradYY = gradY:gradient():split()
	local dst = Image(self.width, self.height, 1, self.format)
	for index=0,self.width*self.height-1 do
		dst.buffer[index] = (gradXX.buffer[index] * gradY.buffer[index]^2 - 2 * gradXY.buffer[index] * gradX.buffer[index] * gradY.buffer[index] + gradYY.buffer[index] * gradX.buffer[index]^2)
--			/ math.sqrt(gradX.buffer[index]^2 + gradY.buffer[index]^2)^3
	end
	return dst
end

function Image:curl()
	assert(self.channels == 2)
	local imgX, imgY = self:split()
	local _, dy_dx = imgX:gradient():split()
	local dx_dy = imgY:gradient():split()
	return dy_dx - dx_dy
end

function Image:normalize()
	local mins = {}
	local maxs = {}
	for index=0,self.width*self.height-1 do
		for ch=0,self.channels-1 do
			local v = self.buffer[ch + self.channels * index]
			mins[ch] = math.min(mins[ch] or v, v)
			maxs[ch] = math.max(maxs[ch] or v, v)
		end
	end
	local dst = self:clone()
	for index=0,self.width*self.height-1 do
		for ch=0,self.channels-1 do
			local v = self.buffer[ch + self.channels * index]
			dst.buffer[ch + self.channels * index] = (v - mins[ch]) / (maxs[ch] - mins[ch])
		end
	end
	return dst
end

function Image:map(map)
	local dst = Image(self.width, self.height, self.channels, self.format)
	for index=0,self.width*self.height*self.channels-1 do
		dst.buffer[index] = map(self.buffer[index])
	end
	return dst
end

function Image:blur()
	local dst = Image(self.width, self.height, self.channels, self.format)
	for j=0,self.height-1 do
		local jp = (j+1)%self.height
		local jm = (j-1+self.height)%self.height
		for i=0,self.width-1 do
			local ip = (i+1)%self.width
			local im = (i-1+self.width)%self.width
			for ch=0,self.channels-1 do
				dst.buffer[ch+self.channels*(i+self.width*j)] = 
					(self.buffer[ch+self.channels*(ip+self.width*j)]
					+ self.buffer[ch+self.channels*(im+self.width*j)]
					+ self.buffer[ch+self.channels*(i+self.width*jp)]
					+ self.buffer[ch+self.channels*(i+self.width*jm)]
					+ 4 * self.buffer[ch+self.channels*(i+self.width*j)])/8
			end
		end
	end
	return dst
end

function Image:kernel(kernel)
	assert(kernel.channels == 1)
	local dst = Image(self.width, self.height, self.channels, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			for ch=0,self.channels-1 do
				local n = 0
				local d = 0
				for y=0,kernel.height-1 do
					for x=0,kernel.width-1 do
						local sx = (i + x + self.width) % self.width
						local sy = (j + y + self.height) % self.height
						local k = kernel.buffer[x+kernel.width*y]
						n = n + k * self.buffer[ch + self.channels * (sx + self.width * sy)]
						d = d + k
					end
				end
				dst.buffer[ch + self.channels * (i + self.width * j)] = n / d
			end
		end
	end
	return dst
end

function Image:transpose()
	local dst = Image(self.height, self.width, self.channels, self.format)
	for j=0,dst.height-1 do
		for i=0,dst.width-1 do
			for ch=0,dst.channels-1 do
				dst.buffer[ch+self.channels*(i+dst.width*j)] = self.buffer[ch+self.channels*(j+dst.height*i)]
			end
		end
	end
	return dst
end

-- static function
function Image.gaussianKernel(sigma, width, height)
	if not width then width = 6*math.floor(sigma)+1 end
	if not height then height = width end
	local sigmaSq = sigma^2
	local normalization = 1 / math.sqrt(2 * math.pi * sigmaSq)
	return Image(width, height, 1, 'double', function(x,y)
		local dx = (x+.5) - (width/2)
		local dy = (y+.5) - (height/2)
		return normalization * math.exp((-dx*dx-dy*dy)/sigmaSq) 
	end)
end

function Image:gaussianBlur(size, sigma)
	sigma = sigma or size / 3
	-- separate kernels and apply individually for performance's sake
	local xKernel = Image.gaussianKernel(sigma, 2*size+1, 1)
	local yKernel = xKernel:transpose()
	return self:kernel(xKernel):kernel(yKernel)
end

function Image.dot(a,b)
	assert(a.width == b.width)
	assert(a.height == b.height)
	assert(a.channels == b.channels)
	local sum = 0
	for i=0,a.width*a.height*a.channels-1 do
		sum = sum + a.buffer[i] * b.buffer[i]
	end
	return sum
end

function Image:norm() return self:dot(self) end 

--[[
args:
	A = linear function applied to image
	epsilon = error tolerance
	maxiter = max iterations to run

TODO use LinearSolvers
	- abstract vec() and :norm() and make error tracking optional
--]]
function Image:solveConjGrad(args)
	-- optionally accept a single function as the linear function, use defaults for the rest
	if type(args) == 'function' then args = {A=args} end
	
	local A = assert(args.A, "expected A")
	local epsilon = args.epsilon or 1e-20
	local maxiter = args.maxiter or 100
	
	local b = self:clone()
	local x = b:clone()
	local r = b - A(x)
	local r2 = r:norm()
	print('error',r2)
	if r2 < epsilon then return x end
	local p = r:clone()
	for iter=1,maxiter do
		local Ap = A(p)
		local alpha = r2 / Image.dot(p, Ap)
		x = x + alpha * p
		local nr = r - alpha * Ap
		local nr2 = nr:norm()
		print('error',nr2)
		local beta = nr2 / r2
		if nr2 < epsilon then break end
		r = nr
		r2 = nr2
		p = r + beta * p
	end
	return x
end


Image.simpleBlurKernel = Image(3,3,1,'double',{0,1,0, 1,4,1, 0,1,0})/8
function Image:simpleBlur()
	return self:kernel(simpleBlurKernel)
end

return Image
