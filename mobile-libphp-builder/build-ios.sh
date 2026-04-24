#!/usr/bin/env bash
# iOS (arm64) 向け libphp.a + 依存ライブラリをクロスビルドする。
# Docker は使わない (Xcode は macOS ネイティブ)。
# Xcode.app + iOS SDK が必須。
#
# 使い方:
#   cd mobile-libphp-builder/
#   bash build-ios.sh
#
# 成果物:
#   app/src/main/staticLibs/arm64-apple-ios/
#     ├ libphp.a       (PHP 8.3.30, ZTS + PIC + mysqlnd + openssl + mbstring + xml)
#     ├ libssl.a       (OpenSSL 3.0.15)
#     ├ libcrypto.a
#     ├ libonig.a      (Oniguruma 6.9.9)
#     └ libxml2.a      (libxml2 2.12.7)

set -euo pipefail

PHP_VERSION=8.3.30
OPENSSL_VERSION=3.0.15
ONIG_VERSION=6.9.9
LIBXML2_VERSION=2.12.7
IOS_MIN_VERSION=16.0

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${ROOT}/ios-build"
PREFIX="${BUILD}/ios-install"
DEST="${ROOT}/app/src/main/staticLibs/arm64-apple-ios"

# ----- 前提チェック -----
if ! command -v xcrun >/dev/null 2>&1; then
  echo "❌ xcrun not found. Install Xcode.app from Mac App Store."
  exit 1
fi

if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  echo "❌ xcode-select が Command Line Tools を指してます。以下を実行:"
  echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC_IOS="$(xcrun --sdk iphoneos -f clang)"
AR_IOS="$(xcrun --sdk iphoneos -f ar)"
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "=== iOS クロスビルド開始 ==="
echo "  IOS_SDK : ${IOS_SDK}"
echo "  CC      : ${CC_IOS}"
echo "  AR      : ${AR_IOS}"
echo "  NPROC   : ${NPROC}"
echo "  BUILD   : ${BUILD}"
echo "  PREFIX  : ${PREFIX}"
echo ""

mkdir -p "${BUILD}" "${PREFIX}/lib/pkgconfig" "${PREFIX}/include" "${DEST}"
cd "${BUILD}"

# ----- OpenSSL 3.0.15 -----
build_openssl() {
  [[ -f "${PREFIX}/lib/libssl.a" ]] && { echo "✅ OpenSSL: cached"; return; }
  echo "=== [1/4] OpenSSL ${OPENSSL_VERSION} ==="
  local src="openssl-${OPENSSL_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" | tar -xz
  }
  cd "${src}"
  ./Configure ios64-xcrun \
    -D__DARWIN_ONLY_UNIX_CONFORMANCE=1 \
    --prefix="${PREFIX}" \
    no-shared no-tests
  make -j"${NPROC}" build_libs
  make install_dev
  cd "${BUILD}"
}

# ----- Oniguruma 6.9.9 -----
build_oniguruma() {
  [[ -f "${PREFIX}/lib/libonig.a" ]] && { echo "✅ Oniguruma: cached"; return; }
  echo "=== [2/4] Oniguruma ${ONIG_VERSION} ==="
  local src="onig-${ONIG_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://github.com/kkos/oniguruma/releases/download/v${ONIG_VERSION}/onig-${ONIG_VERSION}.tar.gz" | tar -xz
  }
  cd "${src}"
  ./configure \
    --host=arm-apple-darwin \
    CC="${CC_IOS}" \
    CFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC" \
    --prefix="${PREFIX}" \
    --enable-static --disable-shared
  # libtool 迂回
  make -C src -j"${NPROC}" 2>&1 | tail -5 || true
  [[ -f src/.libs/libonig.a ]] || { echo "❌ libonig.a not built"; exit 1; }
  cp src/.libs/libonig.a "${PREFIX}/lib/"
  find . -name "oniguruma.h" -exec cp {} "${PREFIX}/include/" \;
  find . -name "onig.pc" -exec cp {} "${PREFIX}/lib/pkgconfig/" \;
  cd "${BUILD}"
}

