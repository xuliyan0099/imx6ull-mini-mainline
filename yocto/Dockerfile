FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat \
      cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping \
      python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales \
      libacl1 bzip2 ca-certificates curl rsync libssl-dev libncurses-dev \
      pkg-config autoconf automake libtool lz4 bison flex \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8

# 降级 tar：noble-updates 的 tar 1.35+dfsg-3ubuntu0.x 改用 openat2()，
# 与 poky scarthgap 自带的 pseudo 1.9.0 不兼容，打包任务会报
# "got *at() syscall for unknown directory, fd 4"（Yocto bug 16117）
RUN curl -fsSL http://archive.ubuntu.com/ubuntu/pool/main/t/tar/tar_1.35+dfsg-3build1_amd64.deb -o /tmp/tar.deb \
    && dpkg -i --force-downgrade /tmp/tar.deb \
    && apt-mark hold tar \
    && rm -f /tmp/tar.deb

# bitbake 拒绝以 root 运行；宿主 /vol1 数据属主是 uid 1000，直接用镜像自带的 ubuntu 用户（同为 1000）
RUN mkdir -p /work && chown 1000:1000 /work

ENV HOME=/home/ubuntu
WORKDIR /work
USER ubuntu
