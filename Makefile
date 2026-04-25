# NativePHP Mobile + MySQL Template - トップレベル Makefile
#
# clone 後に 1 発で Android / iOS のビルドまで持っていくためのエントリポイント。
# 各ターゲットは冪等 (再実行しても壊れない) ように書かれている。
#
# Quick Start:
#   make help            # コマンド一覧
#   make doctor          # 環境診断
#   make all-android     # Android を一気通貫で立ち上げ
#
# 個別:
#   make setup           # Composer + NativePHP 初期化
#   make libphp          # 自前 libphp.a をクロスビルド
#   make install-libs    # 生成した .a を NativePHP に差し替え
#   make patch           # Kotlin の DB 設定を MySQL に切替
#   make mysql-up        # MySQL コンテナ起動
#   make mysql-down      # MySQL コンテナ停止
#   make run-android     # Android エミュレータでビルド実行
#   make run-ios         # iOS シミュレータでビルド実行 (要 Xcode.app)
#   make clean           # ビルド生成物を削除 (再現性確認用)

SHELL := /bin/bash

# CocoaPods が Ruby 4.x 環境で UTF-8 不整合エラーを起こすのを回避
export LANG := en_US.UTF-8
export LC_ALL := en_US.UTF-8

# SDKMAN は ~/.bashrc 経由で初期化されるが、Make の非対話シェルでは読まれない。
# Java を Make Recipe からも見つけられるよう JAVA_HOME を明示する。
ifneq ($(wildcard $(HOME)/.sdkman/candidates/java/current/bin/java),)
export JAVA_HOME := $(HOME)/.sdkman/candidates/java/current
export PATH := $(JAVA_HOME)/bin:$(PATH)
endif

# プロジェクトルート (Makefile が置かれた場所)
ROOT    := $(shell pwd)
APP     := $(ROOT)/nativephp-test
BUILDER := $(ROOT)/mobile-libphp-builder

# Android SDK / NDK
ANDROID_HOME ?= /opt/homebrew/share/android-commandlinetools
export ANDROID_HOME
export PATH := $(ANDROID_HOME)/cmdline-tools/latest/bin:$(ANDROID_HOME)/platform-tools:$(ANDROID_HOME)/emulator:$(PATH)

# AVD 名 (環境により変える)
AVD ?= Pixel_6_Pro_arm

# --- デフォルトターゲット ---

.DEFAULT_GOAL := help

