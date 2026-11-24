#ifndef DISPLAY_H
#define DISPLAY_H

#include "lvgl.h"

/* Open /dev/fb0, map it, and register an LVGL display driver.
 * Resolution is taken from the framebuffer itself, so the same binary
 * works on 4.3" 480x272, 7" 800x480/1024x600 and HDMI/VGA panels. */
int display_init(void);

#ifdef DUMMY_DISPLAY
/* Host-side preview: render into RAM and dump a PPM screenshot. */
int display_dump_ppm(const char *path);
#endif

#endif
