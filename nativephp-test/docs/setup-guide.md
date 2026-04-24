# 完全構築手順: NativePHP Mobile + MySQL (ゼロから再現)

このドキュメントは、本 PoC を新しい macOS マシンでゼロから再現するための手順書。
読み進めれば 2〜3 時間で Android エミュレータから MySQL に接続できる状態になる。

## 前提環境

- **macOS Apple Silicon** (Intel Mac は未検証)
- インターネット接続 (NDK 540MB ほか合計数 GB ダウンロードする)
- 空きディスク容量: 15 GB 以上

## Step 0: 必要ツールのインストール

```bash
# Homebrew が未インストールなら先に:
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install php@8.3 composer node
brew install --cask android-commandlinetools docker

# Rosetta 2 を有効化 (Apple Silicon で x86_64 コンテナを動かすため)
softwareupdate --install-rosetta --agree-to-license

# Android SDK コンポーネントを導入
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" \
           "ndk;27.0.12077973" "emulator" "system-images;android-34;default;arm64-v8a"

# AVD (エミュレータ) を作成
avdmanager create avd -n Pixel_6_Pro_arm \
  -k "system-images;android-34;default;arm64-v8a" -d "pixel_6_pro"

# Docker Desktop を起動 (GUI から初回のみ)
open -a Docker
# … Docker が起動するまで待機 (初回 30 秒〜1 分)

# 動作確認
php --version        # PHP 8.3.x
composer --version   # 2.x
adb --version        # Platform-Tools 36+
docker --version     # 27.x
```

## Step 1: Laravel + NativePHP Mobile のセットアップ

```bash
cd ~/Desktop/sandbox  # 任意の作業ディレクトリ
composer create-project laravel/laravel nativephp-test --prefer-dist --no-interaction
cd nativephp-test
composer require nativephp/mobile

# NATIVEPHP_APP_ID を .env に追記 (bundle ID)
echo "NATIVEPHP_APP_ID=com.yourname.nativephpdemo" >> .env

# NativePHP Mobile の初期化 (Android プロジェクト生成 + libphp.a ダウンロード)
php artisan native:install android --no-interaction
```

この時点で動作確認:

```bash
emulator -avd Pixel_6_Pro_arm -no-snapshot-save &
sleep 30  # エミュレータ起動待ち
php artisan native:run android --build=debug --no-tty
# → Laravel Welcome ページがエミュレータに出れば OK (配布 libphp.a の状態)
```

## Step 2: 自前 libphp.a ビルダーの取得

```bash
cd ~/Desktop/sandbox

# v3l0c1r4pt0r/php-ndk を独立リポジトリ化 (フォークではなく完全コピー)
git clone --depth 1 https://github.com/v3l0c1r4pt0r/php-ndk.git mobile-libphp-builder
cd mobile-libphp-builder
rm -rf .git
git init -q
git add -A
git commit -m "chore: import php-ndk as independent copy" -q
```

## Step 3: Dockerfile を NativePHP Mobile 向けに改造

