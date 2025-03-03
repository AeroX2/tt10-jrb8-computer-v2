import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
from cocotb.handle import Force

IDLE = 0
SEND_COMMAND = 1
SEND_ADDRESS = 2
SEND_DATA = 3
RECEIVE_DATA = 4

QUAD_READ_COMMAND = 0xEB
QUAD_WRITE_COMMAND = 0x32

async def setup(dut):
    qspi = dut.tt_um_aerox2_jrb16_computer.qspi_rom_module
    clk = qspi.clk

    qspi.start.value = Force(0)
    qspi.write.value = Force(0)
    qspi.address.value = 0
    qspi.data_in.value = 0

    clock = Clock(clk, 10, units="us")
    cocotb.start_soon(clock.start())

    qspi.rst.value = Force(1)
    await Timer(1)
    qspi.rst.value = Force(0)
    await Timer(1)

    return qspi, clk

@cocotb.test()
async def test_qspi_idle_state(dut):
    qspi, clk = await setup(dut)

    await ClockCycles(clk, 10)
    assert qspi.qspi_state.value == IDLE
    assert qspi.cs.value == 1
    assert qspi.io_out.value == 0
    assert qspi.busy.value == 0

@cocotb.test()
async def test_qspi_read(dut):
    qspi, clk = await setup(dut)

    address_value = random.randint(0, 0xFFFFFF)
    qspi.address.value = Force(address_value)
    await ClockCycles(clk, 10)

    qspi.start.value = Force(1)
    await ClockCycles(clk, 1)
    await Timer(1)
    assert qspi.qspi_state.value == SEND_COMMAND
    assert qspi.cs.value == 0
    assert qspi.busy.value == 1
    qspi.start.value = Force(0)

    # Verify QUAD READ command
    output = 0
    for i in range(8):
        await RisingEdge(qspi.sclk)
        output = (output << 1) | qspi.io_out[0].value.integer
    assert output == QUAD_READ_COMMAND

    await FallingEdge(qspi.sclk)
    assert qspi.qspi_next_state.value == SEND_ADDRESS

    # Verify address
    output = 0
    for i in range(8):
        await RisingEdge(qspi.sclk)
        output = (output << 4) | qspi.io_out.value.integer
    assert output == address_value

    await FallingEdge(qspi.sclk)
    assert qspi.qspi_next_state.value == RECEIVE_DATA

    # Simulate receiving 32-bit data
    input_value = random.randint(0, 0xFFFFFFFF)
    for i in range(8):  # 32 bits / 4 bits per cycle = 8 cycles
        await RisingEdge(qspi.sclk)
        qspi.io_in.value = (input_value >> (28 - i * 4)) & 0xF

    await ClockCycles(clk, 2)
    assert qspi.data_out.value == input_value
    assert qspi.qspi_state.value == IDLE
    assert qspi.busy.value == 0

@cocotb.test()
async def test_qspi_write(dut):
    qspi, clk = await setup(dut)

    address_value = random.randint(0, 0xFFFFFF)
    data_value = random.randint(0, 0xFFFFFFFF)
    qspi.address.value = Force(address_value)
    qspi.data_in.value = Force(data_value)

    await ClockCycles(clk, 10)
    qspi.start.value = Force(1)
    qspi.write.value = Force(1)
    await ClockCycles(clk, 1)
    await Timer(1)

    assert qspi.qspi_state.value == SEND_COMMAND
    assert qspi.cs.value == 0
    assert qspi.busy.value == 1
    qspi.start.value = Force(0)

    # Verify QUAD WRITE command
    output = 0
    for i in range(2):  # 8 bits / 4 bits per cycle = 2 cycles
        await RisingEdge(qspi.sclk)
        output = (output << 4) | qspi.io_out.value.integer
    assert output == QUAD_WRITE_COMMAND

    await FallingEdge(qspi.sclk)
    assert qspi.qspi_next_state.value == SEND_ADDRESS

    # Verify address
    output = 0
    for i in range(6):  # 24 bits / 4 bits per cycle = 6 cycles
        await RisingEdge(qspi.sclk)
        output = (output << 4) | qspi.io_out.value.integer
    assert output == address_value

    await FallingEdge(qspi.sclk)
    assert qspi.qspi_next_state.value == SEND_DATA

    # Verify data being sent
    output = 0
    for i in range(8):  # 32 bits / 4 bits per cycle = 8 cycles
        await RisingEdge(qspi.sclk)
        output = (output << 4) | qspi.io_out.value.integer
    assert output == data_value

    await ClockCycles(clk, 2)
    assert qspi.qspi_state.value == IDLE
    assert qspi.busy.value == 0