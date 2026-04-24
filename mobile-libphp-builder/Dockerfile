FROM --platform=linux/amd64 alpine:3.21 as buildsystem

RUN apk update
RUN apk add wget unzip gcompat libgcc bash patch make curl pkgconfig binutils perl

WORKDIR /opt
ENV NDK_VERSION android-ndk-r27c-linux
RUN wget https://dl.google.com/android/repository/${NDK_VERSION}.zip && unzip ${NDK_VERSION}.zip && rm ${NDK_VERSION}.zip

ENV PATH="$PATH:/opt/android-ndk-r27c/:/opt/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin"

WORKDIR /root

##########
# CONFIG #
##########
ARG TARGET=aarch64-linux-android32
ARG PHP_VERSION=8.3.30

ENV SQLITE3_VERSION 3470200
RUN wget https://www.sqlite.org/2024/sqlite-amalgamation-${SQLITE3_VERSION}.zip
RUN unzip sqlite-amalgamation-${SQLITE3_VERSION}.zip

WORKDIR /root/sqlite-amalgamation-${SQLITE3_VERSION}
RUN ${TARGET}-clang -o libsqlite3.so -shared -fPIC sqlite3.c

# OpenSSL を Android NDK でクロスビルド
WORKDIR /root
ENV OPENSSL_VERSION 3.0.15
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
RUN tar -xf openssl-${OPENSSL_VERSION}.tar.gz
WORKDIR /root/openssl-${OPENSSL_VERSION}
RUN ANDROID_NDK_ROOT=/opt/android-ndk-r27c \
    PATH=/opt/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH \
    ./Configure android-arm64 \
      -D__ANDROID_API__=32 \
      --prefix=/root/openssl-install \
      no-shared no-tests
RUN ANDROID_NDK_ROOT=/opt/android-ndk-r27c \
    PATH=/opt/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH \
    make -j7 build_libs
RUN ANDROID_NDK_ROOT=/opt/android-ndk-r27c \
    PATH=/opt/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH \
    make install_dev

# libxml2 (DOM / SimpleXML / XMLReader / XMLWriter 用)
WORKDIR /root
ENV LIBXML2_VERSION 2.12.7
RUN wget https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz
RUN tar -xf libxml2-${LIBXML2_VERSION}.tar.xz
WORKDIR /root/libxml2-${LIBXML2_VERSION}
RUN CC=${TARGET}-clang CFLAGS="-fPIC" ./configure \
    --host=${TARGET} \
    --prefix=/root/libxml2-install \
    --enable-static --disable-shared \
    --without-python --without-iconv --without-icu --without-lzma --without-zlib
