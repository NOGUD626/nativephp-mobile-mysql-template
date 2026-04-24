# 設計: NativePHP Mobile + MySQL 対応 PoC

## 設計の 3 レイヤー

MySQL 対応は **1 か所** の修正では達成できない。以下の 3 レイヤーすべての改修が必要。

```
    ┌─────────────────────────────────────────┐
    │ L3: MySQL サーバー                        │
    │   Docker Compose (MySQL 8.4)              │
    │   ホスト :3306 → エミュレータ 10.0.2.2:3306 │
    └─────────────────────────────────────────┘
                     ▲ TCP
                     │
    ┌─────────────────────────────────────────┐
    │ L2: Kotlin 層 (LaravelEnvironment.kt)    │
    │   setenv("DB_CONNECTION", "mysql", 1)    │
    │   setenv("DB_HOST", "10.0.2.2", 1) 等     │
    └─────────────────────────────────────────┘
                     ▲ PHP 側が getenv() で読む
                     │
    ┌─────────────────────────────────────────┐
    │ L1: PHP ランタイム (libphp.a)             │
    │   pdo_mysql / mysqli / mysqlnd を組込    │
    │   ← 自前 NDK クロスビルドで再生成         │
    └─────────────────────────────────────────┘
```

## L1: 自前 libphp.a のビルド設計

### ビルド環境

- **ベース**: `v3l0c1r4pt0r/php-ndk` (MIT License) を独立リポジトリ化して使用
- **コンテナ**: Alpine Linux 3.21 (`--platform=linux/amd64` で Rosetta 経由)
- **クロスコンパイラ**: Android NDK r27c (Linux x86_64 版)
- **ターゲット**: `aarch64-linux-android32` (Android arm64-v8a, API level 32)

### configure フラグ (MySQL 対応)

```bash
./configure \
  --host=aarch64-linux-android32 \
  --disable-cli \
  --disable-cgi \
  --disable-phar \
  --disable-phpdbg \
  --disable-dom --disable-simplexml --disable-xml \
  --disable-xmlreader --disable-xmlwriter \
  --without-pear --without-libxml \
  --enable-embed=static \
  --with-sqlite3 \
  --with-pdo-sqlite \
  --enable-mysqlnd \
  --disable-mysqlnd-compression-support \
  --with-pdo-mysql=mysqlnd \
  --with-mysqli=mysqlnd \
  SQLITE_CFLAGS="-I/root/sqlite-amalgamation-3470200" \
  SQLITE_LIBS="-lsqlite3 -L/root/sqlite-amalgamation-3470200" \
  CC=aarch64-linux-android32-clang
```

重要ポイント:

- **`--enable-embed=static`**: `sapi/embed/libphp.a` を生成させる (これを差し替える)
- **`--disable-cli --disable-cgi`**: embed モードと両立させる (CLI バイナリは作らない)
- **`mysqlnd`**: 純 PHP 実装なので `libmysqlclient` を別途リンクする必要なし
- **`--disable-mysqlnd-compression-support`**: zlib + pkg-config 依存を避ける

### 出力

- `build/.libs/libphp.a` (目標: MySQL シンボル入り、数十 MB)

## L2: Kotlin 層の修正設計

### 変更対象

`nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt`

### 変更内容 (二カ所の setEnvironmentVariables ブロックのうち該当部)

```diff
 setEnvironmentVariables(
     "APP_URL" to "http://127.0.0.1",
     "ASSET_URL" to "http://127.0.0.1/_assets",
-    "DB_CONNECTION" to "sqlite",
-    "DB_DATABASE" to "${appStorageDir.absolutePath}/persisted_data/database/database.sqlite",
+    "DB_CONNECTION" to "mysql",
+    "DB_HOST" to "10.0.2.2",
+    "DB_PORT" to "3306",
+    "DB_DATABASE" to "nativephp_test",
+    "DB_USERNAME" to "root",
+    "DB_PASSWORD" to "root",
     "CACHE_DRIVER" to "file",
     ...
 )
```

PoC では値をハードコードするが、本番運用では:

- BuildConfig 経由で `.env` 相当を注入 (Gradle ビルド時に環境変数注入)
- 接続情報は Android Keystore で暗号化保存

### 永続化戦略

`nativephp/android/` は `native:install --force` で再生成されるので、
変更が消える。PoC 段階では:

- `--force` を使わない運用
- 変更を patch ファイルとして保存 (`patches/laravel-environment-mysql.patch`)

本格運用では:

- `vendor/nativephp/mobile/resources/androidstudio/...` 側を直接編集
- または fork 扱いで patch を composer post-install-cmd で当てる

## L3: MySQL サーバー設計

### docker-compose.mysql.yml

```yaml
services:
  mysql:
    image: mysql:8.4
    container_name: nativephp-mysql
    ports:
      - "3306:3306"                 # ホスト Mac の 3306 に bind
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: nativephp_test
      MYSQL_USER: laravel
      MYSQL_PASSWORD: laravel
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

### エミュレータから見たネットワーク

- Android エミュレータの中からは `localhost` = エミュレータ自身
- **ホスト Mac を指すには `10.0.2.2`** (エミュレータ NAT)
- よって Laravel 側 (アプリ内) は `DB_HOST=10.0.2.2`
- ホスト Mac の MySQL はすでに 3306 bind なのでそのまま届く

## 動作確認のためのテストルート

`routes/web.php`:

```php
use Illuminate\Support\Facades\DB;

Route::get('/db-test', function () {
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

### 成功した場合

```json
{"status":"ok","driver":"mysql","version":"8.4.3"}
```

### 失敗パターン (想定)

| レイヤー | エラー | 症状 |
|---|---|---|
| L1 (libphp) | `Driver [mysql] not found` | libphp.a に pdo_mysql が無い |
| L2 (Kotlin) | `driver: "sqlite"` になる | LaravelEnvironment.kt 書き換え忘れ |
| L3 (MySQL) | `Connection refused` | MySQL コンテナ未起動 or 3306 未 bind |
| L3 (ネットワーク) | `No such host` | DB_HOST を `localhost` にしてしまった |

## リリース判定

成功基準 4 つ全てがグリーンになったら PoC 完了。その後、以下を検討:

1. **拡張セットの完全化**: openssl, curl, libxml2, mbstring も追加した完全版 libphp.a
2. **iOS 対応**: Xcode + iOS SDK でクロスビルド (別の大仕事)
3. **本番化**: Android Keystore, 暗号化接続, ビルド自動化 (CI)
