`default_nettype none

module qspi (
    input clk,
    input rst,

    // QSPI wiring
    output logic sclk,
    output logic cs,
    output logic [3:0] io_out,
    input [3:0] io_in,

    // Control
    input start,
    input write,
    output logic busy,

    input [23:0] address,

    input [31:0] data_in,
    output logic [31:0] data_out
);

  // Constants
  localparam QUAD_READ_COMMAND = 'hEB;
  localparam QUAD_WRITE_COMMAND = 'h32;

  // States
  typedef enum {
    IDLE,
    SEND_COMMAND,
    SEND_ADDRESS,
    SEND_DATA,
    RECEIVE_DATA
  } State;

  // Registers
  State qspi_state, qspi_next_state;
  logic [4:0]  shift_counter;
  logic        sclk_reg;

  logic [31:0] qspi_in_reg;
  logic [31:0] qspi_out_reg;

  // State transition and control logic
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      qspi_state <= IDLE;
      shift_counter <= 0;
      sclk_reg <= 0;
      qspi_in_reg <= 0;
    end else begin
      qspi_state <= qspi_next_state;
      case (qspi_state)
        IDLE: begin
          sclk_reg <= 0;
          shift_counter <= 0;

          if (start) begin
            sclk_reg <= 0;
            shift_counter <= 7;
          end
        end
        SEND_COMMAND: begin
          sclk_reg <= ~sclk_reg;
          if (sclk_reg) begin
            shift_counter <= shift_counter - 1;
            if (shift_counter == 0) begin
              shift_counter <= 23;
            end
          end
        end
        SEND_ADDRESS: begin
          sclk_reg <= ~sclk_reg;
          if (sclk_reg) begin
            shift_counter <= shift_counter - 1;
            if (shift_counter == 0) begin
              shift_counter <= 7;
            end
          end
        end
        SEND_DATA: begin
          sclk_reg <= ~sclk_reg;
          if (sclk_reg) begin
            shift_counter <= shift_counter - 1;
          end
        end
        RECEIVE_DATA: begin
          sclk_reg <= ~sclk_reg;
          if (sclk_reg) begin
            shift_counter <= shift_counter - 1;
            qspi_in_reg[shift_counter -: 4] <= io_in;
          end
        end
      endcase
    end
  end

  always_comb begin
    qspi_out_reg = 0;
    qspi_next_state = IDLE;
    busy = (qspi_state != IDLE);

    case (qspi_state)
      IDLE: begin
        if (write || !write) qspi_next_state = SEND_COMMAND;
        else qspi_next_state = IDLE;
      end
      SEND_COMMAND: begin
        if (write) qspi_out_reg = QUAD_WRITE_COMMAND;
        else qspi_out_reg = QUAD_READ_COMMAND;

        if ((shift_counter == 0 && sclk))
          qspi_next_state = SEND_ADDRESS;
        else qspi_next_state = SEND_COMMAND;
      end
      SEND_ADDRESS: begin
        qspi_out_reg = {8'b0, address};
        if ((shift_counter == 0 && sclk)) begin
          if (write) qspi_next_state = SEND_DATA;
          else qspi_next_state = RECEIVE_DATA;
        end else qspi_next_state = SEND_ADDRESS;
      end
      SEND_DATA: begin
        qspi_out_reg = data_in;
        if ((shift_counter == 0 && sclk)) qspi_next_state = IDLE;
        else qspi_next_state = SEND_DATA;
      end
      RECEIVE_DATA: begin
        if ((shift_counter == 0 && sclk)) qspi_next_state = IDLE;
        else qspi_next_state = RECEIVE_DATA;
      end
    endcase
  end

  always_comb begin
    sclk = sclk_reg;
    data_out = qspi_in_reg;

    cs = 1;
    io_out = 4'b0000;
    if (qspi_state != IDLE) begin
      cs = 0;

      if (qspi_state != RECEIVE_DATA) begin
        io_out = qspi_out_reg[shift_counter[2:0] * 4 +: 4];
      end
    end
  end
endmodule