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

RUN echo "=== Checking NVIDIA library existence during BUILD ===" \
    && ls -la /usr/lib/aarch64-linux-gnu/nvidia/ || echo "Directory doesn't exist" \
    && ls -la /usr/lib/aarch64-linux-gnu/nvidia/libnvjpeg* || echo "libnvjpeg not found" \
    && ls -la /usr/lib/aarch64-linux-gnu/nvidia/libnvbufsurface* || echo "libnvbufsurface not found" \
    && ls -la /usr/lib/aarch64-linux-gnu/nvidia/libnvbufsurftransform* || echo "libnvbufsurftransform not found" \
    && ls -la /usr/lib/aarch64-linux-gnu/libv4l2* || echo "libv4l2 not found" \
    && file /usr/lib/aarch64-linux-gnu/nvidia/libnvjpeg.so 2>/dev/null || echo "Cannot stat libnvjpeg.so" \
    && echo "=== End diagnostic ==="

RUN cd /usr/lib/aarch64-linux-gnu/nvidia && \
    for lib in libnvbufsurface libnvbufsurftransform libnvjpeg; do \
        if [ -f ${lib}.so.* ] && [ ! -f ${lib}.so ]; then \
            ln -s $(ls ${lib}.so.* | head -1) ${lib}.so; \
            echo "Created symlink: ${lib}.so -> $(ls ${lib}.so.* | head -1)"; \
        fi; \
    done && \
    ldconfig

RUN mkdir -p /usr/lib/aarch64-linux-gnu/nvidia && \
    cp -a /usr/lib/aarch64-linux-gnu/nvidia/* /usr/lib/aarch64-linux-gnu/nvidia/ 2>/dev/null || true

RUN git clone https://github.com/Keylost/jetson-ffmpeg.git \
    && cd jetson-ffmpeg \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
             -DCMAKE_BUILD_TYPE=Release \
             -DLIB_NVBUFSURFACE=/usr/lib/aarch64-linux-gnu/nvidia/libnvbufsurface.so \
             -DLIB_NVBUFSURFTRANSFORM=/usr/lib/aarch64-linux-gnu/nvidia/libnvbufsurftransform.so \
             -DLIB_NVJPEG=/usr/lib/aarch64-linux-gnu/nvidia/libnvjpeg.so \
             -DLIB_V4L2=/usr/lib/aarch64-linux-gnu/libv4l2.so \
             .. \
    && make VERBOSE=1 -j$(nproc) 2>&1 | tee /tmp/build.log || (tail -200 /tmp/build.log && exit 1) \
    && make install \
    && ldconfig

#
# Build FFmpeg
#
FROM build-nvmpi AS main

ARG FFMPEG_VERSION=8.0

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig

RUN wget https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && tar xvf ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && rm ffmpeg-${FFMPEG_VERSION}.tar.bz2 \
    && cd jetson-ffmpeg \
    && ./ffpatch.sh ../ffmpeg-${FFMPEG_VERSION} \
    && cd ../ffmpeg-${FFMPEG_VERSION} \
    && ldconfig \
    && echo "=== Checking for nvmpi library files ===" \
    && ls -la /usr/local/lib/libnvmpi* || echo "NO libnvmpi.so in /usr/local/lib" \
    && ls -la /usr/local/include/nvmpi* || echo "NO nvmpi headers in /usr/local/include" \
    && echo "=== Searching entire system for nvmpi libraries ===" \
    && find / -name "libnvmpi*" 2>/dev/null || echo "No libnvmpi found anywhere" \
    && echo "=== Checking library dependencies ===" \
    && ldd /usr/local/lib/libnvmpi.so 2>/dev/null || echo "Cannot check ldd - file may not exist" \
    && echo "=== Testing pkg-config commands ===" \
    && pkg-config --exists nvmpi && echo "EXISTS: OK" || echo "EXISTS: FAIL" \
    && pkg-config --cflags nvmpi && echo "CFLAGS: OK" || echo "CFLAGS: FAIL" \
    && pkg-config --libs nvmpi && echo "LIBS: OK" || echo "LIBS: FAIL" \
    && echo "=== Manual compile test ===" \
    && echo '#include <stdio.h>' > /tmp/test.c \
    && echo 'int main() { printf("basic test"); return 0; }' >> /tmp/test.c \
    && gcc /tmp/test.c -o /tmp/test $(pkg-config --cflags --libs nvmpi) && echo "MANUAL LINK: OK" || echo "MANUAL LINK: FAIL" \
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
        --extra-libs="-ldl -lpthread -lm" \
        --enable-shared \
        --enable-pic \
    || (echo "=== CONFIGURE FAILED - Showing config.log tail ===" && tail -100 ffbuild/config.log && exit 1) \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd ../ \
    && rm -r jetson-ffmpeg \
    && rm -r ffmpeg-${FFMPEG_VERSION}
