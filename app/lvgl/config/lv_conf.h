/**
 * lv_conf.h for the I.MX6ULL Mini framebuffer build, LVGL 9.6.
 * Only the options that differ from LVGL's defaults are listed here;
 * the rest fall back to lv_conf_internal.h.
 */
#ifndef LV_CONF_H
#define LV_CONF_H

/* Framebuffer is XRGB8888.  LVGL's renderer writes B,G,R,X bytes, which
 * matches the i.MX6 IPU / mxsfb 32bpp layout. */
#define LV_COLOR_FORMAT_DEFAULT LV_COLOR_FORMAT_XRGB8888

/* Heap: single 4 MB built-in pool. */
#define LV_USE_STDLIB_MALLOC LV_STDLIB_BUILTIN
#define LV_MEM_SIZE          (4U * 1024U * 1024U)
#define LV_MEM_ADR           0

/* Use libc for strings/formatting (the BusyBox rootfs has uClibc). */
#define LV_USE_STDLIB_STRING  LV_STDLIB_CLIB
#define LV_USE_STDLIB_SPRINTF LV_STDLIB_CLIB

#define LV_USE_OS            LV_OS_NONE
#define LV_DEF_REFR_PERIOD   30
#define LV_DPI_DEF           130

/* Assertions and logs off for the production image. */
#define LV_USE_LOG                  0
#define LV_USE_ASSERT_NULL          0
#define LV_USE_ASSERT_MALLOC        0
#define LV_USE_ASSERT_MEM_INTEGRITY 0
#define LV_USE_ASSERT_OBJ           0
#define LV_USE_ASSERT_STYLE         0

#define LV_USE_THEME_DEFAULT    1
#define LV_THEME_DEFAULT_DARK   1
#define LV_USE_THEME_SIMPLE     0

/* Fonts used by the dashboard. */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_DEFAULT       LV_FONT_DEFAULT_MONTSERRAT_16
#define LV_FONT_FMT_TXT_LARGE 0
#define LV_USE_FONT_COMPRESSED 0

/* Widgets used by the dashboard. */
#define LV_USE_LABEL 1
#define LV_USE_BAR   1
#define LV_USE_CHART 1
#define LV_USE_OBJ   1
#define LV_USE_ARC   1
#define LV_USE_LINE  1
#define LV_USE_BTN   1
#define LV_USE_SLIDER 1

#define LV_USE_DEMO_WIDGETS   0
#define LV_USE_DEMO_BENCHMARK 0
#define LV_USE_DEMO_STRESS    0
#define LV_USE_DEMO_MUSIC     0
#define LV_USE_PERF_MONITOR   0
#define LV_USE_MEM_MONITOR    0
#define LV_USE_SYSMON         0

#endif
