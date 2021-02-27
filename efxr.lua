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

-- @module efxr
local efxr = {}
local bit = bit32 or require 'bit'

-- Constants
efxr.VERSION = "0.1"
efxr.WAVEFUNC = { } -- filled in after generator functions are defined below
efxr.WAVENAME = { } -- filled in after generator functions are defined below
efxr.SAMPLERATE = { [22050] = 22050, [44100] = 44100 }
efxr.BITDEPTH = { [0] = 0, [8] = 8, [16] = 16 }

-- Utilities
local function trunc(n)
    if n >= 0 then return math.floor(n) else return -math.floor(-n) end
end

local function random(rng, low, high)
    return low + rng:random() * (high - low)
end

local function maybe(rng,w)
    return math.floor(random(rng, 0, w or 1)) == 0
end

local function clamp(n, min, max)
    return math.max(min or -math.huge, math.min(max or math.huge, n))
end

local function shallowcopy(t)
    if type(t) == "table" then
        local t2 = {}
        for k,v in pairs(t) do
            t2[k] = v
        end
        return t2
    else
        return t
    end
end

local function mergetables(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" then
            if type(t1[k] or false) == "table" then
                mergetables(t1[k] or {}, t2[k] or {})
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
    return t1
end

-- encode a float value from -1 to 1 as a 8 byte long decimal number with leading sign +/-
local function to8bFixed(val)
  local ret = ""
  -- +/- prefix
  if val < 0 then ret = ret .. '+' else ret = ret .. '-' end
  -- scale and add the value
  local tst = 1000000
  local sval = val * tst
  local cnt = 7
  repeat
    local rval = math.floor(sval / tst)
    ret = ret + tostring(rval)
    cnt = cnt - 1
    sval = sval - (rval * tst)
    tst = tst / 10
  until cnt == 0
end

-- decode a float value from -1 to 1 as a 8 byte long decimal number with leading sign +/-
local function from8bFixed(val,pos)
  local ret = 0
  if not pos then pos = 0 end
  -- +/- prefix
  local neg = (string.byte (val, 1 + pos) == 45)

  if val < 0 then ret = ret .. '+' else ret = ret .. '-' end
  -- scale and add the value
  local tst = 1000000
  local cnt = 1
  repeat
    ret = ret + (string.byte (val, 1 + cnt + pos) - 48) * tst
    cnt = cnt + 1
    tst = tst / 10
  until cnt > 7
  return ret / 1000000
end

function efxr.newSound(...)
    local instance = setmetatable({}, efxr.Sound)
    instance:__init(...)
    return instance
end

-- wave generators
local function genWave_square(self,phase,period,square_duty,noisebuffer)
  if (phase / period) < square_duty then return 0.5 else return -0.5 end
end

local function genWave_sawtooth(self,phase,period,square_duty,noisebuffer)
  return 1 - (phase / period) * 2
end

local function genWave_triangle(self,phase,period,square_duty,noisebuffer)
  if (phase / period) <= 0.5 then
    return (phase / period) * 2 - 0.5
  else
    return (1 - (phase / period)) * 2 - 0.5
  end
end

local function genWave_sine(self,phase,period,square_duty,noisebuffer)
  return math.sin(phase / period * 2 * math.pi)
end

local function genWave_noise(self,phase,period,square_duty,noisebuffer)
  return noisebuffer[trunc(phase * 32 / period) % 32 + 1]
end

efxr.WAVEFUNC.SQUARE = genWave_square
efxr.WAVEFUNC.SAWTOOTH = genWave_sawtooth
efxr.WAVEFUNC.TRIANGLE = genWave_triangle
efxr.WAVEFUNC.SINE = genWave_sine
efxr.WAVEFUNC.NOISE = genWave_noise
efxr.WAVEFUNC[0] = genWave_square
efxr.WAVEFUNC[1] = genWave_sawtooth
efxr.WAVEFUNC[2] = genWave_sine
efxr.WAVEFUNC[3] = genWave_triangle
efxr.WAVEFUNC[4] = genWave_noise
efxr.WAVENAME[0] = 'SQUARE'
efxr.WAVENAME[1] = 'SAWTOOTH'
efxr.WAVENAME[2] = 'SINE'
efxr.WAVENAME[3] = 'TRIANGLE'
efxr.WAVENAME[4] = 'NOISE'
efxr.WAVENAME['SQUARE'] = 0
efxr.WAVENAME['SAWTOOTH'] = 1
efxr.WAVENAME['SINE'] = 2
efxr.WAVENAME['TRIANGLE'] = 3
efxr.WAVENAME['NOISE'] = 4

-- the module itself
efxr.Sound = {}
efxr.Sound.__index = efxr.Sound

function efxr.Sound:__init()
    self.supersampling = 8
    self:resetParameters()
    self.volume.master = 0.5
    self.volume.sound = 0.5
end

function efxr.Sound:resetParameters()
    self.repeatspeed = 0.0
    self.waveform = efxr.WAVENAME['SQUARE']
    self.genWave = efxr.WAVEFUNC[self.waveform]
    self.wavepow = nil  -- no quadratic on a default waveform

    self.envelope = { attack = 0.0, sustain = 0.3, punch = 0.0, decay = 0.4 }
    self.frequency = { start = 0.3, min = 0.0, slide = 0.0, dslide = 0.0 }
    self.vibrato = { depth = 0.0, speed = 0.0, delay = 0.0 }
    self.change = { amount = 0.0, speed = 0.0 }
    self.duty = { ratio = 0.0, sweep = 0.0 }
    self.phaser = { offset = 0.0, sweep = 0.0 }
    self.lowpass = { cutoff = 1.0, sweep = 0.0, resonance = 0.0 }
    self.highpass = { cutoff = 0.0, sweep = 0.0 }
end

function efxr.Sound:sanitizeParameters()
    self.repeatspeed = clamp(self.repeatspeed, 0, 1)
    self.waveform = clamp(self.waveform, 0, #efxr.WAVENAME)
    self.genWave = efxr.WAVEFUNC[self.waveform]

    if self.wavepow then self.wavepow = clamp(self.wavepow, 0, 4) end

    self.envelope.attack = clamp(self.envelope.attack, 0, 1)
    self.envelope.sustain = clamp(self.envelope.sustain, 0, 1)
    self.envelope.punch = clamp(self.envelope.punch, 0, 1)
    self.envelope.decay = clamp(self.envelope.decay, 0, 1)

    self.frequency.start = clamp(self.frequency.start, 0, 1)
    self.frequency.min = clamp(self.frequency.min, 0, 1)
    self.frequency.slide = clamp(self.frequency.slide, -1, 1)
    self.frequency.dslide = clamp(self.frequency.dslide, -1, 1)

    self.vibrato.depth = clamp(self.vibrato.depth, 0, 1)
    self.vibrato.speed = clamp(self.vibrato.speed, 0, 1)
    self.vibrato.delay = clamp(self.vibrato.delay, 0, 1)

    self.change.amount = clamp(self.change.amount, -1, 1)
    self.change.speed = clamp(self.change.speed, 0, 1)

    self.duty.ratio = clamp(self.duty.ratio, 0, 1)
    self.duty.sweep = clamp(self.duty.sweep, -1, 1)

    self.phaser.offset = clamp(self.phaser.offset, -1, 1)
    self.phaser.sweep = clamp(self.phaser.sweep, -1, 1)

    self.lowpass.cutoff = clamp(self.lowpass.cutoff, 0, 1)
    self.lowpass.sweep = clamp(self.lowpass.sweep, -1, 1)
    self.lowpass.resonance = clamp(self.lowpass.resonance, 0, 1)
    self.highpass.cutoff = clamp(self.highpass.cutoff, 0, 1)
    self.highpass.sweep = clamp(self.highpass.sweep, -1, 1)
end

function efxr.Sound:generate(rate, depth)
    rate = rate or 44100
    depth = depth or 0
    assert(efxr.SAMPLERATE[rate], "efxr.Sound:generate() invalid sampling rate: " .. tostring(rate))
    assert(efxr.BITDEPTH[depth], "efxr.Sound:generate() invalid bit depth: " .. tostring(depth))

    -- Initialize all locals
    local fperiod, maxperiod
    local slide, dslide
    local square_duty, square_slide
    local chg_mod, chg_time, chg_limit

    local phaserbuffer = {}
    local noisebuffer = {}

    -- Initialize the sample buffers
    for i=1, 1024 do
        phaserbuffer[i] = 0
    end

    for i=1, 32 do
        noisebuffer[i] = random(-1, 1)
    end

    --- Reset the sound period
    local function reset()
        fperiod = 100 / (self.frequency.start^2 + 0.001)
        maxperiod = 100 / (self.frequency.min^2 + 0.001)
        period = trunc(fperiod)

        slide = 1.0 - self.frequency.slide^3 * 0.01
        dslide = -self.frequency.dslide^3 * 0.000001

        square_duty = 0.5 - self.duty.ratio * 0.5
        square_slide = -self.duty.sweep * 0.00005

        if self.change.amount >= 0 then
            chg_mod = 1.0 - self.change.amount^2 * 0.9
        else
            chg_mod = 1.0 + self.change.amount^2 * 10
        end

        chg_time = 0
        if self.change.speed == 1 then
            chg_limit = 0
        else
            chg_limit = trunc((1 - self.change.speed)^2 * 20000 + 32)
        end
    end

    local phase = 0
    reset()

    local second_sample = false

    local env_vol = 0
    local env_stage = 1
    local env_time = 0
    local env_length = {self.envelope.attack^2 * 100000,
        self.envelope.sustain^2 * 100000,
        self.envelope.decay^2 * 100000}

    local fphase = self.phaser.offset^2 * 1020
    if self.phaser.offset < 0 then fphase = -fphase end
    local dphase = self.phaser.sweep^2
    if self.phaser.sweep < 0 then dphase = -dphase end
    local ipp = 0

    local iphase = math.abs(trunc(fphase))

    local fltp = 0
    local fltdp = 0
    local fltw = self.lowpass.cutoff^3 * 0.1
    local fltw_d = 1 + self.lowpass.sweep * 0.0001
    local fltdmp = 5 / (1 + self.lowpass.resonance^2 * 20) * (0.01 + fltw)
    fltdmp = clamp(fltdmp, nil, 0.8)
    local fltphp = 0
    local flthp = self.highpass.cutoff^2 * 0.1
    local flthp_d = 1 + self.highpass.sweep * 0.0003

    local vib_phase = 0
    local vib_speed = self.vibrato.speed^2 * 0.01
    local vib_amp = self.vibrato.depth * 0.5

    local rep_time = 0
    local rep_limit = trunc((1 - self.repeatspeed)^2 * 20000 + 32)
    if self.repeatspeed == 0 then
        rep_limit = 0
    end

    -- The main closure (returned as a generator)
    local function next()
        -- Repeat when needed
        rep_time = rep_time + 1
        if rep_limit ~= 0 and rep_time >= rep_limit then
            rep_time = 0
            reset()
        end

        -- Update the change time and apply it if needed
        chg_time = chg_time + 1
        if chg_limit ~= 0 and chg_time >= chg_limit then
            chg_limit = 0
            fperiod = fperiod * chg_mod
        end

        -- Apply the frequency slide and stuff
        slide = slide + dslide
        fperiod = fperiod * slide

        if fperiod > maxperiod then
            fperiod = maxperiod
            -- Fail if the minimum frequency is too small
            if (self.frequency.min > 0) then
                return nil
            end
        end

        -- Vibrato
        local rfperiod = fperiod
        if vib_amp > 0 then
            vib_phase = vib_phase + vib_speed
            -- Apply to the frequency period
            rfperiod = fperiod * (1.0 + math.sin(vib_phase) * vib_amp)
        end

        -- Update the period
        period = trunc(rfperiod)
        if (period < 8) then period = 8 end

        -- Update the square duty
        square_duty = clamp(square_duty + square_slide, 0, 0.5)

        -- Volume envelopes
        env_time = env_time + 1

        if env_time > env_length[env_stage] then
            env_time = 0
            env_stage = env_stage + 1
            -- After the decay stop generating
            if env_stage == 4 then
                return nil
            end
        end

        -- Attack, Sustain, Decay/Release
        if env_stage == 1 then
            env_vol = env_time / env_length[1]
        elseif env_stage == 2 then
            env_vol = 1 + (1 - env_time / env_length[2])^1 * 2 * self.envelope.punch
        elseif env_stage == 3 then
            env_vol = 1 - env_time / env_length[3]
        end

        -- Phaser
        fphase = fphase + dphase
        iphase = clamp(math.abs(trunc(fphase)), nil, 1023)

        -- Filter stuff
        if flthp_d ~= 0 then
            flthp = clamp(flthp * flthp_d, 0.00001, 0.1)
        end

        -- And finally the actual tone generation and supersampling
        local ssample = 0
        for si = 0, self.supersampling-1 do
            local sample = 0

            phase = phase + 1

            -- fill the noise buffer every period
            if phase >= period then
                --phase = 0
                phase = phase % period
                if self.waveform == efxr.WAVEFORM.NOISE then
                    for i = 1, 32 do
                        noisebuffer[i] = random(-1, 1)
                    end
                end
            end

            -- Tone generators ahead
            local fp = phase / period

            -- call on the wave generator to make the waveform
            sample = self.genWave(self,phase,period,square_duty,noisebuffer)

            -- do we have a quadratic to run on this?
            if self.wavepow and self.wavepow ~= 1 then
              sample = (sample + 1.0) * 0.5 -- move the sample into 0,1 space
              sample = sample ^ self.wavepow
              sample = (sample * 2.0) - 1   -- move back into -1,1 space
            end

            -- Apply the lowpass filter to the sample
            local pp = fltp
            fltw = clamp(fltw * fltw_d, 0, 0.1)
            if self.lowpass.cutoff ~= 1 then
                fltdp = fltdp + (sample - fltp) * fltw
                fltdp = fltdp - fltdp * fltdmp
            else
                fltp = sample
                fltdp = 0
            end
            fltp = fltp + fltdp

            -- Apply the highpass filter to the sample
            fltphp = fltphp + (fltp - pp)
            fltphp = fltphp - (fltphp * flthp)
            sample = fltphp

            -- Apply the phaser to the sample
            phaserbuffer[bit.band(ipp, 1023) + 1] = sample
            sample = sample + phaserbuffer[bit.band(ipp - iphase + 1024, 1023) + 1]
            ipp = bit.band(ipp + 1, 1023)

            -- Accumulation and envelope application
            ssample = ssample + sample * env_vol
        end

        -- Apply the volumes
        ssample = (ssample / self.supersampling) * self.volume.master
        ssample = ssample * (2 * self.volume.sound)

        -- Hard limit
        ssample = clamp(ssample, -1, 1)

        -- Frequency conversion
        second_sample = not second_sample
        if rate == 22050 and second_sample then
            -- hah!
            local nsample = next()
            if nsample then
                return (ssample + nsample) / 2
            else
                return nil
            end
        end

        -- bit conversions
        if depth == 0 then
            return ssample
        elseif depth == 16 then
            return trunc(ssample * 32000)
        else
            return trunc(ssample * 127 + 128)
        end
    end

    return next
end

function efxr.Sound:getEnvelopeLimit(rate)
    rate = rate or 44100
    assert(efxr.SAMPLERATE[rate], "efxr.Sound:getEnvelopeLimit() invalid sampling rate: " .. tostring(rate))

    local env_length = {
        self.envelope.attack^2 * 100000, --- attack
        self.envelope.sustain^2 * 100000, --- sustain
        self.envelope.decay^2 * 100000 --- decay
    }
    local limit = trunc(env_length[1] + env_length[2] + env_length[3] + 2)

    return math.ceil(limit / (rate / 44100))
end

function efxr.Sound:generateTable(rate, depth, tab)
    rate = rate or 44100
    depth = depth or 0
    assert(efxr.SAMPLERATE[rate], "efxr.Sound:generateTable() invalid sampling rate: " .. tostring(rate))
    assert(efxr.BITDEPTH[depth], "efxr.Sound:generateTable() invalid bit depth: " .. tostring(depth))

    -- this could really use table pre-allocation, but Lua doesn't provide that
    local t = tab or {}
    local i = 1
    for v in self:generate(rate, depth) do
        t[i] = v
        i = i + 1
    end
    return t, i
end

function efxr.Sound:generateFunc(func, other, rate, depth)
  rate = rate or 44100
  depth = depth or 0
  assert(efxr.SAMPLERATE[rate], "efxr.Sound:generateTable() invalid sampling rate: " .. tostring(rate))
  assert(efxr.BITDEPTH[depth], "efxr.Sound:generateTable() invalid bit depth: " .. tostring(depth))

  local i = 1
  if other then
    for v in self:generate(rate, depth) do
      func(other,i,v)
      i = i + 1
    end
  else
    for v in self:generate(rate, depth) do
      func(i,v)
      i = i + 1
    end
  end
end

function efxr.Sound:randomize(rng,seed)
    self.seed = seed

    local waveform = self.waveform
    self:resetParameters()
    self.waveform = waveform
    self.genWave = efxr.WAVEFUNC[self.waveform]

    if maybe(rng) then
      self.wavepow = random(rng,0.25,4)
    end

    if maybe(rng) then
        self.repeatspeed = random(rng,0, 1)
    end

    if maybe(rng) then
        self.frequency.start = random(rng,-1, 1)^3 + 0.5
    else
        self.frequency.start = random(rng,-1, 1)^2
    end
    self.frequency.limit = 0
    self.frequency.slide = random(rng,-1, 1)^5
    if self.frequency.start > 0.7 and self.frequency.slide > 0.2 then
        self.frequency.slide = -self.frequency.slide
    elseif self.frequency.start < 0.2 and self.frequency.slide <-0.05 then
        self.frequency.slide = -self.frequency.slide
    end
    self.frequency.dslide = random(rng,-1, 1)^3

    self.duty.ratio = random(rng,-1, 1)
    self.duty.sweep = random(rng,-1, 1)^3

    self.vibrato.depth = random(rng,-1, 1)^3
    self.vibrato.speed = random(rng,-1, 1)
    self.vibrato.delay = random(rng,-1, 1)

    self.envelope.attack = random(rng,-1, 1)^3
    self.envelope.sustain = random(rng,-1, 1)^2
    self.envelope.punch = random(rng,-1, 1)^2
    self.envelope.decay = random(rng,-1, 1)

    if self.envelope.attack + self.envelope.sustain + self.envelope.decay < 0.2 then
        self.envelope.sustain = self.envelope.sustain + 0.2 + random(rng,0, 0.3)
        self.envelope.decay = self.envelope.decay + 0.2 + random(rng,0, 0.3)
    end

    self.lowpass.resonance = random(rng,-1, 1)
    self.lowpass.cutoff = 1 - random(rng,0, 1)^3
    self.lowpass.sweep = random(rng,-1, 1)^3
    if self.lowpass.cutoff < 0.1 and self.lowpass.sweep < -0.05 then
        self.lowpass.sweep = -self.lowpass.sweep
    end
    self.highpass.cutoff = random(rng,0, 1)^3
    self.highpass.sweep = random(rng,-1, 1)^5

    self.phaser.offset = random(rng,-1, 1)^3
    self.phaser.sweep = random(rng,-1, 1)^3

    self.change.speed = random(rng,-1, 1)
    self.change.amount = random(rng,-1, 1)

    self:sanitizeParameters()
end

function efxr.Sound:mutate(amount, rng, changefreq)
    local amount = (amount or 1)
    local a = amount / 20
    local b = (1 - a) * 10
    local changefreq = (changefreq == nil) and true or changefreq

    if changefreq == true then
        if maybe(b) then self.frequency.start = self.frequency.start + random(rng,-a, a) end
        if maybe(b) then self.frequency.slide = self.frequency.slide + random(rng,-a, a) end
        if maybe(b) then self.frequency.dslide = self.frequency.dslide + random(rng,-a, a) end
    end

    if maybe(b) then self.duty.ratio = self.duty.ratio + random(rng,-a, a) end
    if maybe(b) then self.duty.sweep = self.duty.sweep + random(rng,-a, a) end

    if maybe(b) then self.vibrato.depth = self.vibrato.depth + random(rng,-a, a) end
    if maybe(b) then self.vibrato.speed = self.vibrato.speed + random(rng,-a, a) end
    if maybe(b) then self.vibrato.delay = self.vibrato.delay + random(rng,-a, a) end

    if maybe(b) then self.envelope.attack = self.envelope.attack + random(rng,-a, a) end
    if maybe(b) then self.envelope.sustain = self.envelope.sustain + random(rng,-a, a) end
    if maybe(b) then self.envelope.punch = self.envelope.punch + random(rng,-a, a) end
    if maybe(b) then self.envelope.decay = self.envelope.decay + random(rng,-a, a) end

    if maybe(b) then self.lowpass.resonance = self.lowpass.resonance + random(rng,-a, a) end
    if maybe(b) then self.lowpass.cutoff = self.lowpass.cutoff + random(rng,-a, a) end
    if maybe(b) then self.lowpass.sweep = self.lowpass.sweep + random(rng,-a, a) end
    if maybe(b) then self.highpass.cutoff = self.highpass.cutoff + random(rng,-a, a) end
    if maybe(b) then self.highpass.sweep = self.highpass.sweep + random(rng,-a, a) end

    if maybe(b) then self.phaser.offset = self.phaser.offset + random(rng,-a, a) end
    if maybe(b) then self.phaser.sweep = self.phaser.sweep + random(rng,-a, a) end

    if maybe(b) then self.change.speed = self.change.speed + random(rng,-a, a) end
    if maybe(b) then self.change.amount = self.change.amount + random(rng,-a, a) end

    if maybe(b) then self.repeatspeed = self.repeatspeed + random(rng,-a, a) end

    self:sanitizeParameters()
end

local function rnd_pickup(s,r)
  s.frequency.start = random(r,0.4, 0.9)
  s.envelope.attack = 0
  s.envelope.sustain = random(r,0, 0.1)
  s.envelope.punch = random(r,0.3, 0.6)
  s.envelope.decay = random(r,0.1, 0.5)

  if maybe(r) then
      s.change.speed = random(r,0.5, 0.7)
      s.change.amount = random(r,0.2, 0.6)
  end
end

local function rnd_laser(s,r)
  s.waveform = trunc(random(r,0, 4))
  if s.waveform == efxr.WAVENAME['SINE'] and maybe(r) then
      s.waveform = trunc(random(r,0, 1))
      s.genWave = efxr.WAVEFUNC[s.waveform]
  end

  if maybe(r,2) then
      s.frequency.start = random(r,0.3, 0.9)
      s.frequency.min = random(r,0, 0.1)
      s.frequency.slide = random(r,-0.65, -0.35)
  else
      s.frequency.start = random(r,0.5, 1)
      s.frequency.min = clamp(s.frequency.start - random(r,0.2, 0.4), 0.2)
      s.frequency.slide = random(r,-0.35, -0.15)
  end

  if maybe(r) then
      s.duty.ratio = random(r,0, 0.5)
      s.duty.sweep = random(r,0, 0.2)
  else
      s.duty.ratio = random(r,0.4, 0.9)
      s.duty.sweep = random(r,-0.7, 0)
  end

  s.envelope.attack = 0
  s.envelope.sustain = random(r,0.1, 0.3)
  s.envelope.decay = random(r,0, 0.4)

  if maybe(r) then
      s.envelope.punch = random(r,0, 0.3)
  end

  if maybe(r,2) then
      s.phaser.offset = random(r,0, 0.2)
      s.phaser.sweep = random(r,-0.2, 0)
  end

  if maybe(r) then
      s.highpass.cutoff = random(r,0, 0.3)
  end
end

local function rnd_powerup(s,r)
  if maybe(r) then
      s.waveform = efxr.WAVENAME['SAWTOOTH']
      s.genWave = efxr.WAVEFUNC[s.waveform]
  else
      s.duty.ratio = random(r,0, 0.6)
  end

  if maybe(r) then
      s.frequency.start = random(r,0.2, 0.5)
      s.frequency.slide = random(r,0.1, 0.5)
      s.repeatspeed = random(r,0.4, 0.8)
  else
      s.frequency.start = random(r,0.2, 0.5)
      s.frequency.slide = random(r,0.05, 0.25)
      if maybe(r) then
          s.vibrato.depth = random(r,0, 0.7)
          s.vibrato.speed = random(r,0, 0.6)
      end
  end
  s.envelope.attack = 0
  s.envelope.sustain = random(r,0, 0.4)
  s.envelope.decay = random(r,0.1, 0.5)
end

local function rnd_hit(s,r)
  s.waveform = trunc(random(r,0, 3))

  if s.waveform == efxr.WAVENAME['SINE'] then
      s.waveform = efxr.WAVENAME['NOISE']
  elseif s.waveform == efxr.WAVENAME['SQUARE'] then
      s.duty.ratio = random(r,0, 0.6)
  end

  s.genWave = efxr.WAVEFUNC[s.waveform]

  s.frequency.start = random(r,0.2, 0.8)
  s.frequency.slide = random(r,-0.7, -0.3)
  s.envelope.attack = 0
  s.envelope.sustain = random(r,0, 0.1)
  s.envelope.decay = random(r,0.1, 0.3)

  if maybe(r) then
      s.highpass.cutoff = random(r,0, 0.3)
  end
end

local function rnd_jump(s,r)
  s.waveform = efxr.WAVENAME['SQUARE']
  s.genWave = efxr.WAVEFUNC[s.waveform]

  s.duty.value = random(r,0, 0.6)
  s.frequency.start = random(r,0.3, 0.6)
  s.frequency.slide = random(r,0.1, 0.3)

  s.envelope.attack = 0
  s.envelope.sustain = random(r,0.1, 0.4)
  s.envelope.decay = random(r,0.1, 0.3)

  if maybe(r) then
      s.highpass.cutoff = random(r,0, 0.3)
  end
  if maybe(r) then
      s.lowpass.cutoff = random(r,0.4, 1)
  end
end

local function rnd_blip(s,r)
  s.waveform = trunc(random(r,0, 2))
  s.genWave = efxr.WAVEFUNC[s.waveform]

  if s.waveform == efxr.WAVENAME['SQUARE'] then
      s.duty.ratio = random(r,0, 0.6)
  end

  s.frequency.start = random(r,0.2, 0.6)
  s.envelope.attack = 0
  s.envelope.sustain = random(r,0.1, 0.2)
  s.envelope.decay = random(r,0, 0.2)
  s.highpass.cutoff = 0.1
end

local function rnd_explosion(s,r)
  s.waveform = efxr.WAVENAME['NOISE']
  s.genWave = efxr.WAVEFUNC[s.waveform]

  if maybe(r) then
      s.frequency.start = random(r,0.1, 0.5)
      s.frequency.slide = random(r,-0.1, 0.3)
  else
      s.frequency.start = random(r,0.2, 0.9)
      s.frequency.slide = random(r,-0.2, -0.4)
  end
  s.frequency.start = s.frequency.start^2

  if maybe(r,4) then
      s.frequency.slide = 0
  end
  if maybe(r,2) then
      s.repeatspeed = random(r,0.3, 0.8)
  end

  s.envelope.attack = 0
  s.envelope.sustain = random(r,0.1, 0.4)
  s.envelope.punch = random(r,0.2, 0.8)
  s.envelope.decay = random(r,0, 0.5)

  if maybe(r) then
      s.phaser.offset = random(r,-0.3, 0.6)
      s.phaser.sweep = random(r,-0.3, 0)
  end
  if maybe(r) then
      s.vibrato.depth = random(r,0, 0.7)
      s.vibrato.speed = random(r,0, 0.6)
  end
  if maybe(r,2) then
      s.change.speed = random(r,0.6, 0.9)
      s.change.amount = random(r,-0.8, 0.8)
  end
end

local efxrSndType = { 'blip' = rnd_blip, 'explosion' = rnd_explosion, 'hit' = rnd_hit,
    'jump' = rnd_jump, 'laser' = rnd_laser, 'pickup' = rnd_pickup, 'powerup' = rnd_powerup }

function efxr.Sound:random(rng,what)
    self:resetParameters()
    local rnd_func = efxrSndType[what]
    assert(rnd_func,"efxr.Sound:random() bad type provided: " .. what)
    rnd_func(self,rng)
end

function efxr.Sound:newSndType(name,func)
  assert(not efxrSndType[name],'efxr.Sound:newSndType() named type already registered: ' .. name)
  efxrSndType[name] = func
end

function efxr.Sound:newWaveGenerator(name,func)
  assert(not exfr.WAVENAME[name],'efxr.Sound:newWaveGenerator() named type already registered: ' .. name)
  local spot = #efxr.WAVENAME
  efxr.WAVENAME[name] = spot
  efxr.WAVENAME[spot] = name
  efxr.WAVEFUNC[spot] = func
  efxr.WAVEFUNC[name] = func
end

function efxr.Sound:tolua(f, minify)
    local code = "local "

    -- we'll compare the current parameters with the defaults
    local defaults = efxr.newSound()

    -- this part is pretty awful but it works for now
    function store(keys, obj)
        local name = keys[#keys]

        if type(obj) == "number" then
            -- fetch the default value
            local def = defaults
            for i=2, #keys do
                def = def[keys[i]]
            end

            if obj ~= def then
                local k = table.concat(keys, ".")
                if not minify then
                    code = code .. "\n" .. string.rep(" ", #keys - 1)
                end
                code = code .. string.format("%s=%s;", name, obj)
            end

        elseif type(obj) == "table" then
            local spacing = minify and "" or "\n" .. string.rep(" ", #keys - 1)
            code = code .. spacing .. string.format("%s={", name)

            for k, v in pairs(obj) do
                local newkeys = shallowcopy(keys)
                newkeys[#newkeys + 1] = k
                store(newkeys, v)
            end

            code = code .. spacing .. "};"
        end
    end

    store({"s"}, self)
    code = code .. "\nreturn s, \"" .. efxr.VERSION .. "\""
    return code
end

function efxr.Sound:fromlua(f)
    local code = f

    local params, version = assert(loadstring(code))()
    -- check version compatibility
    assert(version > efxr.VERSION, "incompatible version: " .. tostring(version))

    self:resetParameters()
    -- merge the loaded table into the own
    mergetables(self, params)
end

function efxr.Sound:tostring()
  local ret = ""
  ret = ret .. to8bFixed(self.repeatspeed)
  ret = ret .. to8bFixed(self.waveform * 0.01)  -- have to shrink it under 1.0

  ret = ret .. to8bFixed(self.envelope.attack)
  ret = ret .. to8bFixed(self.envelope.sustain)
  ret = ret .. to8bFixed(self.envelope.punch)
  ret = ret .. to8bFixed(self.envelope.decay)

  ret = ret .. to8bFixed(self.frequency.start)
  ret = ret .. to8bFixed(self.frequency.min)
  ret = ret .. to8bFixed(self.frequency.slide)
  ret = ret .. to8bFixed(self.frequency.dslide)

  ret = ret .. to8bFixed(self.vibrato.depth)
  ret = ret .. to8bFixed(self.vibrato.speed)
  ret = ret .. to8bFixed(self.vibrato.delay)

  ret = ret .. to8bFixed(self.change.amount)
  ret = ret .. to8bFixed(self.change.speed)

  ret = ret .. to8bFixed(self.duty.ratio)
  ret = ret .. to8bFixed(self.duty.sweep)

  ret = ret .. to8bFixed(self.phaser.offset)
  ret = ret .. to8bFixed(self.phaser.sweep)

  ret = ret .. to8bFixed(self.lowpass.cutoff)
  ret = ret .. to8bFixed(self.lowpass.sweep)
  ret = ret .. to8bFixed(self.lowpass.resonance)
  ret = ret .. to8bFixed(self.highpass.cutoff)
  ret = ret .. to8bFixed(self.highpass.sweep)
  return ret
end

function efxr.Sound:fromstring(s,pos)
  if not pos then pos = 0 end
  self.repeatspeed = from8bFixed(s,pos)
  self.waveform = from8bFixed(s,pos+8) * 100.0  -- have to scale it from under 1.0

  self.envelope.attack = from8bFixed(s,pos+16)
  self.envelope.sustain = from8bFixed(s,pos+24)
  self.envelope.punch = from8bFixed(s,pos+32)
  self.envelope.decay = from8bFixed(s,pos+40)

  self.frequency.start = from8bFixed(s,pos+48)
  self.frequency.min = from8bFixed(s,pos+56)
  self.frequency.slide = from8bFixed(s,pos+64)
  self.frequency.dslide = from8bFixed(s,pos+72)

  self.vibrato.depth = from8bFixed(s,pos+80)
  self.vibrato.speed = from8bFixed(s,pos+88)
  self.vibrato.delay = from8bFixed(s,pos+96)

  self.change.amount = from8bFixed(s,pos+104)
  self.change.speed = from8bFixed(s,pos+112)

  self.duty.ratio = from8bFixed(s,pos+120)
  self.duty.sweep = from8bFixed(s,pos+128)

  self.phaser.offset = from8bFixed(s,pos+136)
  self.phaser.sweep = from8bFixed(s,pos+144)

  self.lowpass.cutoff = from8bFixed(s,pos+152)
  self.lowpass.sweep = from8bFixed(s,pos+160)
  self.lowpass.resonance = from8bFixed(s,pos+168)
  self.highpass.cutoff = from8bFixed(s,pos+176)
  self.highpass.sweep = from8bFixed(s,pos+184)
end

return efxr
