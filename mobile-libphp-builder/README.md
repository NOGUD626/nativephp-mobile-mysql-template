# mobile-libphp-builder

NativePHP Mobile 用 `libphp.a` を **MySQL 拡張付き** でクロスコンパイルするための
独立ビルド環境。

## 経緯

- 親プロジェクト: `~/Desktop/sandbox/nativephp-test/` (NativePHP Mobile + Laravel PoC)
- 公式の `libphp.a` (https://bin.nativephp.com/ 配布版) には **`pdo_mysql` / `mysqli` / `mysqlnd` が同梱されていない**
- ベース: [v3l0c1r4pt0r/php-ndk](https://github.com/v3l0c1r4pt0r/php-ndk) (MIT) を
  **完全コピーで独立リポジトリ化** し、NativePHP Mobile 互換の `libphp.a` を
  作るよう改造

## 主な改造点 (v3l0c1r4pt0r/php-ndk からの差分)

| 変更 | 理由 |
|---|---|
| `PHP_VERSION` を `8.4.2` → `8.3.30` | NativePHP 配布と一致させる |
| `--enable-embed=static` を追加 | `sapi/embed/libphp.a` を出力させる (元は CLI バイナリ) |
| `--disable-cli --disable-cgi` を追加 | embed モードと共存 |
| `--enable-mysqlnd` + `--with-pdo-mysql=mysqlnd` + `--with-mysqli=mysqlnd` | **MySQL 対応 (今回の目的)** |
| `--disable-mysqlnd-compression-support` | zlib + pkg-config 依存を避ける |
| `FROM --platform=linux/amd64` | Apple Silicon Mac 上で x86_64 NDK を Rosetta 経由で実行 |
| `make libphp.la` ターゲット | CLI バイナリではなく static library を作る |
| 出力先を `staticLibs/` に変更 | NativePHP 側の配置 (`jniLibs/` は shared 用) |
| ターゲットプラットフォームを `aarch64` のみに絞る | PoC スコープ (arm64-v8a エミュレータ前提) |

## 前提環境 (macOS Apple Silicon)

- Docker Desktop 27+
- Rosetta 2 (`softwareupdate --install-rosetta --agree-to-license`)
- GNU make

## ビルド手順

```bash
# 初回のみ 30〜60 分 (NDK r27c ダウンロード + Alpine + PHP クロスビルド)
make aarch64

# install サブコマンドで成果物を取り出す (docker cp ベース)
make install-aarch64
```

## 成果物

ビルド成功時、以下のパスにファイルが配置される:

```
mobile-libphp-builder/app/src/main/staticLibs/arm64-v8a/
├── libphp.a           ← 目的のもの (MySQL 対応 static library)
└── libsqlite3.so      ← おまけ (SQLite shared library)
```

## NativePHP プロジェクトへの組込

親プロジェクト (`~/Desktop/sandbox/nativephp-test/`) への差し替え:

```bash
cp app/src/main/staticLibs/arm64-v8a/libphp.a \
   ~/Desktop/sandbox/nativephp-test/nativephp/android/app/src/main/staticLibs/arm64-v8a/libphp.a

cd ~/Desktop/sandbox/nativephp-test
(cd nativephp/android && ./gradlew clean)
php artisan native:run android --build=debug
```

この後、APK の `libphp_wrapper.so` に MySQL 関連シンボルが含まれているかを nm で確認:

```bash
unzip -p nativephp/android/app/build/outputs/apk/debug/app-debug.apk \
  lib/arm64-v8a/libphp_wrapper.so > /tmp/check.so
nm /tmp/check.so | grep -c mysql    # 数百以上あれば OK
```

## 関連ドキュメント

- [docs/build-guide.md](docs/build-guide.md) — 詳細ビルド手順とトラブルシュート
- 親プロジェクトの PoC 設計: `../nativephp-test/.steering/20260424-nativephp-mobile-mysql-poc/design.md`

## ライセンス

元コード (v3l0c1r4pt0r/php-ndk): MIT License を継承。
改造分も MIT 継続。`fork.patch` 等のパッチ群は元リポジトリと同じ。

## 制約 / 未対応

- **iOS 未対応**: Xcode + iOS SDK の別系統が必要、今回はスコープ外
- **拡張セットが最小**: openssl, curl, libxml2, mbstring, sodium は非有効
  (NativePHP 配布の `libphp.a` と完全互換ではない)
- Laravel で `openssl_encrypt` / `Http::get` / XML 処理を使うと落ちる可能性あり
  → PoC で MySQL 疎通確認まで済んだら、拡張追加フェーズに移行する
