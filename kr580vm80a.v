/* verilator lint_off WIDTH */
/* verilator lint_off CASEX */
/* verilator lint_off CASEINCOMPLETE */

module KR580VM80ALite
(
    input               clock,
    input               reset_n,
    input               ce,
    output              m0,
    output      [15:0]  address,
    output reg  [ 7:0]  port,
    input       [ 7:0]  in,
    input       [ 7:0]  port_in,
    output reg  [ 7:0]  out,
    output reg          rd,
    output reg          we,
    output reg          port_we,
    output reg          iff1
);

assign address = sw ? cp : pc;
assign m0 = (t == 0);

localparam
    CF = 0, PF = 2, HF = 4, ZF = 6, SF = 7;

localparam
    ADD = 0, ADC = 1, SUB = 2, SBB = 3,
    AND = 4, XOR = 5, OR  = 6, CMP = 7;

// ----------------------------------------------
reg [15:0]  pc;
reg [15:0]  bc  = 16'h10FF,
            de  = 16'hBEEF,
            hl  = 16'hFF13,
            sp  = 16'h00FF;
reg [ 7:0]  a   = 8'h9A,
            //       NZ H P C
            psw = 8'b00000011;
// ----------------------------------------------
reg         sw;     // =1 Адрес указывает на CP, иначе =0 PC
reg [15:0]  cp;     // Адрес для считывания данных из памяти
reg [ 7:0]  opcode; // Сохраненный опкод
reg [ 4:0]  t;      // Исполняемый такт опкода [0..31]
// ----------------------------------------------
reg         b;      // =1 Запись d в 8-битный регистр n
reg         w;      // =1 Запись d в 16-битный регистр n
reg [16:0]  d;      // Данные
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
wire        daa1 = psw[HF] || a[3:0] > 9;
wire        daa2 = psw[CF] || a[7:4] > 9 || (a[7:4] >= 9 && a[3:0] > 9);
wire [3:0]  cond = {psw[SF], psw[PF], psw[CF], psw[ZF]};
wire        ccc  = (cond[ opc[5:4] ] == opc[3]) || (opc == 8'hC9) || (opc == 8'hCD);
// ----------------------------------------------
wire [8:0]  alur =
    opc[5:3] == ADD ? a + op20 :             // ADD
    opc[5:3] == ADC ? a + op20 + psw[CF] :   // ADC
    opc[5:3] == SBB ? a - op20 - psw[CF] :   // SBB
    opc[5:3] == AND ? a & op20 :             // ANA
    opc[5:3] == XOR ? a ^ op20 :             // XRA
    opc[5:3] == OR  ? a | op20 :             // ORA
                      a - op20;              // SUB|CMP

wire sf =   alur[7];
wire zf =   alur[7:0] == 0;
wire hf =   a[4] ^ op20[4] ^ alur[4];
wire af =  (a[4] | op20[4]) & (opc[5:3] == AND);
wire pf = ~^alur[7:0];
wire cf =   alur[8];