```bash
# Makefile を編集: PHP 8.3.30, aarch64 のみに絞る
cat > Makefile << 'EOF'
DESTDIR=.
EABI_PLATFORMS=armv7a
NOABI_PLATFORMS=aarch64 i686 riscv64 x86_64
PLATFORMS=$(EABI_PLATFORMS) $(NOABI_PLATFORMS)
INSTALL_PLATFORMS=$(foreach platform,$(PLATFORMS),install-$(platform))
LIBDIR_PATH=app/src/main/jniLibs/
armv7a_LIBDIR=armeabi-v7a
aarch64_LIBDIR=arm64-v8a
i686_LIBDIR=x86
x86_64_LIBDIR=x86_64
riscv64_LIBDIR=riscv64
LIBDIRS=armv7a_LIBDIR aarch64_LIBDIR

PHP_VERSION=8.3.30
PATCHLEVEL=nativephp-mysql
API_LEVEL=32
IMAGE_NAME=nativephp-libphp-mysql

ENABLED_PLATFORMS=aarch64
ENABLES_INSTALLS=$(foreach platform,$(ENABLED_PLATFORMS),install-$(platform))

all: $(ENABLED_PLATFORMS)
install: $(ENABLES_INSTALLS)

$(EABI_PLATFORMS):
	docker build --build-arg=TARGET=$@-linux-androideabi$(API_LEVEL) --build-arg=LIBDIR=$($@_LIBDIR) -t $(IMAGE_NAME):$(PHP_VERSION)-$@-api$(API_LEVEL)-$(PATCHLEVEL) .

$(NOABI_PLATFORMS):
	docker build --build-arg=TARGET=$@-linux-android$(API_LEVEL) --build-arg=LIBDIR=$($@_LIBDIR) -t $(IMAGE_NAME):$(PHP_VERSION)-$@-api$(API_LEVEL)-$(PATCHLEVEL) .

$(INSTALL_PLATFORMS):
	$(eval CONTAINER=$(shell docker create $(IMAGE_NAME):$(PHP_VERSION)-$(subst install-,,$@)-api$(API_LEVEL)-$(PATCHLEVEL) /dummy))
	docker cp $(CONTAINER):/app $(DESTDIR)/
	docker rm -f $(CONTAINER)

.PHONY: $(PLATFORMS) install-$(PLATFORMS)
EOF
```

`Dockerfile` を次の内容で置き換え:

