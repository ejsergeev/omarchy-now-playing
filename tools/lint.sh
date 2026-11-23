#!/bin/sh
# Every static check the plugin is held to (docs/METRICS.md, Q1-Q6). Exits
# non-zero if any of them finds something.
#   tools/lint.sh            all checks
#   tools/lint.sh qml        one check: qml, sh, test, i18n, structure, manifest
set -u
cd "$(dirname "$0")/.." || exit 1
QT_BIN=${QT_BIN:-/usr/lib/qt6/bin}
SHELL_DIR=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
only=${1:-}
failed=""

run() { [ -z "$only" ] || [ "$only" = "$1" ]; }
fail() { failed="$failed $1"; }

# QML: the shell's own modules are imported as qs.*; a qs link to the shell
# lets qmllint resolve them as Quickshell does. It lives outside the plugin
# folder, where Omarchy allows no symlinks.
if run qml; then
  imports="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-now-playing/qmllint"
  mkdir -p "$imports" && ln -sfn "$SHELL_DIR" "$imports/qs"
  qml_files=$(find . -name '*.qml' -not -path './bench/*' | sort)
  # shellcheck disable=SC2086 # one argument per file
  out=$("$QT_BIN/qmllint" -I /usr/lib/qt6/qml -I "$imports" $qml_files 2>&1)
  count=$(printf '%s\n' "$out" | grep -c '^Warning')
  printf '%s\n' "$out" | grep '^Warning'
  echo "qmllint: $count warnings"
  [ "$count" -eq 0 ] || fail qml
fi

if run sh; then
  if command -v shellcheck >/dev/null; then
    # shellcheck disable=SC2046 # one argument per file
    shellcheck -x $(find . -name '*.sh' | sort) && echo "shellcheck: clean" || fail sh
  else
    echo "shellcheck: not installed, skipped (pacman -S shellcheck)"
  fi
fi

if run test; then
  node --test --experimental-test-coverage \
    --test-coverage-include='lib/**/*.js' \
    --test-coverage-lines=100 --test-coverage-branches=95 \
    tests/ || fail test
fi

if run i18n; then node tools/check-i18n.mjs || fail i18n; fi
if run structure; then node tools/metrics.mjs || fail structure; fi

if run manifest && command -v omarchy >/dev/null; then
  omarchy plugin validate "$PWD" || fail manifest
fi

if [ -n "$failed" ]; then
  echo "lint failed:$failed"
  exit 1
fi
echo "lint: all checks passed"
