FROM --platform=linux/arm64 docker.io/ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Kernel build deps + ISO creation (native arm64 via QEMU binfmt)
RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libelf-dev \
    libssl-dev \
    cpio \
    python3 \
    kmod \
    git \
    xorriso \
    grub-efi-arm64-bin \
    dosfstools \
    mtools \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
