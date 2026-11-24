#include "input.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/input.h>

static int evfd = -1;
static char devname[64] = "none";
static int last_x = 0, last_y = 0;
static int pressed = 0;
static int abs_x_min = 0, abs_x_max = 0;
static int abs_y_min = 0, abs_y_max = 0;
static int swap_xy = 0, invert_x = 0, invert_y = 0;

static int has_abs(int fd, int code)
{
    unsigned long bits[(ABS_MAX / (8 * sizeof(long))) + 2];
    memset(bits, 0, sizeof(bits));
    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(bits)), bits) < 0)
        return 0;
    return (bits[code / (8 * sizeof(long))] >> (code % (8 * sizeof(long)))) & 1UL;
}

static int try_open(const char *path)
{
    struct input_absinfo ai;
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd < 0)
        return -1;

    memset(devname, 0, sizeof(devname));
    if (ioctl(fd, EVIOCGNAME(sizeof(devname) - 1), devname) < 0)
        strcpy(devname, path);

    if (!has_abs(fd, ABS_X) || !has_abs(fd, ABS_Y)) {
        close(fd);
        return -1;
    }
    if (ioctl(fd, EVIOCGABS(ABS_X), &ai) < 0)
        memset(&ai, 0, sizeof(ai));
    abs_x_min = ai.minimum;
    abs_x_max = ai.maximum ? ai.maximum : 1;

    if (ioctl(fd, EVIOCGABS(ABS_Y), &ai) < 0)
        memset(&ai, 0, sizeof(ai));
    abs_y_min = ai.minimum;
    abs_y_max = ai.maximum ? ai.maximum : 1;

    /* Some panels report swapped/inverted axes; keep raw values and let the
     * user adjust with the environment if needed (see README). */
    evfd = fd;
    return 0;
}

const char *input_device_name(void)
{
    return devname;
}

static void read_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    static struct input_event ev;
    (void)indev;

    while (read(evfd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_X || ev.code == ABS_MT_POSITION_X)
                last_x = ev.value;
            else if (ev.code == ABS_Y || ev.code == ABS_MT_POSITION_Y)
                last_y = ev.value;
            else if (ev.code == ABS_PRESSURE)
                pressed = ev.value > 0;
        } else if (ev.type == EV_KEY && (ev.code == BTN_TOUCH || ev.code == BTN_LEFT)) {
            pressed = ev.value;
        }
        if (ev.type == EV_SYN && ev.code == SYN_REPORT)
            break;
    }

    {
        lv_display_t *disp = lv_display_get_default();
        int32_t hor = disp ? lv_display_get_horizontal_resolution(disp) : 800;
        int32_t ver = disp ? lv_display_get_vertical_resolution(disp) : 480;
        int32_t x = (last_x - abs_x_min) * (hor - 1) / (abs_x_max - abs_x_min);
        int32_t y = (last_y - abs_y_min) * (ver - 1) / (abs_y_max - abs_y_min);
        int32_t t;

        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x > hor - 1) x = hor - 1;
        if (y > ver - 1) y = ver - 1;

        if (swap_xy) { t = x; x = y; y = t; }
        if (invert_x) x = hor - 1 - x;
        if (invert_y) y = ver - 1 - y;

        data->point.x = x;
        data->point.y = y;
    }
    data->state = pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}

int input_init(void)
{
    char path[32];
    int i;
    const char *env;

    env = getenv("LVGL_TOUCH_SWAP");
    swap_xy = env ? atoi(env) : 0;
    env = getenv("LVGL_TOUCH_INVERT_X");
    invert_x = env ? atoi(env) : 0;
    env = getenv("LVGL_TOUCH_INVERT_Y");
    invert_y = env ? atoi(env) : 0;

    for (i = 0; i < 10; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        if (try_open(path) == 0) {
            lv_indev_t *indev = lv_indev_create();
            lv_indev_set_type(indev, LV_INDEV_TYPE_POINTER);
            lv_indev_set_read_cb(indev, read_cb);
            printf("touch: %s (%s), x[%d..%d] y[%d..%d]\n",
                   path, devname, abs_x_min, abs_x_max, abs_y_min, abs_y_max);
            return 0;
        }
    }
    printf("touch: no ABS pointer device found, running display-only\n");
    return 0;
}
