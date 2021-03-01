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
local utf8 = require 'utf8'

-- utility
local function split(inp)
  local t = {}
  for str in string.gmatch(inp, "([^%s]+)") do table.insert(t, str) end
  return t
end

local function toUtf8Array(s)
  local t = {}
  for p, c in utf8.codes(s) do table.insert(t,c) end
  return t
end

local function fromUtf8Array(ua)
  local r = {}
  for i,v in ipairs(ua) do r[i] = utf8.char(v) end
  return table.concat(r)
end

-- I like the cut of your gib!
local Gib = 'X24680()[]\\/[]{}'

Screen = {}

function Screen:clear()
  -- determine the amount of text lines we will show
  -- put us in a state without functions
  self.height = love.graphics.getHeight()
  self.width = love.graphics.getWidth()
  self.lines = math.floor(love.graphics.getHeight() / (self.font_size + self.font_padding)) - 1
  self.pos = 0
  self.posChar = '>'
  self.posCharW = self.font:getWidth(self.posChar)
  self.sel = -1
  self.laction = -1
  self.inedit = false
  self.line = {}
  self.fade = {}
  self.buffer = {}
  self.action = {}
  self.data = {}
  self.drate = 3
  self.rate = self.drate
  self.next = 0.0
  self.scroll = 0
  self.page = 0
  self.blink = false
  self.brate = 0.66
  self.bclk = self.brate
  for i=0,self.lines,1 do self.line[i] = _INVALID self.fade[i] = 0 end
  if not self.name then self.name = "Screen" end
end

function Screen:register(name,tab)
  self.data[name] = tab
end

function Screen:draw()
  local line_height = (self.font_size + self.font_padding)
  local dx = self.posCharW + 2
  love.graphics.setFont(self.font)
  local sel = self.sel
  local g = love.graphics
  if sel == -1 then sel = self.pos-1 end
  for i=self.scroll,self.lines+self.scroll,1 do
    local dy = (i - self.scroll) * line_height
    local ln = self.line[i]
    local act = self.action[i]
    local fade = self.fade[i]
    if i == sel then
      if self.inedit then
        g.setColor(0.00, 0.33, 0.0, 1.0)
        g.rectangle('fill', dx, dy, self.width, line_height)
        g.setColor(0.0, 0.5, 0.0, 1.0)
        g.rectangle('line', dx, dy, self.width, line_height)
        g.setColor(0.0, 0.9, 0.0, 1.0)
        g.print('@',0,dy)
      else
        g.setColor(0.22, 0.22, 0.0, 1.0)
        g.rectangle('fill', dx, dy, self.width, line_height)
        g.setColor(0.3, 0.3, 0.1, 1.0)
        g.rectangle('line', dx, dy, self.width, line_height)
        g.setColor(0.8, 0.8, 0.4, 1.0)
        g.print(self.posChar,0,dy)
      end
    end
    if ln == _INVALID then
      -- draw faint gibberish
      local off = Rng:random(1,128)
      g.setColor(0.1, 0.1, 0.1, 1.0)
      g.print(self.gibberish:sub(off,off+128),dx+0.8,dy+0.8)
      g.setColor(0.15, 0.24, 0.15, 1.0)
      g.print(self.gibberish:sub(off,off+128),dx,dy)
    else
      -- draw the line!
      local off = Rng:random(1,128)
      g.setColor(0.1, 0.1, 0.2, 1.0)
      g.print(self.gibberish:sub(off,off+128),dx+0.8,dy+0.8)
      if type(ln) == 'string' then
        if fade < 0 then
          local falpha = (1.0 - (0 - fade)) * 0.8 + 0.2
          g.setColor(0.2, 0.2, 0.2, 0.8)
          g.print(ln,dx+0.8,dy+0.8-(fade * fade * line_height * 1.0))
          g.setColor(0.9, 1.0, 0.9, falpha)
          g.print(ln,dx,dy-(fade * fade * line_height * 1.0))
        else
          g.setColor(0.2, 0.2, 0.2, 1.0)
          g.print(ln,dx+0.8,dy+0.8)
          g.setColor(0.9, 1.0, 0.9, 1.0)
          g.print(ln,dx,dy)
        end
      else
        ln:draw(self,i,scroll,0,dy,fade)
      end
      if act then
        -- display data
        if act.data then
          local d = act.data
          if act.altedit and self.inedit and i == sel then d = act.altedit end
          if fade < 0 then
            local falpha = (1.0 - (0 - fade)) * 0.8 + 0.2
            g.setColor(0.2, 0.2, 0.2, 0.8)
            g.print(d,dx+0.8+act.offset,dy+0.8-(fade * fade * line_height * 1.0))
            g.setColor(0.9, 1.0, 0.9, falpha)
            g.print(d,dx+act.offset,dy-(fade * fade * line_height * 1.0))
          else
            g.setColor(0.2, 0.2, 0.2, 1.0)
            g.print(d,dx+0.8+act.offset,dy+0.8)
            g.setColor(0.9, 1.0, 0.9, 1.0)
            g.print(d,dx+act.offset,dy)
          end
        end
        if act.edit then
          if act.dtype == 'string' and act.opts then
            -- draw the options
            local cx = self.font:getWidth(act.altedit .. " ")
            for i,v in ipairs(act.opts) do

              if v == act.data then
                if i == 1 then v = ' < ' .. v end
                g.setColor(0.0, 0.0, 0.0, 1.0)
                g.print(v,dx+0.8+act.offset+cx,dy+0.8)
                g.setColor(1.0, 1.0, 1.0, 1.0)
                g.print(v,dx+act.offset+cx,dy)
              else
                if i == 1 then v = ' < ' .. v end
                g.setColor(0.0, 0.0, 0.0, 1.0)
                g.print(v,dx+1+act.offset+cx,dy+1)
                g.setColor(1.0, 1.0, 0.0, 0.6)
                g.print(v,dx+act.offset+cx,dy)
              end
              cx = cx + self.font:getWidth(v .. " ")
            end
          elseif act.dtype == 'number' then
          elseif act.dtype == 'string' then
            -- draw the cursor
            if self.blink then
              local cx = 0
              if self.cursor > 1 then cx = self.font:getWidth(act.data:sub(1,self.cursor-1)) end
              g.setColor(0.0, 0.0, 0.0, 1.0)
              g.rectangle('fill',dx+1+act.offset+cx,dy-1+self.font_size*3/4,self.font_wid,self.font_size / 4)
              g.setColor(1.0, 1.0, 0.7, 1.0)
              g.rectangle('fill',dx+act.offset+cx,dy+self.font_size*3/4,self.font_wid,self.font_size / 4)
            end
          end
        end
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
    self.rate = self.drate
  end
  -- update fades
  for i=0,self.lines+(self.page*self.lines)-1,1 do
    if self.fade[i] < 0 then
      self.fade[i] = self.fade[i] + dt
      if self.fade[i] > 0 then self.fade[i] = 0 end
    end
  end
  self.bclk = self.bclk - dt
  if self.bclk <= 0 then
    self.bclk = self.brate
    self.blink = not self.blink
  end
