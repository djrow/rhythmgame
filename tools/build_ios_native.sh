#!/usr/bin/env bash
# ==============================================================================
# Build Native ONNX Runtime GDExtension XCFramework for iOS & macOS (arm64/x86_64)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/addons/onnx_pitch/bin"
BUILD_DIR="${PROJECT_ROOT}/build/ios_native_tmp"
ORT_VERSION="1.20.0"

mkdir -p "${BIN_DIR}" "${BUILD_DIR}"

echo "[1/5] Fetching ONNX Runtime CocoaPod XCFramework (v${ORT_VERSION})..."
if [ ! -d "${BIN_DIR}/onnxruntime.xcframework" ]; then
    ORT_ARCHIVE="${BUILD_DIR}/onnxruntime-c-${ORT_VERSION}.zip"
    ORT_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ORT_VERSION}.zip"
    curl -fSL "${ORT_URL}" -o "${ORT_ARCHIVE}"
    mkdir -p "${BUILD_DIR}/ort_extracted"
    unzip -q "${ORT_ARCHIVE}" -d "${BUILD_DIR}/ort_extracted"
    FOUND_XCF="$(find "${BUILD_DIR}/ort_extracted" -name "onnxruntime.xcframework" -type d | head -n 1)"
    if [ -z "${FOUND_XCF}" ]; then
        echo "ERROR: onnxruntime.xcframework not found in archive" >&2
        exit 1
    fi
    rm -rf "${BIN_DIR}/onnxruntime.xcframework"
    cp -R "${FOUND_XCF}" "${BIN_DIR}/onnxruntime.xcframework"
    echo "  -> Installed ${BIN_DIR}/onnxruntime.xcframework"
else
    echo "  -> Existing ${BIN_DIR}/onnxruntime.xcframework found"
fi

ORT_XCF="${BIN_DIR}/onnxruntime.xcframework"
mkdir -p "${BUILD_DIR}/device" "${BUILD_DIR}/sim" "${BUILD_DIR}/macos"

echo "[2/5] Building iOS Device (iphoneos arm64) dynamic library with embedded ONNX Runtime..."
IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang \
    -arch arm64 \
    -isysroot "${IOS_SDK_PATH}" \
    -miphoneos-version-min=15.0 \
    -O2 -fPIC -fvisibility=hidden \
    -I "${PROJECT_ROOT}/native" \
    -c "${PROJECT_ROOT}/native/onnx_pitch_gdextension.c" \
    -o "${BUILD_DIR}/device/onnx_pitch_gdextension.o"

xcrun --sdk iphoneos clang++ \
    -dynamiclib \
    -arch arm64 \
    -isysroot "${IOS_SDK_PATH}" \
    -miphoneos-version-min=15.0 \
    -install_name "@rpath/libonnx_pitch.ios.framework/libonnx_pitch.ios" \
    "${BUILD_DIR}/device/onnx_pitch_gdextension.o" \
    "${ORT_XCF}/ios-arm64/onnxruntime.framework/onnxruntime" \
    -framework Foundation -framework CoreFoundation -framework Accelerate \
    -lc++ \
    -o "${BUILD_DIR}/device/libonnx_pitch.ios.dylib"

echo "[3/5] Building iOS Simulator (iphonesimulator arm64 + x86_64) dynamic library..."
SIM_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang \
    -arch arm64 -arch x86_64 \
    -isysroot "${SIM_SDK_PATH}" \
    -miphonesimulator-version-min=15.0 \
    -O2 -fPIC -fvisibility=hidden \
    -I "${PROJECT_ROOT}/native" \
    -c "${PROJECT_ROOT}/native/onnx_pitch_gdextension.c" \
    -o "${BUILD_DIR}/sim/onnx_pitch_gdextension.o"

xcrun --sdk iphonesimulator clang++ \
    -dynamiclib \
    -arch arm64 -arch x86_64 \
    -isysroot "${SIM_SDK_PATH}" \
    -miphonesimulator-version-min=15.0 \
    -install_name "@rpath/libonnx_pitch.ios.framework/libonnx_pitch.ios" \
    "${BUILD_DIR}/sim/onnx_pitch_gdextension.o" \
    "${ORT_XCF}/ios-arm64_x86_64-simulator/onnxruntime.framework/onnxruntime" \
    -framework Foundation -framework CoreFoundation -framework Accelerate \
    -lc++ \
    -o "${BUILD_DIR}/sim/libonnx_pitch.ios.dylib"

echo "[4/5] Building macOS universal dynamic library for headless Godot export..."
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang \
    -arch arm64 -arch x86_64 \
    -isysroot "${MACOS_SDK_PATH}" \
    -mmacosx-version-min=12.0 \
    -O2 -fPIC -fvisibility=hidden \
    -I "${PROJECT_ROOT}/native" \
    -c "${PROJECT_ROOT}/native/onnx_pitch_gdextension.c" \
    -o "${BUILD_DIR}/macos/onnx_pitch_gdextension.o"

MACOS_ORT_BIN="${ORT_XCF}/macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime"
if [ ! -f "${MACOS_ORT_BIN}" ]; then
    MACOS_ORT_BIN="${ORT_XCF}/macos-arm64_x86_64/onnxruntime.framework/onnxruntime"
fi

xcrun --sdk macosx clang++ \
    -dynamiclib \
    -arch arm64 -arch x86_64 \
    -isysroot "${MACOS_SDK_PATH}" \
    -mmacosx-version-min=12.0 \
    -install_name "@rpath/libonnx_pitch.macos.dylib" \
    "${BUILD_DIR}/macos/onnx_pitch_gdextension.o" \
    "${MACOS_ORT_BIN}" \
    -framework Foundation -framework CoreFoundation -framework Accelerate \
    -lc++ \
    -o "${BIN_DIR}/libonnx_pitch.macos.dylib"

echo "[5/5] Packaging addons/onnx_pitch/bin/onnx_pitch.ios.xcframework..."
rm -rf "${BIN_DIR}/onnx_pitch.ios.xcframework"
xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/device/libonnx_pitch.ios.dylib" \
    -library "${BUILD_DIR}/sim/libonnx_pitch.ios.dylib" \
    -output "${BIN_DIR}/onnx_pitch.ios.xcframework"

rm -rf "${BUILD_DIR}"
echo "SUCCESS: Built ${BIN_DIR}/onnx_pitch.ios.xcframework and ${BIN_DIR}/libonnx_pitch.macos.dylib"
