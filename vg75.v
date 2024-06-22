/* verilator lint_off WIDTH */
/* verilator lint_off CASEINCOMPLETE */
/* verilator lint_off CASEX */

module vg75
(
    input               clock,          // 25 Мгц тактовый генератор
    input               reset_n,        // Сброс чипа на =0
    output reg          r,
    output reg          g,
    output reg          b,
    output              hs,
    output              vs,
    // Порты и так далее
    input      [15:0]   cpu_address,
    input      [ 7:0]   cpu_out,
    input               cpu_we,
    input               cpu_rd,
    // Интерфейс взаимодействия с видеопамятью
    output reg [15:0]   address,        // Указатель на адрес в памяти
    output reg [10:0]   font_address,   // Указатель на FONT-ROM
    input       [7:0]   in,             // Считывание из памяти
    input       [7:0]   font_in         // Считывание из знакогенератора
);

localparam

    hz_visible = 640, vt_visible = 400,
    hz_front   = 16,  vt_front   = 12,
    hz_sync    = 96,  vt_sync    = 2,
    hz_back    = 48,  vt_back    = 35,
    hz_whole   = 800, vt_whole   = 449;

localparam

    LOAD_CURSOR = 1,
    DISPLAY_OFF = 2;

// -----------------------------------------------------------------------------
assign hs = x  < (hz_back + hz_visible + hz_front); // NEG.
assign vs = y >= (vt_back + vt_visible + vt_front); // POS.
// -----------------------------------------------------------------------------
wire        xmax = (x == hz_whole - 1);
wire        ymax = (y == vt_whole - 1);
wire        vis  = (x >= hz_back && x < hz_visible + hz_back && y >= vt_back && y < vt_visible + vt_back);
// -----------------------------------------------------------------------------
reg  [10:0] x    = 0;
reg  [10:0] y    = 0;
reg  [ 2:0] cnt_xfine;  // 0..7
reg  [ 3:0] cnt_yfine;  // 0..9
reg  [ 6:0] cnt_x;      // 0..79
reg  [ 5:0] cnt_y;      // 0..29
reg         flash;      // Состояние курсора
reg  [ 5:0] frame;      // Количество фреймов
reg  [ 7:0] mask;       // Строка знакоместа
// -----------------------------------------------------------------------------
reg         display;
reg  [ 2:0] cmd;
reg  [ 2:0] cmd_cnt;
// -----------------------------------------------------------------------------
reg  [ 6:0] cursor_x;
reg  [ 5:0] cursor_y;
reg  [15:0] base_address;
reg  [ 2:0] sym_height;
reg  [ 1:0] sym_gap;
// -----------------------------------------------------------------------------
wire [ 7:0] cursor_area =
    (cursor_x == cnt_x && cursor_y == cnt_y) &&
    (flash && cnt_yfine > sym_height) ?
        8'hFF : 8'h00;
// -----------------------------------------------------------------------------

// Вывод видеосигнала
always @(negedge clock)
if (reset_n == 0) begin

    base_address <= 16'hE6A0;
    sym_height   <= 7; // 8 px высота символа
    sym_gap      <= 2; // 2 px междустрочный интервал
    cursor_x     <= 0;
    cursor_y     <= 0;
    display      <= 1;

end
else begin

    // Кадровая развертка
    x <= xmax ?         0 : x + 1;
    y <= xmax ? (ymax ? 0 : y + 1) : y;

    // Фрейм и курсор
    if (xmax && ymax) begin

        frame <= (frame == 29) ? 0 : frame + 1;
        if (frame == 29) flash <= ~flash;

    end

    // Вывод окна видеоадаптера
    {r, g, b} <= display & vis & mask[5 - cnt_xfine] ? 3'b111 : 3'b000;

    // По ширине
    if (x >= hz_back + 74 && x < hz_back + 79 + (80*6) && y >= vt_back + 50 && cnt_y < 30) begin

        // [0..5] т.е. 6 пикселей по ширине
        cnt_xfine <= cnt_xfine + 1;

        case (cnt_xfine)
        0: begin address      <= cnt_x + (80*cnt_y) + base_address; end
        1: begin font_address <= {in, cnt_yfine[2:0]}; end
        5: begin

            mask      <= (cnt_yfine > sym_height ? cursor_area : font_in);
            cnt_xfine <= 0;
            cnt_x     <= cnt_x + 1;

        end
        endcase

    end
    // Сброс счетчика X вне зоны рисования
    else begin

        cnt_xfine <= 0;
        cnt_x     <= 0;
        mask      <= 0;

        if (xmax) begin

            if (y >= vt_back + 50 && cnt_y < 30) begin

                // 10 пикселей по высоте
                cnt_yfine <= (cnt_yfine == (sym_height + sym_gap) ? 0 : cnt_yfine + 1);

                // К следующему символу
                if (cnt_yfine == (sym_height + sym_gap)) cnt_y <= cnt_y + 1;

            end

            // Отрисовал экран, и вернуть на место все
            if (ymax) begin cnt_y <= 0; cnt_yfine <= 0; end

        end

    end

    // Обработка данных
    if (cpu_we) begin

        // Загрузка команды
        if (cpu_address == 16'hC001) begin

            casex (cpu_out)
            8'b001x_xxxx: begin cmd <= DISPLAY_OFF; cmd_cnt <= 0; display <= |cpu_out[4:0]; end
            8'b1000_0000: begin cmd <= LOAD_CURSOR; cmd_cnt <= 0; end
            endcase

        end
        // Загрузка данных
        else if (cpu_address == 16'hC000) begin

            case (cmd)

                LOAD_CURSOR: case (cmd_cnt)
                0: begin cmd_cnt <= 1; cursor_x <= cpu_out; end
                1: begin cmd_cnt <= 0; cursor_y <= cpu_out; end
                endcase

            endcase

        end

    end

end

endmodule
