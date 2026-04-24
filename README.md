# NativePHP Mobile + MySQL Template

![PHP](https://img.shields.io/badge/PHP-8.3.30-777BB4?logo=php&logoColor=white)
![Laravel](https://img.shields.io/badge/Laravel-13.6-FF2D20?logo=laravel&logoColor=white)
![NativePHP](https://img.shields.io/badge/NativePHP_Mobile-3.2-8892BF)
![Android](https://img.shields.io/badge/Android-arm64--v8a-3DDC84?logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-手順書のみ-lightgrey?logo=apple&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-27+-2496ED?logo=docker&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-8.4-4479A1?logo=mysql&logoColor=white)
![OpenSSL](https://img.shields.io/badge/OpenSSL-3.0.15-721412?logo=openssl&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Template](https://img.shields.io/badge/Template-Ready-blueviolet)
![Status](https://img.shields.io/badge/Android_CRUD-✅_Verified-success)

[NativePHP Mobile](https://nativephp.com/) (Laravel を Android/iOS アプリにパッケージする
フレームワーク) に **MySQL 対応** を追加するための独立ビルド環境付きテンプレート。

公式配布の `libphp.a` には `pdo_mysql` / `mysqli` / `mysqlnd` が含まれていないため、
Android NDK でクロスコンパイルした自前の `libphp.a` に差し替えることで、
モバイルアプリから業務 MySQL への直接接続を実現する。

## 実動作検証済

| 項目 | 結果 |
|---|---|
| Android エミュレータから MySQL 8.4.9 接続 | ✅ (2026-04-24) |
| `php artisan migrate` (Laravel 13 標準 10 テーブル作成) | ✅ |
| Eloquent CRUD (Create / Read / Update / Delete) | ✅ |
| 日本語 utf8mb4 対応 | ✅ |
| iOS 対応 | 🚧 手順書整備中 (Xcode.app インストール環境で検証予定) |

## 動作環境

- **開発ホスト**: macOS Apple Silicon (Intel Mac は未検証)
- **ターゲット**: Android arm64-v8a (API 32+)
- **PHP バージョン**: 8.3.30 (NativePHP 配布と同一)

### 必要ツール

```bash
brew install php@8.3 composer node
brew install --cask android-commandlinetools docker
# iOS 対応の場合: Xcode.app (Mac App Store 経由、約 12 GB)
softwareupdate --install-rosetta --agree-to-license
```

SDK コンポーネント:

```bash
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" \
           "ndk;27.0.12077973" "emulator" "system-images;android-34;default;arm64-v8a"
```

## クイックスタート

### 方法 A: GitHub の "Use this template" ボタン

リポジトリ上部の緑色ボタンから派生リポジトリを作成。

### 方法 B: 手動 clone

```bash
git clone https://github.com/NOGUD626/nativephp-mobile-mysql-template.git my-project
cd my-project
rm -rf .git && git init  # 履歴を切り離して新規プロジェクトに
```

### 方法 C: Makefile で一気通貫 🚀

```bash
make doctor         # 環境診断 (php/composer/docker/sdk/ndk/avd/xcode)
make all-android    # Composer install → libphp.a ビルド → 差し替え →
                    #   Kotlin patch → MySQL 起動 → エミュ起動 → APK ビルド
                    #   (初回 30〜60 分、Docker + NDK 初期ダウンロード含む)
```

成功するとエミュレータ画面に Laravel + MySQL の CRUD 結果が表示されます。

利用可能な Makefile target 一覧は `make help` で確認。

## ゼロから動作させるまでの 8 ステップ

詳細は [nativephp-test/docs/setup-guide.md](nativephp-test/docs/setup-guide.md) に記載。

```bash
# 1. Laravel / Composer 依存の復元
cd nativephp-test
composer install
cp .env.example .env  # APP_KEY 生成など
php artisan key:generate
echo "NATIVEPHP_APP_ID=com.yourname.yourapp" >> .env

# 2. NativePHP Mobile の Android プロジェクト生成
php artisan native:install android

# 3. 自前 libphp.a をクロスビルド (初回 25〜35 分、要 Docker)
cd ../mobile-libphp-builder
make aarch64 && make install-aarch64

# 4. 生成された .a を NativePHP プロジェクトへ差し替え
DEST=../nativephp-test/nativephp/android/app/src/main/staticLibs/arm64-v8a
cp app/src/main/staticLibs/arm64-v8a/libphp.a     $DEST/
cp app/src/main/staticLibs/arm64-v8a/libssl.a     $DEST/
cp app/src/main/staticLibs/arm64-v8a/libcrypto.a  $DEST/
cp app/src/main/staticLibs/arm64-v8a/libonig.a    $DEST/
cp app/src/main/staticLibs/arm64-v8a/libxml2.a    $DEST/

# 5. Kotlin の DB 設定を MySQL に切替
cd ../nativephp-test
patch -p1 < patches/laravel-environment-mysql.patch

# 6. MySQL サーバー起動 (Docker Compose)
docker compose -f docker-compose.mysql.yml up -d

# 7. Android エミュレータ起動
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH
emulator -avd Pixel_6_Pro_arm -no-snapshot-save &

# 8. ビルド & デプロイ
cd nativephp/android && ./gradlew clean && cd ../..
php artisan native:run android --build=debug
```

成功すると、エミュレータに `{"status":"ok","driver":"mysql",...}` が表示される。

## アーキテクチャ

### ランタイム (静的構成図 ASCII)

```
 [Android 端末 / エミュレータ]                    [ホスト Mac]
 ┌──────────────────────────────────────┐        ┌─────────────────┐
 │  APK  (com.nogulab.nativephpdemo)     │        │  Docker Compose │
 │  ┌──────────────────────────────┐    │        │                 │
 │  │ WebView (Blade / Livewire)   │    │        │  MySQL 8.4      │
 │  └──────────────┬───────────────┘    │        │  :3306          │
 │                 │ HTTP loopback       │        │                 │
 │  ┌──────────────▼───────────────┐    │        │  nativephp_test │
 │  │ Kotlin 層                    │    │        │  DB             │
 │  │  - MainActivity              │    │        └────────▲────────┘
 │  │  - LaravelEnvironment.kt     │    │                 │
 │  │    setenv DB_CONNECTION=mysql│    │                 │
 │  └──────────────┬───────────────┘    │                 │
 │                 │ JNI                 │                 │
 │  ┌──────────────▼───────────────┐    │                 │
 │  │ libphp_wrapper.so  (25 MB)   │    │                 │
 │  │  ├ libphp.a    ★ 自前ビルド  │    │                 │
 │  │  ├ libsqlite3.a              │    │                 │
 │  │  ├ libssl.a + libcrypto.a    │    │                 │
 │  │  ├ libonig.a  (Oniguruma)    │    │                 │
 │  │  └ libxml2.a                 │    │                 │
 │  └──────────────┬───────────────┘    │                 │
 │                 │ pdo_mysql (mysqlnd) │                 │
 │                 │                      │                 │
 │                 └──────────────────────┼─────────────────┘
 │                             TCP: 10.0.2.2:3306
 └──────────────────────────────────────┘
```

### 起動シーケンス (Mermaid)

```mermaid
sequenceDiagram
    actor User
    participant Emu as Android Emulator
    participant K as Kotlin Layer
    participant PHP as libphp_wrapper.so
    participant L as Laravel App
    participant MySQL as MySQL Container
    User->>Emu: App 起動
    Emu->>K: MainActivity.onCreate
    K->>K: LaravelEnvironment setupEnvironment()
    K->>PHP: setenv("DB_CONNECTION","mysql",1)
    K->>PHP: setenv("DB_HOST","10.0.2.2",1)
    K->>PHP: persistent_php_boot()
    PHP->>L: Laravel kernel boot
    User->>Emu: WebView requests "/"
    Emu->>K: PHPSchemeHandler intercepts
    K->>PHP: persistent_php_dispatch(GET /)
    PHP->>L: Router::dispatch
    L->>L: DB::connection()->getDriverName()
    L->>MySQL: TCP SELECT VERSION()
    MySQL-->>L: 8.4.9
    L-->>PHP: JSON response
    PHP-->>K: HTTP response
    K-->>Emu: render in WebView
    Emu-->>User: "🎉 driver: mysql"
```

### ビルドパイプライン (Mermaid)

```mermaid
flowchart LR
    Start([make all-android]) --> Doctor[doctor<br/>環境診断]
    Doctor --> Setup[setup<br/>composer install<br/>.env + key:generate<br/>native:install android]
    Setup --> LibPHP[libphp<br/>Docker でクロスビルド<br/>NDK r27c + OpenSSL 3<br/>+ Oniguruma + libxml2<br/>+ PHP 8.3.30]
    LibPHP --> Install[install-libs<br/>cp staticLibs/arm64-v8a/]
    Install --> Patch[patch<br/>LaravelEnvironment.kt<br/>DB_CONNECTION=mysql]
    Patch --> MySQL[mysql-up<br/>docker compose up]
    MySQL --> Emu[emu-start<br/>Pixel_6_Pro_arm]
    Emu --> Run[run-android<br/>gradle clean + APK]
    Run --> Result([🎉 driver: mysql])
```

詳細は [nativephp-test/docs/architecture.md](nativephp-test/docs/architecture.md)。

## ディレクトリ構成

```
nativephp-mobile-mysql-template/
├── README.md                          # 本ファイル
├── LICENSE                            # MIT
├── .gitignore
│
├── nativephp-test/                    # Laravel + NativePHP Mobile アプリ
│   ├── app/                           # Laravel 業務ロジック
│   ├── config/
│   ├── database/migrations/
│   ├── routes/web.php                 # CRUD テストルート含む
│   ├── docker-compose.mysql.yml       # MySQL 8.4 コンテナ定義
│   ├── patches/
│   │   └── laravel-environment-mysql.patch  # Kotlin DB 設定切替
│   ├── docs/
│   │   ├── prd.md                     # 要求仕様
│   │   ├── architecture.md            # アーキテクチャ詳細
│   │   ├── development-guide.md       # 開発手順
│   │   ├── repository-structure.md    # ディレクトリ責務
│   │   ├── setup-guide.md             # ゼロから再現手順
│   │   └── poc-result.md              # PoC 結果レポート
│   └── .steering/20260424-nativephp-mobile-mysql-poc/
│       ├── requirements.md
│       ├── design.md
│       └── tasklist.md
│
└── mobile-libphp-builder/             # libphp.a クロスビルダー
    ├── Dockerfile                     # Alpine + NDK r27c + クロスビルド
    ├── Makefile
    ├── *.patch                        # PHP ソースに当てるパッチ
    ├── README.md                      # ビルダー概要
    └── docs/
        └── build-guide.md             # ビルダー詳細
```

## 技術スタック

| カテゴリ | 使用バージョン |
|---|---|
| PHP | 8.3.30 (クロスコンパイル済) |
| Laravel | 13.6.0 |
| NativePHP Mobile | 3.2.2 |
| OpenSSL | 3.0.15 |
| Oniguruma | 6.9.9 |
| libxml2 | 2.12.7 |
| SQLite | 3.47.2 |
| MySQL | 8.4.9 (Docker Compose) |
| Android NDK | r27c |
| Android SDK | platforms;android-35, build-tools;35.0.0 |
| Docker Desktop | 27+ (Rosetta 経由 linux/amd64) |

## 含まれる PHP 拡張

- **DB**: pdo, pdo_mysql, mysqli, mysqlnd, pdo_sqlite, sqlite3
- **暗号**: openssl, hash, random
- **文字列**: mbstring (Oniguruma バックエンド)
- **XML**: dom, simplexml, xml, xmlreader, xmlwriter (libxml2 バックエンド)
- **標準**: json, pcre, session, spl, reflection, date, filter, fileinfo, ほか

## iOS 対応 (🚧 未検証)

iOS は Android とは別系統 (Xcode + iOS SDK) でクロスビルドする必要があり、
現状の `mobile-libphp-builder/Dockerfile` (Android NDK 専用) では対応不可。

### iOS 向けに必要なこと

1. **Xcode.app の full インストール** (Mac App Store)
2. **CocoaPods**: `brew install cocoapods`
3. **自前 libphp.a の iOS 向けビルド**:
   - Docker 不可 (Xcode は macOS ネイティブ)
   - ホスト macOS の bash スクリプトで `./configure --host=arm-apple-darwin ...`
   - `--enable-embed=static` (同じ)
   - `CC=$(xcrun --sdk iphoneos -f clang)`
   - `-isysroot $(xcrun --sdk iphoneos --show-sdk-path)`
   - OpenSSL / Oniguruma / libxml2 も同様に iOS SDK で再ビルド
4. **生成した `libphp.a` を `nativephp/ios/NativePHP/` の Xcode プロジェクトに配置**
5. **`LaravelEnvironment.kt` 相当の Swift/Obj-C コード** (`PersistentPHPRuntime.swift`)
   内で `setenv("DB_CONNECTION", "mysql", 1)` を呼ぶようにパッチ

### iOS 対応の着手手順 (推奨)

```bash
# 1. Xcode インストール後:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 2. NativePHP の iOS プロジェクト生成
cd nativephp-test
php artisan native:install ios
cd nativephp/ios && pod install

# 3. まず配布の libphp.a (SQLite 限定) で動作確認
open NativePHP.xcworkspace
# → Xcode でビルド → シミュレータで Laravel Welcome 確認

# 4. 自前 iOS 向け libphp.a を作る (TODO: シェルスクリプト化する)
# 5. 差し替えて MySQL 接続確認
```

### iOS 対応のリスク

- **App Store 審査**: TCP で外部 MySQL サーバーに直接接続する構成は App Store のガイドライン
  で制限される可能性がある (App Transport Security、暗号化通信必須)
- **シミュレータと実機の ABI 差**: シミュレータ用 (x86_64 / arm64 Mac) と実機用 (arm64)
  の 2 種類 `.a` が必要
- **Bitcode / Code Signing**: 配布時に必要

現状、iOS 対応手順は **文書のみ** で、実動作は未検証。検証協力者を募集中。

## トラブルシュート

[nativephp-test/docs/setup-guide.md](nativephp-test/docs/setup-guide.md) のトラブルシュート早見表を参照。

よくある問題:

| 症状 | 対応 |
|---|---|
| `Driver [mysql] not found` | 配布 libphp.a のまま。自前ビルドに差し替え忘れ |
| `Class "DOMDocument" not found` | libxml2 + DOM 拡張が未同梱 |
| `Call to undefined function openssl_*` | OpenSSL 拡張が未同梱 |
| `Connection refused 10.0.2.2:3306` | MySQL コンテナ未起動、Docker Desktop 再起動 |
| Docker build exit 133 | Apple Silicon で x86_64 NDK → `--platform=linux/amd64` 必要 |
| `driver: "sqlite"` のまま | `LaravelEnvironment.kt` の patch 適用忘れ |

## ライセンス

MIT License. 参考にした以下のプロジェクトも MIT:

- [NativePHP Mobile](https://github.com/NativePHP/mobile-air) (MIT)
- [v3l0c1r4pt0r/php-ndk](https://github.com/v3l0c1r4pt0r/php-ndk) (MIT) — `mobile-libphp-builder/` の原型

## 関連リンク

- [NativePHP 公式](https://nativephp.com/)
- [NativePHP Mobile v3 Introduction](https://nativephp.com/docs/mobile/3/getting-started/introduction)
- [v3l0c1r4pt0r blog - PHP on Android](https://re-ws.pl/2024/12/php-build-for-use-bundled-in-android-applications/)

## Contributing

Issue / PR 歓迎。特に以下の分野で協力者を求めてます:

- iOS 対応 (Xcode 環境での libphp.a ビルド手順確立)
- OpenSSL / Oniguruma / libxml2 以外の依存ライブラリ追加 (libcurl, libsodium, libzip, ICU)
- CI 化 (GitHub Actions + Linux aarch64 NDK でビルド高速化)
- Linux aarch64 ホスト NDK 対応 (Rosetta 経由の遅さを解消)