```dockerfile
FROM --platform=linux/amd64 alpine:3.21 as buildsystem

RUN apk update
RUN apk add wget unzip gcompat libgcc bash patch make curl pkgconfig binutils perl

WORKDIR /opt
ENV NDK_VERSION android-ndk-r27c-linux
RUN wget https://dl.google.com/android/repository/${NDK_VERSION}.zip \
    && unzip ${NDK_VERSION}.zip && rm ${NDK_VERSION}.zip

ENV PATH="$PATH:/opt/android-ndk-r27c/:/opt/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin"

WORKDIR /root

ARG TARGET=aarch64-linux-android32
ARG PHP_VERSION=8.3.30

# SQLite amalgamation (共有用 .so)
ENV SQLITE3_VERSION 3470200
RUN wget https://www.sqlite.org/2024/sqlite-amalgamation-${SQLITE3_VERSION}.zip
RUN unzip sqlite-amalgamation-${SQLITE3_VERSION}.zip

WORKDIR /root/sqlite-amalgamation-${SQLITE3_VERSION}
RUN ${TARGET}-clang -o libsqlite3.so -shared -fPIC sqlite3.c

# OpenSSL 3.0.15 (Android NDK でクロスビルド)
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

# Oniguruma 6.9.9 (mbstring 正規表現エンジン)
WORKDIR /root
ENV ONIG_VERSION 6.9.9
RUN wget https://github.com/kkos/oniguruma/releases/download/v${ONIG_VERSION}/onig-${ONIG_VERSION}.tar.gz
RUN tar -xf onig-${ONIG_VERSION}.tar.gz
WORKDIR /root/onig-${ONIG_VERSION}
RUN CC=${TARGET}-clang CFLAGS="-fPIC" ./configure \
    --host=${TARGET} --prefix=/root/onig-install \
    --enable-static --disable-shared
# libtool の .la 生成を迂回
RUN make -C src -j7 2>&1 | tail -40 || true
RUN test -f src/.libs/libonig.a
RUN mkdir -p /root/onig-install/lib/pkgconfig /root/onig-install/include && \
    cp src/.libs/libonig.a /root/onig-install/lib/libonig.a && \
    find . -name "oniguruma.h" -exec cp {} /root/onig-install/include/ \; && \
    find . -name "onig.pc" -exec cp {} /root/onig-install/lib/pkgconfig/ \;

# PHP 8.3.30
WORKDIR /root
RUN wget https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz
RUN tar -xvf php-${PHP_VERSION}.tar.gz

COPY *.patch /root/
WORKDIR /root/php-${PHP_VERSION}
RUN patch -p1 < ../ext-standard-dns.c.patch \
 && patch -p1 < ../resolv.patch \
 && patch -p1 < ../ext-standard-php_fopen_wrapper.c.patch \
 && patch -p1 < ../main-streams-cast.c.patch \
 && patch -p1 < ../fork.patch

WORKDIR /root
RUN mkdir build install
WORKDIR /root/build

RUN CFLAGS="-fPIC" CXXFLAGS="-fPIC" \
    ac_cv_func_getloadavg=no \
    PKG_CONFIG_PATH=/root/onig-install/lib/pkgconfig:/root/openssl-install/lib/pkgconfig \
    ONIG_CFLAGS="-I/root/onig-install/include" \
    ONIG_LIBS="-L/root/onig-install/lib -lonig" \
    OPENSSL_CFLAGS="-I/root/openssl-install/include" \
    OPENSSL_LIBS="-L/root/openssl-install/lib -lssl -lcrypto" \
    ../php-${PHP_VERSION}/configure \
  --with-pic --enable-zts \
  --enable-mbstring --with-openssl \
  --host=${TARGET} \
  --disable-dom --disable-simplexml --disable-xml \
  --disable-xmlreader --disable-xmlwriter \
  --without-pear --without-libxml \
  SQLITE_CFLAGS="-I/root/sqlite-amalgamation-${SQLITE3_VERSION}" \
  SQLITE_LIBS="-lsqlite3 -L/root/sqlite-amalgamation-${SQLITE3_VERSION}" \
  CC=$TARGET-clang \
  --disable-cli --disable-cgi --disable-phar --disable-phpdbg \
  --enable-embed=static \
  --with-sqlite3 --with-pdo-sqlite \
  --enable-mysqlnd --disable-mysqlnd-compression-support \
  --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd

# Android bionic に無いヘッダを補完
RUN for hdr in resolv_params.h resolv_private.h resolv_static.h resolv_stats.h; do \
      curl https://android.googlesource.com/platform/bionic/+/refs/heads/android12--mainline-release/libc/dns/include/$hdr?format=TEXT | base64 -d > $hdr; \
    done

# make libphp.la: libtool の .la 生成は失敗するが .o は生成される
RUN make libphp.la 2>&1 | tail -5 || true

# libtool を迂回して llvm-ar で libphp.a を直接作成
RUN cd /root/build && \
    echo "=== .o ファイル数 $(find . -name '*.o' -not -path '*/.libs/*' | wc -l) ===" && \
    llvm-ar rcs /root/install/libphp.a \
      $(find . -name "*.o" -not -path "*/.libs/*" -not -path "*/libphp.lax/*")

# 成果物をコピー
RUN cp /root/sqlite-amalgamation-${SQLITE3_VERSION}/libsqlite3.so /root/install/libsqlite3.so && \
    cp /root/openssl-install/lib/libssl.a /root/install/libssl.a && \
    cp /root/openssl-install/lib/libcrypto.a /root/install/libcrypto.a && \
    cp /root/onig-install/lib/libonig.a /root/install/libonig.a

FROM scratch
ARG LIBDIR
ENV LIBDIR ${LIBDIR}
COPY --from=buildsystem /root/install/* /app/src/main/staticLibs/${LIBDIR}/
```

改造をコミット:

```bash
git add -A && git commit -m "feat: PHP 8.3.30 + ZTS + PIC + mysqlnd + OpenSSL3 + Oniguruma 対応" -q
```

## Step 4: libphp.a のビルド

