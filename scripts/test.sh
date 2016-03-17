#!/bin/bash
#
# Run toybox tests.
#
# Usage:
#   scripts/test.sh [command]...
#
# Examples:
#   $ scripts/test.sh all   # run tests for all commands
#   $ scripts/test.sh commands grep sed   # run tests for these two commands
#
#   # Test 'grep' on the system, not toybox
#   $ TEST_HOST=1 scripts/test.sh commands grep 
#
# TODO:
# - Document the test interface!  Can't exit 1.

[ -z "$TOPDIR" ] && TOPDIR="$(pwd)"

trap 'kill $(jobs -p) 2>/dev/null; exit 1' INT

rm -rf generated/testdir
mkdir -p generated/testdir/testdir

setup_test_env()
{
  PATH="$TOPDIR/generated/testdir:$PATH"
  cd generated/testdir/testdir
  export LC_COLLATE=C

  # Library functions used by .test scripts, e.g. 'testing'.
  . "$TOPDIR"/scripts/runtest.sh

  if [ -f "$TOPDIR/generated/config.h" ]
  then
    export OPTIONFLAGS=:$(echo $(sed -nr 's/^#define CFG_(.*) 1/\1/p' "$TOPDIR/generated/config.h") | sed 's/ /:/g')
  fi
}

# Run tests for specific commands.
commands()
{
  # Build individual binaries
  [ -z "$TEST_HOST" ] &&
    PREFIX=generated/testdir/ scripts/single.sh "$@" || exit 1

  setup_test_env

  # Run tests for the given commands
  for cmd in "$@"
  do
    CMDNAME=$cmd
    . "$TOPDIR"/tests/$cmd.test
  done
}

# Run tests for all commands.
all()
{
  # Build a toybox binary and create symlinks to it.
  [ -z "$TEST_HOST" ] &&
    make install_flat PREFIX=generated/testdir || exit 1

  setup_test_env

  # Run all tests
  for test_file in "$TOPDIR"/tests/*.test
  do
    CMDNAME="${test_file##*/}"
    CMDNAME="${CMDNAME%.test}"

    if [ -h ../$CMDNAME ] || [ -n "$TEST_HOST" ]
    then
      # clear the test dir
      cd .. && rm -rf testdir && mkdir testdir && cd testdir || exit 1
      . $test_file
    else
      echo "$CMDNAME disabled"
    fi
  done
}

"$@"
