#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [ "${expected}" != "${actual}" ]; then
    fail "${msg}: expected='${expected}' actual='${actual}'"
  fi
}

assert_not_eq() {
  local unexpected="$1"
  local actual="$2"
  local msg="$3"
  if [ "${unexpected}" = "${actual}" ]; then
    fail "${msg}: value should not equal '${unexpected}'"
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if ! grep -Fq "${needle}" "${file}"; then
    fail "${msg}: '${needle}' not found in ${file}"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq "${needle}" "${file}"; then
    fail "${msg}: '${needle}' unexpectedly found in ${file}"
  fi
}

assert_success() {
  local msg="$1"
  shift
  if ! "$@"; then
    fail "${msg}: command failed"
  fi
}

assert_failure() {
  local msg="$1"
  shift
  if "$@"; then
    fail "${msg}: command unexpectedly succeeded"
  fi
}

assert_not_empty() {
  local val="$1"
  local msg="$2"
  if [ -z "${val}" ]; then
    fail "${msg}: value is empty but should not be"
  fi
}

assert_empty() {
  local val="$1"
  local msg="$2"
  if [ -n "${val}" ]; then
    fail "${msg}: value should be empty but got '${val}'"
  fi
}

new_temp_dir() {
  mktemp -d
}

make_stub_bin() {
  local dir="$1"
  mkdir -p "${dir}"
}

write_stub() {
  local path="$1"
  local content="$2"
  cat > "${path}" <<EOS
#!/bin/sh
${content}
EOS
  chmod +x "${path}"
}

pass() {
  echo "[PASS] $1"
}
