# アーキテクチャ: NativePHP Mobile (Android) + MySQL 対応

## 全体像

```
  [Android 端末 / エミュレータ]
  ┌──────────────────────────────────────────────────────┐
  │  APK (com.noguchi.nativephpdemo)                      │
  │  ┌──────────────────────────────────────────────┐   │
  │  │ Kotlin 層                                      │   │
  │  │  - MainActivity (WebView を表示)               │   │
  │  │  - LaravelEnvironment.kt                       │   │
  │  │     (setenv で Laravel 用の環境変数を注入)     │   │
  │  │  - PHPBridge (Kotlin → JNI → C)                │   │
  │  └──────────────────────┬───────────────────────┘   │
  │                         │ JNI                          │
  │  ┌──────────────────────▼───────────────────────┐   │
  │  │ C/C++ 層 (libphp_wrapper.so ≈ 25 MB)          │   │
  │  │  - PHP.c / bridge_jni.cpp (NativePHP が作成)  │   │
  │  │  - libphp.a (PHP 本体 + 内蔵拡張)             │   │
  │  │  - libsqlite3.a / libssl.a / libcurl.a 等    │   │
  │  └──────────────────────┬───────────────────────┘   │
  │                         │                              │
  │                         │ PDO_MYSQL (自前ビルド後)     │
  │  ┌──────────────────────▼───────────────────────┐   │
  │  │ Laravel アプリ (laravel_bundle.zip → 展開)    │   │
  │  │  - Eloquent / Query Builder                   │   │
  │  │  - routes/ controllers/ migrations/           │   │
  │  └──────────────────────┬───────────────────────┘   │
  └─────────────────────────┼──────────────────────────┘
                            │
                            │ TCP: 10.0.2.2:3306
                            │ (エミュレータ→ホスト)
                            ▼
  [ホスト Mac]
  ┌──────────────────────────────────────────┐
  │  Docker Desktop                          │
  │   └─ MySQL 8.4 コンテナ (:3306)          │
  └──────────────────────────────────────────┘
```

## NativePHP Mobile の核心: `libphp_wrapper.so`

Android APK の `lib/arm64-v8a/libphp_wrapper.so` (約 25 MB) が PHP ランタイムの本体。
CMake が以下を**静的リンク**して単一の共有ライブラリにまとめている:

| 静的ライブラリ | サイズ | 役割 |
|---|---|---|
| `libphp.a` | 22 MB | PHP 本体 + 内蔵拡張 (Zend エンジン含む) |
| `libsqlite3.a` | 2.0 MB | SQLite 3 本体 (C 実装) |
| `libcrypto.a` / `libssl.a` | 6.3 MB | OpenSSL |
| `libxml2.a` | 2.6 MB | libxml2 |
| `libcurl.a` | 1.3 MB | libcurl |
| `libiconv.a` / `libonig.a` / `libsodium.a` | 2.7 MB | mbstring / sodium / iconv |

CMake の該当部分 (抜粋):

```cmake
target_link_libraries(php_wrapper
    -Wl,--whole-archive php -Wl,--no-whole-archive   # PHP モジュール登録子を保護
    -Wl,--start-group ${STATIC_DEP_LIBS} -Wl,--end-group  # 循環参照解決
)
```

- `--whole-archive`: `libphp.a` 内の module registration コンストラクタを link から削ぎ落とさない
- `--start-group/--end-group`: `libxml2` と `libiconv` の相互参照を解決
- `--defsym`: libiconv の関数名エイリアス (`iconv_open` → `libiconv_open`)

## PHP ランタイムが起動するまで

1. `MainActivity.onCreate()` で `LaravelEnvironment.kt::setupEnvironment()` 呼び出し
2. Kotlin 側で `setenv("DB_CONNECTION", "sqlite", 1)` など **Laravel 用環境変数をハードコード注入**
3. JNI 経由で `persistent_php_boot()` を呼ぶ → PHP インタプリタが起動
4. `laravel_bundle.zip` をサンドボックス (`$appStorageDir/laravel/`) に展開
5. 以降、WebView の URL 要求が `PHPSchemeHandler` でインターセプトされ、
   JNI 経由で `persistent_php_dispatch()` が呼ばれて Laravel にルーティングされる