RUN make -C . -j7 2>&1 | tail -10 || true
RUN test -f .libs/libxml2.a && \
    mkdir -p /root/libxml2-install/lib/pkgconfig /root/libxml2-install/include/libxml2/libxml && \
    cp .libs/libxml2.a /root/libxml2-install/lib/libxml2.a && \
    cp include/libxml/*.h /root/libxml2-install/include/libxml2/libxml/ && \
    cp libxml-2.0.pc /root/libxml2-install/lib/pkgconfig/libxml-2.0.pc

# Oniguruma (mbstring の正規表現エンジン) を Android NDK でクロスビルド
WORKDIR /root
ENV ONIG_VERSION 6.9.9
RUN wget https://github.com/kkos/oniguruma/releases/download/v${ONIG_VERSION}/onig-${ONIG_VERSION}.tar.gz
RUN tar -xf onig-${ONIG_VERSION}.tar.gz
WORKDIR /root/onig-${ONIG_VERSION}
RUN CC=${TARGET}-clang CFLAGS="-fPIC" ./configure \
    --host=${TARGET} \
    --prefix=/root/onig-install \
    --enable-static --disable-shared
# libtool の .la 生成を回避して src/.libs/libonig.a を直接配置
RUN make -C src -j7 2>&1 | tail -40 || true
RUN test -f src/.libs/libonig.a || (echo "libonig.a not built" && exit 1)
RUN echo "=== onig.pc 探索 ===" && find /root/onig-6.9.9 -name "*.pc" -o -name "oniguruma.h" | head -10
RUN mkdir -p /root/onig-install/lib/pkgconfig /root/onig-install/include && \
    cp src/.libs/libonig.a /root/onig-install/lib/libonig.a && \
    find . -name "oniguruma.h" -exec cp {} /root/onig-install/include/ \; && \
    find . -name "onig.pc" -exec cp {} /root/onig-install/lib/pkgconfig/ \; && \
    ls -la /root/onig-install/lib/ /root/onig-install/include/ /root/onig-install/lib/pkgconfig/

WORKDIR /root
RUN wget https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz
RUN tar -xvf php-${PHP_VERSION}.tar.gz

COPY *.patch /root/
WORKDIR /root/php-${PHP_VERSION}
RUN \
patch -p1 < ../ext-standard-dns.c.patch && \
patch -p1 < ../resolv.patch && \
patch -p1 < ../ext-standard-php_fopen_wrapper.c.patch && \
patch -p1 < ../main-streams-cast.c.patch && \
patch -p1 < ../fork.patch \
;

WORKDIR /root
RUN mkdir build install
WORKDIR /root/build

RUN CFLAGS="-fPIC" CXXFLAGS="-fPIC" \
    ac_cv_func_getloadavg=no \
    PKG_CONFIG_PATH=/root/onig-install/lib/pkgconfig:/root/openssl-install/lib/pkgconfig:/root/libxml2-install/lib/pkgconfig \
    ONIG_CFLAGS="-I/root/onig-install/include" \
    ONIG_LIBS="-L/root/onig-install/lib -lonig" \
    OPENSSL_CFLAGS="-I/root/openssl-install/include" \
    OPENSSL_LIBS="-L/root/openssl-install/lib -lssl -lcrypto" \
    LIBXML_CFLAGS="-I/root/libxml2-install/include/libxml2" \
    LIBXML_LIBS="-L/root/libxml2-install/lib -lxml2" \
    ../php-${PHP_VERSION}/configure \
  --with-pic \
  --enable-zts \
  --enable-mbstring \
  --with-openssl \
  --host=${TARGET} \
  --with-libxml \
  --enable-dom \
  --enable-simplexml \
  --enable-xml \
  --enable-xmlreader \
  --enable-xmlwriter \
  --without-pear \
  SQLITE_CFLAGS="-I/root/sqlite-amalgamation-${SQLITE3_VERSION}" \
  SQLITE_LIBS="-lsqlite3 -L/root/sqlite-amalgamation-${SQLITE3_VERSION}" \
  CC=$TARGET-clang \
  --disable-cli \
  --disable-cgi \
  --disable-phar \
  --disable-phpdbg \
  --enable-embed=static \
  --with-sqlite3 \
  --with-pdo-sqlite \
  --enable-mysqlnd \
  --disable-mysqlnd-compression-support \
  --with-pdo-mysql=mysqlnd \
  --with-mysqli=mysqlnd \
  ;

RUN \
  for hdr in resolv_params.h resolv_private.h resolv_static.h resolv_stats.h; do \
    curl https://android.googlesource.com/platform/bionic/+/refs/heads/android12--mainline-release/libc/dns/include/$hdr?format=TEXT | base64 -d > $hdr; \
  done
# 全 .lo をコンパイル (libtool による最終リンクは失敗するが .o 群は生成される)
RUN make libphp.la 2>&1 | tail -5 || true
RUN ls /root/build/.libs/libphp.lax/ 2>/dev/null | head -5 && \
    echo "=== libphp.lax 内のオブジェクト ==="

# libtool を迂回して、直接 ar で .o を全部束ねて libphp.a を作る
# .lo は libtool ファイル、実体は同名の .o (非 PIC ビルドなので .libs/ に入らない場合がある)
RUN cd /root/build && \
    find . -name "*.o" | grep -v "\.libs/" | head -5 && \
    echo "=== .o ファイル数 $(find . -name '*.o' -not -path '*/.libs/*' | wc -l) ===" && \
    llvm-ar rcs /root/install/libphp.a \
      $(find . -name "*.o" -not -path "*/.libs/*" -not -path "*/libphp.lax/*") && \
    ls -la /root/install/libphp.a && \
    llvm-ar t /root/install/libphp.a | head -5
RUN cp /root/sqlite-amalgamation-${SQLITE3_VERSION}/libsqlite3.so /root/install/libsqlite3.so && \
    cp /root/openssl-install/lib/libssl.a /root/install/libssl.a && \
    cp /root/openssl-install/lib/libcrypto.a /root/install/libcrypto.a && \
    cp /root/onig-install/lib/libonig.a /root/install/libonig.a && \
    cp /root/libxml2-install/lib/libxml2.a /root/install/libxml2.a

FROM scratch
ARG LIBDIR
ENV LIBDIR ${LIBDIR}
COPY --from=buildsystem /root/install/* /app/src/main/staticLibs/${LIBDIR}/
