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

-- Load some default values for our rectangle.
function love.load()
  love.keyboard.setKeyRepeat(true)
  -- make the font
  Screen:setFont('res/Flexi_IBM_VGA_True_437.ttf', 16)
  -- a fresh clean screen
  Screen:clear()
  -- add title
  Screen:print("EFXR 0.1 by Muragami")
  Screen:print("-")
  Screen:print("Audio generator with keyboard controls only for the desktop!")
  Screen:print("-")
  Screen:print(love.filesystem.lines('res/splash.txt'))
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
  if key == 'space' then
    Screen:clear()
    Screen:print(love.filesystem.lines('res/README.TXT'))
  end
end
