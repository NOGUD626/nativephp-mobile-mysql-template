# PoC 結果: NativePHP Mobile + MySQL 対応

## 結論: 完全成功 ✅

**2026-04-24**, Android エミュレータ上の NativePHP Mobile Laravel アプリから
ホスト Mac 上の MySQL 8.4.9 コンテナへ直接接続 (mysqlnd) + **CRUD 全動作確認** に成功した。

### 検証した項目

| 操作 | 結果 |
|---|---|
| 接続 (PDO MySQL via mysqlnd) | ✅ MySQL 8.4.9 |
| `php artisan migrate` | ✅ Laravel 標準 10 テーブル作成 (cache, users, sessions 等) |
| Create (`User::create`) | ✅ id=1 生成、`name=テスト太郎_HHMMSS` |
| Read (`User::find`) | ✅ email 取得 |
| Update (`$user->save()`) | ✅ 名前更新が `fresh()` で反映確認 |
| Delete (`$user->delete()`) | ✅ 1 件 → 0 件 (count 確認) |
| 日本語 (utf8mb4) | ✅ 「テスト太郎」「更新太郎」正常保存・読出 |

### エミュレータ画面キャプチャ

```
{
    "status": "🎉 SUCCESS",
    "driver": "mysql",
    "version": "8.4.9",
    "env": {
        "DB_CONNECTION": "mysql",
        "DB_HOST": "10.0.2.2",
        "DB_DATABASE": "nativephp_test"
    }
}
```

## 技術スタック (最終構成)

| レイヤー | バージョン / 設定 |
|---|---|
| **Android 端末** | Pixel 6 Pro emulator (arm64-v8a, API 34) |
| **NativePHP Mobile** | 3.2.2 |
| **Laravel** | 13.6.0 |
| **PHP** | 8.3.30 (自前クロスビルド) |
| **PHP configure** | `--enable-zts --with-pic --enable-embed=static --enable-mbstring --with-openssl --with-libxml --enable-dom --enable-simplexml --enable-xml --enable-xmlreader --enable-xmlwriter --enable-mysqlnd --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd` |
| **PHP 拡張** | pdo_sqlite, sqlite3, **pdo_mysql**, **mysqli**, **mysqlnd**, mbstring, **openssl**, **dom**, **simplexml**, **xml**, **xmlreader**, **xmlwriter**, hash, json, spl, pcre, session, …ほか 40 個 |
| **OpenSSL** | 3.0.15 (自前 Android NDK クロスビルド) |
| **Oniguruma** | 6.9.9 (mbstring 正規表現用) |
| **libxml2** | 2.12.7 (DOM/XML 系拡張用) |
| **SQLite** | 3.47.2 (オマケで同梱) |
| **Android NDK** | r27c |
| **Docker build host** | Alpine 3.21 + Rosetta 2 (linux/amd64 platform) |
| **MySQL サーバー** | 8.4.9 (Docker Compose, ホスト `:3306`) |
| **エミュレータ → ホスト** | `10.0.2.2:3306` 経由 |

## 差し替えたファイル

`nativephp/android/app/src/main/staticLibs/arm64-v8a/` に以下を配置:

| ファイル | サイズ | 出典 |
|---|---|---|
| libphp.a | 26 MB | 自前ビルド (PHP 8.3.30 + MySQL 拡張) |
| libssl.a | 1.3 MB | 自前ビルド (OpenSSL 3.0.15) |
| libcrypto.a | 9 MB | 自前ビルド (OpenSSL 3.0.15) |
| libonig.a | 953 KB | 自前ビルド (Oniguruma 6.9.9) |
| libsqlite3.a | 2 MB | NativePHP 配布 (上書きせず) |
| libcurl.a, libxml2.a, libiconv.a, ... | ... | NativePHP 配布 (そのまま) |

## 修正したコード

`nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt:765`

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
 )
