--[[
  efxr.lua

  based on the original efxr by Tomas Pettersson, ported to Lua by nucular,
  refactored/rewritten/extended by muragami

MIT LICENSE
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]]--

_APP = {
  NAME = 'EFXR Audio Generator',
  VERSION = '0.1',
  AUTHOR = 'muragami',
  WEBSITE = 'https://muragami.wishray.com'
}

-- just a placeholder to make something invalid or empty
_INVALID = {}

-- some RNG!
Rng = love.math.newRandomGenerator()

-- I like the cut of your gib!
Gib = 'X24680BD@#&*[]{}'

Screen = {}

function Screen:clear()
  -- determine the amount of text lines we will show
  self.height = love.graphics.getHeight()
  self.width = love.graphics.getWidth()
  self.lines = math.floor(love.graphics.getHeight() / (self.font_size + self.font_padding)) - 1
  self.pos = 0
  self.line = {}
  self.fade = {}
  for i=0,self.lines,1 do self.line[i] = _INVALID self.fade[i] = 0 end
  print("Screen:clear() wiped " .. self.lines .. " lines")
end

function Screen:draw()
  local line_height = (self.font_size + self.font_padding)
  love.graphics.setFont(self.font)
  for i=0,self.lines,1 do
    local dy = i * line_height
    local ln = self.line[i]
    if ln == _INVALID then
      -- draw faint gibberish
      local off = Rng:random(1,128)
      love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
      love.graphics.print(self.gibberish:sub(off,off+128),0.5,dy+0.5)
      love.graphics.setColor(0.15, 0.24, 0.15, 1.0)
      love.graphics.print(self.gibberish:sub(off,off+128),0,dy)
    else
      -- draw the line!
      if type(ln) == 'string' then
        love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
        love.graphics.print(ln,0.5,dy+0.5)
        love.graphics.setColor(0.9, 1.0, 0.9, 1.0)
        love.graphics.print(ln,0,dy)
      else
        ln:draw(self,i,0,dy)
      end
    end
  end
end

function Screen:update(dt)
  if not self.gibberish then
    -- create a long garbage string
    self.gibberish = ''
    self.gibberish_offset = 0
    for i=1,256,1 do
      local spot = Rng:random(1,#Gib)
      self.gibberish = self.gibberish .. Gib:sub(spot,spot+1)
    end
  end
  self.gibberish_offset = self.gibberish_offset + dt
end

function Screen:setFont(f,px)
  Screen.font = love.graphics.newFont(f, px)
  Screen.font_size = px
  Screen.font_padding = 2
  print("Screen:setFont() now '" .. f .. "' lines at " .. px .. ' pixels')
end

function Screen:print(txt)
  self.line[self.pos] = txt
  self.pos = self.pos + 1
  if self.pos > self.lines then error("Screen:print() can't add more lines than we can show!") end
end

-- Load some default values for our rectangle.
function love.load()
  -- make the font
  Screen:setFont('res/Flexi_IBM_VGA_True_437.ttf', 16)
  -- a fresh clean screen
  Screen:clear()
  -- add title
  Screen:print("EFXR 0.1 by Muragami")
end

-- Increase the size of the rectangle every frame.
function love.update(dt)
  Screen:update(dt)
end

-- Draw a coloured rectangle.
function love.draw()
  Screen:draw()
end
