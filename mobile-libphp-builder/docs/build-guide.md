# ビルドガイド: mobile-libphp-builder

## ビルドフロー (概念)

```
 [Host macOS (Apple Silicon)]
     │
     │ docker build --platform=linux/amd64
     ▼
 [Alpine Linux x86_64 コンテナ (Rosetta 経由)]
     │
     ├─ android-ndk-r27c-linux.zip ダウンロード (540MB)
     │
     ├─ sqlite-amalgamation-3470200 ダウンロード & .so 化
     │
     ├─ php-8.3.30.tar.gz ダウンロード & 展開
     │
     ├─ patches/*.patch を php-src に適用
     │   - ext-standard-dns.c.patch
     │   - resolv.patch
     │   - ext-standard-php_fopen_wrapper.c.patch
     │   - main-streams-cast.c.patch
     │   - fork.patch
     │
     ├─ resolv headers をホスト (Android bionic) から取得
     │
     ├─ ./configure --host=aarch64-linux-android32 ...
     │   (CC=aarch64-linux-android32-clang)
     │
     ├─ make libphp.la
     │   → .libs/libphp.a (aarch64 向け静的ライブラリ)
     │
     └─ 成果物を /root/install/ にコピー
 [scratch stage]
     └─ /app/src/main/staticLibs/arm64-v8a/ に配置
 [Host 側 docker cp]
     └─ プロジェクトルートの app/src/main/staticLibs/arm64-v8a/ に展開
```

## configure フラグ全体

```bash
./configure \
  --host=aarch64-linux-android32 \
  --disable-dom \
  --disable-simplexml \
  --disable-xml \
  --disable-xmlreader \
  --disable-xmlwriter \
  --without-pear \
  --without-libxml \
  SQLITE_CFLAGS="-I/root/sqlite-amalgamation-3470200" \
  SQLITE_LIBS="-lsqlite3 -L/root/sqlite-amalgamation-3470200" \
  CC=aarch64-linux-android32-clang \
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
  --with-mysqli=mysqlnd
```

### 各フラグの意図

| フラグ | 意図 |
|---|---|
| `--host=aarch64-linux-android32` | クロスコンパイルのターゲット (Android arm64, API 32) |
| `--disable-dom` 他 XML 系 | libxml2 を持ち込まない (依存削減) |
| `--disable-cli --disable-cgi` | CLI/CGI SAPI は作らない (embed に集中) |
| `--disable-phar` | cross-compile 時に host PHP で phar 生成しないといけない制約を回避 |
| `--disable-phpdbg` | デバッガ SAPI は不要 |
| `--enable-embed=static` | **sapi/embed/libphp.a を出力させる (これが本命)** |
| `--with-sqlite3` / `--with-pdo-sqlite` | SQLite 拡張 (NativePHP 本来の機能維持) |
| `--enable-mysqlnd` | **mysqlnd (純 PHP 実装の MySQL プロトコル) を有効化** |
| `--with-pdo-mysql=mysqlnd` | **PDO MySQL ドライバを mysqlnd バックエンドで** |
| `--with-mysqli=mysqlnd` | **mysqli 拡張も mysqlnd バックエンドで** |
| `--disable-mysqlnd-compression-support` | zlib/pkg-config 依存を避ける |

### なぜ mysqlnd なのか

- MySQL クライアントには 2 系統ある:
  - **libmysqlclient** (MySQL 本家 C ライブラリ、GPL、要 cross-compile の追加作業)
  - **mysqlnd** (PHP 本体に含まれる純 PHP 実装、依存ライブラリ不要)
- **mysqlnd 一択**: Android NDK 環境で libmysqlclient をクロスコンパイルするのは非常に手間
  (cmake + boost + openssl 等を aarch64 向けに全部作り直す必要)
- 実運用上も mysqlnd がデフォルト推奨 (Debian/Ubuntu の php-mysql も mysqlnd)

## 既知のハマりどころ

### 1. exit code 133 (SIGTRAP)

```
/bin/sh -c ${TARGET}-clang ... did not complete successfully: exit code: 133
```

