#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 固定证书可让 macOS 在重新编译后继续识别同一应用。
ice_signing_identity="${ICE_CODE_SIGN_IDENTITY:-}"
if [[ -z "$ice_signing_identity" ]]; then
    ice_signing_identity="$(python3 - <<'PY'
import re
import subprocess
import sys

result = subprocess.run(
    ['security', 'find-identity', '-v', '-p', 'codesigning'],
    check=True, capture_output=True, text=True,
)
identities = re.findall(r'^\s*\d+\) ([A-F0-9]{40}) "Apple Development:[^\n]+"$', result.stdout, re.MULTILINE)
if len(identities) != 1:
    sys.exit('请用 ICE_CODE_SIGN_IDENTITY 指定固定签名证书；临时签名可能导致每次编译后重新授权。')
print(identities[0])
PY
)"
fi
ice_hardened_runtime=YES
if [[ "$ice_signing_identity" == "-" ]]; then
    echo '注意：临时签名无法稳定保留系统权限，仅用于一次性构建。' >&2
    ice_hardened_runtime=NO
fi

# 保留锁定依赖，并在编译前应用必要的兼容修复。
xcodebuild -resolvePackageDependencies \
    -project Ice.xcodeproj -scheme Ice \
    -clonedSourcePackagesDirPath build/SourcePackages
python3 scripts/prepare_dependencies.py build/SourcePackages
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
    -derivedDataPath build/DerivedData \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -disableAutomaticPackageResolution \
    CODE_SIGN_IDENTITY="$ice_signing_identity" CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME="$ice_hardened_runtime" build
