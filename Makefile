# Mac Health Keeper - テスト & 検証集約
#
# make test       : Swift（XCTest）とシェルのテストを実行し、結果を集約する。
#                   XCTest が利用可能な環境では swift test の失敗も全体失敗に反映する。
#                   XCTest 非搭載環境（Command Line Tools のみ等）では swift test を
#                   警告付きで skip し、シェルテスト結果で全体の成否を判定する。
#                   いずれの場合もシェルテストは必ず実行する。
# make test-swift : Swift の XCTest のみ実行する。
# make test-shell : シェルテストのみ実行する（bats 利用可なら bats、不在なら自前 assert）。
#
# make check            : lint / format / 循環検出 / セキュリティ / test を一気通貫で実行する。
#                         未導入の任意ツール（shfmt / swift-format / swiftlint）は SKIP する。
# make lint             : シェル/Swift の lint 系をまとめて実行（test は含まない）。
# make lint-shell       : shellcheck（必須ツール）。
# make lint-shfmt       : shfmt によるシェル整形差分検査（任意・未導入なら SKIP）。
# make lint-swift-format: swift-format による Swift lint（任意・未導入なら SKIP）。
# make lint-swiftlint   : swiftlint（任意・未導入なら SKIP）。
# make check-cycles     : シェル source 依存の循環検出。
# make security-scan    : 秘密情報・危険パターンの静的検出。
#
# 終了コード: swift test とシェルテストのいずれかが失敗すると非 0 終了する。
#            全て成功（または XCTest skip + シェル成功）で 0 終了する。
#            make check はいずれかの検証が失敗すると非 0 終了する。

.PHONY: test test-swift test-swift-purecore test-shell \
        check lint lint-shell lint-shfmt lint-swift-format lint-swiftlint \
        check-cycles security-scan \
        build install reinstall

# 純粋関数の単体テスト経路は 2 系統ある（issue: 20260529_083530_メトリクス非表示修正 フォロー）。
#   1) test-swift-purecore: `swift run MacHealthCheck` で XCTest 非依存の純粋テストを実行。
#      Command Line Tools のみの環境でも必ず実行され、失敗は全体失敗に反映する（必須経路）。
#   2) test-swift:          XCTest が利用可能な環境でのみ `swift test` を実行する（追加経路）。
# どちらの経路でも、続けて test-shell（シェル単体 + smoke）を必ず実行する。
test:
	@rc=0; \
	echo "==> swift run MacHealthCheck (pure-core BDD, always runs)"; \
	if swift run MacHealthCheck; then \
		echo "    MacHealthCheck: OK"; \
	else \
		echo "    MacHealthCheck: FAILED" >&2; \
		rc=1; \
	fi; \
	if xcrun --find xctest >/dev/null 2>&1; then \
		echo "==> swift test (XCTest available)"; \
		if swift test; then \
			echo "    swift test: OK"; \
		else \
			echo "    swift test: FAILED" >&2; \
			rc=1; \
		fi; \
	else \
		echo "==> swift test: SKIP (XCTest not available; e.g. Command Line Tools only)" >&2; \
		echo "    -> MacHealthCheck covers the pure-core path; full XCTest suite needs a Xcode environment." >&2; \
	fi; \
	echo "==> shell tests"; \
	if $(MAKE) --no-print-directory test-shell; then \
		echo "    shell tests: OK"; \
	else \
		echo "    shell tests: FAILED" >&2; \
		rc=1; \
	fi; \
	if [ $$rc -eq 0 ]; then \
		echo "==> all tests passed"; \
	else \
		echo "==> some tests failed" >&2; \
	fi; \
	exit $$rc

# XCTest 非依存の純粋テスト経路（CI/CommandLineTools でも常に実行可能）。
# 失敗時は終了コード 1 を返す。
test-swift-purecore:
	@echo "==> swift run MacHealthCheck"
	swift run MacHealthCheck

test-swift:
	@echo "==> swift test"
	swift test

test-shell:
	@echo "==> shell tests"
	@if command -v bats >/dev/null 2>&1; then \
		echo "    (using bats)"; \
		bats scripts/test/; \
	else \
		echo "    (bats not found -> fallback to self-made assert runner)"; \
		bash scripts/test/monitor_test.sh \
		  && bash scripts/test/metrics_test.sh \
		  && bash scripts/test/log_rotate_test.sh \
		  && bash scripts/test/install_metrics_smoke_test.sh \
		  && bash scripts/test/version_stamp_test.sh \
		  && bash scripts/test/launchagent_lifecycle_test.sh \
		  && bash scripts/test/plist_validator_test.sh \
		  && bash scripts/test/launchagent_doctor_test.sh; \
	fi

# ------------------------------------------------------------------
# 検証集約（make check）
# 各検証スクリプトを順次呼び出し、終了コードを集約する。
# 02_設計 §3.1 を実装。
# ------------------------------------------------------------------

check:
	@rc=0; \
	for step in lint-shell lint-shfmt lint-swift-format lint-swiftlint \
	            check-cycles security-scan test; do \
		echo "==> $$step"; \
		if $(MAKE) --no-print-directory $$step; then \
			echo "    $$step: OK"; \
		else \
			echo "    $$step: FAILED" >&2; \
			rc=1; \
		fi; \
	done; \
	if [ $$rc -eq 0 ]; then \
		echo "==> all checks passed"; \
	else \
		echo "==> some checks failed" >&2; \
	fi; \
	exit $$rc

lint: lint-shell lint-shfmt lint-swift-format lint-swiftlint

lint-shell:
	@bash scripts/lint/run-shellcheck.sh

lint-shfmt:
	@bash scripts/lint/run-shfmt.sh

lint-swift-format:
	@bash scripts/lint/run-swift-format.sh

lint-swiftlint:
	@bash scripts/lint/run-swiftlint.sh

check-cycles:
	@bash scripts/lint/check-source-cycles.sh

security-scan:
	@bash scripts/lint/security-scan.sh

# ------------------------------------------------------------------
# ビルド / インストール導線
# issue: 20260529_083530_メトリクス非表示修正
# install.sh / uninstall.sh への薄い委譲ターゲット。
# 「アプリだけ更新／scripts だけ更新」の運用ミスを避けるため、
# 開発者には make install（または make reinstall）の利用を推奨する。
# build は install.sh の swiftc コマンドと同じファイル構成で
# build/MacHealth を生成する。.app バンドルや LaunchAgent 配置は install.sh が担う。
# ------------------------------------------------------------------

build:
	@echo "==> swiftc build (build/MacHealth)"
	@mkdir -p build
	@swiftc src/MacHealth.swift src/MetricsCollector.swift src/MenuBuilder.swift \
	  Sources/MacHealthKit/ScheduleTiming.swift \
	  Sources/MacHealthKit/Metrics.swift \
	  Sources/MacHealthKit/JobCatalog.swift \
	  Sources/MacHealthKit/MetricsParser.swift \
	  Sources/MacHealthKit/MetricsCollectorPolicy.swift \
	  Sources/MacHealthKit/MenuModel.swift \
	  Sources/MacHealthKit/ShellRunner.swift \
	  Sources/MacHealthKit/AppleScriptEscaper.swift \
	  Sources/MacHealthKit/JobController.swift \
	  Sources/MacHealthKit/Version.swift \
	  -o build/MacHealth
	@ls -la build/MacHealth

install:
	@echo "==> ./install.sh"
	@./install.sh

reinstall:
	@echo "==> ./uninstall.sh && ./install.sh"
	@./uninstall.sh || true
	@./install.sh