wire [7:0] aluf =
    opc[5:3] == AND || opc[5:3] == XOR || opc[5:3] == OR ?
        {sf, zf, 1'b0, af, 1'b0, pf, 1'b1, 1'b0} : // AND, XOR, OR
        {sf, zf, 1'b0, hf, 1'b0, pf, 1'b1,   cf};  // ADD, ADC, SUB, SBB, CMP

always @(posedge clock)
if (reset_n == 0) begin
    t    <= 0;        // Установить чтение кода на начало
    sw   <= 0;        // Позиционировать память к PC
    pc   <= 16'hF800; // Указатель на программу "Монитор"
    iff1 <= 0;        // Отключение прерываний
    rd   <= 1;
end
else if (ce) begin

    t  <= t + 1;    // Счетчик микрооперации
    b  <= 0;        // Выключить запись в регистр (по умолчанию) 8bit
    w  <= 0;        // Выключить запись в регистр (по умолчанию) 16bit
    we <= 0;        // Аналогично, выключить запись в память (по умолчанию)
    rd <= 0;        // Сигнал запроса чтения из памяти
    port_we <= 0;   // Запись в порт

    // Запись опкода на первом такте выполнения инструкции
    if (m0) begin opcode <= in; pc <= pcn; end

    // Исполнение инструкции
    casex (opc)

    // ==========================
    // ДИАПАЗОН ИНСТРУКЦИИ 00-3F
    // ==========================

    // 4T NOP
    8'b0000_0000: case (t)

        3: begin t <= 0; rd <= 1; end

    endcase
    // 10T LXI R,**
    8'b00xx_0001: case (t)

        0: begin rd <= 1; end
        1: begin pc <= pcn; d[ 7:0] <= in; n <= opcode[5:4]; rd <= 1; end
        2: begin pc <= pcn; d[15:8] <= in; w <= 1; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 10T DAD R
    8'b00xx_1001: case (t)

        0: begin d <= hl + r16; w <= 1; n <= 2; end
        1: begin psw[CF] <= d[16]; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 7T STAX B|D
    8'b000x_0010: case (t)

        0: begin we <= 1; out <= a; cp <= r16; sw <= 1; end
        6: begin sw <= 0; t <= 0; rd <= 1; end

    endcase
    // 7T LDAX B|D
    8'b000x_1010: case (t)

        0: begin cp <= r16; sw <= 1; rd <= 1; end
        1: begin b  <= 1; n <= 7; d <= in; end
        6: begin sw <= 0; t <= 0; rd <= 1; end

    endcase
    // 16T [22] SHLD **
    8'b0010_0010: case (t)

        0: begin rd <= 1; end
        1: begin cp[ 7:0] <= in; pc <= pcn; rd <= 1; end
        2: begin cp[15:8] <= in; pc <= pcn; sw <= 1; end
        3: begin we <= 1; out <= hl[ 7:0]; end
        4: begin we <= 1; out <= hl[15:8]; cp <= cpn; end
        15: begin sw <= 0; t <= 0; rd <= 1; end

    endcase
    // 16T [2A] LDHL ** -- Чтение из 16-битного адреса в памяти в HL
    8'b0010_1010: case (t)

        0: begin rd <= 1; end
        1: begin cp[ 7:0] <= in; pc <= pcn; rd <= 1; end
        2: begin cp[15:8] <= in; pc <= pcn; rd <= 1; sw <= 1; end
        3: begin d [ 7:0] <= in; rd <= 1; cp <= cpn; end
        4: begin d [15:8] <= in; w <= 1; n <= 2; sw <= 0; end
        15: begin t <= 0; rd <= 1; end

    endcase
    // 13T [32,3A] STA|LDA ** -- Запись A в 16-битный адрес или чтение в A из 16-битного адреса
    8'b0011_x010: case (t)

        0: begin rd <= 1; end
        1: begin cp[ 7:0] <= in; pc <= pcn; rd <= 1; end
        2: begin cp[15:8] <= in; pc <= pcn; sw <= 1; we <= ~opc[3]; rd <= opc[3]; out <= a; end
        3: begin d <= in; b <= opc[3]; n <= 7; sw <= 0; end
        12: begin t <= 0; rd <= 1; end

    endcase
    // 5T DCX|INX R
    8'b00xx_x011: case (t)

        0: begin w <= 1; n <= in[5:4]; d <= in[3] ? r16 - 1 : r16 + 1; end
        4: begin t <= 0; rd <= 1; end

    endcase
    // 5/10T INR|DCR RM
    8'b00xx_x10x: case (t)

        0: begin cp <= hl; sw <= 1; rd <= 1; end
        1: begin d <= opc[0] ? op53 - 1 : op53 + 1; end
        2: begin

            psw[SF] <= d[7];
            psw[ZF] <= d[7:0] == 0;
            psw[HF] <= d[3:0] == (opc[0] ? 4'hF : 4'h0);
            psw[PF] <= ~^d[7:0];

            n   <= opc[5:3];
            b   <= ~m53;        // Либо в регистр запись
            we  <= m53;         // Либо запись в память
            out <= d;

        end
        4: begin sw <= 0; t <= m53 ? 5 : 0; rd <= m53 ? 0 : 1; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 7T MVI RM,*
    8'b00xx_x110: case (t)

        0: begin rd <= 1; end
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
        6: begin t <= sw ? 7 : 0; sw <= 0; rd <= sw ? 0 : 1; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 4T [07] RLC, [0F] RRC, [17] RAL, [1F] RAR
    8'b000x_x111: case (t)

        0: begin

            b <= 1;
            n <= 7;

            case (opc[4:3])
            2'b00: d <= {a[6:0],  a[7]};    // RLC
            2'b01: d <= {a[0],    a[7:1]};  // RRC
            2'b10: d <= {a[6:0],  psw[CF]}; // RAL
            2'b11: d <= {psw[CF], a[7:1]};  // RAR
            endcase

            psw[CF] <= a[opc[3] ? 0 : 7];

        end

        3: begin t <= 0; rd <= 1; end

    endcase
    // 4T [27] DAA
    8'b0010_0111: case (t)

        0: begin d[15:8] <= (daa1 ? 6 : 0) + (daa2 ? 8'h60 : 0); end
        1: begin d[ 7:0] <= a + d[15:8]; end
        2: begin

            psw[SF] <= d[7];
            psw[ZF] <= d[7:0] == 0;
            psw[HF] <= a[4] ^ d[4] ^ d[12];
            psw[PF] <= ~^d[7:0];
            psw[CF] <= daa2 | psw[0];

            b <= 1;
            n <= 7;

        end
        3: begin t <= 0; rd <= 1; end

    endcase
    // 4T [2F] CMA
    8'b0010_1111: case (t)

        0: begin d <= ~a; b <= 1; n <= 7; end
        3: begin t <= 0; rd <= 1; end

    endcase
    // 4T [37] STC [3F] CMC
    8'b0011_x111: case (t)

        0: begin psw[CF] <= opc[3] ? ~psw[CF] : 1'b1; end
        3: begin t <= 0; rd <= 1; end

    endcase

    // ==========================
    // ДИАПАЗОН ИНСТРУКЦИИ 40-BF
    // ==========================
    // 5/7T MOV x,x
    8'b01xx_xxxx: case (t)

        0: begin cp <= hl; sw <= 1; rd <= m20; if (m53 && m20) pc <= pc; end
        1: begin

            n   <= opc[5:3];
            b   <= !m53;
            we  <=  m53;
            d   <= op20;
            out <= op20;

        end
        4: begin sw <= 0; t <= (m53 || m20) ? 5 : 0; rd <= (m53 || m20) ? 0 : 1; end
        6: begin t <= 0; rd <= 1; end

    endcase
    // 5/7T [ALU] Op
    8'b10xx_xxxx: case (t)

        0: begin cp <= hl; sw <= 1; rd <= m20; end
        1: begin d  <= alur; b <= (opc[5:3] != CMP); n <= 7; psw <= aluf; end
        4: begin sw <= 0; t <= m20 ? 5 : 0; rd <= m20 ? 0 : 1; end
        6: begin t  <= 0; rd <= 1; end

    endcase

    // ==========================
    // ДИАПАЗОН ИНСТРУКЦИИ С0-FF
    // ==========================

    // 5/11T RET ccc
    8'b11xx_x000,
    8'b1100_1001: case (t)

        0:  begin d <= sp + 2; w <= ccc; n <= 3; sw <= 1; cp <= sp; rd <= 1; end
        1:  begin d[ 7:0] <= in; cp <= cpn; rd <= 1; end
        2:  begin d[15:8] <= in; sw <= 0; end
        4:  begin t <= ccc ? 5 : 0; rd <= ccc ? 0 : 1; end
        10: begin t <= 0; pc <= d; rd <= 1; end

    endcase
    // 11T POP
    8'b11xx_0001: case (t)

        0:  begin d <= sp + 2; w <= 1; n <= 3; sw <= 1; cp <= sp; rd <= 1; end
        1:  begin d[ 7:0] <= in; cp <= cpn; rd <= 1;end
        2:  begin d[15:8] <= in; sw <= 0; n <= opc[5:4]; w <= opc[5:4] != 3; end
        3:  begin if (opc[5:4] == 3) begin d[7:0] <= d[15:8]; psw <= d[7:0]; b <= 1; n <= 7; end end
        10: begin t <= 0; rd <= 1; end

    endcase
    // 5T [E9] PCHL
    8'b1110_1001: case (t)

        4: begin pc <= hl; t <= 0; rd <= 1; end

    endcase
    // 5T [F9] SPHL -- Записывается SP в HL (LD HL,SP)
    8'b1111_1001: case (t)

        0: begin d <= hl; w <= 1; n <= 3; end
        4: begin t <= 0; end

    endcase
    // 10T JMP ccc, **
    8'b11xx_x010,
    8'b1100_0011: case (t)

        0: begin rd <= 1; end
        1: begin cp[ 7:0] <= in; pc <= pcn; rd <= 1;end
        2: begin cp[15:8] <= in; pc <= pcn; end
        9: begin t <= 0; rd <= 1; if (ccc || opc[0]) pc <= cp; end

    endcase
    // 4T DI, EI
    8'b1111_x011: case (t)

        0: begin iff1 <= opc[3]; end
        3: begin t <= 0; rd <= 1; end

    endcase
    // 10T OUT (*), A
    8'b1101_0011: case (t)

        0: begin rd <= 1; end
        1: begin port <= in; port_we <= 1; out <= a; pc <= pcn; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 10T IN A, (*)
    8'b1101_1011: case (t)

        0: begin rd <= 1; end
        1: begin port <= in; pc <= pcn; end
        2: begin b <= 1; n <= 7; d <= port_in; end
        9: begin t <= 0; rd <= 1; end

    endcase
    // 18T XTHL -- EX (SP),HL -- Обмен вершины стека с HL
    8'b1110_0011: case (t)

        0: begin sw <= 1; cp <= sp; rd <= 1; end
        1: begin d[ 7:0] <= in; cp <= cpn; rd <= 1; end
        2: begin d[15:8] <= in; w <= 1; n <= 2; cp <= hl; end
        3: begin we <= 1; out <= cp[7:0]; d[7:0] <= cp[15:8]; cp <= sp; end
        4: begin we <= 1; out <= d[7:0]; cp <= cpn; end
        17: begin sw <= 0; t <= 0; rd <= 1; end

    endcase
    // 4T XCHG -- EX DE,HL
    8'b1110_1011: case (t)

        0: begin d <= de; n <= 2; w <= 1; cp <= hl; end
        1: begin d <= cp; n <= 1; w <= 1; end
        3: begin t <= 0; rd <= 1; end

    endcase
    // 11/17T CALL ccc
    8'b11xx_x100,
    8'b1100_1101: case (t)

        0: begin rd <= 1; end
        1: begin d[ 7:0] <= in; pc <= pcn; rd <= 1; end
        2: begin d[15:8] <= in; pc <= pcn; end
        3: begin we <= ccc; out <= pc[ 7:0]; sw <= 1; cp <= sp - 2; end
        4: begin we <= ccc; out <= pc[15:8]; cp <= cpn; end
        5: begin if (ccc) pc <= d[15:0]; end
        6: begin w <= ccc; d <= sp - 2; n <= 3; end
        10: begin t <= ccc ? 11 : 0; rd <= ccc ? 0 : 1;end
        16: begin t <= 0; rd <= 1; end

    endcase
    // 11T PUSH
    8'b11xx_0101: case (t)

        0: begin d <= sp - 2; w <= 1; n <= 3; sw <= 1; cp <= sp - 2; end
        1: begin d <= opc[5:4] == 2'b11 ? {a, (psw & 8'b11010101) | 2'b10} : r16; end
        2: begin we <= 1; out <= d[ 7:0]; end
        3: begin we <= 1; out <= d[15:8]; cp <= cpn; end
        10: begin sw <= 0; t <= 0; rd <= 1; end

    endcase
    // 7T [ALU] Imm
    8'b11xx_x110: case (t)

        0: begin rd <= 1; end
        1: begin d <= alur; pc <= pcn; b <= (opc[5:3] != CMP); n <= 7; psw <= aluf; end
        6: begin t <= 0; end

    endcase
    // 11T RST
    8'b11xx_x111: case (t)

        1: begin we <= 1; d <= sp - 2; n <= 3; w <= 1; cp <= sp - 2; sw <= 1; out <= pc[7:0]; end
        2: begin we <= 1; out <= pc[15:8]; cp <= cpn; pc <= {opc[5:3], 3'b000}; end
        10: begin sw <= 0; t <= 0; rd <= 1; end

    endcase

    endcase

end

// Запись данных в регистры
always @(posedge clock)
if (reset_n && ce) begin

    // 8-bit
    if (b)
    case (n)
    0: bc[15:8] <= d[7:0]; 1: bc[ 7:0] <= d[7:0]; // BC
    2: de[15:8] <= d[7:0]; 3: de[ 7:0] <= d[7:0]; // DE
    4: hl[15:8] <= d[7:0]; 5: hl[ 7:0] <= d[7:0]; // HL
    7:  a       <= d[7:0];
    endcase

    // 16-bit
    if (w)
    case (n)
    2'b00: bc <= d[15:0];
    2'b01: de <= d[15:0];
    2'b10: hl <= d[15:0];
    2'b11: sp <= d[15:0];
    endcase

end

endmodule
