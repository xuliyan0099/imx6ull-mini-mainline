#include "display.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

#ifndef DUMMY_DISPLAY
static int fbfd = -1;
#endif
static unsigned char *fbp = NULL;
static struct fb_var_screeninfo vinfo;
static struct fb_fix_screeninfo finfo;
static lv_display_t *disp = NULL;
static unsigned char *draw_buf = NULL;

/* Partial rendering: 40 scanlines at 800 px / 32 bpp = 128 KB. */
#define DRAW_BUF_LINES 40

static void flush_cb(lv_display_t *d, const lv_area_t *area, uint8_t *px_map)
{
    int x, y;
    int w = area->x2 - area->x1 + 1;
    int h = area->y2 - area->y1 + 1;
    int bytes_pp = vinfo.bits_per_pixel / 8;

    for (y = 0; y < h; y++) {
        unsigned char *dst = fbp + (size_t)(area->y1 + y) * finfo.line_length
                                 + (size_t)area->x1 * bytes_pp;
        if (vinfo.bits_per_pixel == 32) {
            memcpy(dst, px_map, (size_t)w * 4);
        } else if (vinfo.bits_per_pixel == 16) {
            uint16_t *d16 = (uint16_t *)dst;
            const lv_color32_t *src = (const lv_color32_t *)px_map;
            for (x = 0; x < w; x++) {
                uint32_t r = src[x].red;
                uint32_t g = src[x].green;
                uint32_t b = src[x].blue;
                d16[x] = (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
            }
        }
        px_map += (size_t)w * 4;
    }

    lv_display_flush_ready(d);
}

int display_init(void)
{
#ifdef DUMMY_DISPLAY
    memset(&vinfo, 0, sizeof(vinfo));
    vinfo.xres = 800;
    vinfo.yres = 480;
    vinfo.bits_per_pixel = 32;
    finfo.line_length = vinfo.xres * 4;
    finfo.smem_len = (size_t)finfo.line_length * vinfo.yres;
    fbp = (unsigned char *)calloc(1, finfo.smem_len);
    if (!fbp)
        return -1;
#else
    fbfd = open("/dev/fb0", O_RDWR);
    if (fbfd < 0) {
        perror("open /dev/fb0");
        return -1;
    }
    if (ioctl(fbfd, FBIOGET_FSCREENINFO, &finfo) < 0 ||
        ioctl(fbfd, FBIOGET_VSCREENINFO, &vinfo) < 0) {
        perror("FBIOGET_*SCREENINFO");
        close(fbfd);
        return -1;
    }

    printf("fb: %ux%u, %ubpp, line_length=%u\n",
           vinfo.xres, vinfo.yres, vinfo.bits_per_pixel, finfo.line_length);

    fbp = (unsigned char *)mmap(NULL, finfo.smem_len, PROT_READ | PROT_WRITE,
                                MAP_SHARED, fbfd, 0);
    if (fbp == MAP_FAILED) {
        perror("mmap fb");
        close(fbfd);
        return -1;
    }
#endif

    draw_buf = (unsigned char *)calloc(1, (size_t)vinfo.xres * DRAW_BUF_LINES * 4);
    if (!draw_buf) {
        fprintf(stderr, "no memory for draw buffer\n");
        return -1;
    }

    disp = lv_display_create((int32_t)vinfo.xres, (int32_t)vinfo.yres);
    if (!disp)
        return -1;
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_XRGB8888);
    lv_display_set_flush_cb(disp, flush_cb);
    lv_display_set_buffers(disp, draw_buf, NULL,
                           (uint32_t)((size_t)vinfo.xres * DRAW_BUF_LINES * 4),
                           LV_DISPLAY_RENDER_MODE_PARTIAL);

    return 0;
}

#ifdef DUMMY_DISPLAY
int display_dump_ppm(const char *path)
{
    FILE *f = fopen(path, "wb");
    int x, y;
    if (!f)
        return -1;
    fprintf(f, "P6\n%u %u\n255\n", vinfo.xres, vinfo.yres);
    for (y = 0; y < (int)vinfo.yres; y++) {
        unsigned char *row = fbp + (size_t)y * finfo.line_length;
        for (x = 0; x < (int)vinfo.xres; x++) {
            fputc(row[x * 4 + 2], f);
            fputc(row[x * 4 + 1], f);
            fputc(row[x * 4 + 0], f);
        }
    }
    fclose(f);
    return 0;
}
#endif
