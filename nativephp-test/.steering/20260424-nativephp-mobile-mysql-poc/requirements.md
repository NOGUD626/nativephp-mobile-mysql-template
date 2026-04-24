# 要求仕様: NativePHP Mobile + MySQL 対応 PoC

## 開始日

2026-04-24

## 動機

NativePHP Mobile v3 (MIT) で Laravel アプリを Android にビルドする構成を採用しようとした。
既存の業務データベース (MySQL 上の NANS21V 等) と直接連携したかったが、
配布 `libphp.a` には MySQL ドライバが含まれておらず、**そのままでは `Driver [mysql] not found` エラーで接続不可** であることが実測で判明した。

検証した事実:

- 配布 `libphp.a` (22 MB) の nm で `zm_startup_pdo_mysql` 等のシンボルは **存在しない**
- 同梱 DB 拡張は `pdo`, `pdo_sqlite`, `sqlite` (= ext/sqlite3) の 3 つのみ
- NativePHP Mobile の Android 側は `LaravelEnvironment.kt:765` で
  `DB_CONNECTION="sqlite"` をハードコードで setenv しており、Laravel の `.env` を
  読まない

## スコープ

### やる

- R1: Android NDK でクロスコンパイルした MySQL 対応 `libphp.a` のビルド環境を作る
- R2: 自前 `libphp.a` を配布版と差し替えて `libphp_wrapper.so` がリンクできる
- R3: `LaravelEnvironment.kt` の DB 設定を MySQL に書き換える
- R4: ホスト Mac で MySQL サーバーを立て、エミュレータ (`10.0.2.2:3306`) から接続可能にする
- R5: エミュレータ上の Laravel から `DB::select('SELECT VERSION()')` が成功する

### やらない

- NR1: iOS 対応 (Xcode + iOS SDK の別系統、工数数倍)
- NR2: 実機での動作確認 (エミュレータのみ)
- NR3: NativePHP 公式に upstream PR を出す
- NR4: MySQL 以外の DB (PostgreSQL/SQL Server 等)
- NR5: `libphp.a` を NativePHP 配布版と完全同等の拡張セットにする
  (今回は MySQL 追加 + SQLite 維持の最小構成で PoC)
- NR6: 本番配布 (App Store / Play Store)

## 成功基準

1. **自前 libphp.a に MySQL シンボルが入っていること**
   ```bash
   nm /path/to/libphp.a | grep -E "zm_startup_(pdo_mysql|mysqli|mysqlnd)"
   # → 3 件とも検出されること
   ```

2. **APK の libphp_wrapper.so にも MySQL シンボルが残っていること**
   ```bash
   nm libphp_wrapper.so | grep -c mysql
   # → 数百以上 (現状 0)
   ```

3. **Laravel が mysql ドライバを認識すること**
   - Android エミュレータで `/db-test` ルートを叩いて `driver: "mysql"` が返る
   - `SELECT VERSION()` が MySQL のバージョン文字列を返す

4. **マイグレーションが MySQL 側で実行できること**
   - `users` テーブル等が MySQL 側に作成される
   - Docker Compose の MySQL コンテナから SQL で確認可能

## 制約

- 開発 OS: macOS Apple Silicon (M シリーズ)
- NDK r27c の Linux バージョンは x86_64 のみのため、Docker ビルドは Rosetta 経由
  (`--platform=linux/amd64`)
- PHP バージョンは 8.3.30 (NativePHP 配布と一致させる)
- ビルド時間の制約は無し (初回 30〜60 分を許容)

## ステークホルダー

- ユーザー: noguchi@nogu-lab.com (NOGU-LAB、マラソン計測/NANS21V 系)
- 成果物の使用先: 現場計測系 Android タブレットアプリ (将来)

## リスク

| リスク | 影響 | 緩和策 |
|---|---|---|
| 自前 libphp.a が配布 libphp.a に比べて拡張が少ない | Laravel が openssl/curl 等で落ちる | 最初は最小構成で PoC、通ったら libxml2/openssl/curl を追加する段階移行 |
| Kotlin ハードコード書き換えが `native:install --force` で消える | PoC の再現性が落ちる | `--force` を使わない運用 + 変更を patch として保存 |
| NativePHP の将来バージョンで Kotlin 構造が変わる | 移植が必要 | バージョン固定 (3.2.2 を基準) |
| Rosetta 経由の Docker ビルドが極端に遅い | 開発サイクルが長くなる | 最終手段として Linux aarch64 NDK への移行を検討 |
