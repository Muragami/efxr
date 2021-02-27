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

-- some RNG!
local Rng = love.math.newRandomGenerator()

-- I like the cut of your gib!
local Gib = 'X24680()[]\\/[]{}'

Screen = {}

function Screen:clear()
  -- determine the amount of text lines we will show
  self.height = love.graphics.getHeight()
  self.width = love.graphics.getWidth()
  self.lines = math.floor(love.graphics.getHeight() / (self.font_size + self.font_padding)) - 1
  self.pos = 0
  self.posChar = '>'
  self.posCharW = self.font:getWidth(self.posChar)
  self.sel = -1
  self.line = {}
  self.fade = {}
  self.buffer = {}
  self.rate = 1.0
  self.next = 0.0
  self.scroll = 0
  self.page = 0
  for i=0,self.lines,1 do self.line[i] = _INVALID self.fade[i] = 0 end
  print("Screen:clear() wiped " .. self.lines .. " lines")
end

function Screen:draw()
  local line_height = (self.font_size + self.font_padding)
  local dx = self.posCharW + 2
  love.graphics.setFont(self.font)
  local sel = self.sel
  if sel == -1 then sel = self.pos-1 end
  for i=self.scroll,self.lines+self.scroll,1 do
    local dy = (i - self.scroll) * line_height
    local ln = self.line[i]
    local fade = self.fade[i]
    if i == sel then
      love.graphics.setColor(0.22, 0.22, 0.0, 1.0)
      love.graphics.rectangle('fill', dx, dy, self.width, line_height)
      love.graphics.setColor(0.3, 0.3, 0.1, 1.0)
      love.graphics.rectangle('line', dx, dy, self.width, line_height)
      love.graphics.setColor(0.8, 0.8, 0.4, 1.0)
      love.graphics.print(self.posChar,0,dy)
    end
    if ln == _INVALID then
      -- draw faint gibberish
      local off = Rng:random(1,128)
      love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
      love.graphics.print(self.gibberish:sub(off,off+128),dx+0.8,dy+0.8)
      love.graphics.setColor(0.15, 0.24, 0.15, 1.0)
      love.graphics.print(self.gibberish:sub(off,off+128),dx,dy)
    else
      -- draw the line!
      local off = Rng:random(1,128)
      love.graphics.setColor(0.1, 0.1, 0.2, 1.0)
      love.graphics.print(self.gibberish:sub(off,off+128),dx+0.8,dy+0.8)
      if type(ln) == 'string' then
        if fade < 0 then
          local falpha = (1.0 - (0 - fade)) * 0.8 + 0.2
          love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
          love.graphics.print(ln,dx+0.8,dy+0.8+fade * line_height)
          love.graphics.setColor(0.9, 1.0, 0.9, falpha)
          love.graphics.print(ln,dx,dy+fade * line_height)
        else
          love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
          love.graphics.print(ln,dx+0.8,dy+0.8)
          love.graphics.setColor(0.9, 1.0, 0.9, 1.0)
          love.graphics.print(ln,dx,dy)
        end
      else
        ln:draw(self,i,scroll,0,dy,fade)
      end
    end
  end
end

function Screen:update(dt)
  -- make sure we have gibberish
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
  -- our clock
  self.next = self.next + dt
  -- do we need to add anything?
  if #self.buffer > 0 then
    -- is it time?
    if self.next > (1.0 / self.rate) then
      self:add(self.buffer[1])
      table.remove(self.buffer,1)
      self.next = 0
    end
  else
    -- since we aren't adding we are done, so reset add rate
    self.rate = 1.0
  end
  -- update fades
  for i=0,self.lines+(self.page*self.lines)-1,1 do
    if self.fade[i] < 0 then
      self.fade[i] = self.fade[i] + dt
      if self.fade[i] > 0 then self.fade[i] = 0 end
    end
  end
end

function Screen:setFont(f,px)
  Screen.font = love.graphics.newFont(f, px)
  Screen.font_size = px
  Screen.font_padding = 2
  print("Screen:setFont() now '" .. f .. "' lines at " .. px .. ' pixels')
end

function Screen:add(txt)
  self.line[self.pos] = txt
  self.fade[self.pos] = -1
  self.pos = self.pos + 1
  if self.pos >= self.lines then
    local onpage = math.floor(self.pos / self.lines)
    while self.page < onpage do
      -- add more _INVALID to our new page(s)
      self.page = self.page + 1
      for i=self.page*self.lines,self.page*self.lines+self.lines,1 do
        self.line[i] = _INVALID
        self.fade[i] = 0
      end
    end
    self.scroll = self.pos - self.lines
  end
end

function Screen:print(txt,other)
  if type(txt) == 'table' then
    -- add ipairs from this table
    for _,v in ipairs(txt) do
      table.insert(self.buffer,txt)
      self.rate = self.rate + 0.5   -- the more we add, accelerate our additions!
    end
  elseif type(txt) == 'function' then
    -- txt better be an iterator!
    for ln in txt do
      table.insert(self.buffer,ln)
      self.rate = self.rate + 0.5   -- the more we add, accelerate our additions!
    end
  else
    table.insert(self.buffer,txt)
    self.rate = self.rate + 0.5   -- the more we add, accelerate our additions!
  end
end

function Screen:onKey(key,isrepeat)
  if key == 'pageup' then
    self.scroll = self.scroll - self.lines
    if self.scroll < 0 then self.scroll = 0 end
  elseif key == 'pagedown' then
    self.scroll = self.scroll + self.lines
    if self.scroll > (self.page * self.lines) then
      self.scroll = (self.page * self.lines)
    end
  elseif key == 'up' then
    -- move selection up
    if self.sel == -1 then self.sel = self.pos - 1 end
    self.sel = self.sel - 1
    if self.sel < 0 then self.sel = self.pos - 1 end
    if self.sel < self.scroll then
      self.scroll = self.sel
    elseif self.sel > self.scroll + self.lines then
      self.scroll = self.scroll + (self.sel - (self.scroll + self.lines))
    end
  elseif key == 'down' then
    -- move selection down
    if self.sel == -1 then self.sel = self.pos - 1 end
    self.sel = self.sel + 1
    if self.sel > self.pos - 1 then self.sel = 0 end
    if self.sel < self.scroll then
      self.scroll = self.sel
    elseif self.sel > self.scroll + self.lines then
      self.scroll = self.scroll + (self.sel - (self.scroll + self.lines))
    end
  elseif key == 'left' then
  elseif key == 'right' then
  end
end
