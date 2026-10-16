#!/usr/bin/env bash
# ==============================================================================
# Build Native ONNX Runtime GDExtension XCFramework for iOS (arm64 Device + Sim)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/addons/onnx_pitch/bin"
BUILD_DIR="${PROJECT_ROOT}/build/ios_native_tmp"
ORT_VERSION="1.20.0"

mkdir -p "${BIN_DIR}" "${BUILD_DIR}"

echo "[1/4] Fetching ONNX Runtime iOS XCFramework (v${ORT_VERSION})..."
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

echo "[2/4] Compiling native/onnx_pitch_gdextension.c for iphoneos (arm64)..."
IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "${BUILD_DIR}/device" "${BUILD_DIR}/sim"

xcrun --sdk iphoneos clang \
    -arch arm64 \
    -isysroot "${IOS_SDK_PATH}" \
    -miphoneos-version-min=15.0 \
    -O2 -fPIC -fvisibility=hidden \
    -I "${PROJECT_ROOT}/native" \
    -c "${PROJECT_ROOT}/native/onnx_pitch_gdextension.c" \
    -o "${BUILD_DIR}/device/onnx_pitch_gdextension.o"

libtool -static -o "${BUILD_DIR}/device/libonnx_pitch.a" "${BUILD_DIR}/device/onnx_pitch_gdextension.o"

echo "[3/4] Compiling native/onnx_pitch_gdextension.c for iphonesimulator (arm64 + x86_64)..."
SIM_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"

xcrun --sdk iphonesimulator clang \
    -arch arm64 -arch x86_64 \
    -isysroot "${SIM_SDK_PATH}" \
    -miphonesimulator-version-min=15.0 \
    -O2 -fPIC -fvisibility=hidden \
    -I "${PROJECT_ROOT}/native" \
    -c "${PROJECT_ROOT}/native/onnx_pitch_gdextension.c" \
    -o "${BUILD_DIR}/sim/onnx_pitch_gdextension.o"

libtool -static -o "${BUILD_DIR}/sim/libonnx_pitch.a" "${BUILD_DIR}/sim/onnx_pitch_gdextension.o"

echo "[4/4] Packaging addons/onnx_pitch/bin/onnx_pitch.ios.xcframework..."
rm -rf "${BIN_DIR}/onnx_pitch.ios.xcframework"
xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/device/libonnx_pitch.a" \
    -library "${BUILD_DIR}/sim/libonnx_pitch.a" \
    -output "${BIN_DIR}/onnx_pitch.ios.xcframework"

rm -rf "${BUILD_DIR}"
echo "SUCCESS: Built ${BIN_DIR}/onnx_pitch.ios.xcframework and ${BIN_DIR}/onnxruntime.xcframework"
