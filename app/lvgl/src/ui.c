#include "ui.h"
#include "input.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <time.h>
#include <ctype.h>

#define W 800
#define H 480

/* Palette kept in sync with the FreeRTOS dashboard:
 * 0x0b1625 background, 0x172b42 cards, 0x36c8b3 teal, 0x5ca7ff blue. */
#define COL_BG      0x0b1625
#define COL_CARD    0x172b42
#define COL_MUTED   0x9eb4cc
#define COL_TEXT    0xe7eff8
#define COL_TEAL    0x36c8b3
#define COL_BLUE    0x5ca7ff

static lv_obj_t *cpu_value;
static lv_obj_t *cpu_bar;
static lv_obj_t *mem_value;
static lv_obj_t *mem_bar;
static lv_obj_t *mem_hint;
static lv_obj_t *task_value;
static lv_obj_t *clock_label;
static lv_obj_t *chart;
static lv_chart_series_t *series;
static lv_obj_t *footer_stats;
static lv_obj_t *footer_touch;

static unsigned long long last_total, last_idle;
static double smooth_load = -1.0;

static void label(lv_obj_t *parent, int x, int y, int w, const char *text,
                  const lv_font_t *font, uint32_t color)
{
    lv_obj_t *o = lv_label_create(parent);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_width(o, w);
    lv_label_set_long_mode(o, LV_LABEL_LONG_CLIP);
    lv_label_set_text(o, text);
    lv_obj_set_style_text_font(o, font, 0);
    lv_obj_set_style_text_color(o, lv_color_hex(color), 0);
}

