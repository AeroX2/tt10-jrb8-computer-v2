import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.handle import Force


async def setup(dut):
    jmp = dut.tt_um_aerox2_jrb16_computer.jmp_module
    clk = jmp.clk

    clock = Clock(clk, 10, units="us")
    cocotb.start_soon(clock.start())

    jmp.rst.value = 1
    await ClockCycles(clk, 1)
    jmp.rst.value = 0
    await ClockCycles(clk, 1)

    return jmp, clk


async def jmp_tick(jmp, clk):
    pc_value = random.randint(0,65536)
    jmp.databus.value = Force(pc_value)
    await ClockCycles(clk, 1)
    await Timer(1)
    assert jmp.pcoe.value == 0

    jmp.oe.value = Force(1)
    await ClockCycles(clk, 1)

    return pc_value


@cocotb.test()
async def test_jmp_sanity(dut):
    jmp, clk = await setup(dut)

    jmp.oe.value = Force(0)
    await ClockCycles(clk, 10)

    assert jmp.pcoe.value == 0
    assert jmp.pcout.value == 0


@cocotb.test()
async def test_jmp_jumps_correctly(dut):
    jmp, clk = await setup(dut)

    # No condition, always jump
    jmp.ir.value = Force(0x99)
    pc_out = await jmp_tick(jmp, clk)
    assert jmp.pcoe.value == 1
    assert jmp.pcout.value == pc_out


@cocotb.test()
async def test_jmp_conditions(dut):
    jmp, clk = await setup(dut)

    # = condition
    jmp.ir.value = Force(0x9A)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.zflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # != condition
    jmp.ir.value = Force(0x9B)
    jmp.zflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

@cocotb.test()
async def test_jmp_less_conditions(dut):
    jmp, clk = await setup(dut)

    # < condition
    jmp.ir.value = Force(0x9C)
    jmp.cflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.cflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # <= condition
    jmp.ir.value = Force(0x9D)
    jmp.cflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.cflag.value = Force(1)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1
    jmp.cflag.value = Force(0)
    jmp.zflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

@cocotb.test()
async def test_jmp_greater_conditions(dut):
    jmp, clk = await setup(dut)

    # > condition
    jmp.ir.value = Force(0x9E)
    jmp.cflag.value = Force(1)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.cflag.value = Force(0)
    jmp.zflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.cflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # >= condition
    jmp.ir.value = Force(0x9F)
    jmp.cflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.cflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

@cocotb.test()
async def test_jmp_signed_conditions(dut):
    jmp, clk = await setup(dut)

    # Signed < condition
    jmp.ir.value = Force(0xA0)
    jmp.oflag.value = Force(0)
    jmp.sflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.oflag.value = Force(1)
    jmp.sflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # Signed <= condition
    jmp.ir.value = Force(0xA1)
    jmp.oflag.value = Force(0)
    jmp.sflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.oflag.value = Force(1)
    jmp.sflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1
    jmp.oflag.value = Force(0)
    jmp.sflag.value = Force(0)
    jmp.zflag.value = Force(1)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # Signed > condition
    jmp.ir.value = Force(0xA2)
    jmp.oflag.value = Force(1)
    jmp.sflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.oflag.value = Force(0)
    jmp.sflag.value = Force(0)
    jmp.zflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

    # Signed >= condition
    jmp.ir.value = Force(0xA3)
    jmp.oflag.value = Force(1)
    jmp.sflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 0
    jmp.oflag.value = Force(0)
    jmp.sflag.value = Force(0)
    await ClockCycles(clk, 1)
    assert jmp.pcoe.value == 1

