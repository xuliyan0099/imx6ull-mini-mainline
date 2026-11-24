LVGL_DIR ?= $(abspath $(CURDIR)/../../src/lvgl)
CC       ?= gcc
TARGET    = lvgl_demo
STRIP    ?= strip

CFLAGS  = -O2 -Wall -fno-strict-aliasing -std=gnu99 \
          -ffunction-sections -fdata-sections \
          -I$(LVGL_DIR) -Iconfig -Isrc \
          -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE

LDFLAGS ?= -Wl,--gc-sections -lm -lpthread

LVGL_SRCS := $(shell find $(LVGL_DIR)/src -name '*.c' | sort)
SRCS      := src/main.c src/display.c src/input.c src/ui.c $(LVGL_SRCS)

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $@ $(LDFLAGS)

# 目标板用的静态版本（rootfs 里不带共享库）
static: $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET) -static -Wl,--gc-sections -lm -lpthread
	$(STRIP) $(TARGET)

# 主机端预览（假 framebuffer，无触摸），不需要板子
demo_host: $(SRCS)
	$(CC) $(CFLAGS) -DDUMMY_DISPLAY $(SRCS) -o demo_host $(LDFLAGS)

preview: demo_host
	./demo_host preview.ppm && python3 ../../tools/ppm2png.py preview.ppm preview.png

clean:
	rm -f $(TARGET) demo_host preview.ppm preview.png

.PHONY: all static preview clean