```bash
cd ~/Desktop/sandbox/mobile-libphp-builder

# 初回は 25-35 分 (NDK 540MB + OpenSSL + Oniguruma + PHP を順次クロスビルド)
# Apple Silicon では Rosetta 経由になるためさらに遅い
make aarch64

# Docker image → ホストに取り出し
make install-aarch64

# 生成物を確認
ls -la app/src/main/staticLibs/arm64-v8a/
# -rw-r--r--  libphp.a       26M
# -rw-r--r--  libssl.a       1.3M
# -rw-r--r--  libcrypto.a    9M
# -rw-r--r--  libonig.a      953K
# -rwxr-xr-x  libsqlite3.so  1.3M

# MySQL 拡張が入っていることを確認
nm app/src/main/staticLibs/arm64-v8a/libphp.a 2>&1 | grep -oE "zm_startup_[a-z_]+" | sort -u | grep mysql
# zm_startup_mysqli
# zm_startup_mysqlnd
# zm_startup_pdo_mysql
```

## Step 5: 自前 .a を NativePHP プロジェクトに差し替え

```bash
cd ~/Desktop/sandbox

DEST=nativephp-test/nativephp/android/app/src/main/staticLibs/arm64-v8a
cp mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/libphp.a     $DEST/
cp mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/libssl.a     $DEST/
cp mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/libcrypto.a  $DEST/
cp mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/libonig.a    $DEST/
```

## Step 6: Kotlin の DB_CONNECTION を MySQL に切替

`patches/laravel-environment-mysql.patch` を作成:

```diff
--- a/nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt
+++ b/nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt
@@ -762,8 +762,12 @@
                 // Laravel environment settings
                 "APP_URL" to "http://127.0.0.1",
                 "ASSET_URL" to "http://127.0.0.1/_assets",
-                "DB_CONNECTION" to "sqlite",
-                "DB_DATABASE" to "${appStorageDir.absolutePath}/persisted_data/database/database.sqlite",
+                "DB_CONNECTION" to "mysql",
+                "DB_HOST" to "10.0.2.2",
+                "DB_PORT" to "3306",
+                "DB_DATABASE" to "nativephp_test",
+                "DB_USERNAME" to "root",
+                "DB_PASSWORD" to "root",
                 "CACHE_DRIVER" to "file",
                 "CACHE_STORE" to "file",
                 "QUEUE_CONNECTION" to "database",
```

適用:

```bash
cd ~/Desktop/sandbox/nativephp-test
patch -p1 < patches/laravel-environment-mysql.patch
```

## Step 7: MySQL サーバー起動 (Docker Compose)

`docker-compose.mysql.yml`:

```yaml
services:
  mysql:
    image: mysql:8.4
    container_name: nativephp-mysql
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: nativephp_test
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-proot"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  mysql-data:
```

```bash
docker compose -f docker-compose.mysql.yml up -d

# healthcheck 待ち
until [ "$(docker inspect --format='{{.State.Health.Status}}' nativephp-mysql)" = "healthy" ]; do
  sleep 3
done
```

## Step 8: テストルートを追加してビルド

`routes/web.php`:

```php
<?php
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    try {
        $driver = DB::connection()->getDriverName();
        $version = DB::selectOne('SELECT VERSION() as v');
        return response()->json([
            'status'  => 'ok',
            'driver'  => $driver,
            'version' => $version->v,
        ]);
    } catch (\Throwable $e) {
        return response()->json([
            'status' => 'error',
            'error'  => $e->getMessage(),
        ], 500);
    }
});
```

ビルド & エミュレータで起動:

```bash
cd nativephp/android && ./gradlew clean && cd ../..

export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH

# エミュレータが止まってるなら起動:
# emulator -avd Pixel_6_Pro_arm -no-snapshot-save &

php artisan native:run android --build=debug --no-tty
```

エミュレータ画面で以下が出れば **完了**:

```json
{"status":"ok","driver":"mysql","version":"8.4.9"}
```

## トラブルシュート早見表

