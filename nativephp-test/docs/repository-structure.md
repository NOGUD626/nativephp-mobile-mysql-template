# リポジトリ構造

## 全体像

```
~/Desktop/sandbox/
├── nativephp-test/                # 本プロジェクト (Laravel アプリ + PoC 管理)
└── mobile-libphp-builder/         # 自前 libphp.a ビルダー (独立リポジトリ)
```

2 つのディレクトリは独立した git リポジトリ。Laravel アプリ側から libphp.a ビルダーを
参照するのは **ファイルコピーのみ** (ビルダーの成果物を手動で staticLibs/ に置く)。

## nativephp-test/ (本プロジェクト)

```
nativephp-test/
├── app/                           # Laravel アプリケーション本体
│   ├── Http/Controllers/
│   ├── Models/
│   └── Providers/
├── bootstrap/
├── config/
│   └── database.php               # Laravel DB 設定 (Kotlin の setenv で上書きされる)
├── database/
│   ├── migrations/                # マイグレーション
│   └── database.sqlite            # ホスト側 dev 用の SQLite (Android には行かない)
├── nativephp/                     # NativePHP 生成物 (.gitignore 対象)
│   ├── android/                   # native:install で生成された Android プロジェクト
│   │   └── app/src/main/
│   │       ├── assets/laravel_bundle.zip   # ビルド時に Laravel が圧縮される
│   │       ├── cpp/                        # C/C++ ブリッジ (PHP.c, bridge_jni.cpp)
│   │       │   └── CMakeLists.txt
│   │       ├── java/com/nativephp/mobile/bridge/
│   │       │   └── LaravelEnvironment.kt   # DB_CONNECTION 等の setenv
│   │       └── staticLibs/arm64-v8a/       # 静的リンク対象 (libphp.a 差し替え箇所)
│   ├── binaries/                          # ダウンロード済み PHP zip キャッシュ
│   └── android-build.log                  # ビルド毎のログ
├── routes/
│   └── web.php
├── vendor/
│   └── nativephp/mobile/          # NativePHP Mobile Composer パッケージ
├── docs/                          # 本ドキュメント
│   ├── prd.md                     # 要求仕様
│   ├── architecture.md            # アーキテクチャ
│   ├── development-guide.md       # 開発手順
│   └── repository-structure.md    # 本ファイル
├── .steering/                     # 作業単位の計画・追跡
│   └── 20260424-nativephp-mobile-mysql-poc/
│       ├── requirements.md
│       ├── design.md
│       └── tasklist.md
├── .env                           # Laravel 環境変数 (Mobile では Kotlin が上書きする)
├── composer.json
└── package.json
```

### 責務

| ディレクトリ | 責務 |
|---|---|
| `app/` | Laravel アプリの業務ロジック。将来 MySQL で Eloquent を動かす対象 |
| `nativephp/android/` | native:install で生成される Android Studio プロジェクト。git 管理外 |
| `nativephp/android/app/src/main/cpp/` | PHP ランタイム組込のための C/C++ ブリッジ |
| `nativephp/android/app/src/main/staticLibs/arm64-v8a/` | **自前 libphp.a の差し替え対象** |
| `nativephp/android/app/src/main/java/.../LaravelEnvironment.kt` | DB 接続先を決める Kotlin ハードコード |
| `vendor/nativephp/mobile/resources/androidstudio/` | Android プロジェクトテンプレートの原本 |
| `docs/` | 永続ドキュメント。仕様・アーキテクチャ・運用手順 |
| `.steering/` | 作業単位の計画。完了後も参照用に保持 |

## mobile-libphp-builder/ (自前 libphp.a ビルダー)

```
mobile-libphp-builder/
├── Dockerfile                     # Alpine Linux + NDK r27c + PHP クロスビルド
├── Makefile                       # docker build / cp のラッパー
├── README.md                      # ビルダーの概要
├── *.patch                        # PHP ソースに当てるパッチ (fork, resolv, dns 等)
├── docs/
│   └── build-guide.md             # ビルド手順の詳細
└── app/src/main/staticLibs/arm64-v8a/
    └── libphp.a                   # ビルド成果 (docker cp で出力される)
```

詳細は [mobile-libphp-builder/README.md](../../mobile-libphp-builder/README.md) を参照。

## 命名規則 (CLAUDE.md 準拠)

- **テーブル名は単数形**: `user`, `tag`, `reader` (複数形 `users` は使わない)
- **複数件変数は `~List`**: `$userList = User::all()` (`$users` は使わない)
- **マジックナンバー禁止**: 定数化 + enum
- **Guard Clause**: 早期 return でネストを浅く
- **3 分岐以上は switch**: if-else if チェーンは避ける

## コミット規約

- Conventional Commits + 日本語本文
- `Co-Authored-By: Claude ...` トレーラーは付けない
- PR 末尾の `🤖 Generated with Claude Code` も付けない
