--[[
TODO all the loaders are currently designed to work for RGB,
whereas the other options (luaimg, sdl_image) are designed to work for RGBA
so this needs to be changed to work with RGBA too
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local path = require 'ext.path'	-- getext
local table = require 'ext.table'
local string = require 'ext.string'
local assert = require 'ext.assert'


local char = ffi.typeof'char'
local int8_t = ffi.typeof'int8_t'
local signed_char = ffi.typeof'signed char'
local unsigned_char = ffi.typeof'unsigned char'
local uint8_t = ffi.typeof'uint8_t'
local short = ffi.typeof'short'
local signed_short = ffi.typeof'signed short'
local unsigned_short = ffi.typeof'unsigned short'
local int16_t = ffi.typeof'int16_t'
local uint16_t = ffi.typeof'uint16_t'
local int = ffi.typeof'int'
local signed_int = ffi.typeof'signed int'
local unsigned_int = ffi.typeof'unsigned int'
local int32_t = ffi.typeof'int32_t'
local uint32_t = ffi.typeof'uint32_t'

local uint8_t_p = ffi.typeof'uint8_t*'

local double = ffi.typeof'double'


local Image = class()

Image.loaders = {
	bmp = 'image.luajit.bmp',
	fits = 'image.luajit.fits',
	jpg = 'image.luajit.jpeg',
	jpeg = 'image.luajit.jpeg',
	png = 'image.luajit.png',
	tif = 'image.luajit.tiff',
	tiff = 'image.luajit.tiff',
	gif = 'image.luajit.gif',
}

local function getLoaderForFilename(filename)
	local ext = select(2, path(filename):getext())
	if ext then ext = ext:lower() end
	assert(ext, "failed to get extension for filename "..tostring(filename))
	local loaderRequire = assert(Image.loaders[ext], "failed to find loader class for extension "..ext.." for filename "..filename)
	local loaderClass = require(loaderRequire)
	local loader = loaderClass()
	return loader
end

local function packptr(n, ptr, value, ...)
	if n <= 0 then return end
	ptr[0] = value or 0
	return packptr(n-1, ptr+1, ...)
end

-- TODO .format -> .type or .ctype?
function Image:init(width,height,channels,format,generator)
	channels = channels or 4
	format = ffi.typeof(format or double)
	if type(width) == 'string' then
		local filename = width
		local loader = getLoaderForFilename(filename)
		local result = loader:load(filename)
		for k,v in pairs(result) do
			self[k] = v
		end
	else
		local format_arr = ffi.typeof('$[?]', format)
		self.buffer = format_arr(width * height * channels)
		self.width = width
		self.height = height
		self.channels = channels
		self.format = format
		if type(generator) == 'function' then
			for y=0,self.height-1 do
				for x=0,self.width-1 do
					-- 'unpackptr' is found in /gl/get.lua, maybe I should put them both somewhere else ...
					packptr(
						self.channels,
						self.buffer + self.channels * (x + self.width * y),
						generator(x,y)
					)
				end
			end
		elseif type(generator) == 'table' then
			for i=0,self.width*self.height*self.channels-1 do
				self.buffer[i] = generator[i+1]
			end
		end
	end
end

function Image:getBufferSize()
	return self.width * self.height * self.channels * ffi.sizeof(self.format)
end

-- in-place operation
function Image:clear()
	ffi.fill(self.buffer, self:getBufferSize(), 0)
	return self
end

local formatInfos = {
	-- will these always equate, or does that depend on where luajit was compiled?
	-- to handle that I would like to key them all as ffi.typeof(typename)
	-- but while ffi.typeof'char'==ffi.typeof'int8_t' is true ...
	-- ... rawequal(ffi.typeof'char', ffi.typeof'int8_t') is false ...
	-- therefore I can't use them for keys in tables ...
	-- so maybe later I'll rewrite all searches to be linear, and still use ffi.typeof() here to ensure type equivalence even if they typename differs
	[tostring(char)] = {bias=128, scale=255},
	[tostring(int8_t)] = {bias=128, scale=255},
	[tostring(signed_char)] = {bias=128, scale=255},
	[tostring(unsigned_char)] = {scale=255},
	[tostring(uint8_t)] = {scale=255},
	[tostring(short)] = {bias=32768, scale=65535},
	[tostring(signed_short)] = {bias=32768, scale=65535},
	[tostring(unsigned_short)] = {scale=65535},
	[tostring(int16_t)] = {bias=32768, scale=65535},
	[tostring(uint16_t)] = {scale=65535},
	[tostring(int)] = {bias=2^31, scale=2^32-1},
	[tostring(signed_int)] = {bias=2^31, scale=2^32-1},
	[tostring(unsigned_int)] = {scale=2^32-1},
	[tostring(int32_t)] = {bias=2^31, scale=2^32-1},
	[tostring(uint32_t)] = {scale=2^32-1},
}

function Image:setChannels(newChannels)
	local dst = Image(self.width, self.height, newChannels, self.format)
	local minCh = math.min(self.channels, newChannels)
	local formatInfo = formatInfos[tostring(self.format)]
	local fillvalue = formatInfo and (formatInfo.scale - (formatInfo.bias or 0)) or 1
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			local index = i + self.width * j
			for ch=0,minCh-1 do
				dst.buffer[ch + newChannels * index] = self.buffer[ch + self.channels * index]
			end
			for ch=minCh,newChannels-1 do
				dst.buffer[ch + newChannels * index] = fillvalue
			end
		end
	end
	return dst
end

function Image:setFormat(newFormat)
	newFormat = ffi.typeof(newFormat)
	assert.eq(newFormat, ffi.typeof(newFormat), 'format must be a ctype')
	local dst = Image(self.width, self.height, self.channels, newFormat)
	local fromFormatInfo = formatInfos[tostring(self.format)]
	local toFormatInfo = formatInfos[tostring(newFormat)]
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

function Image:rgb(useAlpha)	-- me merging rgb() and rgba()
	local dstch = useAlpha and 4 or 3
	local dst = Image(self.width, self.height, dstch, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			local dstOffset = dstch * (i + dst.width * j)
			if self.channels == 1 then
				if self.palette then
					local index = self.buffer[i + self.width * j]
					local palEntry = self.palette[index+1]
					dst.buffer[0 + dstOffset] = palEntry[1]
					dst.buffer[1 + dstOffset] = palEntry[2]
					dst.buffer[2 + dstOffset] = palEntry[3]
					if useAlpha then
						dst.buffer[3 + dstOffset] = palEntry[4] or 255
					end
				else
					-- luminance
					local grey = self.buffer[i + self.width * j]
					dst.buffer[0 + dstOffset] = grey
					dst.buffer[1 + dstOffset] = grey
					dst.buffer[2 + dstOffset] = grey
					if useAlpha then
						dst.buffer[3  + dstOffset] = 255
					end
				end
			elseif self.channels == 2 and useAlpha then
				-- luminance-alpha but only when alpha is being requested ...
				-- should channels == 2 be treated as RedGreen or LumAlpha?
				-- or should I convert channels==2 LumAlpha into RGBA in the loader?
				-- FIXME because otherwise, when converting to RGB, we are throwing away an entire channel ...
				-- seems at this point I need to introduce some extra information to describe what each channel means (red, green, blue, lum, alpha, etc) and what its format is...
				local grey = self.buffer[0 + 2 * (i + self.width * j)]
				local alpha = self.buffer[1 + 2 * (i + self.width * j)]
				dst.buffer[0 + dstOffset] = grey
				dst.buffer[1 + dstOffset] = grey
				dst.buffer[2 + dstOffset] = grey
				if useAlpha then
					dst.buffer[3  + dstOffset] = alpha
				end
			else
				local srcOffset = self.channels * (i + self.width * j)
				dst.buffer[0 + dstOffset] = self.channels < 1 and 0 or self.buffer[0 + srcOffset]
				dst.buffer[1 + dstOffset] = self.channels < 2 and 0 or self.buffer[1 + srcOffset]
				dst.buffer[2 + dstOffset] = self.channels < 3 and 0 or self.buffer[2 + srcOffset]
				if useAlpha then
					dst.buffer[3 + dstOffset] = self.channels < 4 and 255 or self.buffer[3 + srcOffset]
				end
			end
		end
	end
	return dst
end

function Image:rgba()
	return self:rgb(true)
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

	loader:save(table(converted, {
		filename = filename,
	}))

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
	local info = formatInfos[tostring(self.format)]
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
	return table.unpack(oldPixel)
end

function Image:data()
	return self.buffer
end
-- end common API

function Image:clone()
	local result = Image(self.width, self.height, self.channels, self.format)
	ffi.copy(result.buffer, self.buffer, self:getBufferSize())
	return result
end

local op = require 'ext.op'
for _,info in ipairs{
	{op='__add', func=op.add},
	{op='__sub', func=op.sub},
	{op='__mul', func=op.mul},
	{op='__div', func=op.div},
	{op='__pow', func=op.pow},
	{op='__mod', func=op.mod},
} do
	Image[info.op] = function(a,b)
		local aIsImage = Image:isa(a)
		local bIsImage = Image:isa(b)
		if aIsImage and bIsImage then
			assert.eq(a.width, b.width)
			assert.eq(a.height, b.height)
			assert.eq(a.channels, b.channels)
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
	return table.unpack(dsts)
end

-- merges all image channels together
-- assumes sizes all match
-- uses the first image's format
function Image.combine(...)
	local srcs = {...}
	assert.gt(#srcs, 0)
	local width = srcs[1].width
	local height = srcs[1].height
	local channels = srcs[1].channels
	local format = srcs[1].format
	for i=2,#srcs do
		assert.eq(width, srcs[i].width)
		assert.eq(height, srcs[i].height)
		if srcs[i].format ~= format then
			srcs[i] = srcs[i]:setFormat(format)
		end
		channels = channels + srcs[i].channels
	end
	assert.gt(channels, 0)
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
			assert.eq(dstch, channels)
		end
	end
	return result
end

function Image:greyscale()
	assert.ge(self.channels, 3)
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

function Image:l2norm()
	local dst = Image(self.width, self.height, 1, self.format)
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			local index = self.channels * (i + self.width * j)
			local sum = 0
			for ch=0,self.channels-1 do
				local v = self.buffer[ch + index]
				sum = sum + v * v
			end
			dst.buffer[i + self.width * j] = math.sqrt(sum)
		end
	end
	return dst
end

-- args: x, y, width, height
-- Maybe rename to 'clip' or 'crop', or is copy good?
function Image:copy(args)
	local argsx = math.floor(assert.index(args, 'x'))
	local argsy = math.floor(assert.index(args, 'y'))
	local argsw = math.floor(assert.index(args, 'width'))
	local argsh = math.floor(assert.index(args, 'height'))
	local result = Image(argsw, argsh, self.channels, self.format)
	for y=0,result.height-1 do
		for x=0,result.width-1 do
			for ch=0,result.channels-1 do
				local sx = x + argsx
				local sy = y + argsy
				if sx >= 0 and sy >= 0 and sx < self.width and sy < self.height then
					result.buffer[ch+result.channels*(x+result.width*y)] = self.buffer[ch+self.channels*(sx+self.width*sy)]
				else
					result.buffer[ch+result.channels*(x+result.width*y)] = 0
				end
			end
		end
	end
	result.palette = self.palette	-- preserve palette if present
	return result
end

-- args: image, x, y
-- paste in-place, so don't make a new copy of the image
function Image:pasteInto(args)
	local pasted = assert.index(args, 'image')
	assert.eq(pasted.channels, self.channels, "channels don't match")	-- for now ...
	for y=0,pasted.height-1 do
		for x=0,pasted.width-1 do
			local destx = x + args.x
			local desty = y + args.y
			if destx >= 0 and destx < self.width
			and desty >= 0 and desty < self.height
			then
				for ch=0,pasted.channels-1 do
					self.buffer[ch+self.channels*(destx+self.width*desty)] = pasted.buffer[ch+pasted.channels*(x+pasted.width*y)]
				end
			end
		end
	end
	return self
end

-- args: image, x, y
-- return a new copy of the image with pasted modification
function Image:paste(args)
	return self:clone():pasteInto(args)
end

--[[
tile an image
	w = new width
	h = new height
	x = offset x to start tiling the upper-left corner.  default = 0
	y = offset y to start tiling.  default = 0
--]]
function Image:tile(w, h, x, y)
	x = x or 0
	y = y or 0
	local result = Image(w, h, self.channels, self.format)
	for dsty=0,h-1 do
		local srcy = (dsty - y) % self.height
		for dstx=0,w-1 do
			local srcx = (dstx - x) % self.width
			for ch=0,self.channels-1 do
				result.buffer[ch+self.channels*(dstx+result.width*dsty)]
					= self.buffer[ch+self.channels*(srcx+self.width*srcy)]
			end
		end
	end
	return result
end

Image.gradientKernels = {
	simple = Image(2,1,1,double,{-1,1}),
	Sobel = Image(3,3,1,double,{-1,0,1,-2,0,2,-1,0,1})/4,
	Scharr = Image(3,3,1,double,{-3,0,3,-10,0,10,-3,0,3})/16,
	-- TODO Gaussian gradient
	-- TODO make boundary modulo optional
}
function Image:gradient(kernelName, offsetX, offsetY)
	if not kernelName then kernelName = 'Sobel' end
	local kernel = assert.index(self.gradientKernels, kernelName, "could not find gradient")
	-- TODO cache transposed kernels?
	offsetX = (offsetX or 0) - math.floor(kernel.width/2)
	offsetY = (offsetY or 0) - math.floor(kernel.height/2)
	return
		self:kernel(kernel, false, offsetX, offsetY),
		self:kernel(kernel:transpose(), false, offsetY, offsetX)
end

-- https://en.wikipedia.org//wiki/Curvature
function Image:curvature()
	assert.eq(self.channels, 1)
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
	assert.eq(self.channels, 2)
	local imgX, imgY = self:split()
	local _, dy_dx = imgX:gradient()
	local dx_dy = imgY:gradient()
	return dy_dx - dx_dy
end

--[[
should this return ...
... a single value of all channel bounds?
... two tables, one of mins and one of maxs?
... interleaved per-channel, so that 1-channel images can just say "min, max = img:getBounds()"
--]]
function Image:getRange()
	local mins = {}
	local maxs = {}
	local p = self.buffer
	for ch=1,self.channels do
		mins[ch] = p[0]
		maxs[ch] = p[0]
		p = p + 1
	end
	for index=1,self.width*self.height-1 do
		for ch=1,self.channels do
			local v = p[0]
			mins[ch] = math.min(mins[ch], v)
			maxs[ch] = math.max(maxs[ch], v)
			p = p + 1
		end
	end
	return mins, maxs
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
	return dst, mins, maxs
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
	assert.eq(kernel.channels, 1)
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
	return Image(width, height, 1, double, function(x,y)
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
	assert.eq(a.width, b.width)
	assert.eq(a.height, b.height)
	assert.eq(a.channels, b.channels)
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

Image.simpleBlurKernel = Image(3,3,1,double,{0,1,0, 1,4,1, 0,1,0})/8
function Image:simpleBlur()
	return self:kernel(self.simpleBlurKernel, false, -1, -1)
end

-- TODO offer multiple options
Image.divergenceKernel = Image(3,3,1,double,{0,1,0,1,-4,1,0,1,0})
function Image:divergence()
	return self:kernel(self.divergenceKernel, false, -1, -1)
end

-- should this invert all channels, or just up to the first three?
-- first three ...
function Image:invert()
	local info = formatInfos[tostring(self.format)]
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
		return table.unpack(pixel)
	end)
end

--[[
resize options:
nearest
linear
TODO magnification and minification filter options.
--]]
function Image:resize(newx, newy, method)
	newx = math.floor(newx)
	newy = math.floor(newy)
	method = method or 'nearest'	-- TODO use this
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
					pixel[ch+1] = tonumber(self.buffer[ch+self.channels*(sx+self.width*sy)]) + pixel[ch+1]
					total = total + 1
				end
			end
			if total>0 then
				pixel[ch+1] = math.floor(pixel[ch+1] / total)
			end
		end
		return table.unpack(pixel)
	end)
end


function Image:getHistogram()
	local hist = {}
	local p = uint8_t_p(self.buffer)
	local pixlen = self.channels * ffi.sizeof(self.format)
	for i=0,self.height*self.width-1 do
		local key = ffi.string(p, pixlen)
		hist[key] = (hist[key] or 0) + 1
		p = p + pixlen
	end
	return hist
end

function Image:flip(dest)
	local w, h, ch, fmt = self.width, self.height, self.channels, self.format
	if not dest then
		dest = Image(w, h, ch, fmt)
	end
	local sf = ffi.sizeof(fmt)
	local rowsize = w * ch * sf
	for y=0,h-1 do
		ffi.copy(dest.buffer + (h-y-1) * rowsize, self.buffer + y * rowsize, rowsize)
	end
	return dest
end

function Image:mirror(dest)
	local w, h, ch, fmt = self.width, self.height, self.channels, self.format
	if not dest then
		dest = Image(w, h, ch, fmt)
	end
	local sf = ffi.sizeof(fmt)
	local rowsize = w * ch * sf
	for y=0,h-1 do
		for x=0,w-1 do
			local i1 = ch * (x + w * y)
			local i2 = ch * (w-1-x + w * y)
			for c=0,ch-1 do
				dest.buffer[c + i1] = self.buffer[c + i2]
			end
		end
	end
	return dest
end

function Image:getZealousCropRect()
	assert.eq(self.channels, 4, "zealous crop only works with alpha channels")

	-- find the first and last cols and rows with content
	local results = {}
	for _,info in ipairs{
		{0,self.width-1,1, 'xmin'},
		{self.width-1,0,-1, 'xmax'},
	} do
		local istart, iend, istep, ifield = table.unpack(info)
		for i=istart,iend,istep do
			local found
			for j=0,self.height-1 do
				if self.buffer[3 + 4 * (i + self.width * j)] ~= 0 then
					found = true
					break
				end
			end
			if found then
				results[ifield] = i
				break
			end
		end
	end

	-- same thing with rows to determine max row
	for _,info in ipairs{
		{0,self.height-1,1, 'ymin'},
		{self.height-1,0,-1, 'ymax'},
	} do
		local jstart, jend, jstep, jfield = table.unpack(info)
		for j=jstart,jend,jstep do
			local found
			for i=0,self.width-1 do
				if self.buffer[3 + 4 * (i + self.width * j)] ~= 0 then
					found = true
					break
				end
			end
			if found then
				results[jfield] = j
				break
			end
		end
	end

	return results
end

function Image:zealousCrop()
	local results = self:getZealousCropRect()
	if results.xmin and results.xmax and results.ymin and results.ymax then
		return self:copy{
			x = results.xmin,
			y = results.ymin,
			width = results.xmax - results.xmin + 1,
			height = results.ymax - results.ymin + 1,
		}
	else
		return self:clone():clear()
	end
end



---------------- regions and blobs ----------------
-- maybe this should be its own file? maybe its own library?


-- holds each blob in integer indexes
local Regions = class()
Regions.init = table.init
Regions.insert = table.insert
Regions.removeObject = table.removeObject


local Rectangle = class()

function Rectangle:drawToImage(image, color)
	assert.ge(image.channels, 3)
	if self.y1 < image.height and self.y2 >= 0 then
		for y=math.max(0, self.y1),math.min(self.y2, image.height-1) do
			if self.x1 < image.width and self.x1 >= 0 then
				for x=math.max(0, self.x1),math.min(self.x2, image.width-1) do
					local index = x + image.width * y
					image.buffer[0 + image.channels * index] = color.x
					image.buffer[1 + image.channels * index] = color.y
					image.buffer[2 + image.channels * index] = color.z
					if image.channels >= 4 then
						image.buffer[3 + image.channels * index] = 255
					end
				end
			end
		end
	end
end


local Blobs = class(Regions)

function Blobs:toRects()
	local rects = table()
	for _,blob in pairs(self) do
		local rect = Rectangle()
		do
			local int = blob[1]
			rect.x1 = int.x1
			rect.x2 = int.x2
			rect.y1 = int.y
			rect.y2 = int.y
		end
		for j=2,#blob do
			local int = blob[j]
			rect.x1 = math.min(rect.x1, int.x1)
			rect.x2 = math.max(rect.x2, int.x2)
			rect.y1 = math.min(rect.y1, int.y)
			rect.y2 = math.max(rect.y2, int.y)
		end
		rects:insert(rect)
	end
	return rects
end

local Blob = class()
Blob.init = table.init
Blob.insert = table.insert
Blob.append = table.append

function Blob:drawMaskToImage(image, color)
	assert.ge(image.channels, 3)
	for _,row in ipairs(self) do
		local y = row.y
		if y >= 0 and y < image.height then
			if row.x1 < image.width and row.x2 >= 0 then
				for x=math.max(0, row.x1), math.min(row.x2, image.width-1) do
					local index = x + image.width * y
					image.buffer[0 + image.channels * index] = color.x
					image.buffer[1 + image.channels * index] = color.y
					image.buffer[2 + image.channels * index] = color.z
					if image.channels >= 4 then
						image.buffer[3 + image.channels * index] = 255
					end
				end
			end
		end
	end
end

function Blob:copyToImage(dstimg, srcimg)
	assert.ge(dstimg.channels, 3)
	assert.eq(srcimg.width, dstimg.width)
	assert.eq(srcimg.height, dstimg.height)
	for _,row in ipairs(self) do
		local y = row.y
		if y >= 0 and y < dstimg.height then
			if row.x1 < dstimg.width and row.x2 >= 0 then
				for x=math.max(0, row.x1), math.min(row.x2, dstimg.width-1) do
					local index = x + dstimg.width * y
					for ch=0,dstimg.channels-1 do
						dstimg.buffer[ch + dstimg.channels * index] = srcimg.buffer[ch + srcimg.channels * index]
					end
				end
			end
		end
	end
end


function Blob:calcArea()
	local area = 0
	for _,row in ipairs(self) do
		area = area + (row.x2 - row.x1 + 1)
	end
	return area
end

-- TODO anon type?
ffi.cdef[[
typedef struct {
	int x1;
	int x2;
	int y;
	int cl;		//classification
	int blob;	//blob index
} ImageBlobRowInterval_t;
]]
local ImageBlobRowInterval_t = ffi.typeof'ImageBlobRowInterval_t'

-- TODO put this in its own file?
local vector = require 'stl.vector-lua'

function Image:getBlobs(ctx)
	local classify = assert(ctx.classify)

	local rowregions = ctx.rowregions
	if not rowregions then
		rowregions = {}
		ctx.rowregions = rowregions
	end
	for j=1,self.height do
		local row = rowregions[j]
		if not row then
			row = vector(ImageBlobRowInterval_t)
			rowregions[j] = row
		else
			row:clear()
		end
	end
	for j=self.height+1,#rowregions do
		rowregions[j] = nil
	end

	local blobs = ctx.blobs
	if not blobs then
		blobs = Blobs()
		ctx.blobs = blobs
	else
		for k in pairs(blobs) do blobs[k] = nil end
	end
	local nextblobindex = 1

	-- first find intervals in rows
	local p = self.buffer
	for y=0,self.height-1 do
		local row = rowregions[y+1]
		local x = 0
		local cl = classify(p, self.channels)
		repeat
			local cl2
			local xstart = x
			repeat
				x = x + 1
				p = p + self.channels
				if x == self.width then break end
				cl2 = classify(p, self.channels)
			until cl ~= cl2
			local r = row:emplace_back()
			-- [x1, x2) = [incl, excl) = row of pixels inside the classifier
			r.x1 = xstart
			r.x2 = x - 1
			r.y = y
			r.cl = cl
			r.blob = -1
			-- prepare for next col
			cl = cl2
		until x == self.width
	end

	-- next combine touching intervals in neighboring rows
	local lastrow
	for y=0,self.height-1 do
		local row = rowregions[y+1]
		-- if the previous row is empty then the next row will be filled with all new blobs
		if not lastrow or lastrow.size == 0 then
			if row.size > 0 then
				for i=0,row.size-1 do
					local int = row.v[i]
					local blob = Blob()	-- blob will be a table of intervals, of {x1, x2, y, blob}
					blobs[nextblobindex] = blob
					int.blob = nextblobindex
					nextblobindex = nextblobindex + 1
					blob:insert(int)
					blob.cl = int.cl
				end
			end
		-- last row exists, so merge previous row's blobs with this row's intervals
		else
			if row.size > 0 then
				for i=0,row.size-1 do
					local int = row.v[i]
					for j=0,lastrow.size-1 do
						local lint = lastrow.v[j]
						if lint.blob <= -1 then
							print("row["..y.."] previous-row interval had no blob "..lint.blob)
							error'here'
						end

						if lint.x1 <= int.x2
						and lint.x2 >= int.x1
						then
							-- touching - make sure they are in the same blob
							if int.blob ~= lint.blob
							and int.cl == lint.cl
							then
								local oldblobindex = int.blob
								if oldblobindex > -1 then
									local oldblob = blobs[oldblobindex]
									-- remove the old blob
									blobs[oldblobindex] = nil

									for _,oint in ipairs(oldblob) do
										oint.blob = lint.blob
									end
									blobs[lint.blob]:append(oldblob)
								else
									int.blob = lint.blob
									blobs[lint.blob]:insert(int)
								end
							end
						end
					end
					if int.blob == -1 then
						local blob = Blob()
						blobs[nextblobindex] = blob
						int.blob = nextblobindex
						nextblobindex = nextblobindex + 1
						blob:insert(int)
						blob.cl = int.cl
					end
				end
			end
		end
		for i=0,row.size-1 do
			if row.v[i].blob <= -1 then
				print("on row "..y.." failed to assign all intervals to blobs")
			end
		end
		lastrow = row
	end

	return blobs
end


local vec3d = require 'vec-ffi.vec3d'
function Image:drawRegions(regions)
	self:clear()
	if self.channels > 3 then
		for i=0,self.width*self.height-1 do
			self.buffer[3 + self.channels * i] = 255
		end
	end
	for _,region in pairs(regions) do
		local color = (vec3d(math.random(), math.random(), math.random()):normalize() * 255):map(math.floor)
		region:drawMaskToImage(self, color)
	end
	return self
end

-- I convert to palette often enough
--[[
args:
	size = max size of palette
returns a new 1bpp indexed image with .palette assigned
--]]
function Image:toIndexed(args)
	args = args or {}
	local targetSize = args.targetSize or 256

	-- TODO this in the image/tests/quantize tool
	-- and then use it in numo9/edit/sheet.lua
	local Quantize = require 'image.quantize_mediancut'
	local image, hist = Quantize.reduceColorsMedianCut{
		image = self,
		targetSize = targetSize,
	}
	local colors = table.keys(hist):sort()
	local indexForColor = colors:mapi(function(color,i)	-- 0-based index
		return i-1, color
	end)
	local image1ch = Image(image.width, image.height, 1, uint8_t)
	local srcp = image.buffer
	local dstp = image1ch.buffer
	local chsize = ffi.sizeof(image.format) * image.channels
	for i=0,image.width*image.height-1 do
		local key = ffi.string(srcp, chsize)
		local dstIndex = indexForColor[key]
		if not dstIndex then
print("no index for color "..string.hex(key))
print('possible colors: '..require 'ext.tolua'(colors))
			error'here'
		end
		dstp[0] = dstIndex
		dstp = dstp + 1
		srcp = srcp + chsize
	end
	image1ch.palette = colors:mapi(function(color)
		return string.bytes(color)
	end)
	return image1ch
end

return Image
