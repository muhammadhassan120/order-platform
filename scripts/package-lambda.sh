#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/services/order-processor"
BUILD_DIR="${ROOT_DIR}/infra/modules/async/lambda_build"

if [[ -n "${PYTHON_BIN:-}" ]]; then
  # shellcheck disable=SC2206
  PYTHON_CMD=(${PYTHON_BIN})
elif command -v py >/dev/null 2>&1 && py -3 -m pip --version >/dev/null 2>&1; then
  PYTHON_CMD=(py -3)
elif command -v py.exe >/dev/null 2>&1 && py.exe -3 -m pip --version >/dev/null 2>&1; then
  PYTHON_CMD=(py.exe -3)
elif command -v python >/dev/null 2>&1 && python -m pip --version >/dev/null 2>&1; then
  PYTHON_CMD=(python)
elif command -v python.exe >/dev/null 2>&1 && python.exe -m pip --version >/dev/null 2>&1; then
  PYTHON_CMD=(python.exe)
elif command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
  PYTHON_CMD=(python3)
else
  echo "Python with pip was not found. Set PYTHON_BIN to the Python executable." >&2
  exit 1
fi

case "${BUILD_DIR}" in
  "${ROOT_DIR}/infra/modules/async/lambda_build") ;;
  *)
    echo "Refusing to remove unexpected build directory: ${BUILD_DIR}" >&2
    exit 1
    ;;
esac

to_windows_path() {
  local path="$1"
  if [[ "${path}" =~ ^/mnt/([A-Za-z])/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]^^}"
    local rest="${BASH_REMATCH[2]//\//\\}"
    printf '%s:\\%s' "${drive}" "${rest}"
  else
    printf '%s' "${path}"
  fi
}

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

PIP_REQUIREMENTS="${SRC_DIR}/requirements.txt"
PIP_TARGET="${BUILD_DIR}"
case "${PYTHON_CMD[0]}" in
  py|py.exe|python.exe)
    if command -v cygpath >/dev/null 2>&1; then
      PIP_REQUIREMENTS="$(cygpath -w "${PIP_REQUIREMENTS}")"
      PIP_TARGET="$(cygpath -w "${PIP_TARGET}")"
    else
      PIP_REQUIREMENTS="$(to_windows_path "${PIP_REQUIREMENTS}")"
      PIP_TARGET="$(to_windows_path "${PIP_TARGET}")"
    fi
    ;;
esac

"${PYTHON_CMD[@]}" -m pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  -r "${PIP_REQUIREMENTS}" \
  -t "${PIP_TARGET}"

cp "${SRC_DIR}/handler.py" "${BUILD_DIR}/handler.py"
cp "${SRC_DIR}/invoice_generator.py" "${BUILD_DIR}/invoice_generator.py"

find "${BUILD_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "${BUILD_DIR}" -type f -name "*.pyc" -delete

echo "Lambda package source synced to ${BUILD_DIR}"
