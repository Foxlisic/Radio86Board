#include "obj_dir/Vvg75.h"
#include "tb.h"

int main(int argc, char** argv) {

    int   instr  = 125000;
    float target = 100;

    Verilated::commandArgs(argc, argv);
    TB* tb = new TB(argc, argv);

    while (tb->main()) {

        Uint32 start = SDL_GetTicks();

        // Автоматическая коррекция кол-ва инструкции в секунду
        for (int i = 0; i < instr; i++) tb->tick();

        // Коррекция тактов
        Uint32 delay = (SDL_GetTicks() - start);
        instr = (instr * (0.5 * target) / (float)delay);
        instr = instr < 1000 ? 1000 : instr;
    }

    return tb->destroy();
}