## v3.1 で導入された Persistent モード

- 旧来: リクエストごとに Laravel カーネルをブート → 200-300ms/req
- v3.1+: ブート済みカーネルを保持、リクエスト間で一部状態をリセット → 5-30ms/req (約 10 倍)
- 失敗時は Classic モード (毎回ブート) にフォールバック
- 参考ソース: `vendor/nativephp/mobile/src/Runtime.php`

## MySQL 対応に必要な 3 つの修正

### (1) `libphp.a` の再ビルド

配布 `libphp.a` には MySQL 系シンボルが存在しない (`nm` で確認済):

```
$ nm libphp.a | grep -oE "zm_startup_[a-z_]+" | sort -u | grep mysql
(何も出ない)
```

自前 NDK クロスビルドで以下のフラグを追加:

```
--enable-mysqlnd                      # mysqlnd (純 PHP 実装、libmysqlclient 不要)
--with-pdo-mysql=mysqlnd              # PDO ドライバ
--with-mysqli=mysqlnd                 # mysqli 拡張
--disable-mysqlnd-compression-support # zlib 依存回避
```

詳細は `mobile-libphp-builder/docs/build-guide.md` を参照。

### (2) `LaravelEnvironment.kt` の書き換え

`nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt:765`
でハードコードされている DB 設定を MySQL 向けに変更:

```diff
 setEnvironmentVariables(
-    "DB_CONNECTION" to "sqlite",
-    "DB_DATABASE" to "${appStorageDir.absolutePath}/persisted_data/database/database.sqlite",
+    "DB_CONNECTION" to "mysql",
+    "DB_HOST" to "10.0.2.2",
+    "DB_PORT" to "3306",
+    "DB_DATABASE" to "nativephp_test",
+    "DB_USERNAME" to "root",
+    "DB_PASSWORD" to "root",
 )
```

Laravel の `.env` だけ変えても効かない (Kotlin 側 setenv が後から優先で上書きするため)。

### (3) MySQL サーバー起動

Docker Compose でホスト Mac 上に MySQL を立て、`10.0.2.2:3306` で
エミュレータから到達可能にする (Android エミュレータは `10.0.2.2` をホスト Mac として扱う)。

## ビルドフロー (native:run android)

```
 php artisan native:run android
    │
    ├─ Laravel ソースを nativephp/android/app/src/main/assets/laravel_bundle.zip に圧縮
    │
    ├─ nativephp/android/app/build.gradle.kts のプレースホルダーを置換
    │   (REPLACE_APP_ID → com.noguchi.nativephpdemo 等)
    │
    ├─ ./gradlew assembleDebug
    │    │
    │    └─ externalNativeBuild (CMake)
    │         │
    │         ├─ libphp.a + libsqlite3.a + ... を静的リンク
    │         └─ libphp_wrapper.so 生成 (arm64-v8a)
    │
    ├─ APK 生成 (app-debug.apk, 約 79 MB)
    │
    ├─ adb install で emulator-5554 にインストール
    │
    └─ adb shell am start でアプリ起動
```

## 関連ファイルの場所

| 何 | 場所 |
|---|---|
| Laravel アプリ | `/Users/noguchi/Desktop/sandbox/nativephp-test/` |
| 自前 libphp.a ビルダー | `/Users/noguchi/Desktop/sandbox/mobile-libphp-builder/` |
| 生成された Android プロジェクト | `nativephp-test/nativephp/android/` |
| 配布の libphp.a (置換対象) | `nativephp/android/app/src/main/staticLibs/arm64-v8a/libphp.a` |
| CMakeLists.txt | `nativephp/android/app/src/main/cpp/CMakeLists.txt` |
| PHP 環境変数ハードコード | `nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt:765` |
| PHP バイナリ配布元 (参考) | `https://bin.nativephp.com/main/versions.json` |
