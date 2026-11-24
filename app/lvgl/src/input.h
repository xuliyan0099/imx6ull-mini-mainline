#ifndef INPUT_H
#define INPUT_H

#include "lvgl.h"

/* Find the touchscreen event node automatically (works with GT911/FT5x06
 * and the usual /dev/input/event0..event3 numbering) and register it as an
 * LVGL pointer input device. If no touchscreen exists we still return 0 so
 * the UI can run read-only on HDMI/VGA panels. */
int input_init(void);

const char *input_device_name(void);

#endif
