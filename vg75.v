module vg75
(
    input           clock,
    output reg      r,
    output reg      g,
    output reg      b,
    output          hs,
    output          vs
);

localparam

    hz_visible = 640, vt_visible = 400,
    hz_front   = 16,  vt_front   = 12,
    hz_sync    = 96,  vt_sync    = 2,
    hz_back    = 48,  vt_back    = 35,
    hz_whole   = 800, vt_whole   = 449;

assign hs = x  < (hz_back + hz_visible + hz_front); // NEG.
assign vs = y >= (vt_back + vt_visible + vt_front); // POS.
// ---------------------------------------------------------------------
wire        xmax = (x == hz_whole - 1);
wire        ymax = (y == vt_whole - 1);
wire        vis  = (x >= hz_back && x < hz_visible + hz_back && y >= vt_back && y < vt_visible + vt_back);
reg  [10:0] x    = 0;
reg  [10:0] y    = 0;
wire [10:0] X    = x - hz_back + 8;     // X=[0..639]
wire [ 9:0] Y    = y - vt_back;         // Y=[0..399]
// ---------------------------------------------------------------------

// Вывод видеосигнала
always @(negedge clock) begin

    // Кадровая развертка
    x <= xmax ?         0 : x + 1;
    y <= xmax ? (ymax ? 0 : y + 1) : y;

    // Вывод окна видеоадаптера
    {r, g, b} <= vis ? ((X[3:0] == 0 || Y[3:0] == 0) ? 3'b111 : 3'b000) : 3'b000;

end

endmodule