| 症状 | 対応 |
|---|---|
| Docker exit 133 | Dockerfile の `FROM` に `--platform=linux/amd64` を付ける |
| make libphp.la Error | libtool 迂回 (`llvm-ar rcs` で直接アーカイブ化) |
| duplicate symbol | find の除外パターンを `*/.libs/*` に (全階層) |
| `-fPIC` エラー | CFLAGS="-fPIC" + --with-pic |
| TSRM 未定義 | --enable-zts |
| getloadavg 未定義 | ac_cv_func_getloadavg=no |
| mb_split 未定義 | Oniguruma 同梱 + --enable-mbstring |
| openssl_* 未定義 | OpenSSL 3.0.15 同梱 + --with-openssl |
| SSL_CTX_set0_tmp_dh_pkey 未定義 | 自前 libssl.a + libcrypto.a を staticLibs に配置 |
| `Driver [mysql] not found` | 配布版 libphp.a のまま、自前ビルドに差し替え忘れ |
| `Connection refused 10.0.2.2:3306` | MySQL コンテナ未起動 |
| `driver: "sqlite"` のまま | LaravelEnvironment.kt の patch 適用忘れ |

## iOS 対応手順 (🚧 未検証)

Android と iOS は **完全に別系統** でクロスビルドする必要がある。Docker + NDK は使えず、
Mac ホスト上で **Xcode + iOS SDK** を直接使う。

### iOS 対応に必要な追加環境

```bash
# Xcode.app (Mac App Store、約 12 GB) — Command Line Tools だけでは不可
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# CocoaPods
brew install cocoapods

# iOS Simulator (Xcode 同梱) / または実機 + Apple Developer アカウント
```

### iOS Step 1: NativePHP iOS プロジェクトの生成

```bash
cd nativephp-test
php artisan native:install ios
cd nativephp/ios
pod install
open NativePHP.xcworkspace
```

Xcode でまず配布 `libphp.a` (SQLite 限定) のまま ⌘R で起動 → Laravel Welcome 確認。

### iOS Step 2: 自前 iOS 向け libphp.a のクロスビルド

**Docker 不可**。ホスト bash で直接:

```bash
mkdir ~/Desktop/ios-libphp-builder && cd ~/Desktop/ios-libphp-builder

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC_IOS=$(xcrun --sdk iphoneos -f clang)

# --- OpenSSL 3.0.15 (iOS 向け) ---
wget https://www.openssl.org/source/openssl-3.0.15.tar.gz
tar -xf openssl-3.0.15.tar.gz
cd openssl-3.0.15
./Configure ios64-xcrun \
  --prefix=$PWD/../openssl-ios \
  no-shared no-tests no-asm
make -j7 build_libs && make install_dev
cd ..

# --- Oniguruma 6.9.9 (iOS 向け) ---
wget https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz
tar -xf onig-6.9.9.tar.gz
cd onig-6.9.9
./configure \
  --host=arm-apple-darwin \
  CC="$CC_IOS" \
  CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=16.0 -fPIC" \
  --prefix=$PWD/../onig-ios \
  --enable-static --disable-shared
make -C src -j7 || true
# libonig.a を手動配置 (Android と同じ libtool 迂回手法)
mkdir -p ../onig-ios/{lib/pkgconfig,include}
cp src/.libs/libonig.a ../onig-ios/lib/
find . -name "oniguruma.h" -exec cp {} ../onig-ios/include/ \;
find . -name "onig.pc" -exec cp {} ../onig-ios/lib/pkgconfig/ \;
cd ..

# --- libxml2 2.12.7 (iOS 向け) ---
wget https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.7.tar.xz
tar -xf libxml2-2.12.7.tar.xz
cd libxml2-2.12.7
./configure \
  --host=arm-apple-darwin \
  CC="$CC_IOS" \
  CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=16.0 -fPIC" \
  --prefix=$PWD/../libxml2-ios \
  --enable-static --disable-shared \
  --without-python --without-iconv --without-icu --without-lzma --without-zlib
make -j7 || true
# 同様に手動配置
cd ..

# --- PHP 8.3.30 (iOS 向け) ---
wget https://www.php.net/distributions/php-8.3.30.tar.gz
tar -xf php-8.3.30.tar.gz
mkdir build && cd build
CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=16.0 -fPIC" \
CXXFLAGS="$CFLAGS" \
LDFLAGS="-arch arm64 -isysroot $IOS_SDK" \
ac_cv_func_getloadavg=no \
PKG_CONFIG_PATH=$PWD/../openssl-ios/lib/pkgconfig:$PWD/../onig-ios/lib/pkgconfig:$PWD/../libxml2-ios/lib/pkgconfig \
../php-8.3.30/configure \
  --host=arm-apple-darwin \
  --with-pic --enable-zts \
  --disable-cli --disable-cgi --disable-phar --disable-phpdbg \
  --enable-embed=static \
  --enable-mbstring --with-openssl \
  --with-libxml --enable-dom --enable-simplexml --enable-xml \
  --enable-xmlreader --enable-xmlwriter \
  --enable-mysqlnd --disable-mysqlnd-compression-support \
  --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd \
  --with-sqlite3 --with-pdo-sqlite \
  CC="$CC_IOS"
make libphp.la || true

# libtool 迂回
AR=$(xcrun --sdk iphoneos -f ar)
$AR rcs install/libphp.a $(find . -name "*.o" -not -path "*/.libs/*" -not -path "*/libphp.lax/*")
```

