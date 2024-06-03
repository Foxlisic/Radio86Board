`timescale 10ns / 1ns
module tb;
// ---------------------------------------------------------------------
reg reset_n = 0, clock_100 = 1, clock_25 = 0;
// ---------------------------------------------------------------------
always #0.5 clock_100 = ~clock_100;  // Генератор частоты 100 мгц
always #2.0 clock_25  = ~clock_25;   // И 25 мгц
// ---------------------------------------------------------------------
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
initial begin #2.5 reset_n = 1; #2000 $finish; end
// ---------------------------------------------------------------------
reg  [ 7:0] memory[65536];
wire [15:0] address;
wire [ 7:0] in = memory[address];
wire [ 7:0] out;
wire        we, iff1;

initial $readmemh("tb.hex", memory, 16'hF800);
always @(posedge clock_100) if (we) memory[address] <= out;
// ---------------------------------------------------------------------

KR580VM80ALite CORE
(
    .clock      (clock_25),
    .reset_n    (reset_n),
    .ce         (1'b1),
    .address    (address),
    .in         (in),
    .port_in    (8'hFF),
    .out        (out),
    .we         (we),
    .iff1       (iff1)
);

endmodule
