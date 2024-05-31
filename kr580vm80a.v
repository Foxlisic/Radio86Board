module KR580VM80ALite
(
    input               clock,
    input               reset_n,
    input               ce,
    output              m0,
    output      [15:0]  address,
    input       [ 7:0]  in,
    output reg  [ 7:0]  out,
    output reg          we
);

assign address = sw ? cp : pc;
assign m0 = (t == 0);

// ----------------------------------------------
reg [15:0]  pc;
reg [15:0]  bc  = 16'hDEFF,
            de  = 16'hBEEF,
            hl  = 16'h1234,
            sp  = 16'h00FF;
reg [ 7:0]  a   = 8'hAF,
            psw = 8'b00000010;
// ----------------------------------------------
reg         sw;     // =1 Адрес указывает на CP, иначе =0 PC
reg [15:0]  cp;     // Адрес для считывания данных из памяти
reg [ 7:0]  opcode; // Сохраненный опкод
reg [ 4:0]  t;      // Исполняемый такт опкода [0..31]
// ----------------------------------------------
reg         b;      // =1 Запись d в 8-битный регистр n
reg         w;      // =1 Запись d в 16-битный регистр n
reg [15:0]  d;      // Данные
reg [ 2:0]  n;      // Номер регистра для записи
// ----------------------------------------------
wire [ 7:0] opc = t ? opcode : in;
wire [15:0] r16 =
    opc[5:4] == 2'b00 ? bc :
    opc[5:4] == 2'b01 ? de :
    opc[5:4] == 2'b10 ? hl : sp;

// Выбор 8-битного регистра
wire [ 7:0] op53 =
    opc[5:3] == 3'b000 ? bc[15:8] : opc[5:3] == 3'b001 ? bc[ 7:0] :
    opc[5:3] == 3'b010 ? de[15:8] : opc[5:3] == 3'b011 ? de[ 7:0] :
    opc[5:3] == 3'b100 ? hl[15:8] : opc[5:3] == 3'b101 ? hl[ 7:0] :
    opc[5:3] == 3'b110 ? in       : a;

wire [ 7:0] op20 =
    opc[2:0] == 3'b000 ? bc[15:8] : opc[2:0] == 3'b001 ? bc[ 7:0] :
    opc[2:0] == 3'b010 ? de[15:8] : opc[2:0] == 3'b011 ? de[ 7:0] :
    opc[2:0] == 3'b100 ? hl[15:8] : opc[2:0] == 3'b101 ? hl[ 7:0] :
    opc[2:0] == 3'b110 ? in       : a;
// ----------------------------------------------
wire [15:0] pcn = pc + 1;
wire [15:0] cpn = cp + 1;
wire        m53 = opc[5:3] == 3'b110;
wire        m20 = opc[2:0] == 3'b110;
// ----------------------------------------------

always @(posedge clock)
if (reset_n == 0) begin
    t  <= 0;        // Установить чтение кода на начало
    sw <= 0;        // Позиционировать память к PC
    pc <= 16'hF800; // Указатель на программу "Монитор"
end
else if (ce) begin

    t  <= t + 1;      // Счетчик микрооперации
    b  <= 0;          // Выключить запись в регистр (по умолчанию) 8bit
    w  <= 0;          // Выключить запись в регистр (по умолчанию) 16bit
    we <= 0;          // Аналогично, выключить запись в память (по умолчанию)

    // Запись опкода на первом такте выполнения инструкции
    if (m0) begin opcode <= in; pc <= pcn; end

    // Исполнение инструкции
    casex (opc)
    // 4T NOP
    8'b0000_0000: case (t)

        3: begin t <= 0; end

    endcase
    // 10T LXI R,**
    8'b00xx_0001: case (t)

        1: begin pc <= pcn; d[ 7:0] <= in; n <= opcode[5:4]; end
        2: begin pc <= pcn; d[15:8] <= in; w <= 1; end
        9: begin t <= 0; end

    endcase
    // 7T STAX B|D
    8'b000x_0010: case (t)

        0: begin we <= 1; out <= a; cp <= r16; sw <= 1; end
        6: begin sw <= 0; t <= 0; end

    endcase
    // 7T LDAX B|D
    8'b000x_1010: case (t)

        0: begin cp <= r16; sw <= 1; end
        1: begin b  <= 1; n <= 7; d <= in; end
        6: begin sw <= 0; t <= 0; end

    endcase
    // 16T [22] SHLD **
    8'b0010_0010: case (t)

        1: begin cp[ 7:0] <= in; pc <= pcn; end
        2: begin cp[15:8] <= in; pc <= pcn; sw <= 1; end
        3: begin we <= 1; out <= hl[ 7:0]; end
        4: begin we <= 1; out <= hl[15:8]; cp <= cpn; end
        15: begin sw <= 0; t <= 0; end

    endcase
    // 16T [2A] LDHL **
    8'b0010_1010: case (t)

        1: begin cp[ 7:0] <= in; pc <= pcn; end
        2: begin cp[15:8] <= in; pc <= pcn; sw <= 1; end
        3: begin d [ 7:0] <= in; cp <= cpn; end
        4: begin d [15:8] <= in; w <= 1; n <= 2; end
        15: begin sw <= 0; t <= 0; end

    endcase
    // 13T [32,3A] STA|LDA **
    8'b0011_x010: case (t)

        1: begin cp[ 7:0] <= in; pc <= pcn; end
        2: begin cp[15:8] <= in; pc <= pcn; sw <= 1; we <= ~opc[3]; out <= a; end
        3: begin d <= in; b <= opc[3]; n <= 7; sw <= 0; end
        12: begin t <= 0; end

    endcase
    // 5T DCX|INX R
    8'b00xx_x011: case (t)

        0: begin w <= 1; n <= in[5:4]; d <= in[3] ? r16 - 1 : r16 + 1; end
        4: begin t <= 0; end

    endcase
    // 7T MVI RM,*
    8'b00xx_x110: case (t)

        1: begin

            pc  <= pcn;      // PC = PC + 1
            cp  <= hl;       // Указатель HL
            n   <= opc[5:3]; // Номер регистра
            b   <= !m53;     // Запись в регистр, если не M
            we  <= m53;      // Запись в память,  если M
            sw  <= m53;      // Активация указателя CP
            d   <= in;       // Данные для записи в регистр
            out <= in;       // Данные для записи в память

        end
        6: begin t <= sw ? 7 : 0; sw <= 0; end
        9: begin t <= 0; end

    endcase

    endcase

end

// Запись данных в регистры
always @(posedge clock)
if (reset_n && ce) begin

    // 8-bit
    if (b)
    case (n)
    0: bc[15:8] <= d[7:0];  // B
    1: bc[ 7:0] <= d[7:0];  // C
    2: de[15:8] <= d[7:0];  // D
    3: de[ 7:0] <= d[7:0];  // E
    4: hl[15:8] <= d[7:0];  // H
    5: hl[ 7:0] <= d[7:0];  // L
    7:  a       <= d[7:0];  // A
    endcase

    // 16-bit
    if (w)
    case (n)
    2'b00: bc <= d;
    2'b01: de <= d;
    2'b10: hl <= d;
    2'b11: sp <= d;
    endcase

end

endmodule
