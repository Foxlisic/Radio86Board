#include <SDL2/SDL.h>
#include "fontrom.h"

class TB {

protected:

    int width, height, scale, frame_length, pticks;
    int x, y, _hs, _vs;

    SDL_Surface*        screen_surface;
    SDL_Window*         sdl_window;
    SDL_Renderer*       sdl_renderer;
    SDL_PixelFormat*    sdl_pixel_format;
    SDL_Texture*        sdl_screen_texture;
    SDL_Event           evt;
    Uint32*             screen_buffer;

    // E000...EFFF Video data (80x30 = 2400)
    // F000...F7FF [Reserved mon]
    // F800...FFFF Monitor
    uint8_t memory[65536]; // 64Kb

    // Модули
    Vvg75* vg75_mod;
    Vkr580vm80a* core8080;

public:

    TB(int argc, char** argv) {

        x   = 0;
        y   = 0;
        _hs = 1;
        _vs = 0;

        pticks       = 0;
        vg75_mod     = new Vvg75();
        core8080     = new Vkr580vm80a();

        // Удвоение пикселей
        scale        = 2;
        width        = 640;
        height       = 400;
        frame_length = 50;      // 20 кадров в секунду

        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
            exit(1);
        }

        SDL_ClearError();
        sdl_window          = SDL_CreateWindow("SDL2", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, scale*width, scale*height, SDL_WINDOW_SHOWN);
        sdl_renderer        = SDL_CreateRenderer(sdl_window, -1, SDL_RENDERER_PRESENTVSYNC);
        screen_buffer       = (Uint32*) malloc(width * height * sizeof(Uint32));
        sdl_screen_texture  = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, width, height);
        SDL_SetTextureBlendMode(sdl_screen_texture, SDL_BLENDMODE_NONE);

        // Инициализация памяти
        for (int i = 0; i < 2400; i++) {
            memory[0xE6A0 + i] = (1*i) & 255;
        }

        // Загрузка MONITOR в память
        if (argc > 1) {
            FILE* fp = fopen(argv[1], "rb");
            if (fp) {
                fread(memory + 0xF800, 1, 2048, fp);
                fclose(fp);
            }
        }

        // Сброс видеоконтроллера
        vg75_mod->reset_n = 0;
        vg75_mod->clock   = 1; vg75_mod->eval();
        vg75_mod->clock   = 0; vg75_mod->eval();
        vg75_mod->reset_n = 1;

        // Сброс процессора
        core8080->ce      = 1;
        core8080->reset_n = 0;
        core8080->clock   = 0; core8080->eval();
        core8080->clock   = 1; core8080->eval();
        core8080->reset_n = 1;
    }

    int main() {

        for (;;) {

            Uint32 ticks = SDL_GetTicks();

            // Прием событий
            while (SDL_PollEvent(& evt)) {

                // Событие выхода
                switch (evt.type) { case SDL_QUIT: return 0; }
            }

            // Обновление экрана
            if (ticks - pticks >= frame_length) {

                pticks = ticks;
                update();
                return 1;
            }

            SDL_Delay(1);
        }
    }

    // Один такт 25 мгц
    void tick() {

        // Сначала запись
        if (core8080->we) {
            memory[core8080->address] = core8080->out;
        }

        // А потом чтение
        core8080->in = memory[core8080->address];

        // Взаимодействие с видеоконтроллером
        vg75_mod->cpu_address = core8080->address;
        vg75_mod->cpu_out     = core8080->out;
        vg75_mod->cpu_we      = core8080->we;

        // Подключение ПЗУ шрифтов
        vg75_mod->font_in = fontrom[vg75_mod->font_address];
        vg75_mod->in      = memory[vg75_mod->address];

        // VGA
        vg75_mod->clock = 1; vg75_mod->eval();
        vg75_mod->clock = 0; vg75_mod->eval();

        // CPU
        core8080->clock = 0; core8080->eval();
        core8080->clock = 1; core8080->eval();

        vg75(vg75_mod->hs, vg75_mod->vs, (vg75_mod->r*192)*65536 + (vg75_mod->g*192)*256 + (vg75_mod->b*192));
    }

    // Обновить окно
    void update() {

        SDL_Rect dstRect;

        dstRect.x = 0;
        dstRect.y = 0;
        dstRect.w = scale * width;
        dstRect.h = scale * height;

        SDL_UpdateTexture       (sdl_screen_texture, NULL, screen_buffer, width * sizeof(Uint32));
        SDL_SetRenderDrawColor  (sdl_renderer, 0, 0, 0, 0);
        SDL_RenderClear         (sdl_renderer);
        SDL_RenderCopy          (sdl_renderer, sdl_screen_texture, NULL, & dstRect);
        SDL_RenderPresent       (sdl_renderer);
    }

    // Убрать окно из памяти
    int destroy() {

        free(screen_buffer);

        SDL_DestroyTexture(sdl_screen_texture);
        SDL_FreeFormat(sdl_pixel_format);
        SDL_DestroyRenderer(sdl_renderer);
        SDL_DestroyWindow(sdl_window);
        SDL_Quit();

        return 0;
    }

    // Установка точки
    void pset(int x, int y, Uint32 cl) {

        if (x < 0 || y < 0 || x >= 640 || y >= 400)
            return;

        screen_buffer[width*y + x] = cl;
    }

    // 640 x 400 x 70
    void vg75(int hs, int vs, int color) {

        if (hs) x++;

        // Отслеживание изменений HS/VS
        if (_hs == 0 && hs == 1) { x = 0; y++; }
        if (_vs == 1 && vs == 0) { x = 0; y = 0; }

        // Сохранить предыдущее значение
        _hs = hs;
        _vs = vs;

        // Вывод на экран
        pset(x-48, y-35, color);
    }
};
