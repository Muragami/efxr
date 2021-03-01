local bit = bit32 or require 'bit'
local rng = love.math.newRandomGenerator()

local function trunc(n) if n >= 0 then return math.floor(n) else return -math.floor(-n) end end
local function clamp(n, min, max) return math.max(min or -math.huge, math.min(max or math.huge, n)) end
local function random(rng, low, high) return low + rng:random() * (high - low) end

local function genWave_square(self,phase,period,square_duty,noisebuffer) if (phase / period) < square_duty then return 0.5 else return -0.5 end end
local function genWave_sawtooth(self,phase,period,square_duty,noisebuffer) return 1 - (phase / period) * 2 end
local function genWave_triangle(self,phase,period,square_duty,noisebuffer)
  if (phase / period) <= 0.5 then return (phase / period) * 2 - 0.5
  else return (1 - (phase / period)) * 2 - 0.5 end end
local function genWave_sine(self,phase,period,square_duty,noisebuffer) return math.sin(phase / period * 2 * math.pi) end
local function genWave_noise(self,phase,period,square_duty,noisebuffer) return noisebuffer[trunc(phase * 32 / period) % 32 + 1] end

local function generate($rate, $depth)
    local fperiod, maxperiod
    local slide, dslide
    local square_duty, square_slide
    local chg_mod, chg_time, chg_limit

    local phaserbuffer = {}
    local noisebuffer = {}

    for i=1, 1024 do
        phaserbuffer[i] = 0
    end

    for i=1, 32 do
        noisebuffer[i] = random(rng,-1, 1)
    end

    local function reset()
        fperiod = 100 / ($frequency.start^2 + 0.001)
        maxperiod = 100 / ($frequency.min^2 + 0.001)
        period = trunc(fperiod)

        slide = 1.0 - $frequency.slide^3 * 0.01
        dslide = -$frequency.dslide^3 * 0.000001

        square_duty = 0.5 - $duty.ratio * 0.5
        square_slide = -$duty.sweep * 0.00005

        if $change.amount >= 0 then
            chg_mod = 1.0 - $change.amount^2 * 0.9
        else
            chg_mod = 1.0 + $change.amount^2 * 10
        end

        chg_time = 0
        if $change.speed == 1 then
            chg_limit = 0
        else
            chg_limit = trunc((1 - $change.speed)^2 * 20000 + 32)
        end
    end

    local phase = 0
    reset()

    local second_sample = false

    local env_vol = 0
    local env_stage = 1
    local env_time = 0
    local env_length = {$envelope.attack^2 * 100000,
        $envelope.sustain^2 * 100000,
        $envelope.decay^2 * 100000}

    local fphase = $phaser.offset^2 * 1020
    if $phaser.offset < 0 then fphase = -fphase end
    local dphase = $phaser.sweep^2
    if $phaser.sweep < 0 then dphase = -dphase end
    local ipp = 0

    local iphase = math.abs(trunc(fphase))

    local fltp = 0
    local fltdp = 0
    local fltw = $lowpass.cutoff^3 * 0.1
    local fltw_d = 1 + $lowpass.sweep * 0.0001
    local fltdmp = 5 / (1 + $lowpass.resonance^2 * 20) * (0.01 + fltw)
    fltdmp = clamp(fltdmp, nil, 0.8)
    local fltphp = 0
    local flthp = $highpass.cutoff^2 * 0.1
    local flthp_d = 1 + $highpass.sweep * 0.0003

    local vib_phase = 0
    local vib_speed = $vibrato.speed^2 * 0.01
    local vib_amp = $vibrato.depth * 0.5

    local rep_time = 0
    local rep_limit = trunc((1 - $repeatspeed)^2 * 20000 + 32)
    if $repeatspeed == 0 then
        rep_limit = 0
    end

    local function next()
        rep_time = rep_time + 1
        if rep_limit ~= 0 and rep_time >= rep_limit then
            rep_time = 0
            reset()
        end

        chg_time = chg_time + 1
        if chg_limit ~= 0 and chg_time >= chg_limit then
            chg_limit = 0
            fperiod = fperiod * chg_mod
        end

        slide = slide + dslide
        fperiod = fperiod * slide

        if fperiod > maxperiod then
            fperiod = maxperiod
            if ($frequency.min > 0) then
                return nil
            end
        end

        local rfperiod = fperiod
        if vib_amp > 0 then
            vib_phase = vib_phase + vib_speed
            -- Apply to the frequency period
            rfperiod = fperiod * (1.0 + math.sin(vib_phase) * vib_amp)
        end

        period = trunc(rfperiod)
        if (period < 8) then period = 8 end

        square_duty = clamp(square_duty + square_slide, 0, 0.5)

        env_time = env_time + 1

        if env_time > env_length[env_stage] then
            env_time = 0
            env_stage = env_stage + 1
            if env_stage == 4 then
                return nil
            end
        end

        if env_stage == 1 then
            env_vol = env_time / env_length[1]
        elseif env_stage == 2 then
            env_vol = 1 + (1 - env_time / env_length[2])^1 * 2 * $envelope.punch
        elseif env_stage == 3 then
            env_vol = 1 - env_time / env_length[3]
        end

        fphase = fphase + dphase
        iphase = clamp(math.abs(trunc(fphase)), nil, 1023)

        if flthp_d ~= 0 then
            flthp = clamp(flthp * flthp_d, 0.00001, 0.1)
        end

        local ssample = 0
        for si = 0, $supersampling-1 do
            local sample = 0

            phase = phase + 1

            if phase >= period then
                --phase = 0
                phase = phase % period
                if $waveform == 4 then
                    for i = 1, 32 do
                        noisebuffer[i] = random(rng,-1, 1)
                    end
                end
            end

            local fp = phase / period

            sample = $genWave(self,phase,period,square_duty,noisebuffer)
            if $wavepow and $wavepow ~= 1 then
              sample = (sample + 1.0) * 0.5
              sample = sample ^ $wavepow
              sample = (sample * 2.0) - 1
            end
            local pp = fltp
            fltw = clamp(fltw * fltw_d, 0, 0.1)
            if $lowpass.cutoff ~= 1 then
                fltdp = fltdp + (sample - fltp) * fltw
                fltdp = fltdp - fltdp * fltdmp
            else
                fltp = sample
                fltdp = 0
            end
            fltp = fltp + fltdp
            fltphp = fltphp + (fltp - pp)
            fltphp = fltphp - (fltphp * flthp)
            sample = fltphp
            phaserbuffer[bit.band(ipp, 1023) + 1] = sample
            sample = sample + phaserbuffer[bit.band(ipp - iphase + 1024, 1023) + 1]
            ipp = bit.band(ipp + 1, 1023)
            ssample = ssample + sample * env_vol
        end
        ssample = (ssample / $supersampling) * $volume.master
        ssample = ssample * (2 * $volume.sound)
        ssample = clamp(ssample, -1, 1)
        second_sample = not second_sample
        if $rate == 22050 and second_sample then
            local nsample = next()
            if nsample then
                return (ssample + nsample) / 2
            else
                return nil
            end
        end

        if $depth == 0 then
            return ssample
        elseif $depth == 16 then
            return trunc(ssample * 32000)
        else
            return trunc(ssample * 127 + 128)
        end
    end

    return next
end

local function loveSoundData($rate, $depth)
    $rate = $rate or 44100
    $depth = $depth or 0
    local bits = $depth
    if bits == 0 then bits = 16

    local t = {}
    local i = 1
    for v in generate($rate, $depth) do
        t[i] = v
        i = i + 1
    end

    local data = love.sound.newSoundData(i, $rate, bits, 1)

    if $depth == 0 then
      for p,v in ipairs(t) do
        data:setSample(p-1, v)
      end
    elseif $depth == 8 then
      for p,v in ipairs(t) do
        data:setSample(p-1, (v-128) / 127)
      end
    elseif $depth == 16 then
      for p,v in ipairs(t) do
        data:setSample(p-1, v / 32000)
      end
    end

    return data, i
end

return loveSoundData($rate,$depth)