```

同内容を `patches/laravel-environment-mysql.patch` として保存済み (再現用)。

## ビルドフロー (最終形)

```
[Host Mac (Apple Silicon)]
    │
    ├─ docker compose up mysql      (MySQL 8.4.9 on :3306)
    │
    └─ cd mobile-libphp-builder/ && make aarch64 && make install-aarch64
            │
            ├─ Docker (Rosetta 経由 linux/amd64)
            │   ├─ Alpine 3.21 + 各種ツール (perl, binutils, pkgconfig 等)
            │   ├─ NDK r27c ダウンロード
            │   ├─ OpenSSL 3.0.15 クロスビルド → libssl.a + libcrypto.a
            │   ├─ Oniguruma 6.9.9 クロスビルド → libonig.a
            │   └─ PHP 8.3.30 クロスビルド → libphp.a (26 MB, 390 個の .o)
            │
            └─ 出力: app/src/main/staticLibs/arm64-v8a/{libphp,libssl,libcrypto,libonig}.a
    │
    ├─ cp .../libphp.a nativephp-test/nativephp/android/.../staticLibs/arm64-v8a/
    ├─ patch -p1 < patches/laravel-environment-mysql.patch
    ├─ cd nativephp/android && ./gradlew clean
    │
    └─ php artisan native:run android --build=debug
            │
            ├─ Laravel コードを laravel_bundle.zip に圧縮
            ├─ Gradle + CMake で libphp_wrapper.so をビルド
            │   └─ --whole-archive で libphp.a + libssl.a + libcrypto.a + libonig.a + ... を静的リンク
            ├─ APK 生成 (79 MB)
            ├─ adb install でエミュレータに送信
            └─ am start で起動
                    │
                    └─ PHP ランタイムが Kotlin の setenv で DB_CONNECTION=mysql をセット
                       → Laravel が 10.0.2.2:3306 に TCP 接続
                       → mysqlnd が MySQL 8.4.9 とプロトコル通信
                       → SELECT VERSION() 成功 ✅
```

## ハマりどころ集 (これから挑戦する人へ)

6 回のリトライで解消した問題を時系列で:

| # | 症状 | 根本原因 | 解決策 |
|---|---|---|---|
| 1 | Docker build exit 133 | Apple Silicon で x86_64 NDK | `FROM --platform=linux/amd64` |
| 2 | `pkg-config not found` | mysqlnd compression が zlib 要求 | `--disable-mysqlnd-compression-support` |
| 3 | `make libphp.la Error 1 (libtool)` | libtool の basename conflict 解消で `.la` 生成失敗 | libtool 迂回 + `llvm-ar rcs` で直接アーカイブ化 |
| 4 | `ar: command not found` | Alpine に binutils なし | `apk add binutils` |
| 5 | duplicate symbol (filter.o 4 個) | `find` の除外パターンが浅い | `-not -path "*/.libs/*"` (全階層) |
| 6 | `relocation R_AARCH64_* -fPIC` | 非 PIC で shared にリンク不可 | `CFLAGS="-fPIC" --with-pic` |
| 7 | `tsrm_get_ls_cache` 未定義 | NativePHP は ZTS 前提 | `--enable-zts` |
| 8 | `getloadavg` 未定義 | Android bionic に無い | `ac_cv_func_getloadavg=no` |
| 9 | `mb_split` ランタイムエラー | mbstring 拡張なし | Oniguruma クロスビルド + `--enable-mbstring` |
| 10 | Oniguruma libtool エラー | 同上 (PHP と同じ libtool 問題) | `make -C src -j7` + 手動 cp |
| 11 | `onig.pc` 配置ミス | `find ... -exec cp` で配置 | |
| 12 | `openssl_cipher_iv_length` ランタイムエラー | openssl 拡張なし | OpenSSL 3.0.15 クロスビルド + `--with-openssl` |
| 13 | OpenSSL Configure exit 127 | perl 無し | `apk add perl` |
| 14 | `no-apps` オプション無効 | OpenSSL 3.x の仕様変更 | オプション削除 |
| 15 | `SSL_CTX_set0_tmp_dh_pkey` リンクエラー | NativePHP 配布 libssl は古い (1.1.x) | 自前 libssl.a + libcrypto.a も staticLibs に配置 |

## 今回 Scope 外 (将来的な拡張)

- **iOS 対応**: 別途 Xcode + iOS SDK でのクロスビルド
- **libxml2 対応**: ext/dom, ext/simplexml を有効化したい時
- **libcurl 対応**: Laravel Http クライアントで必要
- **libzip 対応**: ext/zip
- **libsodium 対応**: ext/sodium (一部の password_verify)
- **ICU 対応**: ext/intl
- **upstream PR**: NativePHP 公式に MySQL variant を追加提案
- **CI 化**: GitHub Actions でのビルド自動化 (Linux aarch64 NDK へ移行したほうが速い)

## 関連ドキュメント

- [docs/prd.md](./prd.md) — 要求仕様
- [docs/architecture.md](./architecture.md) — アーキテクチャ詳細
- [docs/development-guide.md](./development-guide.md) — 開発手順
- [docs/repository-structure.md](./repository-structure.md) — ディレクトリ構成
- [mobile-libphp-builder/README.md](../../mobile-libphp-builder/README.md) — libphp.a ビルダー
- [mobile-libphp-builder/docs/build-guide.md](../../mobile-libphp-builder/docs/build-guide.md) — ビルド詳細
