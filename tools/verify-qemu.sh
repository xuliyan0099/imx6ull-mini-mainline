#!/usr/bin/env bash
# 用统一的 QEMU（bin/qemu-system-arm-im6，机型 mcimx6ull-alientek）冷启动
# qemu/images 里的 imx6ull_port 固件，验证串口到 shell 并抓 800×480 截图。
#   IM6_QEMU=<qemu 工程目录> bash tools/verify-qemu.sh
# 输出：docs/qemu-boot.log、docs/qemu-boot.png
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
QEMU=${IM6_QEMU:-}
if [ -z "$QEMU" ]; then
  for c in "$ROOT/../../04_Linux_and_QEMU/02_QEMU_Workspace/qemu" "$ROOT/../qemu" "$ROOT/qemu"; do
    [ -x "$c/bin/qemu-system-arm-im6" ] && QEMU=$(cd "$c" && pwd) && break
  done
fi
[ -n "$QEMU" ] && [ -x "$QEMU/bin/qemu-system-arm-im6" ] || {
  echo "找不到统一 QEMU：设置 IM6_QEMU 指向含 bin/qemu-system-arm-im6 的工程目录" >&2; exit 1; }

IMG=$QEMU/images
for f in zImage-mini-upstream imx6ull-alientek-mini-4.3.dtb rootfs-mini.uimg uboot-emmc.img; do
  [ -f "$IMG/$f" ] || { echo "缺少镜像 $IMG/$f，先跑 tools/install-to-qemu.sh" >&2; exit 1; }
done

WORK=$(mktemp -d /tmp/im6-verify.XXXX)
mkdir -p "$WORK/fat"
cp "$IMG/zImage-mini-upstream"          "$WORK/fat/zImage"
cp "$IMG/imx6ull-alientek-mini-4.3.dtb" "$WORK/fat/mini.dtb"
cp "$IMG/rootfs-mini.uimg"              "$WORK/fat/initrd.uim"
qemu-img create -q -f qcow2 -F raw -b "$IMG/uboot-emmc.img" "$WORK/emmc.qcow2" >/dev/null

cd "$QEMU"
./bin/qemu-system-arm-im6 \
  -accel tcg,tb-size=512 -M mcimx6ull-alientek -m 512 -smp 1 \
  -drive "if=sd,index=0,format=raw,file=fat:rw:$WORK/fat" \
  -drive "if=sd,index=1,format=qcow2,file=$WORK/emmc.qcow2,cache=unsafe" \
  -serial "unix:$WORK/ser,server=on,wait=on" \
  -monitor "unix:$WORK/mon,server=on,wait=off" \
  -vnc 127.0.0.1:97 -L /usr/share/qemu >"$WORK/qemu.log" 2>&1 &
QPID=$!
sleep 2

python3 - "$WORK" <<'PY'
import socket, sys, time, select
work = sys.argv[1]
def conn(name):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    for _ in range(60):
        try:
            s.connect(f'{work}/{name}'); return s
        except OSError: time.sleep(0.5)
    raise SystemExit(f'无法连接 {name}')
ser = conn('ser')
buf = b''
def read(sec, sock):
    global buf
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([sock], [], [], 0.3)
        if r:
            d = sock.recv(8192)
            if not d: break
            buf += d
read(12, ser)
if b'=>' not in buf:
    raise SystemExit('U-Boot 没有走到提示符\n' + buf.decode('utf-8', 'replace')[-800:])
for cmd in ['fatload mmc 0:1 0x80800000 zImage',
            'fatload mmc 0:1 0x83000000 mini.dtb',
            'fatload mmc 0:1 0x84000000 initrd.uim',
            'setenv bootargs console=ttymxc0,115200 root=/dev/ram0 rw',
            'bootz 0x80800000 0x84000000 0x83000000']:
    ser.send(cmd.encode() + b'\r'); time.sleep(1.3)
buf = b''
read(40, ser)
txt = buf.decode('utf-8', 'replace')
open(f'{work}/serial.log', 'w').write(txt)
if 'imx6ull-mini' not in txt:
    raise SystemExit('未出现 imx6ull-mini 提示符：\n' + txt[-1200:])
ser.send(b'\r'); time.sleep(8)
mon = conn('mon'); time.sleep(1)
mon.send(f'screendump {work}/shot.ppm\n'.encode()); time.sleep(4)
print('串口已到 shell，截图已抓取')
PY
RC=$?
kill $QPID 2>/dev/null || true
wait $QPID 2>/dev/null || true
pkill -x qemu-system-arm-im6 2>/dev/null || true

cp "$WORK/serial.log" "$ROOT/docs/qemu-boot.log"
python3 "$ROOT/tools/ppm2png.py" "$WORK/shot.ppm" "$ROOT/docs/qemu-boot.png"
echo "输出：docs/qemu-boot.log、docs/qemu-boot.png"
exit $RC
