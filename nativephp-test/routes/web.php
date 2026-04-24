<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    // PoC: トップページで MySQL に対する CRUD 操作をまとめて実行
    $log = [];

    try {
        $driver = DB::connection()->getDriverName();
        $version = DB::selectOne('SELECT VERSION() as v');
        $log[] = "🎉 接続 OK: {$driver} / MySQL {$version->v}";
        $log[] = "";

        // Migrate (冪等、既に実行済なら何もしない)
        \Artisan::call('migrate', ['--force' => true]);
        $log[] = "📦 migrate:";
        foreach (explode("\n", trim(\Artisan::output())) as $line) {
            if (trim($line)) $log[] = "   " . trim($line);
        }
        $log[] = "";

        // ==== C: Create ====
        $user = \App\Models\User::create([
            'name'     => 'テスト太郎_' . now()->format('His'),
            'email'    => 'test' . time() . '@example.com',
            'password' => bcrypt('secret'),
        ]);
        $log[] = "✅ Create: id={$user->id}, name={$user->name}";

        // ==== R: Read ====
        $found = \App\Models\User::find($user->id);
        $log[] = "✅ Read:   id={$found->id}, email={$found->email}";

        // ==== U: Update ====
        $found->name = '更新太郎_' . now()->format('His');
        $found->save();
        $fresh = $found->fresh();
        $log[] = "✅ Update: name={$fresh->name}";

        // ==== 全件カウント ====
        $total = \App\Models\User::count();
        $log[] = "📊 Count:  合計 {$total} 件";

        // ==== D: Delete ====
        $found->delete();
        $log[] = "✅ Delete: id={$user->id} 削除完了";

        // 最終カウント
        $afterCount = \App\Models\User::count();
        $log[] = "📊 After:  合計 {$afterCount} 件 (1 件減 確認)";

    } catch (\Throwable $e) {
        $log[] = "";
        $log[] = "❌ ERROR: " . $e::class;
        $log[] = "   " . $e->getMessage();
        $log[] = "   at " . $e->getFile() . ':' . $e->getLine();
    }

    return response('<pre style="font-size:14px;padding:16px;line-height:1.6">'
        . htmlspecialchars(implode("\n", $log))
        . '</pre>');
});

Route::get('/db-test', function () {
    try {
        $driver = DB::connection()->getDriverName();
        $version = DB::selectOne('SELECT VERSION() as v');
        return response()->json([
            'status'  => 'ok',
            'driver'  => $driver,
            'version' => $version->v ?? null,
            'env'     => [
                'DB_CONNECTION' => env('DB_CONNECTION'),
                'DB_HOST'       => env('DB_HOST'),
                'DB_DATABASE'   => env('DB_DATABASE'),
            ],
        ]);
    } catch (\Throwable $e) {
        return response()->json([
            'status' => 'error',
            'class'  => $e::class,
            'error'  => $e->getMessage(),
            'env'    => [
                'DB_CONNECTION' => env('DB_CONNECTION'),
                'DB_HOST'       => env('DB_HOST'),
                'DB_DATABASE'   => env('DB_DATABASE'),
            ],
        ], 500);
    }
});