**原因**: Apple Silicon 上で x86_64 NDK バイナリが動けない
**対策**: `Dockerfile` の `FROM` を `--platform=linux/amd64` に固定 (済)

### 2. configure: pkg-config not found (zlib)

```
checking whether to enable mysqlnd... yes
checking whether to enable compressed protocol support in mysqlnd... yes
checking for zlib... no
configure: error: The pkg-config script could not be found
```

**原因**: mysqlnd の compressed protocol support がデフォルト on で zlib を要求
**対策**: `--disable-mysqlnd-compression-support` を追加 (済)

### 3. libphp.la のリンクで libtool Error 1

```
copying selected object files to avoid basename conflicts...
make: *** [Makefile:118: libphp.la] Error 1
```

**原因**: libtool が static archive を作る際に、同名 basename のオブジェクトファイル
(例: `ext/pdo_mysql/mysql_driver.lo` 等) をコピーする段階で失敗
**対策候補**:
- `.libs/libphp.a` が既に生成されていれば、libtool の最終段失敗を無視して `cp` で回収
- make を `-j1` で実行して詳細エラーを観察
- `--preserve-dup-deps` は既に付いているので追加効果なし

### 4. Rosetta 経由で遅い

Apple Silicon 上で x86_64 Linux コンテナを動かすため、ビルドに **30〜60 分**かかる。
改善案:
- Linux aarch64 版 NDK (`android-ndk-r27c-linux-aarch64`) に切り替える (Google が配布中)
- `FROM --platform=linux/amd64` を外して ARM64 Linux ネイティブ実行
- ただし Dockerfile の `ENV PATH` や `--host` の triple も見直す必要あり

## トラブルシュート時のコマンド

### Docker build キャッシュを活用 (PHP 再 configure 不要で make だけリトライ)

```bash
# デフォルトで buildkit がキャッシュを使う
make aarch64
```

### キャッシュを完全にクリア (最初から)

```bash
docker builder prune -f
docker images | grep nativephp-libphp-mysql | awk '{print $3}' | xargs docker rmi -f
make aarch64
```

### コンテナに入って中を調べる

```bash
# 最後の成功レイヤで止めた状態に入る (通常は直前のステップ)
docker run --rm -it --platform=linux/amd64 \
  -v $(pwd):/workspace -w /workspace \
  $(docker images -q | head -1) sh

# 中で手動 make
cd /root/build && make libphp.la 2>&1 | tail -50
ls -la .libs/
```

### 生成された libphp.a の検証

```bash
# アーキテクチャ確認
ar t app/src/main/staticLibs/arm64-v8a/libphp.a | head -3    # .o ファイル一覧
ar x app/src/main/staticLibs/arm64-v8a/libphp.a zend.o        # 1 つ取り出し
file zend.o
# → ELF 64-bit LSB relocatable, ARM aarch64, ...

# MySQL シンボルの存在確認
nm app/src/main/staticLibs/arm64-v8a/libphp.a | grep -oE "zm_startup_[a-z_]+" | \
  sort -u | grep mysql
# 期待: zm_startup_mysqli, zm_startup_pdo_mysql, zm_startup_mysqlnd

# SQLite シンボルも維持されてるか
nm app/src/main/staticLibs/arm64-v8a/libphp.a | grep -oE "zm_startup_[a-z_]+" | \
  sort -u | grep sqlite
# 期待: zm_startup_pdo_sqlite, zm_startup_sqlite
```

## 将来的な拡張

PoC 成功後に対応したい追加作業:

1. **openssl 拡張追加**: Laravel の `encrypt()` や `Http::` 用
2. **curl 拡張追加**: Laravel HTTP クライアント用
3. **libxml2 対応**: `DOMDocument` 等を使うパッケージ互換性
4. **mbstring 拡張追加**: 日本語処理
5. **iOS 対応**: Xcode + iOS SDK でのクロスビルド
6. **ICU 対応**: `ext/intl` が必要なパッケージ互換性

これらは依存ライブラリ (libssl, libcurl, libxml2, libonig, libicu) も
Android NDK 向けにクロスビルドする必要があり、それぞれ相応の工数。
