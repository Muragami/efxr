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

require 'screen'

exec_table = {}

exec_table['1SOUND'] = function()
  Screen:clear()
  Screen:register('snd', { Name = "1" } )
  Screen:read('res/1sound.txt') end
exec_table['NEW_BANK'] = function()
  Screen:clear()
  Screen:register('bank', { Name = "?", Type = "LCODE" } )
  Screen:read('res/new_bank.txt') end
exec_table['MAIN'] = function() Screen:clear() Screen:read('res/splash.txt') end
exec_table['ABOUT'] = function() Screen:clear() Screen:read('res/about.txt') end
exec_table['README'] = function() Screen:clear() Screen:read('res/README.TXT') end
exec_table['EXIT'] = function() love.event.quit() end

function exec(self,cmd,actor)
  print("exec() got: " .. cmd .. " from " .. self.name)
  if exec_table[cmd] then exec_table[cmd](self,cmd,actor) end
end

-- Load some default values for our rectangle.
function love.load()
  love.keyboard.setKeyRepeat(true)
  -- make the font
  Screen:setFont('res/Flexi_IBM_VGA_True_437.ttf', 16)
  -- a fresh clean screen
  Screen:clear()
  -- add title
  Screen:print(love.filesystem.lines('res/splash.txt'))

  Screen.exec = exec
end

-- Increase the size of the rectangle every frame.
function love.update(dt)
  Screen:update(dt)
end

-- Draw a coloured rectangle.
function love.draw()
  Screen:draw()
end

function love.keypressed( key, scancode, isrepeat )
  Screen:onKey(key, isrepeat)
end
