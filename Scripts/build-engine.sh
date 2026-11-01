#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
command -v cargo >/dev/null || { echo '请先安装 Rust stable 和 rustup，并将 cargo 加入 PATH。'; exit 1; }
xcodebuild -checkFirstLaunchStatus
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    rustup target add "$target"
    cargo build --locked --release --manifest-path "$repo_dir/NativeEngine/Cargo.toml" \
        -p grainroom-spectral --target "$target"
done
artifact_dir="${CARGO_TARGET_DIR:-$repo_dir/NativeEngine/target}"
staging_dir="$artifact_dir/grainroom-staging"
mkdir -p "$staging_dir/simulator" "$repo_dir/Frameworks"
xcrun lipo -create \
    "$artifact_dir/aarch64-apple-ios-sim/release/libgrainroom_spectral.a" \
    "$artifact_dir/x86_64-apple-ios/release/libgrainroom_spectral.a" \
    -output "$staging_dir/simulator/libgrainroom_spectral.a"
# xcodebuild requires a fresh output directory. Preserve previous builds.
framework_dir="$repo_dir/Frameworks/GrainroomSpectral.xcframework"
if [ -d "$framework_dir" ]; then
    mv "$framework_dir" "$staging_dir/GrainroomSpectral-$(date +%s).xcframework"
fi
xcodebuild -create-xcframework \
    -library "$artifact_dir/aarch64-apple-ios/release/libgrainroom_spectral.a" -headers "$repo_dir/NativeEngine/include" \
    -library "$staging_dir/simulator/libgrainroom_spectral.a" -headers "$repo_dir/NativeEngine/include" \
    -output "$framework_dir"
