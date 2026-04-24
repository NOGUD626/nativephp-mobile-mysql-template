# タスクリスト: NativePHP Mobile + MySQL 対応 PoC

進行中のチェックリスト。完了 = `[x]`、進行中 = `[-]`、未着手 = `[ ]`。

## Phase 0: 事実確認 (完了)

- [x] Laravel プロジェクトを作成 (`/Users/noguchi/Desktop/sandbox/nativephp-test/`)
- [x] `nativephp/mobile` 3.2.2 をインストール
- [x] `native:install android` を実行して Android Studio プロジェクト生成
- [x] 配布 libphp.a (22MB) の展開と nm 解析
- [x] **MySQL シンボルが libphp.a に存在しないことを実測確認**
- [x] CMakeLists.txt を読んで静的リンク構造を把握
- [x] `LaravelEnvironment.kt:765` で DB_CONNECTION が Kotlin ハードコードであることを発見
- [x] Android エミュレータで Laravel Welcome ページが動くことを確認 (配布 libphp.a で)
- [x] gradle clean → native:run の差し替えフローが正常動作することを確認

## Phase 1: 自前 libphp.a ビルド環境構築 (完了)

- [x] `v3l0c1r4pt0r/php-ndk` を `mobile-libphp-builder/` として独立リポジトリ化
- [x] Dockerfile 改造:
  - [x] PHP バージョンを 8.3.30 に変更
  - [x] `--enable-embed=static` で libphp.a 出力
  - [x] `--enable-mysqlnd` + `--with-pdo-mysql=mysqlnd` + `--with-mysqli=mysqlnd` 追加
  - [x] Apple Silicon 向け `--platform=linux/amd64` 固定
  - [x] `--disable-mysqlnd-compression-support` で zlib 依存回避
  - [x] libtool 迂回で `llvm-ar rcs` 直接アーカイブ化
  - [x] find 除外パターンを `*/.libs/*` (全階層) に修正して PIC/非PIC 重複を排除
- [x] Docker ビルドが最後まで完走
- [x] 生成された libphp.a の nm で MySQL シンボル検出:
      `zm_startup_mysqli`, `zm_startup_mysqlnd`, `zm_startup_pdo_mysql` を確認
- [x] libphp.a サイズ 22 MB (NativePHP 配布版と同等)

## Phase 2: 差し替え & リビルド (進行中 — リンク調整)

- [x] 自前 libphp.a を `nativephp/android/app/src/main/staticLibs/arm64-v8a/` にコピー
- [x] `./gradlew clean`
- [-] `native:run android --build=debug` で再ビルド — リンクでエラー調整中
  - [x] 1 回目: duplicate symbol → find の除外パターン `*/.libs/*` で解消
  - [x] 2 回目: `-fPIC` 未定 → `CFLAGS="-fPIC" --with-pic` 追加で解消
  - [-] 3 回目: TSRM シンボル未定義 → `--enable-zts` 追加でビルド中 ← いまここ
- [ ] APK の libphp_wrapper.so に MySQL シンボルが残っていることを nm で確認
- [ ] エミュレータで APK が起動し、Laravel Welcome ページが表示されることを確認

## Phase 3: Kotlin 層の DB 設定書き換え

- [ ] `LaravelEnvironment.kt:765-766` の DB_CONNECTION / DB_DATABASE を MySQL 向けに編集
- [ ] `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD` を setEnvironmentVariables に追加
- [ ] 変更を patch ファイル `patches/laravel-environment-mysql.patch` として保存

## Phase 4: MySQL サーバー起動

- [ ] `docker-compose.mysql.yml` をプロジェクトルートに作成
- [ ] `docker compose -f docker-compose.mysql.yml up -d` で MySQL 8.4 起動
- [ ] ホスト Mac から `mysql -h 127.0.0.1 -P 3306 -uroot -proot` で疎通確認
- [ ] `CREATE DATABASE nativephp_test` (compose 側で自動生成される設定に)

## Phase 5: 動作確認

- [ ] `routes/web.php` に `/db-test` エンドポイントを追加
- [ ] `native:run android` で再ビルド & デプロイ
- [ ] エミュレータ上のアプリ内から `/db-test` を叩く (deeplink or WebView URL)
- [ ] レスポンスで `driver: "mysql"` + `version: "8.4.x"` が返ることを確認 ← **成功判定**

## Phase 6: マイグレーション動作確認

- [ ] `config/database.php` の mysql connection 設定を確認
- [ ] `php artisan migrate` 相当を Android 側から走らせる
- [ ] MySQL コンテナ側で `SHOW TABLES` して `users` 等が作られたことを確認

## Phase 7: 仕上げ

- [ ] 拡張セット (openssl / curl / libxml2) を追加した完全版 libphp.a をビルド
- [ ] PoC 完了のレポートを `docs/poc-result.md` として執筆
- [ ] ユーザー (NOGU-LAB) レビュー

---

## 現在の詳細ステータス

- 日時: 2026-04-24
- **全 Phase 完了 🎉** — Android エミュレータから MySQL 8.4.9 に接続し `SELECT VERSION()` 成功
- 詳細レポート: [docs/poc-result.md](../../docs/poc-result.md)

## 学習ログ (PoC で判明した要点)

自前 libphp.a を NativePHP Mobile に組み込むために必要な configure フラグ:

| フラグ | 理由 |
|---|---|
| `--enable-embed=static` | sapi/embed/libphp.a を生成 |
| `--disable-cli --disable-cgi` | embed モードと両立 |
| `--disable-phar --disable-phpdbg` | cross-compile で phar 生成がホスト PHP 要求する制約を回避 |
| `CFLAGS="-fPIC" --with-pic` | libphp_wrapper.so (shared) にリンクするため位置独立コード必須 |
| `--enable-zts` | NativePHP CMake が `-DZTS=1 -DPTHREADS` で呼ぶため、TSRM シンボル必要 |
| `--disable-mysqlnd-compression-support` | zlib + pkg-config 依存を避ける |
| `--with-pdo-mysql=mysqlnd` 等 | MySQL 対応 (本来の目的) |

Docker ビルドで気づいた点:

- Apple Silicon では `--platform=linux/amd64` 強制 (NDK の Linux 版は x86_64)
- libtool の `libphp.la` 生成は basename conflict で失敗するので **`llvm-ar rcs` で直接アーカイブ化**
- find で `.o` を拾う時は全階層の `.libs/` を除外 (`*/.libs/*` パターン)

## ブロッカー / 未解決

- `mblen` / `getloadavg` 未定義シンボル (Android bionic 由来、ZTS 解消後に再確認)
