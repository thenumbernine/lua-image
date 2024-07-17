[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

### LuaJIT Image Library

edit image.lua to choose what backend

Options are `sdl_image`, `luaimg` (my image library), and `luajit` (pure LuaJIT).  Pure LuaJIT is enabled by default.

### Dependencies:

- LuaJIT 
- https://github.com/thenumbernine/lua-ext
- https://github.com/thenumbernine/lua-ffi-bindings
- https://github.com/thenumbernine/solver-lua (optional)
- https://github.com/malkia/ufo and/or https://github.com/thenumbernine/lua-ffi-bindings for the PNG, JPEG, and TIFF headers ported to LuaJIT 
- https://github.com/thenumbernine/Image if you are going to use the 'luaimg' option.
