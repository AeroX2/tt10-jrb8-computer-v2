module cmp (
    input [15:0] cmpin,
    input we,
    input overflow,
    input carry,
    input clk,
    input rst,
    output logic zflag,
    output logic oflag,
    output logic cflag,
    output logic sflag
);
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      zflag <= 0;
      oflag <= 0;
      cflag <= 0;
      sflag <= 0;
    end else if (we) begin
      zflag <= cmpin == 0;
      oflag <= overflow;
      cflag <= carry;
      sflag <= cmpin[15];
    end
  end
endmodule