# --- help -------------------------------------------------------------

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mNativePHP Mobile + MySQL Template\033[0m\n\nUsage:\n  make \033[36m<target>\033[0m\n\n\033[1mTargets:\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# --- doctor (環境診断) ------------------------------------------------

.PHONY: doctor
doctor: ## 必要ツールが揃ってるか診断
	@echo "=== 環境診断 ==="
	@command -v php >/dev/null     && echo "✅ php       : $$(php --version | head -1)"      || echo "❌ php       : 未インストール (brew install php@8.3)"
	@command -v composer >/dev/null && echo "✅ composer  : $$(composer --version | head -1)" || echo "❌ composer  : 未インストール (brew install composer)"
	@command -v docker >/dev/null  && echo "✅ docker    : $$(docker --version)"             || echo "❌ docker    : 未インストール (brew install --cask docker)"
	@docker info >/dev/null 2>&1   && echo "✅ docker    : daemon 稼働中"                    || echo "❌ docker    : daemon 停止中 (open -a Docker)"
	@command -v adb >/dev/null     && echo "✅ adb       : $$(adb --version | head -1)"      || echo "❌ adb       : 未インストール (sdkmanager)"
	@test -d "$(ANDROID_HOME)"     && echo "✅ ANDROID_HOME: $(ANDROID_HOME)"                || echo "❌ ANDROID_HOME: 不在"
	@test -d "$(ANDROID_HOME)/ndk" && echo "✅ NDK       : $$(ls $(ANDROID_HOME)/ndk/ 2>/dev/null | head -1)" || echo "⚠  NDK       : 未インストール (sdkmanager \"ndk;27.0.12077973\")"
	@emulator -list-avds 2>/dev/null | grep -q $(AVD) && echo "✅ AVD       : $(AVD) 登録済" || echo "⚠  AVD       : $(AVD) 未作成 (avdmanager create avd ...)"
	@test -d /Applications/Xcode.app && echo "✅ Xcode.app : あり (iOS ビルド可能)"          || echo "⚠  Xcode.app : なし (iOS ビルド不可、Android は OK)"
	@command -v pod >/dev/null      && echo "✅ cocoapods : $$(pod --version)"               || echo "⚠  cocoapods : 未インストール (brew install cocoapods、iOS 用)"
	@echo ""
	@echo "Dependencies check complete."

# --- setup (初期セットアップ) -----------------------------------------

.PHONY: setup
setup: setup-composer setup-env setup-nativephp ## Composer + NativePHP を初期化 (冪等)

.PHONY: setup-composer
setup-composer:
	@echo "=== Composer install ==="
	@cd $(APP) && composer install --no-interaction --prefer-dist

.PHONY: setup-env
setup-env: setup-composer  ## vendor/ 必須なので setup-composer を先に走らせる
	@echo "=== .env 初期化 ==="
	@if [ ! -f $(APP)/.env ]; then \
	  cp $(APP)/.env.example $(APP)/.env; \
	  if cd $(APP) && php artisan key:generate --force; then \
	    echo "NATIVEPHP_APP_ID=com.nogulab.nativephpdemo" >> $(APP)/.env; \
	    echo "✅ .env created"; \
	  else \
	    rm -f $(APP)/.env; \
	    echo "❌ .env 初期化失敗 (artisan key:generate)"; \
	    exit 1; \
	  fi; \
	else \
	  echo "✅ .env 既存 (変更なし)"; \
	fi

.PHONY: setup-nativephp
setup-nativephp: setup-env  ## .env 整ってないと native:install が動かない
	@echo "=== NativePHP Android プロジェクト生成 ==="
	@if [ ! -d $(APP)/nativephp/android ]; then \
	  cd $(APP) && php artisan native:install android --no-interaction --no-force; \
	else \
	  echo "✅ nativephp/android/ 既存 (変更なし。再生成は make clean-nativephp)"; \
	fi
	@if [ -d /Applications/Xcode.app ] && [ ! -d $(APP)/nativephp/ios ]; then \
	  echo "=== NativePHP iOS プロジェクト生成 ==="; \
	  cd $(APP) && php artisan native:install ios --no-interaction --no-force; \
	elif [ -d /Applications/Xcode.app ]; then \
	  echo "✅ nativephp/ios/ 既存 (変更なし)"; \
	else \
	  echo "⚠  Xcode.app なしのため iOS はスキップ"; \
	fi

.PHONY: clean-nativephp
clean-nativephp:
	rm -rf $(APP)/nativephp

# --- libphp.a ビルド --------------------------------------------------

.PHONY: libphp
libphp: ## 自前 libphp.a をクロスビルド (Android 用、Docker 使用、初回 30 分)
	@echo "=== 自前 libphp.a クロスビルド (Android arm64-v8a) ==="
	@cd $(BUILDER) && $(MAKE) aarch64
	@cd $(BUILDER) && rm -rf app && $(MAKE) install-aarch64
	@echo "=== 生成物 ==="
	@ls -la $(BUILDER)/app/src/main/staticLibs/arm64-v8a/
	@echo "=== MySQL シンボル確認 ==="
	@nm $(BUILDER)/app/src/main/staticLibs/arm64-v8a/libphp.a 2>&1 | grep -oE "zm_startup_[a-z_]+" | sort -u | grep -E "mysql|sqlite|openssl|dom|mbstring" | sed 's/^/   /'

.PHONY: install-libs
install-libs: ## 自前ビルド libphp.a 他を NativePHP プロジェクトに配置
	@echo "=== libphp.a / libssl.a / libcrypto.a / libonig.a / libxml2.a を配置 ==="
	@test -f $(BUILDER)/app/src/main/staticLibs/arm64-v8a/libphp.a || \
	  (echo "❌ libphp.a が無い。先に make libphp を実行してください"; exit 1)
	@DEST=$(APP)/nativephp/android/app/src/main/staticLibs/arm64-v8a; \
	 test -d "$$DEST" || (echo "❌ $$DEST 無し。先に make setup を実行"; exit 1); \
	 for lib in libphp.a libssl.a libcrypto.a libonig.a libxml2.a; do \
	   cp $(BUILDER)/app/src/main/staticLibs/arm64-v8a/$$lib $$DEST/ && \
	   echo "   ✅ $$lib"; \
	 done

# --- Kotlin patch -----------------------------------------------------

.PHONY: patch
patch: ## Kotlin の DB 設定を sqlite → mysql に切替 (冪等)
	@echo "=== LaravelEnvironment.kt を MySQL 設定にパッチ ==="
	@cd $(APP) && \
	  if patch -p1 --dry-run -N < patches/laravel-environment-mysql.patch >/dev/null 2>&1; then \
	    patch -p1 < patches/laravel-environment-mysql.patch && echo "✅ patch 適用"; \
	  else \
	    echo "✅ patch 既適用 (skip)"; \
	  fi

.PHONY: unpatch
unpatch: ## Kotlin パッチをロールバック
	@cd $(APP) && patch -p1 -R < patches/laravel-environment-mysql.patch 2>&1 || echo "⚠  既に未適用"

# --- MySQL サーバー ---------------------------------------------------

.PHONY: mysql-up
mysql-up: ## MySQL コンテナ起動 + healthcheck 待機
	@cd $(APP) && docker compose -f docker-compose.mysql.yml up -d
	@echo -n "MySQL 起動待機..."
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do \
	  h=$$(docker inspect --format='{{.State.Health.Status}}' nativephp-mysql 2>/dev/null); \
	  if [ "$$h" = "healthy" ]; then echo " ✅ healthy"; break; fi; \
	  echo -n "."; sleep 2; \
	done
	@docker exec nativephp-mysql mysql -uroot -proot -e "SELECT VERSION() AS mysql_version;" 2>&1 | grep -v Warning

.PHONY: mysql-down
mysql-down: ## MySQL コンテナ停止
	@cd $(APP) && docker compose -f docker-compose.mysql.yml down

.PHONY: mysql-logs
mysql-logs: ## MySQL コンテナのログ tail
	@docker logs -f nativephp-mysql

.PHONY: mysql-shell
mysql-shell: ## mysql クライアントに入る (開発用)
	@docker exec -it nativephp-mysql mysql -uroot -proot nativephp_test

# --- エミュレータ / 実行 -----------------------------------------------

.PHONY: emu-start
emu-start: ## Android エミュレータを起動 (バックグラウンド)
	@if adb devices | grep -q emulator; then \
	  echo "✅ エミュレータ稼働中"; \
	else \
	  echo "=== エミュレータ起動 (AVD: $(AVD)) ==="; \
	  emulator -avd $(AVD) -no-snapshot-save -no-boot-anim & \
	  echo -n "起動待機"; \
	  until [ "$$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')" = "1" ]; do \
	    echo -n "."; sleep 3; \
	  done; \
	  echo " ✅ boot 完了"; \
	fi

.PHONY: run-android
run-android: ## Android でビルド + エミュレータ起動 + インストール + 起動
	@echo "=== Gradle clean ==="
	@cd $(APP)/nativephp/android && ./gradlew clean 2>&1 | tail -2
	@echo "=== native:run android ==="
	@cd $(APP) && php artisan native:run android --build=debug --no-tty --no-interaction
	@grep -E "App launched|Gradle build failed" $(APP)/nativephp/android-build.log | tail -2

.PHONY: setup-pods
setup-pods: ## iOS プロジェクトで pod install + Podfile 退避 (NativePHP の pod install timeout 回避)
	@test -d $(APP)/nativephp/ios || (echo "❌ nativephp/ios/ 無し。make setup-nativephp が先"; exit 1)
	@if [ -f $(APP)/nativephp/ios/Podfile ]; then \
	  cd $(APP)/nativephp/ios && pod install 2>&1 | tail -3; \
	  mv $(APP)/nativephp/ios/Podfile $(APP)/nativephp/ios/Podfile.disabled; \
	  echo "✅ Podfile を退避 (NativePHP の再 pod install をスキップさせる)"; \
	else \
	  echo "✅ Podfile 既退避 (skip)"; \
	fi

.PHONY: setup-pod-wrapper
setup-pod-wrapper: ## pod コマンドを LANG 強制 wrapper に置換 (sudo 必要、Ruby 4.x UTF-8 バグ回避)
	@if grep -q "LANG=en_US.UTF-8" /opt/homebrew/bin/pod 2>/dev/null; then \
	  echo "✅ pod wrapper 既設置 (skip)"; \
	else \
	  echo "⚠  /opt/homebrew/bin/pod を LANG 強制 wrapper に置換します (sudo パスワード要求)"; \
	  printf '#!/bin/bash\nexec env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 /opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec/bin/pod "$$@"\n' > /tmp/pod-wrapper; \
	  chmod +x /tmp/pod-wrapper; \
	  sudo mv /tmp/pod-wrapper /opt/homebrew/bin/pod && echo "✅ wrapper 配置完了" || echo "❌ wrapper 配置失敗"; \
	fi

.PHONY: setup-storage-dirs
setup-storage-dirs: ## Laravel の storage/framework/* と bootstrap/cache を事前作成 (View Compiler エラー回避)
	@for d in storage/framework/cache storage/framework/sessions storage/framework/views storage/framework/testing bootstrap/cache; do \
	  mkdir -p $(APP)/$$d && touch $(APP)/$$d/.gitkeep; \
	done
	@echo "✅ storage/framework/* + bootstrap/cache 作成"

.PHONY: setup-ios-runtime
setup-ios-runtime: ## iOS シミュレータランタイムを DL (8GB、20-30 分)
	@if xcrun simctl list runtimes 2>&1 | grep -q "iOS "; then \
	  echo "✅ iOS ランタイム 既インストール"; \
	else \
	  echo "=== iOS シミュレータランタイム DL (8GB) ==="; \
	  xcodebuild -downloadPlatform iOS; \
	fi

# Xcode インストール済かチェック (sudo なしで)
define check_xcode
	test -d /Applications/Xcode.app || (echo "❌ Xcode.app なし。Mac App Store からインストール"; exit 1)
	[[ "$$(xcode-select -p)" == */Xcode.app/* ]] || { \
	  echo "❌ xcode-select が Command Line Tools を指してます:"; \
	  echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
	  exit 1; \
	}
endef

.PHONY: libphp-ios-device
libphp-ios-device: ## ⚠ 実機 (arm64) 向け libphp.a クロスビルド (WIP: iOS device SDK で configure が hung する既知問題あり)
	@echo "⚠  WIP: 実機向け iOS SDK では configure の AC_TRY_RUN が hung する既知問題があります。"
	@echo "   App Store 配布が必要な場合のみ使用してください (Provisioning Profile も別途必要)。"
	@echo "   シミュレータ動作確認には libphp-ios-sim で十分。"
	@$(call check_xcode)
	@cd $(BUILDER) && bash build-ios.sh iphoneos

.PHONY: libphp-ios-sim
libphp-ios-sim: ## iOS シミュレータ (arm64-apple-ios-simulator) 向け libphp.a クロスビルド (初回 20-30 分、検証済)
	@$(call check_xcode)
	@cd $(BUILDER) && bash build-ios.sh iphonesimulator

.PHONY: libphp-ios
libphp-ios: libphp-ios-sim ## iOS シミュレータ向け libphp.a をクロスビルド (実機向けは libphp-ios-device、WIP)
	@echo "✅ iphonesimulator 向け libphp.a 完成"

.PHONY: install-libs-ios
install-libs-ios: ## iOS 向けに生成した .a を NativePHP iOS プロジェクトに配置 (両 SDK)
	@echo "=== iOS 向け libphp.a / 依存 .a を NativePHP に配置 ==="
	@for sdk in iphoneos iphonesimulator; do \
	  if [ "$$sdk" = "iphoneos" ]; then ARCH=arm64-apple-ios; else ARCH=arm64-apple-ios-simulator; fi; \
	  SRC=$(BUILDER)/app/src/main/staticLibs/$$ARCH; \
	  DEST=$(APP)/nativephp/ios/Libraries/$$sdk; \
	  if [ ! -f $$SRC/libphp.a ]; then echo "⚠  $$SRC/libphp.a 無し → make libphp-ios-$${sdk} 必要"; continue; fi; \
	  test -d "$$DEST" || (echo "❌ $$DEST 無し。先に make setup-nativephp"; exit 1); \
	  for lib in libphp.a libssl.a libcrypto.a libonig.a libxml2.a; do \
	    cp $$SRC/$$lib $$DEST/ && echo "   ✅ $$sdk/$$lib"; \
	  done; \
	done

.PHONY: patch-ios
patch-ios: ## PersistentPHPRuntime.swift の DB 設定を MySQL に切替 (patch ファイル必要、実動作検証後に提供)
	@test -f $(APP)/patches/persistent-php-runtime-mysql.patch || \
	  (echo "⚠  patches/persistent-php-runtime-mysql.patch が未作成。"; \
	   echo "   Xcode 環境で native:install ios 後、PersistentPHPRuntime.swift を手動で書き換え、"; \
	   echo "   diff を patches/ に保存する手順が必要 (setup-guide.md の iOS Step 4 参照)。"; exit 1)
	@cd $(APP) && \
	  if patch -p1 --dry-run -N < patches/persistent-php-runtime-mysql.patch >/dev/null 2>&1; then \
	    patch -p1 < patches/persistent-php-runtime-mysql.patch && echo "✅ patch 適用"; \
	  else \
	    echo "✅ patch 既適用 (skip)"; \
	  fi

.PHONY: run-ios
run-ios: ## iOS でビルド + シミュレータ起動 (UDID 自動取得、要 Xcode)
	@$(call check_xcode)
	@test -d $(APP)/nativephp/ios || (echo "❌ nativephp/ios/ 無し。先に make setup"; exit 1)
	@UDID=$$(xcrun simctl list devices available 2>&1 | grep -E "iPhone [0-9]+ \(" | head -1 | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"); \
	 [ -z "$$UDID" ] && (echo "❌ iPhone シミュレータ無し。make setup-ios-runtime 先実行"; exit 1) || true; \
	 echo "=== UDID: $$UDID ==="; \
	 cd $(APP) && php artisan native:run ios $$UDID --build=debug --no-tty --no-interaction

.PHONY: screenshot-ios
screenshot-ios: ## iOS シミュレータの画面キャプチャ取得
	@UDID=$$(xcrun simctl list devices booted 2>&1 | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1); \
	 [ -z "$$UDID" ] && (echo "❌ booted シミュレータ無し"; exit 1) || true; \
	 xcrun simctl io $$UDID screenshot /tmp/nativephp_ios_screenshot.png; \
	 echo "✅ /tmp/nativephp_ios_screenshot.png"; \
	 open /tmp/nativephp_ios_screenshot.png 2>/dev/null || true

.PHONY: screenshot
screenshot: ## Android エミュレータの画面キャプチャ取得
	@adb shell screencap -p > /tmp/nativephp_screenshot.png
	@echo "✅ /tmp/nativephp_screenshot.png に保存"
	@open /tmp/nativephp_screenshot.png 2>/dev/null || true

# --- 一気通貫 (一発実行) ----------------------------------------------

.PHONY: all-android
all-android: doctor setup libphp install-libs patch mysql-up emu-start run-android screenshot ## 🚀 Android を一気通貫で起動 (初回 30〜60 分)
	@echo ""
	@echo "🎉 Android ビルド完了。エミュレータで /db-test 結果を確認してください。"

.PHONY: all-ios
all-ios: doctor setup setup-storage-dirs setup-pod-wrapper setup-pods setup-ios-runtime libphp-ios-sim install-libs-ios patch-ios mysql-up run-ios screenshot-ios ## 🚀 iOS を一気通貫で起動 (Xcode 必須)
	@echo ""
	@echo "🎉 iOS ビルド完了。シミュレータで MySQL CRUD 結果を確認してください。"

# --- クリーン ---------------------------------------------------------

.PHONY: clean
clean: ## ビルド生成物を削除 (vendor/, nativephp/, mobile-libphp-builder/app/)
	rm -rf $(APP)/vendor
	rm -rf $(APP)/nativephp
	rm -rf $(BUILDER)/app

.PHONY: clean-docker
clean-docker: ## Docker ビルドキャッシュとイメージを削除
	docker image rm -f $$(docker images -q nativephp-libphp-mysql) 2>/dev/null || true
	docker builder prune -f

.PHONY: clean-all
clean-all: clean clean-docker mysql-down ## 全てをクリーンアップ (MySQL データも消える)
	cd $(APP) && docker compose -f docker-compose.mysql.yml down -v