# ----- libxml2 2.12.7 -----
build_libxml2() {
  [[ -f "${PREFIX}/lib/libxml2.a" ]] && { echo "✅ libxml2: cached"; return; }
  echo "=== [3/4] libxml2 ${LIBXML2_VERSION} ==="
  local src="libxml2-${LIBXML2_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz" | tar -xJ
  }
  cd "${src}"
  ./configure \
    --host=arm-apple-darwin \
    CC="${CC_IOS}" \
    CFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC" \
    --prefix="${PREFIX}" \
    --enable-static --disable-shared \
    --without-python --without-iconv --without-icu --without-lzma --without-zlib
  make -j"${NPROC}" 2>&1 | tail -10 || true
  [[ -f .libs/libxml2.a ]] || { echo "❌ libxml2.a not built"; exit 1; }
  cp .libs/libxml2.a "${PREFIX}/lib/"
  mkdir -p "${PREFIX}/include/libxml2/libxml"
  cp include/libxml/*.h "${PREFIX}/include/libxml2/libxml/"
  cp libxml-2.0.pc "${PREFIX}/lib/pkgconfig/"
  cd "${BUILD}"
}

# ----- PHP 8.3.30 -----
build_php() {
  [[ -f "${PREFIX}/lib/libphp.a" ]] && { echo "✅ PHP libphp.a: cached"; return; }
  echo "=== [4/4] PHP ${PHP_VERSION} ==="
  local src="php-${PHP_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" | tar -xz
  }
  # patches (Android build でも使っているものを再利用)
  for patch_file in "${ROOT}"/*.patch; do
    [[ -f "${patch_file}" ]] || continue
    (cd "${src}" && patch -p1 -N < "${patch_file}" 2>/dev/null || true)
  done

  mkdir -p php-build && cd php-build
  CFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC" \
  CXXFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC" \
  LDFLAGS="-arch arm64 -isysroot ${IOS_SDK}" \
  ac_cv_func_getloadavg=no \
  PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig" \
  ONIG_CFLAGS="-I${PREFIX}/include" \
  ONIG_LIBS="-L${PREFIX}/lib -lonig" \
  OPENSSL_CFLAGS="-I${PREFIX}/include" \
  OPENSSL_LIBS="-L${PREFIX}/lib -lssl -lcrypto" \
  LIBXML_CFLAGS="-I${PREFIX}/include/libxml2" \
  LIBXML_LIBS="-L${PREFIX}/lib -lxml2" \
  ../"${src}"/configure \
    --host=arm-apple-darwin \
    --with-pic --enable-zts \
    --disable-cli --disable-cgi --disable-phar --disable-phpdbg \
    --enable-embed=static \
    --enable-mbstring --with-openssl \
    --with-libxml --enable-dom --enable-simplexml --enable-xml \
    --enable-xmlreader --enable-xmlwriter \
    --enable-mysqlnd --disable-mysqlnd-compression-support \
    --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd \
    --without-sqlite3 --without-pdo-sqlite \
    CC="${CC_IOS}"

  # libtool 迂回: make libphp.la でエラー出ても .o は作られる
  make libphp.la 2>&1 | tail -5 || true

  # llvm-ar or xcrun ar で直接アーカイブ化
  "${AR_IOS}" rcs "${PREFIX}/lib/libphp.a" \
    $(find . -name "*.o" -not -path "*/.libs/*" -not -path "*/libphp.lax/*")
  cd "${BUILD}"
}

build_openssl
build_oniguruma
build_libxml2
build_php

# ----- DEST に配置 -----
echo "=== 成果物を ${DEST} に配置 ==="
for lib in libphp.a libssl.a libcrypto.a libonig.a libxml2.a; do
  cp "${PREFIX}/lib/${lib}" "${DEST}/"
  echo "   ✅ ${lib}"
done

echo ""
echo "=== MySQL シンボル確認 ==="
"${AR_IOS}" t "${DEST}/libphp.a" | head -5
echo "..."
nm "${DEST}/libphp.a" 2>&1 | grep -oE "zm_startup_[a-z_]+" | sort -u | grep -E "mysql|sqlite|openssl|dom|mbstring|xml" | sed 's/^/   /'
echo ""
echo "🎉 iOS 向け libphp.a ビルド完了"
echo ""
echo "次のステップ:"
echo "  1. 生成された .a を NativePHP iOS プロジェクトへ配置"
echo "     DEST=../nativephp-test/nativephp/ios/NativePHP/Frameworks/"
echo "     cp ${DEST}/*.a \$DEST/"
echo "  2. PersistentPHPRuntime.swift の setenv を MySQL 設定に変更"
echo "  3. cd ../nativephp-test && php artisan native:run ios"
