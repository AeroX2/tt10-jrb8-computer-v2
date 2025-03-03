import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge
from cocotb.handle import Force

# TODO: Fine tune this
ALU_CYCLES = 5

async def setup(dut):
    alu = dut.tt_um_aerox2_jrb16_computer.alu_module
    clk = alu.clk

    clock = Clock(clk, 10, units="us")
    cocotb.start_soon(clock.start())

    a = random.randint(-32768, 32767)
    b = random.randint(-32768, 32767)

    alu.a.value = Force(a)
    alu.b.value = Force(b)
    alu.oe.value = Force(1)
    alu.ir.value = Force(0)
    alu.carryin.value = Force(0)

    alu.rst.value = 1
    await Timer(1)
    alu.rst.value = 0
    await Timer(1)

    return alu, clk, a, b

@cocotb.test()
async def test_alu_sanity(dut):
    alu, clk, a, b = await setup(dut)

    alu.a.value = Force(0)
    alu.b.value = Force(0)
    await ClockCycles(clk, ALU_CYCLES)

    assert alu.aluout.value.signed_integer == 0

@cocotb.test()
async def test_alu_flags(dut):
    alu, clk, a, b = await setup(dut)

    # Test flags off
    alu.ir.value = Force(0xBA)  # FLAGS_OFF_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

    # Test flags on
    alu.ir.value = Force(0xBB)  # FLAGS_ON_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

    # Test carry off
    alu.ir.value = Force(0xBC)  # CARRY_OFF_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

    # Test carry on
    alu.ir.value = Force(0xBD)  # CARRY_ON_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

    # Test sign off
    alu.ir.value = Force(0xBE)  # SIGN_OFF_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

    # Test sign on
    alu.ir.value = Force(0xBF)  # SIGN_ON_INS
    alu.start.value = Force(1)
    await ClockCycles(clk, 1)
    alu.start.value = Force(0)
    await RisingEdge(alu.done)

async def test(alu, clk, ir_values, expected_vals, signed=True, extra_f=None):
    for v in enumerate(ir_values):
        alu.ir.value = Force(v[1])
        alu.start.value = Force(1)
        await ClockCycles(clk, 1)
        alu.start.value = Force(0)

        await RisingEdge(alu.done)
        if signed:
            assert alu.aluout.value.signed_integer == expected_vals[v[0]]
        else:
            assert alu.aluout.value.integer == expected_vals[v[0]]
        if extra_f is not None:
            extra_f(alu)

def assert_(cond):
    assert cond

@cocotb.test()
async def test_alu_additions_overflows(dut):
    alu, clk, a, b = await setup(dut)

    # Test addition overflow
    alu.a.value = Force(32767)
    alu.b.value = Force(1)
    await test(alu, clk, [0xEB], [-32768], True, lambda alu: assert_(alu.overout.value == 1))

    # Test subtraction overflow
    alu.a.value = Force(-32768)
    alu.b.value = Force(1)
    await test(alu, clk, [0x123], [32767], True, lambda alu: assert_(alu.overout.value == 1))

@cocotb.test()
async def test_alu_simple(dut):
    alu, clk, a, b = await setup(dut)

    await test(alu, clk, [0xC3+i for i in range(8)], [a for _ in range(8)])

    await test(alu, clk, [0xCB+i for i in range(8)], [~a for _ in range(8)])

    await test(alu, clk, [0xD3+i for i in range(8)], [-a for _ in range(8)])

@cocotb.test()
async def test_alu_plus_minus_one(dut):
    alu, clk, a, b = await setup(dut)

    await test(alu, clk, [0xDB+i for i in range(8)], [a + 1 for _ in range(8)])

    await test(alu, clk, [0xE3+i for i in range(8)], [a - 1 for _ in range(8)])

def gen_rand(cond):
    test = True
    while test:
        a = random.randint(-32768, 32767)
        b = random.randint(-32768, 32767)
        if cond(a, b):
            test = False
    return a, b

@cocotb.test()
async def test_alu_additions(dut):
    alu, clk, a, b = await setup(dut)

    # Test without overflow
    a, b = gen_rand(lambda a, b: a + b >= -32768 and a + b <= 32767)
    alu.a.value = Force(a)
    alu.b.value = Force(b)

    await test(alu, clk, [0xEB+i for i in range(3)], [a + b for _ in range(3)])

    a, b = gen_rand(lambda a, b: a - b >= -32768 and a - b <= 32767)
    alu.a.value = Force(a)
    alu.b.value = Force(b)

    await test(alu, clk, [0x123+i for i in range(3)], [a - b for _ in range(3)])

@cocotb.test()
async def test_alu_mult_div(dut):
    alu, clk, a, b = await setup(dut)

    a = random.randint(1, 32767)
    alu.a.value = Force(a)
    b = random.randint(1, 32767)
    alu.b.value = Force(b)
    v = (a * b) & 0xFFFF
    await test(alu, clk, [0x84+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0x88+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0x8C+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0x90+i for i in range(4)], [v for _ in range(4)], False)

    a = random.randint(1, 32767)
    alu.a.value = Force(a)
    b = random.randint(1, 32767)
    alu.b.value = Force(b)
    v = (a * b) >> 16
    await test(alu, clk, [0x94+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0x98+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0x9C+i for i in range(4)], [v for _ in range(4)], False)
    await test(alu, clk, [0xA0+i for i in range(4)], [v for _ in range(4)], False)

    a = random.randint(1, 32767)
    alu.a.value = Force(a)
    b = random.randint(1, 32767)
    alu.b.value = Force(b)
    v = a // b
    await test(alu, clk, [0xA4+i for i in range(3)], [v for _ in range(3)], False)
    await test(alu, clk, [0xA7+i for i in range(3)], [v for _ in range(3)], False)
    await test(alu, clk, [0xAA+i for i in range(3)], [v for _ in range(3)], False)
    await test(alu, clk, [0xAD+i for i in range(3)], [v for _ in range(3)], False)

@cocotb.test()
async def test_alu_logical(dut):
    alu, clk, a, b = await setup(dut)

    v = (a & 0xFFFF) & (b & 0xFFFF)
    await test(alu, clk, [0x15B+i for i in range(56)], [v for _ in range(56)], False)

    v = (a & 0xFFFF) | (b & 0xFFFF)
    await test(alu, clk, [0x193+i for i in range(56)], [v for _ in range(56)], False)

    v = (a & 0xFFFF) ^ (b & 0xFFFF)
    await test(alu, clk, [0x1CB+i for i in range(56)], [v for _ in range(56)], False)

@cocotb.test()
async def test_alu_shifts(dut):
    alu, clk, a, b = await setup(dut)

    # Test left shift
    a, b = gen_rand(lambda a, b: b > 0 and b < 16)
    alu.a.value = Force(a)
    alu.b.value = Force(b)
    await test(alu, clk, [0x23B+i for i in range(56)], [((a & 0xFFFF) << b) & 0xFFFF for _ in range(56)], False)

    # Right shift instruction (a>>b) 
    a, b = gen_rand(lambda a, b: b > 0 and b < 16)
    print(a,b)
    alu.a.value = Force(a)
    alu.b.value = Force(b)
    await test(alu, clk, [0x203+i for i in range(56)], [((a & 0xFFFF) >> b) & 0xFFFF for _ in range(56)], False)