static lv_obj_t *card(int x, int y, int w, int h, const char *title)
{
    lv_obj_t *o = lv_obj_create(lv_screen_active());
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_obj_set_scrollable(o, false);
    lv_obj_set_style_bg_color(o, lv_color_hex(COL_CARD), 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(o, 8, 0);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_shadow_width(o, 0, 0);
    label(o, 16, 10, w - 32, title, &lv_font_montserrat_14, COL_MUTED);
    return o;
}

static lv_obj_t *bar(lv_obj_t *parent, int x, int y, int w, uint32_t color)
{
    lv_obj_t *o = lv_bar_create(parent);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, 6);
    lv_bar_set_range(o, 0, 100);
    lv_obj_set_style_bg_color(o, lv_color_hex(0x253d56), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_bg_color(o, lv_color_hex(color), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(o, 3, LV_PART_MAIN);
    lv_obj_set_style_radius(o, 3, LV_PART_INDICATOR);
    return o;
}

static void read_cpu(unsigned long long *total, unsigned long long *idle)
{
    FILE *f = fopen("/proc/stat", "r");
    unsigned long long v[8] = {0};
    int n;
    if (!f) {
        *total = 0;
        *idle = 0;
        return;
    }
    n = fscanf(f, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
               &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7]);
    fclose(f);
    if (n < 5) {
        *total = 0;
        *idle = 0;
        return;
    }
    *idle = v[3] + v[4];
    *total = 0;
    for (int i = 0; i < 8; i++)
        *total += v[i];
}

static int count_tasks(void)
{
    DIR *d = opendir("/proc");
    struct dirent *e;
    int n = 0;
    if (!d)
        return 0;
    while ((e = readdir(d)) != NULL) {
        if (isdigit((unsigned char)e->d_name[0]))
            n++;
    }
    closedir(d);
    return n;
}

static void read_mem(unsigned long *free_mb, unsigned long *total_mb)
{
    FILE *f = fopen("/proc/meminfo", "r");
    char key[32];
    unsigned long kb, val;
    unsigned long total = 0, avail = 0, freeb = 0;
    *free_mb = 0;
    *total_mb = 0;
    if (!f)
        return;
    while (fscanf(f, "%31s %lu %*s", key, &kb) == 2) {
        val = kb / 1024;
        if (!strcmp(key, "MemTotal:"))
            total = val;
        else if (!strcmp(key, "MemAvailable:"))
            avail = val;
        else if (!strcmp(key, "MemFree:"))
            freeb = val;
    }
    fclose(f);
    *total_mb = total;
    *free_mb = avail ? avail : freeb;
}

static void read_uptime(char *out, size_t n)
{
    FILE *f = fopen("/proc/uptime", "r");
    double up = 0;
    if (f) {
        if (fscanf(f, "%lf", &up) != 1)
            up = 0;
        fclose(f);
    }
    {
        unsigned long sec = (unsigned long)up;
        unsigned long d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60;
        if (d)
            snprintf(out, n, "up %lud %02lu:%02lu", d, h, m);
        else
            snprintf(out, n, "up %02lu:%02lu", h, m);
    }
}

static void touch_timer(lv_timer_t *t)
{
    lv_indev_t *indev = lv_indev_get_next(NULL);
    lv_point_t p;
    (void)t;
    if (indev) {
        lv_indev_get_point(indev, &p);
        lv_label_set_text_fmt(footer_touch, "TOUCH  %d,%d    %s",
                              (int)p.x, (int)p.y, input_device_name());
    }
}

static void data_timer(lv_timer_t *t)
{
    unsigned long long total = 0, idle = 0;
    unsigned long free_mb = 0, total_mb = 0;
    double inst = 0;
    time_t now;
    struct tm tm;
    char up[32];
    char *loadavg = NULL;
    (void)t;

    read_cpu(&total, &idle);
    if (total > last_total && total != last_idle) {
        unsigned long long dt = total - last_total;
        unsigned long long di = idle - last_idle;
        if (dt)
            inst = 100.0 * (double)(dt - di) / (double)dt;
    }
    last_total = total;
    last_idle = idle;
    if (smooth_load < 0)
        smooth_load = inst;
    else
        smooth_load = smooth_load * 0.7 + inst * 0.3;
    if (smooth_load < 0) smooth_load = 0;
    if (smooth_load > 100) smooth_load = 100;

    lv_label_set_text_fmt(cpu_value, "%d%%", (int)(smooth_load + 0.5));
    lv_bar_set_value(cpu_bar, (int)(smooth_load + 0.5), LV_ANIM_OFF);
    lv_chart_set_next_value(chart, series, (lv_coord_t)(smooth_load + 0.5));

    read_mem(&free_mb, &total_mb);
    lv_label_set_text_fmt(mem_value, "%lu MB", free_mb);
    lv_label_set_text_fmt(mem_hint, "used %lu / %lu MB",
                          total_mb - free_mb, total_mb);
    lv_bar_set_value(mem_bar, total_mb ? (int)(100 - free_mb * 100 / total_mb) : 0,
                     LV_ANIM_OFF);

    lv_label_set_text_fmt(task_value, "%d", count_tasks());

    now = time(NULL);
    localtime_r(&now, &tm);
    strftime(up, sizeof(up), "%H:%M:%S", &tm);
    lv_label_set_text(clock_label, up);

    read_uptime(up, sizeof(up));
    {
        FILE *f = fopen("/proc/loadavg", "r");
        static char lb[64] = "";
        if (f) {
            if (fscanf(f, "%63[^\n]", lb) != 1)
                strcpy(lb, "");
            fclose(f);
            loadavg = lb;
        }
    }
    lv_label_set_text_fmt(footer_stats, "%s    load %s", up,
                          loadavg ? loadavg : "--");
}

void ui_create(void)
{
    lv_obj_t *scr = lv_screen_active();
    lv_obj_t *c;
    lv_obj_t *chart_card;

    lv_obj_clean(scr);
    lv_obj_set_scrollable(scr, false);
    lv_obj_set_style_bg_color(scr, lv_color_hex(COL_BG), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

    label(scr, 24, 16, 400, "IMX6ULL / LINUX", &lv_font_montserrat_20, 0xffffff);
    label(scr, 24, 40, 460, "BusyBox rootfs  /  LVGL 9.6  /  800x480 RGB LCD",
          &lv_font_montserrat_14, COL_MUTED);

    clock_label = lv_label_create(scr);
    lv_label_set_text(clock_label, "--:--:--");
    lv_obj_align(clock_label, LV_ALIGN_TOP_RIGHT, -24, 18);
    lv_obj_set_style_text_font(clock_label, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(clock_label, lv_color_hex(COL_TEXT), 0);

    /* Three status cards */
    c = card(20, 64, 240, 108, "CPU LOAD");
    cpu_value = lv_label_create(c);
    lv_label_set_text(cpu_value, "--%");
    lv_obj_set_pos(cpu_value, 16, 30);
    lv_obj_set_style_text_font(cpu_value, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(cpu_value, lv_color_hex(0xffffff), 0);
    cpu_bar = bar(c, 16, 86, 208, COL_TEAL);

    c = card(276, 64, 240, 108, "FREE MEMORY");
    mem_value = lv_label_create(c);
    lv_label_set_text(mem_value, "-- MB");
    lv_obj_set_pos(mem_value, 16, 30);
    lv_obj_set_style_text_font(mem_value, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(mem_value, lv_color_hex(0xffffff), 0);
    mem_bar = bar(c, 16, 86, 208, COL_BLUE);
    mem_hint = lv_label_create(c);
    lv_label_set_text(mem_hint, "used -- / -- MB");
    lv_obj_set_pos(mem_hint, 16, 66);
    lv_obj_set_style_text_font(mem_hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(mem_hint, lv_color_hex(COL_MUTED), 0);

    c = card(532, 64, 248, 108, "PROCESSES");
    task_value = lv_label_create(c);
    lv_label_set_text(task_value, "--");
    lv_obj_set_pos(task_value, 16, 30);
    lv_obj_set_style_text_font(task_value, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(task_value, lv_color_hex(0xffffff), 0);
    label(c, 16, 84, 216, "Linux tasks / Cortex-A7", &lv_font_montserrat_14, COL_MUTED);

    /* CPU history */
    chart_card = card(20, 188, 760, 180, "CPU HISTORY / 60 s");
    chart = lv_chart_create(chart_card);
    lv_obj_set_pos(chart, 8, 30);
    lv_obj_set_size(chart, 744, 130);
    lv_chart_set_type(chart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(chart, 60);
    lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, 0, 100);
    lv_chart_set_div_line_count(chart, 3, 8);
    lv_obj_set_style_bg_opa(chart, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(chart, 0, 0);
    lv_obj_set_style_line_color(chart, lv_color_hex(0x25445f), LV_PART_MAIN);
    lv_obj_set_style_line_width(chart, 2, LV_PART_ITEMS);
    lv_obj_set_style_size(chart, 0, 0, LV_PART_INDICATOR);
    series = lv_chart_add_series(chart, lv_color_hex(COL_TEAL), LV_CHART_AXIS_PRIMARY_Y);
    for (int i = 0; i < 60; i++)
        lv_chart_set_next_value(chart, series, 0);

    footer_stats = lv_label_create(scr);
    lv_label_set_text(footer_stats, "--");
    lv_obj_set_pos(footer_stats, 24, 384);
    lv_obj_set_style_text_font(footer_stats, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(footer_stats, lv_color_hex(COL_TEXT), 0);

    footer_touch = lv_label_create(scr);
    lv_label_set_text(footer_touch, "TOUCH  --");
    lv_obj_set_pos(footer_touch, 24, 444);
    lv_obj_set_style_text_font(footer_touch, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(footer_touch, lv_color_hex(COL_MUTED), 0);

    lv_timer_create(data_timer, 1000, NULL);
    lv_timer_create(touch_timer, 200, NULL);
}
