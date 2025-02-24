module alu (
    input clk,
    input rst,

    // Control
    input start,
    output logic done,

    // Inputs
    input [15:0] a,
    input [15:0] b,
    input [7:0] cins,
    input oe,
    input carryin,

    // Outputs
    output logic carryout,
    output [15:0] aluout,
    output overout,
    output cmpo
);
  localparam CLR_CMP_INS = 'h50;
  localparam CARRY_OFF_INS = 'h51;
  localparam CARRY_ON_INS = 'h52;
  localparam SIGN_OFF_INS = 'h53;
  localparam SIGN_ON_INS = 'h54;

  reg [9:0] alu_rom[0:255];
  initial begin
    $readmemh("../rom/alu_rom.mem", alu_rom);
  end

  logic done_reg;

  logic [9:0] val;
  wire za = val[0];
  wire ia = val[1];
  wire zb = val[2];
  wire ib = val[3];
  wire io = val[4];
  wire po = val[5];
  wire high = val[6];
  wire cmp = val[7];
  wire [1:0] cselect = val[9:8];

  logic [15:0] aandz;
  logic [15:0] bandz;

  logic [15:0] xora;
  logic [15:0] xorb;

  logic [16:0] full_sum;
  logic [15:0] muxoutput;

  logic [31:0] mult;
  logic [15:0] mult_a, mult_b;
  logic [4:0] mult_count;

  wire carried = carry_mode && carryin;

  typedef enum {
    IDLE,
    DECODE,
    ANDZ,
    XORZ,
    SUM,
    AND,
    MULT_INIT,
    MULT_CALC,
    DIV,
    INVERT
  } State;

  State state, next_state;
  logic carry_mode, signed_mode;
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      state <= IDLE;

      done_reg <= 1;
      carry_mode <= 0;
      signed_mode <= 0;

      val <= 0;

      aandz <= 0;
      bandz <= 0;

      xora <= 0;
      xorb <= 0;

      muxoutput <= 0;
    end else if (clk) begin
      state <= next_state;
      case (state)
        IDLE: begin
          if (cins == CARRY_OFF_INS) begin
            done_reg <= ~done_reg;
            carry_mode <= 0;
          end else if (cins == CARRY_ON_INS) begin
            done_reg <= ~done_reg;
            carry_mode <= 1;
          end else if (cins == SIGN_OFF_INS) begin
            done_reg <= ~done_reg;
            signed_mode <= 0;
          end else if (cins == SIGN_ON_INS) begin
            done_reg <= ~done_reg;
            signed_mode <= 1;
          end else if (start) done_reg <= 0;
          else done_reg <= 1;
        end
        DECODE: begin
          val <= alu_rom[cins];
        end
        ANDZ: begin
          aandz <= za ? 0 : a;
          bandz <= zb ? 0 : b;
        end
        XORZ: begin
          xora <= aandz ^ {16{ia}};
          xorb <= bandz ^ {16{ib}};
        end
        SUM: begin
          muxoutput <= full_sum[15:0];
        end
        AND: begin
          muxoutput <= xora & xorb;
        end
        MULT: begin
          MULT_INIT: begin
            mult_a <= xora;
            mult_b <= xorb;
            mult_count <= 0;
            mult <= 0;
            next_state = MULT_CALC;
          end
          MULT_CALC: begin
            if (mult_count < 16) begin
              if (mult_b[mult_count]) begin
                mult <= mult + (mult_a << mult_count);
              end
              mult_count <= mult_count + 1;
              next_state = MULT_CALC;
            end else begin
              muxoutput <= high ? mult[31:16] : mult[15:0];
              next_state = INVERT;
            end
          end
        end
        DIV: begin
          if (signed_mode) begin
            muxoutput <= $signed(xora) / $signed((xorb == 16'h0 ? 16'h1 : xorb));
          end else begin
            muxoutput <= xora / (xorb == 16'h0 ? 16'h1 : xorb);
          end
        end
        INVERT: begin
          muxoutput <= muxoutput ^ {16{io}};
        end
      endcase
    end
  end

  always_comb begin
    done = done_reg;
    next_state = IDLE;

    mult = signed_mode ? $signed(xora) * $signed(xorb) : xora * xorb;
    full_sum = xora + xorb + {15'b0, po} + {15'b0, (carry_mode && cmp) ? carried : 1'b0};

    case (state)
      IDLE: begin
        if (start) next_state = DECODE;
        else next_state = IDLE;
      end
      DECODE: begin
        next_state = ANDZ;
      end
      ANDZ: begin
        next_state = XORZ;
      end
      XORZ: begin
        case (cselect)
          0: next_state = SUM;
          1: next_state = AND;
          2: next_state = MULT_INIT;
          3: next_state = DIV;
        endcase
      end
      SUM: begin
        next_state = INVERT;
      end
      AND: begin
        next_state = INVERT;
      end
      MULT_INIT: begin
        next_state = MULT_CALC;
      end
      MULT_CALC: begin
        if (mult_count < 16) begin
          next_state = MULT_CALC;
        end else begin
          next_state = INVERT;
        end
      end
      DIV: begin
        next_state = INVERT;
      end
      INVERT: begin
        next_state = IDLE;
      end
    endcase
  end

  assign aluout = oe ? muxoutput : 0;
  assign cmpo = (cmp || cins == CLR_CMP_INS) && state == INVERT;

  assign carryout = cselect == 0 ? (((ia | ib) & po) ? !full_sum[16] : full_sum[16]) : 0;
  assign overout = ((~muxoutput[15]) & xora[15] & xorb[15]) | (muxoutput[15] & ~xora[15] & ~xorb[15]);
endmodule
