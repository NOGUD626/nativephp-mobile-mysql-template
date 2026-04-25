#!/usr/bin/env bash
# iOS (arm64) 向け libphp.a + 依存ライブラリをクロスビルドする。
# Docker は使わない (Xcode は macOS ネイティブ)。Xcode.app + iOS SDK が必須。
#
# 使い方:
#   cd mobile-libphp-builder/
#   bash build-ios.sh                # iphoneos (実機 arm64)  デフォルト
#   bash build-ios.sh iphoneos       # 実機 arm64 明示
#   bash build-ios.sh iphonesimulator # シミュレータ arm64 (Apple Silicon)
#
# 成果物:
#   app/src/main/staticLibs/arm64-apple-ios/           (iphoneos 向け)
#   app/src/main/staticLibs/arm64-apple-ios-simulator/ (iphonesimulator 向け)
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

# ----- SDK 切替 -----
SDK_NAME="${1:-iphoneos}"

case "$SDK_NAME" in
  iphoneos)
    ARCH_DIR="arm64-apple-ios"
    MIN_FLAG="-miphoneos-version-min=${IOS_MIN_VERSION}"
    OPENSSL_TARGET="ios64-xcrun"
    ;;
  iphonesimulator)
    ARCH_DIR="arm64-apple-ios-simulator"
    MIN_FLAG="-mios-simulator-version-min=${IOS_MIN_VERSION}"
    OPENSSL_TARGET="iossimulator-xcrun"
    ;;
  *)
    echo "❌ 不明な SDK: $SDK_NAME (iphoneos or iphonesimulator)"
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${ROOT}/ios-build-${SDK_NAME}"
PREFIX="${BUILD}/install"
DEST="${ROOT}/app/src/main/staticLibs/${ARCH_DIR}"

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

IOS_SDK="$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)"
CC_IOS="$(xcrun --sdk "${SDK_NAME}" -f clang)"
AR_IOS="$(xcrun --sdk "${SDK_NAME}" -f ar)"
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

CFLAGS_IOS="-arch arm64 -isysroot ${IOS_SDK} ${MIN_FLAG} -fPIC"

echo "=== iOS クロスビルド開始 (${SDK_NAME}) ==="
echo "  SDK_NAME       : ${SDK_NAME}"
echo "  ARCH_DIR       : ${ARCH_DIR}"
echo "  IOS_SDK        : ${IOS_SDK}"
echo "  CC             : ${CC_IOS}"
echo "  AR             : ${AR_IOS}"
echo "  OPENSSL_TARGET : ${OPENSSL_TARGET}"
echo "  CFLAGS         : ${CFLAGS_IOS}"
echo "  NPROC          : ${NPROC}"
echo "  BUILD          : ${BUILD}"
echo "  DEST           : ${DEST}"
echo ""

mkdir -p "${BUILD}" "${PREFIX}/lib/pkgconfig" "${PREFIX}/include" "${DEST}"
cd "${BUILD}"

# ----- OpenSSL 3.0.15 -----
build_openssl() {
  [[ -f "${PREFIX}/lib/libssl.a" ]] && { echo "✅ OpenSSL: cached"; return; }
  echo "=== [1/4] OpenSSL ${OPENSSL_VERSION} (${SDK_NAME}) ==="
  local src="openssl-${OPENSSL_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" | tar -xz
  }
  cd "${src}"
  ./Configure "${OPENSSL_TARGET}" \
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
  echo "=== [2/4] Oniguruma ${ONIG_VERSION} (${SDK_NAME}) ==="
  local src="onig-${ONIG_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://github.com/kkos/oniguruma/releases/download/v${ONIG_VERSION}/onig-${ONIG_VERSION}.tar.gz" | tar -xz
  }
  cd "${src}"
  ./configure \
    --host=arm-apple-darwin \
    CC="${CC_IOS}" \
    CFLAGS="${CFLAGS_IOS}" \
    --prefix="${PREFIX}" \
    --enable-static --disable-shared
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
  echo "=== [3/4] libxml2 ${LIBXML2_VERSION} (${SDK_NAME}) ==="
  local src="libxml2-${LIBXML2_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz" | tar -xJ
  }
  cd "${src}"
  ./configure \
    --host=arm-apple-darwin \
    CC="${CC_IOS}" \
    CFLAGS="${CFLAGS_IOS}" \
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
  echo "=== [4/4] PHP ${PHP_VERSION} (${SDK_NAME}) ==="
  local src="php-${PHP_VERSION}"
  [[ -d "${src}" ]] || {
    curl -fsSL "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" | tar -xz
  }
  # iOS は Darwin 系なので Android bionic 向けパッチ (resolv/dns/fork 等) は不要。
  # ただし fork.patch の一部は iOS でも有用な可能性があるが、安全側で全てスキップ。
  echo "  (Android bionic 用 patch は iOS では適用しない)"

  mkdir -p php-build && cd php-build
  CFLAGS="${CFLAGS_IOS}" \
  CXXFLAGS="${CFLAGS_IOS}" \
  LDFLAGS="-arch arm64 -isysroot ${IOS_SDK}" \
  ac_cv_func_getloadavg=no \
  ac_cv_type_gid_t=yes \
  ac_cv_type_uid_t=yes \
  ac_cv_func_posix_spawn_file_actions_addchdir_np=no \
  ac_cv_func___posix_spawn_file_actions_addchdir_np=no \
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
    --without-iconv \
    --disable-opcache \
    --without-pcre-jit \
    CC="${CC_IOS}"

  # iOS では unavailable な関数を configure が誤検出した場合の後処理 (sed で無効化)
  if [[ "$SDK_NAME" == iphone* ]]; then
    sed -i.bak '/#define HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP/d' main/php_config.h
    echo "  ✅ php_config.h から HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP を削除"
  fi

  make libphp.la 2>&1 | tail -5 || true
  "${AR_IOS}" rcs "${PREFIX}/lib/libphp.a" \
    $(find . -name "*.o" -not -path "*/.libs/*" -not -path "*/libphp.lax/*")
  cd "${BUILD}"
}

build_openssl
build_oniguruma
build_libxml2
build_php

echo "=== 成果物を ${DEST} に配置 ==="
for lib in libphp.a libssl.a libcrypto.a libonig.a libxml2.a; do
  cp "${PREFIX}/lib/${lib}" "${DEST}/"
  echo "   ✅ ${lib}"
done

echo ""
echo "=== MySQL / 主要拡張シンボル確認 ==="
nm "${DEST}/libphp.a" 2>&1 | grep -oE "zm_startup_[a-z_]+" | sort -u | grep -E "mysql|sqlite|openssl|dom|mbstring|xml" | sed 's/^/   /'
echo ""
echo "🎉 iOS 向け libphp.a ビルド完了 (${SDK_NAME} / ${ARCH_DIR})"
