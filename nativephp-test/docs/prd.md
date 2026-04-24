# PRD: NativePHP Mobile + MySQL 対応 PoC

## 目的

[NativePHP Mobile](https://nativephp.com/) で構築した Android/iOS アプリから
**MySQL データベースに接続**できるようにする PoC (概念実証) を行う。

NativePHP Mobile は公式には SQLite のみをサポートしているが、既存の MySQL ベースの
業務システム (計測/記録管理系) と直接連携したいケースが多いため、自前で MySQL 対応版
`libphp.a` をビルドし、NativePHP Mobile に組み込む方法を確立する。

## 背景

2026 年 2 月に NativePHP Mobile は v3 (NativePHP Air) として MIT ライセンス化・完全無料化。
Laravel コードベース一つで Web / API / Mobile を共通化できる可能性が出てきた。

ニシ・スポーツ系 (NANS21V) の現場運用では:

- 計測会場のタブレットで計測データを直接 MySQL と同期したい
- しかし NativePHP 公式の libphp.a には **MySQL ドライバが含まれていない**
  (`pdo_mysql`, `mysqli`, `mysqlnd` いずれも非同梱)
- SQLite でローカル保持 + サーバー Laravel API 経由で MySQL にアクセス、という構成は
  オフライン動作の要件が厳しい現場では不利

## ゴール / 非ゴール

### ゴール (今回の PoC)

- [x] NativePHP Mobile の配布 `libphp.a` に MySQL ドライバが無いことを実測で確認
- [x] Android NDK で `libphp.a` をクロスコンパイルする独自ビルド環境を構築
- [ ] `pdo_mysql` / `mysqli` / `mysqlnd` を含む `libphp.a` を自前ビルドできる
- [ ] 自前 `libphp.a` に差し替えて `libphp_wrapper.so` がリンクできる
- [ ] Android エミュレータ上の Laravel アプリから MySQL にクエリが通ることを確認

### 非ゴール (今回やらない)

- iOS 対応 (Android のみ)
- NativePHP 公式への upstream PR
- 本番アプリ配布 (App Store / Play Store)
- MySQL サーバー側の認証情報セキュリティ (検証環境では root/root)
- PostgreSQL / SQL Server 等 MySQL 以外の DB 対応

## 成功基準

1. `nm libphp_wrapper.so | grep mysql` で MySQL 関連シンボルが検出される
2. Android エミュレータで Laravel の `DB::select('SELECT VERSION()')` が成功する
3. マイグレーション `php artisan migrate` が MySQL 側で実行できる

## 制約

- 開発環境: macOS 14+ (Apple Silicon), Docker Desktop, Android Studio 2025.2+,
  Android NDK r27, JDK 21
- ターゲット: Android arm64-v8a (エミュレータ + 実機)
- PHP 8.3.30 (NativePHP 配布版と一致させる)
