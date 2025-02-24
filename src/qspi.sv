module qspi (
    input clk,
    input rst,

    input [7:0] databus,

    // Control
    input write,
    input [23:0] address,
    output logic [7:0] data,
    output logic busy,  // Indicates QSPI is performing an operation

    // QSPI
    output logic sclk,
    output logic cs,
    output logic [3:0] io_out,
    input [3:0] io_in
);

  // Constants
  localparam QUAD_READ_COMMAND = 'hEB;
  localparam QUAD_WRITE_COMMAND = 'h32;
  localparam PREFETCH_BUFFER_SIZE = 4;
  localparam WRITE_QUEUE_SIZE = 4;

  // States
  typedef enum {
    IDLE,
    SEND_COMMAND,
    SEND_ADDRESS,
    SEND_DATA,
    RECEIVE_DATA,
    PREFETCH
  } State;

  // Registers
  State spi_state, spi_next_state;

  logic [ 4:0] shift_counter;
  logic [ 7:0] data_reg;

  logic        done_reg;
  logic        sclk_reg;
  logic [23:0] data_out_reg;

  // Prefetch buffer
  logic [7:0] prefetch_buffer [PREFETCH_BUFFER_SIZE-1:0];
  logic [23:0] prefetch_addresses [PREFETCH_BUFFER_SIZE-1:0];
  logic [$clog2(PREFETCH_BUFFER_SIZE):0] prefetch_count;
  logic [$clog2(PREFETCH_BUFFER_SIZE)-1:0] prefetch_read_ptr;
  logic [$clog2(PREFETCH_BUFFER_SIZE)-1:0] prefetch_write_ptr;

  // Write queue
  logic [7:0] write_data_queue [WRITE_QUEUE_SIZE-1:0];
  logic [23:0] write_addr_queue [WRITE_QUEUE_SIZE-1:0];
  logic [$clog2(WRITE_QUEUE_SIZE):0] write_queue_count;
  logic [$clog2(WRITE_QUEUE_SIZE)-1:0] write_queue_read_ptr;
  logic [$clog2(WRITE_QUEUE_SIZE)-1:0] write_queue_write_ptr;

  // State transition and control logic
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      spi_state <= IDLE;
      done_reg <= 1;
      data_reg <= 0;
      shift_counter <= 0;
      sclk_reg <= 0;
      
      // Reset prefetch buffer
      prefetch_count <= 0;
      prefetch_read_ptr <= 0;
      prefetch_write_ptr <= 0;
      
      // Reset write queue
      write_queue_count <= 0;
      write_queue_read_ptr <= 0;
      write_queue_write_ptr <= 0;
    end else begin
      spi_state <= spi_next_state;
      case (spi_state)
        IDLE: begin
          done_reg <= 1;
          sclk_reg <= 0;
          shift_counter <= 0;

          // Start new operation if needed
          if (write && write_queue_count < WRITE_QUEUE_SIZE) begin
            // Queue write operation
            write_data_queue[write_queue_write_ptr] <= databus;
            write_addr_queue[write_queue_write_ptr] <= address;
            write_queue_write_ptr <= write_queue_write_ptr + 1;
            write_queue_count <= write_queue_count + 1;
            done_reg <= 1;  // Write queued successfully
          end else if (!write && prefetch_count < PREFETCH_BUFFER_SIZE) begin
            // Start prefetch if buffer not full
            spi_state <= PREFETCH;
            done_reg <= 0;
            sclk_reg <= 0;
            shift_counter <= 7;
          end else if (write_queue_count > 0) begin
            // Process queued write
            done_reg <= 0;
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
            data_reg[shift_counter[2:0]] <= io_in[0];
          end
        end
      endcase
    end
  end

  always_comb begin
    data_out_reg = 0;
    spi_next_state = IDLE;
    busy = (spi_state != IDLE) || (write_queue_count > 0) || (prefetch_count < PREFETCH_BUFFER_SIZE);

    case (spi_state)
      IDLE: begin
        if (write_queue_count > 0) spi_next_state = SEND_COMMAND;
        else if (prefetch_count < PREFETCH_BUFFER_SIZE) spi_next_state = PREFETCH;
        else spi_next_state = IDLE;
      end
      SEND_COMMAND: begin
        if (write) data_out_reg = QUAD_WRITE_COMMAND;
        else data_out_reg = QUAD_READ_COMMAND;
        if ((shift_counter == 0 && sclk))
          spi_next_state = SEND_ADDRESS;
        else spi_next_state = SEND_COMMAND;
      end
      SEND_ADDRESS: begin
        data_out_reg = address;
        if ((shift_counter == 0 && sclk)) begin
          if (write) spi_next_state = SEND_DATA;
          else spi_next_state = RECEIVE_DATA;
        end else spi_next_state = SEND_ADDRESS;
      end
      SEND_DATA: begin
        data_out_reg = {16'h00, databus};
        if ((shift_counter == 0 && sclk)) spi_next_state = IDLE;
        else spi_next_state = SEND_DATA;
      end
      RECEIVE_DATA: begin
        if ((shift_counter == 0 && sclk)) spi_next_state = IDLE;
        else spi_next_state = RECEIVE_DATA;
      end
    endcase
  end

  always_comb begin
    done = done_reg;
    sclk = sclk_reg;
    
    // Output from prefetch buffer if available, otherwise use data_reg
    if (prefetch_count > 0 && !write) begin
      data = prefetch_buffer[prefetch_read_ptr];
    end else begin
      data = data_reg;
    end

    cs = 1;
    io_out = 4'b0000;
    if (spi_state != IDLE) begin
      cs = 0;

      if (spi_state != RECEIVE_DATA) begin
        io_out[3:0] = data_out_reg[{shift_counter[4:2], 2'b11}:shift_counter[4:2]*4];
      end
    end
  end

  // Update prefetch buffer read pointer when data is read
  always_ff @(posedge clk) begin
    if (!write && prefetch_count > 0 && done_reg) begin
      prefetch_read_ptr <= prefetch_read_ptr + 1;
      prefetch_count <= prefetch_count - 1;
    end
  end
endmodule