### iOS Step 3: 生成された .a を Xcode プロジェクトに配置

```bash
DEST=~/Desktop/sandbox/nativephp-test/nativephp/ios/NativePHP/Frameworks/
cp build/install/libphp.a $DEST/
cp openssl-ios/lib/libssl.a $DEST/
cp openssl-ios/lib/libcrypto.a $DEST/
cp onig-ios/lib/libonig.a $DEST/
cp libxml2-ios/lib/libxml2.a $DEST/
```

`NativePHP.xcodeproj/project.pbxproj` の Frameworks セクションで参照されていることを確認。

### iOS Step 4: Swift 側の DB 設定書き換え

`nativephp/ios/NativePHP/Bridge/PersistentPHPRuntime.swift` の `boot()` 関数内:

```diff
 setenv("LARAVEL_STORAGE_PATH", storageDir.appendingPathComponent("storage").path, 1)
-setenv("DB_DATABASE", "\(databaseDir)/database.sqlite", 1)
+setenv("DB_CONNECTION", "mysql", 1)
+setenv("DB_HOST", "127.0.0.1", 1)    // シミュレータはホスト Mac と直接ネットワーク共有
+setenv("DB_PORT", "3306", 1)
+setenv("DB_DATABASE", "nativephp_test", 1)
+setenv("DB_USERNAME", "root", 1)
+setenv("DB_PASSWORD", "root", 1)
```

**重要**: iOS の `DB_HOST` 指定先

| 実行環境 | ホスト指定 |
|---|---|
| iOS シミュレータ (macOS 上) | `127.0.0.1` (Mac のネットワークを共有) |
| iOS 実機 (同 LAN) | ホスト Mac の LAN IP (例 `192.168.1.100`) |
| iOS 実機 (本番サーバー) | 実際の MySQL サーバーの公開ホスト名 |

Android エミュレータの `10.0.2.2` とは異なる点に注意。

### iOS Step 5: ビルド & 実行

```bash
cd nativephp-test
php artisan native:run ios --build=debug
# または Xcode から NativePHP.xcworkspace を開いて ⌘R
```

### iOS 対応のリスク

- **App Store 審査**: 外部 MySQL への直接 TCP 接続はプライバシー審査で弾かれる可能性高
  - 必ず TLS 暗号化、証明書ピニング推奨
  - `Info.plist` の `NSAppTransportSecurity` 設定必須
- **シミュレータ/実機 ABI 差**: 両対応には XCFramework 化が必要
- **現状**: 本 template では Android のみ実動作検証済、iOS は手順書のみ。検証協力者募集中

## 参考

- [docs/poc-result.md](./poc-result.md) — PoC の成功レポート (結果詳細)
- [docs/architecture.md](./architecture.md) — アーキテクチャの全体像
- [mobile-libphp-builder/docs/build-guide.md](../../mobile-libphp-builder/docs/build-guide.md) — ビルダー側の詳細
