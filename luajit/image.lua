--[[
TODO all the loaders are currently designed to work for RGB,
whereas the other options (luaimg, sdl_image) are designed to work for RGBA
so this needs to be changed to work with RGBA too
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local gcmem = require 'ext.gcmem'
local io = require 'ext.io'	-- getfileext
local unpack = unpack or table.unpack

local Image = class()

Image.loaders = {
	bmp = 'image.luajit.bmp',
	fits = 'image.luajit.fits',
	jpg = 'image.luajit.jpeg',
	jpeg = 'image.luajit.jpeg',
	png = 'image.luajit.png',
	tif = 'image.luajit.tiff',
	tiff = 'image.luajit.tiff',
}

local function getLoaderForFilename(filename)
	local ext = assert(select(2, io.getfileext(filename)):lower(), "failed to get extension for filename "..tostring(filename))
	local loaderRequire = assert(Image.loaders[ext], "failed to find loader class for extension "..ext.." for filename "..filename)
	local loaderClass = require(loaderRequire)
	local loader = loaderClass()
	return loader
end

function Image:init(width,height,channels,format,generator)
	channels = channels or 4
	format = format or 'double'
	if type(width) == 'string' then
		local filename = width
		local loader = getLoaderForFilename(filename)
		local result = loader:load(filename)
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
				dst.buffer[0 + 3 * (i + self.width * j)] = self.channels < 1 and 0 or self.buffer[0 + index]
				dst.buffer[1 + 3 * (i + self.width * j)] = self.channels < 2 and 0 or self.buffer[1 + index]
				dst.buffer[2 + 3 * (i + self.width * j)] = self.channels < 3 and 0 or self.buffer[2 + index]
			end
		end
	end
	return dst
end

function Image:clamp(min,max)
	local result = self:clone()
	for i=0,result.width*result.height*result.channels-1 do
		result.buffer[i] = math.max(min, math.min(max, result.buffer[i]))
	end
	return result
end

function Image:save(filename, ...)

	local loader = getLoaderForFilename(filename)

	-- may or may not be the same object ...
	local converted = loader:prepareImage(self)	
	
	loader:save{
		filename = filename,
		width = converted.width,
		height = converted.height,
		channels = converted.channels,
		format = converted.format,
		data = converted.buffer,
	}
	
	-- returns self solely for chaining commands
	return self 
end

-- the common API
function Image:size()
	return self.width, self.height, self.channels
end

function Image:__call(x, y, ...)
	local index = self.channels * (x + self.width * y)
	local oldPixel = {}
	local newPixel = {...}
	local info = formatInfo[self.format]
	for j=0,self.channels-1 do
		local v = tonumber(self.buffer[index])
		if info then
			if info.bias then
				v = v + info.bias
			end
			v = v / info.scale
		end
		oldPixel[j+1] = v
	end
	if #newPixel > 0 then
		for j=0,self.channels-1 do
			local v = tonumber(newPixel[j+1])
			if info then
				v = v * info.scale
				if info.bias then
					v = v - info.bias
				end
			end
			self.buffer[index+j] = v
		end
	end
	return unpack(oldPixel)
end

function Image:data()
	return self.buffer
end
-- end common API

function Image:clone()
	local result = Image(self.width, self.height, self.channels, self.format)
	ffi.copy(result.buffer, self.buffer, self.width * self.height * self.channels * ffi.sizeof(self.format))
	return result
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

-- merges all image channels together
-- assumes sizes all match
-- uses the first image's format
function Image.combine(...)
	local srcs = {...}
	assert(#srcs > 0)
	local width = srcs[1].width
	local height = srcs[1].height
	local channels = srcs[1].channels
	local format = srcs[1].format
	for i=2,#srcs do
		assert(width == srcs[i].width)
		assert(height == srcs[i].height)
		if srcs[i].format ~= format then
			srcs[i] = srcs[i]:setFormat(format)
		end
		channels = channels + srcs[i].channels
	end
	assert(channels > 0)
	local result = Image(width, height, channels, format)
	for y=0,height-1 do
		for x=0,width-1 do
			local dstch = 0
			for _,src in ipairs(srcs) do
				for srcch=0,src.channels-1 do
					result.buffer[dstch+channels*(x+width*y)] = src.buffer[srcch+src.channels*(x+width*y)]
					dstch = dstch + 1
				end
			end
			assert(dstch == channels)
		end
	end
	return result
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

-- args: x, y, width, height
function Image:copy(args)
	assert(args.x)
	assert(args.y)
	assert(args.width)
	assert(args.height)
	local result = Image(math.floor(args.width), math.floor(args.height), self.channels, self.format)
	for y=0,result.height-1 do
		for x=0,result.width-1 do
			for ch=0,result.channels-1 do
				local sx = x + math.floor(args.x)
				local sy = y + math.floor(args.y)
				if sx >= 0 and sy >= 0 and sx < self.width and sy < self.height then
					result.buffer[ch+result.channels*(x+result.width*y)] = self.buffer[ch+self.channels*(sx+self.width*sy)]
				else
					result.buffer[ch+result.channels*(x+result.width*y)] = 0
				end
			end
		end
	end
	return result
end

-- args: image, x, y
function Image:paste(args)
	local pasted = assert(args.image)
	assert(pasted.channels == self.channels)	-- for now ...
	local result = self:clone()
	for y=0,pasted.height-1 do
		for x=0,pasted.width-1 do
			for ch=0,pasted.channels-1 do
				result.buffer[ch+result.channels*(x+args.x+result.width*(y+args.y))] = pasted.buffer[ch+pasted.channels*(x+pasted.width*y)]
			end
		end
	end
	return result
end

Image.gradientKernels = {
	simple = Image(2,1,1,'double',{-1,1}),
	Sobel = Image(3,3,1,'double',{-1,0,1,-2,0,2,-1,0,1})/4,
	Scharr = Image(3,3,1,'double',{-3,0,3,-10,0,10,-3,0,3})/16,
	-- TODO Gaussian gradient
	-- TODO make boundary modulo optional
}
function Image:gradient(kernelName, offsetX, offsetY)
	if not kernelName then kernelName = 'Sobel' end
	local kernel = assert(self.gradientKernels[kernelName], "could not find gradient "..tostring(kernelName))
	-- TODO cache transposed kernels?
	offsetX = (offsetX or 0) - math.floor(kernel.width/2)
	offsetY = (offsetY or 0) - math.floor(kernel.height/2)
	return
		self:kernel(kernel, false, offsetX, offsetY),
		self:kernel(kernel:transpose(), false, offsetY, offsetX)
end

function Image:curvature()
	assert(self.channels == 1)
	local gradX, gradY = self:gradient()
	local gradXX, gradXY = gradX:gradient()
	local gradYX, gradYY = gradY:gradient()
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
	local _, dy_dx = imgX:gradient()
	local dx_dy = imgY:gradient()
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
	local index = 0
	for y=0,self.height-1 do
		for x=0,self.width-1 do
			for ch=0,self.channels-1 do
				dst.buffer[index] = map(self.buffer[index],x,y,ch)
				index = index + 1
			end
		end
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

function Image:kernel(kernel, normalize, ofx, ofy)
	assert(kernel.channels == 1)
	local dst = Image(self.width, self.height, self.channels, self.format)

	local normalization = 1
	if normalize then
		normalization = 0
		for y=0,kernel.height-1 do
			for x=0,kernel.width-1 do
				local kernelValue = kernel.buffer[x+kernel.width*y]
				normalization = normalization + kernelValue
			end
		end
		normalization = 1 / normalization 
	end

	for j=0,self.height-1 do
		for i=0,self.width-1 do
			for ch=0,self.channels-1 do
				local sum = 0
				for y=0,kernel.height-1 do
					for x=0,kernel.width-1 do
						local sx = (i + x + ofx + self.width) % self.width
						local sy = (j + y + ofy + self.height) % self.height
						local kernelValue = kernel.buffer[x+kernel.width*y]
						sum = sum + kernelValue * self.buffer[ch + self.channels * (sx + self.width * sy)]
					end
				end
				dst.buffer[ch + self.channels * (i + self.width * j)] = normalization * sum 
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
		:normalize()
	local yKernel = xKernel:transpose()
	return self:kernel(xKernel, false, -size, 0):kernel(yKernel, false, 0, -size)
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

function Image:norm()
	return self:dot(self)
end 

-- 'self' should be the solution vector (b)
function Image:solveConjGrad(args)
	-- optionally accept a single function as the linear function, use defaults for the rest
	if type(args) == 'function' then args = {A=args} end

	local conjgrad = require 'solver.conjgrad'
	return conjgrad{
		A = args.A,
		b = self,
		x = args.x,
		clone = Image.clone,
		dot = Image.dot,
		norm = Image.norm,
		errorCallback = args.errorCallback,
		epsilon = args.epsilon,
		maxiter = args.maxiter,
	}
end

function Image:solveConjRes(args)
	-- optionally accept a single function as the linear function, use defaults for the rest
	if type(args) == 'function' then args = {A=args} end

	local conjres = require 'solver.conjres'
	return conjres{
		A = args.A,
		b = self,
		x = args.x,
		clone = Image.clone,
		dot = Image.dot,
		norm = Image.norm,
		errorCallback = args.errorCallback,
		epsilon = args.epsilon,
		maxiter = args.maxiter,
	}
end

function Image:solveGMRes(args)
	if type(args) == 'function' then args = {A=args} end
	local gmres = require 'solver.gmres'
	local volume = self.width * self.height * self.channels
	return gmres{
		A = args.A,
		b = self,
		x = args.x,
		clone = Image.clone,
		dot = Image.dot,
		norm = Image.norm,
		--MInv = function(x) return preconditioner inverse applied to x end,
		errorCallback = args.errorCallback,
		epsilon = args.epsilon,
		maxiter = args.maxiter or 10 * volume,
		restart = args.restart or volume, 
	}
end

Image.simpleBlurKernel = Image(3,3,1,'double',{0,1,0, 1,4,1, 0,1,0})/8
function Image:simpleBlur()
	return self:kernel(self.simpleBlurKernel, false, -1, -1)
end

-- TODO offer multiple options
Image.divergenceKernel = Image(3,3,1,'double',{0,1,0,1,-4,1,0,1,0})
function Image:divergence()
	return self:kernel(self.divergenceKernel, false, -1, -1)
end

-- should this invert all channels, or just up to the first three?
-- first three ...
function Image:invert()
	local info = formatInfo[self.format]
	local scale = info and info.scale or 1
	local bias = info and info.bias or 0
	return Image(self.width, self.height, self.channels, self.format, function(x,y)
		local pixel = {}
		for ch=1,self.channels do
			pixel[ch] = self.buffer[ch-1 + self.channels * (x + self.width * y)]
			if ch <= 3 then
				pixel[ch] = (scale - (tonumber(pixel[ch]) + bias)) - scale
			end
		end
		return unpack(pixel)
	end)
end

--[[
resize options:
nearest 
linear
--]]
function Image:resize(newx, newy, method)
	newx = math.floor(newx)
	newy = math.floor(newy)
	method = method or 'nearest'
	return Image(newx, newy, self.channels, self.format, function(x,y)
		local sxmin = math.floor(x*self.width/newx)
		local sxmax = math.floor((x+1)*self.width/newx)
		local symin = math.floor(y*self.height/newy)
		local symax = math.floor((y+1)*self.height/newy)
		sxmax = math.max(sxmax, sxmin+1)
		symax = math.max(symax, symin+1)
		local pixel = {}
		for ch=0,self.channels-1 do
			pixel[ch+1] = 0
			local total = 0
			for sy=symin,symax-1 do
				for sx=sxmin,sxmax-1 do
					pixel[ch+1] = self.buffer[ch+self.channels*(sx+self.width*sy)] + pixel[ch+1]
					total = total + 1
				end
			end
			if total>0 then
				pixel[ch+1] = pixel[ch+1] / total
			end
		end
		return unpack(pixel)
	end)
end

return Image
