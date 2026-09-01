#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:-build/local-asr}"
runtime_repo="https://github.com/mweinbach/parakeet-coreml-swift.git"
runtime_tag="v0.1.1"
runtime_commit="75aec2a1c991319657ff4dec5f602c12da6c5012"
work_dir="$(mktemp -d /tmp/freeflow-local-asr.XXXXXX)"

cleanup() {
    if [[ "$work_dir" == /tmp/freeflow-local-asr.* && -d "$work_dir" ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT

git clone --depth 1 --branch "$runtime_tag" "$runtime_repo" "$work_dir/runtime"
actual_commit="$(git -C "$work_dir/runtime" rev-parse HEAD)"
if [[ "$actual_commit" != "$runtime_commit" ]]; then
    echo "Unexpected parakeet-coreml-swift commit: $actual_commit" >&2
    exit 1
fi

swift build -c release --arch arm64 --package-path "$work_dir/runtime" --product parakeet

mkdir -p "$output_dir/licenses"
cp -f "$work_dir/runtime/.build/release/parakeet" "$output_dir/freeflow-local-asr"
cp -f "$work_dir/runtime/LICENSE" "$output_dir/licenses/parakeet-coreml-swift-APACHE-2.0.txt"
cp -f "$work_dir/runtime/.build/checkouts/swift-argument-parser/LICENSE.txt" \
    "$output_dir/licenses/swift-argument-parser-APACHE-2.0.txt"
chmod 755 "$output_dir/freeflow-local-asr"

echo "Built $output_dir/freeflow-local-asr from $runtime_tag ($runtime_commit)"
