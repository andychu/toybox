#!/bin/bash
#
# Run toybox tests.
#
# TODO:
# - Document the test interface!
# - What functions do you get?
#   - testing from runtests.sh
#   - tests/_testfuncs.sh  # common code
# - CMDNAME
# - FAILCOUNT

usage()
{
  cat <<EOF
Usage:
  scripts/test.sh all
  scripts/test.sh single COMMAND...

Examples:
  $ scripts/test.sh all               # run tests for all commands
  $ scripts/test.sh single grep sed   # run tests for these two commands

  # Test 'grep' on the system, not toybox
  $ TEST_HOST=1 scripts/test.sh commands grep 
EOF
}

[ -z "$TOPDIR" ] && TOPDIR="$(pwd)"

trap 'kill $(jobs -p) 2>/dev/null; exit 1' INT

cd_test_dir()
{
  local cmd=$1
  local test_dir=$TEST_ROOT/test_$cmd
  rm -rf $test_dir
  mkdir -p $test_dir
  cd $test_dir
}

setup_test_env()
{
  # Before changing path, set variables for host executables.
  HOST_BIN_TAR=$(which tar)
  HOST_BIN_BZCAT=$(which bzcat)
  HOST_BIN_XZCAT=$(which xzcat)
  HOST_BIN_ZCAT=$(which zcat)

  HOST_BIN_DATE=$(which date)
  HOST_BIN_HOSTNAME=$(which hostname)

  PATH="$BIN_DIR:$PATH"  # Make sure the tests can use toybox tools
  export LC_COLLATE=C

  # Library functions used by .test scripts, e.g. 'testing'.
  . "$TOPDIR/scripts/runtest.sh"

  if [ -f "$TOPDIR/generated/config.h" ]
  then
    export OPTIONFLAGS=:$(echo $(sed -nr 's/^#define CFG_(.*) 1/\1/p' "$TOPDIR/generated/config.h") | sed 's/ /:/g')
  fi
}

# Run tests for specific commands.
single()
{
  # Build individual binaries, e.g. generated/testdir/expr
  [ -z "$TEST_HOST" ] && PREFIX=$BIN_DIR/ scripts/single.sh "$@" || exit 1

  setup_test_env

  for cmd in "$@"
  do
    CMDNAME=$cmd  # .test file uses this
    cd_test_dir $cmd
    . "$TOPDIR"/tests/$cmd.test
    [ $FAILCOUNT -ne 0 ] && echo "Failures so far: $FAILCOUNT"
  done

  [ $FAILCOUNT -eq 0 ]  # exit success if there 0 failures
}

# Run tests for all commands.
all()
{
  # Build a toybox binary and create symlinks to it.
  [ -z "$TEST_HOST" ] && make install_flat PREFIX=$BIN_DIR/ || exit 1

  setup_test_env

  for test_file in "$TOPDIR"/tests/*.test
  do
    # Strip off the front and back of the test filename to get the command
    CMDNAME="${test_file##*/}"
    CMDNAME="${CMDNAME%.test}"

    if [ -h $BIN_DIR/$CMDNAME ] || [ -n "$TEST_HOST" ]
    then
      local old_count=$FAILCOUNT
      cd_test_dir $CMDNAME
      . $test_file
      [ $FAILCOUNT -ne 0 ] && echo "Failures so far: $FAILCOUNT"
      [ $FAILCOUNT -ne $old_count ] && echo "Some $CMDNAME tests failed"
    else
      echo "$CMDNAME not built"
    fi
  done

  [ $FAILCOUNT -eq 0 ]  # exit success if there 0 failures
}

readonly TEST_ROOT=$TOPDIR/generated/test
readonly BIN_DIR=$TEST_ROOT/bin

rm -rf $TEST_ROOT  # clear out data from old runs
mkdir -p $BIN_DIR

case $1 in
  single|all)
    "$@"
    ;;
  *)
    usage
    ;;
esac
