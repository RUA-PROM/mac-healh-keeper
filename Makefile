# Mac Health Keeper - テスト実行集約
#
# make test       : Swift（XCTest）とシェルのテストを実行し、結果を集約する。
#                   XCTest が利用可能な環境では swift test の失敗も全体失敗に反映する。
#                   XCTest 非搭載環境（Command Line Tools のみ等）では swift test を
#                   警告付きで skip し、シェルテスト結果で全体の成否を判定する。
#                   いずれの場合もシェルテストは必ず実行する。
# make test-swift : Swift の XCTest のみ実行する。
# make test-shell : シェルテストのみ実行する（bats 利用可なら bats、不在なら自前 assert）。
#
# 終了コード: swift test とシェルテストのいずれかが失敗すると非 0 終了する。
#            全て成功（または XCTest skip + シェル成功）で 0 終了する。

.PHONY: test test-swift test-shell

# XCTest が利用可能なら swift test を試行（失敗は全体失敗に反映）、
# 非搭載環境では警告して skip する。続けて test-shell を必ず実行し、
# 各段の終了コードを集約して返す。
test:
	@rc=0; \
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
		echo "    -> shell tests still run; Swift logic should be checked on a full Xcode environment." >&2; \
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
		bash scripts/test/monitor_test.sh && bash scripts/test/metrics_test.sh && bash scripts/test/log_rotate_test.sh; \
	fi
