#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

grepc() {
  find . -name \*.c | xargs -- grep --color "$@"
}

# failures: undefined references to xfork
build-all() {
  make clean
  make allyesconfig
  make
}

"$@"
