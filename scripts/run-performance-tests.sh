#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=Flow iPhone 17 Pro}"
result_path="${RESULT_BUNDLE_PATH:-$project_root/.build/performance-tests.xcresult}"

UI_PROFILER_ATTACH_SECONDS="${UI_PROFILER_ATTACH_SECONDS:-0}" \
xcodebuild test \
  -project "$project_root/MultiCurrencyLedger.xcodeproj" \
  -scheme MultiCurrencyLedger \
  -configuration Debug \
  -destination "$destination" \
  -only-testing:MultiCurrencyLedgerUITests/MultiCurrencyLedgerPerformanceUITests \
  -resultBundlePath "$result_path"
