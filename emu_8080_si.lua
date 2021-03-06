#!/usr/bin/env lua
-- 8080 Emu: Space Invaders.
-- Run tools/si.sh with spaceinvaders.rom in the base directory.

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memsz = 0x4000

-- Load bitops
local bitops = loadfile("bitops.lua")(false, true)

local l8080 = dofile("8080/init.lua")
-- Install bitops
l8080.set_bit32(bitops)

local memlib = require("memlib")

-- Localize functions
local band, rshift, lshift = bitops.band, bitops.rshift, bitops.lshift
local iowr, iord = io.write, io.read
local sbyte, schar = string.byte, string.char
local mfloor = math.floor
local ioflush = io.flush

-- Memory: ROM, RAM and peripherals.
local t = f:read(memsz)
local rom = memlib.new("rostring", t, memsz)
f:close()

local mem = memlib.new("rwoverlay", rom, memsz)

local function get(inst, i)
	return mem:get(band(i, 0x3FFF))
end
local function set(inst, i, v)
	local p = band(i, 0x3FFF)
	if p < 0x2000 then
		--error("Game wrote into ROM ~ decimal " .. p)
		--mem:set(bitops.band(p, 0x1FFF) + 0x2000, v)
		return
	end
	mem:set(p, v)
end

local shiftreg = 0
local shiftregofs = 0

local buttons1, buttons2 = 1, 0
local function iog(inst, i)
	if i == 1 then
		return buttons1
	end
	if i == 2 then
		return buttons2
	end
	if i == 3 then
		--io.stderr:write("TEST\n")
		return rshift(band(lshift(shiftreg, shiftregofs), 0xFF00), 8)
	end
	return 0
end
local function ios(inst, i, v)
	if i == 4 then
		shiftreg = mfloor(shiftreg / 256)
		shiftreg = shiftreg + (v * 256)
	end
	if i == 2 then
		shiftregofs = v % 8 -- unsure if this should be % 8
	end
end

-- Get 8080 instance and set up.
local inst = l8080.new(get, set, iog, ios)

-- 2Mhz == 1000000 cycles per second (or maybe 2000000)
-- Rate is 60 hz
-- 16666 cycles per frame???
-- for now I'm just assuming vblank takes as long as draw
-- bleh, int.fail errors. just giving it 1000000 cycles per frame (ridiculous I know)
-- ok, new plan, interrupt some amount of instructions after it's ready.
local vblank = true

local cycleratio = 2000000
local timeframe = 1 / 60
local timer_vblank = mfloor((timeframe * 0.5) * cycleratio)
local timer_draw = mfloor((timeframe * 0.5) * cycleratio)

local timerval = timer_draw
local nexttimer = timerval

while true do
	--if inst.PC == 0x15D3 then io.stderr:write("BFR\n") inst:dump() end
	--if inst.PC == 0x15D6 then io.stderr:write("AFT\n") inst:dump() end
	local t = nexttimer
	if not inst.halted then
		local pc = inst.PC
		local n, c = inst:run()
		t = c
		--print(string.format("0x%04x: %s -> 0x%04x (%i cycles)", pc, n, inst.PC, c))
	end
	if not inst.int_enable then
		nexttimer = timerval
	end
	if nexttimer > 0 then
		nexttimer = nexttimer - t
	else
		if vblank then
			--io.stderr:write("Interrupt VBLK_LEAVE\n")
			if not inst:interrupt(0xD7) then error("Int failed") end
			-- Dump upper half of frame data
			-- 96 * 32 = 3072 (0xC00)
			for i = 0x2400, 0x2FFF do
				iowr(schar(get(inst, i)))
			end
			ioflush()
			timerval = timer_draw
		else
			--io.stderr:write("Interrupt VBLK_ENTER\n")
			if not inst:interrupt(0xCF) then error("int failed") end
			-- Dump lower half of frame data.
			for i = 0x3000, 0x3FFF do
				iowr(schar(get(inst, i)))
			end
			ioflush()
			buttons1 = sbyte(iord(1))
			buttons2 = sbyte(iord(1))
			timerval = timer_vblank
		end
		nexttimer = timerval
		vblank = not vblank
		--io.stderr:write("Next timer " .. nexttimer .. ", point " .. systmr .. "\n")
	end
end
