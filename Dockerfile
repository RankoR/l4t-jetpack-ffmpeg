#
# Base image
#
ARG JETPACK_TAG=r36.4.0

FROM nvcr.io/nvidia/l4t-jetpack:${JETPACK_TAG} AS base

ENV DEBIAN_FRONTEND=noninteractive

#
# Build dependencies
#
FROM base AS build-dependencies

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    git-core \
    build-essential \
    yasm \
    nasm \
    cmake \
    libtool \
    libc6 \
    libc6-dev \
    unzip \
    pkg-config \
    libx264-dev \
    libnuma-dev \
    libfdk-aac-dev \
    libmp3lame-dev \
    libdrm-dev \
    libopus-dev \
    && rm -rf /var/lib/apt/lists/*

#
# Build nvmpi
#
FROM build-dependencies AS build-nvmpi

RUN git clone https://github.com/Keylost/jetson-ffmpeg.git \
    && cd jetson-ffmpeg \
    && mkdir build \
    && cd build \
    && cmake -DWITH_STUBS=ON .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd ../.. \
    && rm -r jetson-ffmpeg/build

#
# Build FFmpeg
#
FROM build-nvmpi AS main

ARG FFMPEG_VERSION=8.0

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig

RUN wget https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && tar xvf ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && rm ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && cd jetson-ffmpeg \
    && ./ffpatch.sh ../ffmpeg-${FFMPEG_VERSION} \
    && cd ../ffmpeg-${FFMPEG_VERSION} \
    && ldconfig \
    && echo "=== Searching for nvmpi.pc ===" \
    && find / -name "nvmpi.pc" 2>/dev/null \
    && echo "=== Content of nvmpi.pc ===" \
    && cat $(find / -name "nvmpi.pc" 2>/dev/null | head -1) \
    && echo "=== Testing pkg-config commands ===" \
    && pkg-config --exists nvmpi && echo "EXISTS: OK" || echo "EXISTS: FAIL" \
    && pkg-config --cflags nvmpi && echo "CFLAGS: OK" || echo "CFLAGS: FAIL" \
    && pkg-config --libs nvmpi && echo "LIBS: OK" || echo "LIBS: FAIL" \
    && pkg-config --modversion nvmpi && echo "VERSION: OK" || echo "VERSION: FAIL" \
    && echo "=== Starting configure ===" \
    && ./configure \
        --enable-gpl \
        --enable-nonfree \
        --enable-libx264 \
        --enable-libdrm \
        --enable-nvmpi \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
        --disable-alsa \
        --extra-libs="-ldl" \
        --enable-shared \
        --enable-pic \
        --extra-libs="-lpthread -lm" \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd ../ \
    && rm -r jetson-ffmpeg \
    && rm -r ffmpeg-${FFMPEG_VERSION}
