#include "lvgl.h"
#include "display.h"
#include "input.h"
#include "ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>

int main(int argc, char **argv)
{
    struct timespec ts;
    long last_ms;
    (void)argc;
    (void)argv;

    printf("lvgl_demo: starting on /dev/fb0 (LVGL %d.%d.%d)\n",
           lv_version_major(), lv_version_minor(), lv_version_patch());

    /* The board RTC keeps UTC; the dashboard shows local wall time. */
    setenv("TZ", "CST-8", 1);
    tzset();

    lv_init();

    if (display_init() != 0) {
        fprintf(stderr, "lvgl_demo: framebuffer init failed\n");
        return 1;
    }
    input_init();
    ui_create();

#ifdef DUMMY_DISPLAY
    {
        int i;
        const char *out = (argc > 1) ? argv[1] : "/tmp/lvgl_preview.ppm";
        for (i = 0; i < 160; i++) {
            lv_tick_inc(30);
            lv_timer_handler();
        }
        if (display_dump_ppm(out) != 0) {
            fprintf(stderr, "lvgl_demo: cannot write %s\n", out);
            return 1;
        }
        printf("lvgl_demo: preview written to %s\n", out);
        return 0;
    }
#endif

    clock_gettime(CLOCK_MONOTONIC, &ts);
    last_ms = (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;

    for (;;) {
        long now_ms;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        now_ms = (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
        if (now_ms > last_ms)
            lv_tick_inc((uint32_t)(now_ms - last_ms));
        last_ms = now_ms;

        lv_timer_handler();
        usleep(5000);
    }
    return 0;
}
