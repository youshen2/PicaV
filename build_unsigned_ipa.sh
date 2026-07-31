#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT}/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData-iOS"
PAYLOAD_ROOT="${BUILD_DIR}/Payload-iOS"
PROJECT="${ROOT}/PicaV.xcodeproj"
SCHEME="PicaV"
APP_NAME="PicaV"
IPA_PATH="${BUILD_DIR}/PicaV-unsigned.ipa"
BUILD_ARGUMENTS=(
  clean build
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration Release
  -sdk iphoneos
  -destination "generic/platform=iOS"
  -derivedDataPath "${DERIVED_DATA}"
  TARGETED_DEVICE_FAMILY="1,2"
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
  CODE_SIGN_ENTITLEMENTS=
  DEVELOPMENT_TEAM=
  PROVISIONING_PROFILE=
  PROVISIONING_PROFILE_SPECIFIER=
)

if [[ -n "${PICAV_MARKETING_VERSION:-}" ]]; then
  if [[ ! "${PICAV_MARKETING_VERSION}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "❌ 版本号格式无效：${PICAV_MARKETING_VERSION}"
    exit 1
  fi
  BUILD_ARGUMENTS+=("MARKETING_VERSION=${PICAV_MARKETING_VERSION}")
fi

if [[ -n "${PICAV_BUILD_NUMBER:-}" ]]; then
  if [[ ! "${PICAV_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "❌ 构建编号格式无效：${PICAV_BUILD_NUMBER}"
    exit 1
  fi
  BUILD_ARGUMENTS+=("CURRENT_PROJECT_VERSION=${PICAV_BUILD_NUMBER}")
fi

if [[ "${BUILD_DIR}" != "${ROOT}/build" ]]; then
  echo "❌ 构建目录校验失败：${BUILD_DIR}"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
rm -rf "${DERIVED_DATA}" "${PAYLOAD_ROOT}"
rm -f "${IPA_PATH}"

echo "========== 构建 iOS App =========="

xcodebuild "${BUILD_ARGUMENTS[@]}"

APP_PATH="$(
  find "${DERIVED_DATA}/Build/Products/Release-iphoneos" \
    -maxdepth 2 \
    -name "${APP_NAME}.app" \
    -type d \
    -print \
    -quit
)"

if [[ -z "${APP_PATH}" ]]; then
  echo "❌ 找不到构建产物：${APP_NAME}.app"
  exit 1
fi

echo "========== 打包未签名 IPA =========="

mkdir -p "${PAYLOAD_ROOT}/Payload"
ditto "${APP_PATH}" "${PAYLOAD_ROOT}/Payload/${APP_NAME}.app"

(
  cd "${PAYLOAD_ROOT}"
  zip -qry "${IPA_PATH}" Payload
)

if [[ ! -f "${IPA_PATH}" ]]; then
  echo "❌ 生成未签名 IPA 失败"
  exit 1
fi

unzip -tq "${IPA_PATH}"

echo "✅ 已生成：${IPA_PATH}"
ls -lh "${IPA_PATH}"