end

function Screen:setFont(f,px)
  self.font = love.graphics.newFont(f, px)
  self.font_size = px
  self.font_padding = 2
  self.font_wid = self.font:getWidth('_')
end

function Screen:add(txt)
  self.line[self.pos] = txt
  self.fade[self.pos] = -1
  self.sel = self.pos         -- automatically select last added line?
  local tst = txt:sub(1,3)
  if tst == '-> ' then
    -- this is an action, fire off an event when it's triggered
    self.action[self.pos] = { 'exec', txt:sub(4):match("([%w-._]+)") }
    self.laction = self.pos
  elseif tst == '|| ' then
    -- this is editable
    self.action[self.pos] =
      { 'edit', txt:sub(4):match("([%w-._]+)"), offset = self.font:getWidth(txt .. " ") }
    self.laction = self.pos

  elseif tst == '-- ' and self.laction > -1 then
    -- this is never shown, and describes a previous editable/action!
    local tok = split(txt:sub(4))
    local act = self.action[self.laction]
    if tok[1] == 'source' then
      -- record the source of this value
      act.source = tok[2]
      act.data = self.data[tok[2]][act[2]]
      act.dtype = type(act.data)
    elseif tok[1] == 'range' then
      -- we are a number value, record that
      act.dtype = 'number'
      act.min = tonumber(tok[3])
      act.max = tonumber(tok[4])
    elseif tok[1] == 'opts' then
      -- we are option selection, so record that
      act.dtype = 'string'
      act.altedit = '***'
      act.opts = {}
      local i = 2
      while tok[i] do
        act.opts[i-1] = tok[i]
        i = i + 1
      end
    end
    return
  end
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
      self.rate = self.rate + (0.5 * self.drate)   -- the more we add, accelerate our additions!
    end
  elseif type(txt) == 'function' then
    -- txt better be an iterator!
    for ln in txt do
      table.insert(self.buffer,ln)
      self.rate = self.rate + (0.5 * self.drate)   -- the more we add, accelerate our additions!
    end
  else
    table.insert(self.buffer,txt)
    self.rate = self.rate + (0.5 * self.drate)   -- the more we add, accelerate our additions!
  end
end

function Screen:read(fname)
  self:print(love.filesystem.lines(fname))
end

function Screen:onKey(key,isrepeat)
  -- if we are editing, so that instead of navigation
  if self.inedit then
    local actor = self.action[self.sel]
    if key == 'return' or key == 'kpenter' then
      -- done editing
      self.inedit = false
      actor.edit = false
      actor.ua = nil
    elseif key == 'right' then
      if actor.opts then
        actor.selpos = actor.selpos + 1
        if actor.selpos > #actor.opts then actor.selpos = 1 end
        actor.data = actor.opts[actor.selpos]
      elseif actor.dtype == 'string' then
      end
    elseif key == 'left' then
      if actor.opts then
        actor.selpos = actor.selpos - 1
        if actor.selpos < 1 then actor.selpos = #actor.opts end
        actor.data = actor.opts[actor.selpos]
      elseif actor.dtype == 'string' then
      end
    end
    return
  end

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
  elseif key == 'return' or key == 'kpenter' then
    local actor = self.action[self.sel]
    if actor and self[actor[1]] then
      self[actor[1]](self,actor[2],actor) -- exec(self,cmd,actor)
    elseif actor and actor[1] == 'edit' then
      self.inedit = true
      self.cursor = 1
      actor.edit = true
      if actor.opts then
        -- figure out selection
        for i,v in ipairs(actor.opts) do
          if v == actor.data then actor.selpos = i end
        end
      elseif actor.dtype == 'string' then
        -- make a mirror table of UTF-8 characters so we respect that when editing
        actor.ua = toUtf8Array(actor.data)
      end
    end
  end
end

function Screen:input(txt)
  if self.inedit then
    local actor = self.action[self.sel]
    if actor.dtype == 'string' then
      -- god why is UTF-8 so painful, dammit
      local ti = toUtf8Array(txt)
      local c = 0
      for i,v in ipairs(ti) do
        table.insert(actor.ua,self.cursor+c,v)
        c = c + 1
      end
      -- update data
      actor.data = fromUtf8Array(actor.ua)
      -- move cursor
      self.cursor = self.cursor + c
    end
  end
end
