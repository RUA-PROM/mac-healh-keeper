# Mac Health Keeper - テスト実行集約
#
# make test       : Swift（XCTest）とシェル（bats / 自前 assert）のテストを順に実行する。
# make test-swift : Swift の XCTest のみ実行する。
# make test-shell : シェルテストのみ実行する（bats 利用可なら bats、不在なら自前 assert）。
#
# いずれかのテストが失敗すると非 0 終了する（&& による連結）。

.PHONY: test test-swift test-shell

test: test-swift test-shell

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
