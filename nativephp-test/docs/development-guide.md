# 開発ガイド: NativePHP Mobile (Android) + MySQL PoC

## 前提環境 (macOS Apple Silicon)

| ツール | バージョン | インストール |
|---|---|---|
| PHP | 8.3.x | `brew install php@8.3` |
| Composer | 2.x | `brew install composer` |
| Node.js | 20+ | `brew install node` |
| Android Studio | 2025.2+ | [公式](https://developer.android.com/studio) |
| Android SDK | 35+ | `brew install --cask android-commandlinetools` 推奨 |
| Android NDK | r27+ | `sdkmanager --install "ndk;27.0.12077973"` |
| Docker Desktop | 27+ | `brew install --cask docker` |

環境変数:

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH=$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH
```

## 初回セットアップ

```bash
cd /Users/noguchi/Desktop/sandbox/nativephp-test

# (1) Composer 依存のインストール
composer install

# (2) NativePHP Mobile の初期化 (Android プロジェクト生成 + libphp.a ダウンロード)
php artisan native:install android

# (3) 環境状況を確認
php artisan native:debug
```

## 動作確認 (配布 libphp.a のまま)

```bash
# エミュレータ起動 (別ターミナル、または & で background)
emulator -avd Pixel_6_Pro_arm -no-snapshot-save

# ビルド + インストール + 起動
php artisan native:run android --build=debug

# → Laravel Welcome ページが Android エミュレータに表示されれば成功
```

## 自前 libphp.a に差し替える手順

1. `../mobile-libphp-builder/` でビルド (詳細は
   [mobile-libphp-builder/docs/build-guide.md](../../mobile-libphp-builder/docs/build-guide.md))
2. 生成された `libphp.a` を差し替え:
   ```bash
   cp /Users/noguchi/Desktop/sandbox/mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/libphp.a \
      nativephp/android/app/src/main/staticLibs/arm64-v8a/libphp.a
   ```
3. `LaravelEnvironment.kt` の DB 設定を MySQL に書き換え (次節)
4. MySQL サーバー起動 (次々節)
5. gradle クリーンリビルド:
   ```bash
   cd nativephp/android && ./gradlew clean && cd ../..
   php artisan native:run android --build=debug
   ```

## Kotlin 側 DB 設定の書き換え

`nativephp/android/app/src/main/java/com/nativephp/mobile/bridge/LaravelEnvironment.kt:765` を編集:

```kotlin
setEnvironmentVariables(
    "APP_URL" to "http://127.0.0.1",
    "ASSET_URL" to "http://127.0.0.1/_assets",
    "DB_CONNECTION" to "mysql",
    "DB_HOST" to "10.0.2.2",        // エミュレータから見たホスト Mac
    "DB_PORT" to "3306",
    "DB_DATABASE" to "nativephp_test",
    "DB_USERNAME" to "root",
    "DB_PASSWORD" to "root",
    // ...
)
```

この変更は `native:install --force` で上書きされる (vendor から再 copy されるため)。
永続化したい場合は `vendor/nativephp/mobile/resources/androidstudio/...` 側も書き換える
(PoC 段階では `native:install --force` を実行しない運用で回避)。

## MySQL サーバー起動 (Docker Compose)

`docker-compose.mysql.yml` を使用:

```bash
docker compose -f docker-compose.mysql.yml up -d
docker compose -f docker-compose.mysql.yml logs -f mysql  # 起動ログ確認
```

接続確認:

```bash
docker compose -f docker-compose.mysql.yml exec mysql mysql -uroot -proot \
  -e "SELECT VERSION();"
```

## Laravel 側で MySQL 接続を確認するテストルート

`routes/web.php` に追加:

```php
use Illuminate\Support\Facades\DB;

Route::get('/db-test', function () {
    $version = DB::selectOne('SELECT VERSION() as v');
    $driver = DB::connection()->getDriverName();
    return [
        'driver'  => $driver,
        'version' => $version->v,
    ];
});
```

エミュレータのブラウザで `http://127.0.0.1/db-test` にアクセス (NativePHP の
`PHPSchemeHandler` が処理する内部 URL)。`driver: mysql` が返れば成功。

## コミット規約

Conventional Commits、日本語本文:

```
feat(builder): mysqlnd 有効化の configure フラグ追加
fix(android): Kotlin setenv の DB_CONNECTION を mysql に修正
docs: architecture.md に MySQL 連携フローを追記
```

トレーラー `Co-Authored-By: Claude ...` は付けない。

## よくあるエラー

| 症状 | 原因 | 対処 |
|---|---|---|
| `Driver [mysql] not found` | 配布 libphp.a のまま MySQL 設定した | 自前ビルド libphp.a に差し替える |
| `Connection refused 10.0.2.2:3306` | MySQL サーバー未起動 or port 未公開 | `docker compose ps` で確認 |
| `./gradlew clean` がハング | Java のバージョン不整合 | `java -version` で 21 を確認 |
| `exit code 133` | Apple Silicon で x86_64 NDK 実行 | Dockerfile を `--platform=linux/amd64` に固定 |
| `pkg-config not found` | mysqlnd compression が zlib 要求 | `--disable-mysqlnd-compression-support` 追加 |
| `Activity class ... does not exist` | MainActivity のパッケージ名誤認 | `native:run` に任せて自分で am start しない |

## クリーン再開手順

全部やり直したいとき:

```bash
cd /Users/noguchi/Desktop/sandbox/nativephp-test
rm -rf nativephp/android nativephp/binaries nativephp/android-build.log
php artisan native:install android --force
```

これで `nativephp/android/` が vendor からフレッシュに再生成される。
