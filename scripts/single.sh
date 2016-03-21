#!/bin/bash
#
# Build standalone toybox commands.
#
# Usage:
#   scripts/single.sh COMMAND_PATH...
#
# Example:
#   $ scripts/single.sh generated/single/grep generated/single/sed

if [ $# -eq 0 ]
then
  echo "Usage: single.sh COMMAND..." >&2
  exit 1
fi

# Harvest TOYBOX_* symbols from .config
if [ ! -e .config ]
then
  echo "Need .config for toybox global settings. Run defconfig/menuconfig." >&2
  exit 1
fi

# For each command:
# 1) write a .singleconfig file (I think this would be better as
# generated/singleconfig/sed)
# 2) make allnoconfig, except turn stuff related to the command on
# 3) make toybox, and then move it to the command name.

export KCONFIG_CONFIG=.singleconfig
for out_path in "$@"
do
  cmd=$(basename $out_path)
  echo -n "$cmd:"
  TOYFILE="$(egrep -l "TOY[(]($cmd)[ ,]" toys/*/*.c)"

  if [ -z "$TOYFILE" ]
  then
    echo "Unknown command '$cmd'" >&2
    exit 1
  fi

  # Enable stuff this command depends on
  DEPENDS="$(sed -n "/^config *$cmd"'$/,/^$/{s/^[ \t]*depends on //;T;s/[!][A-Z0-9_]*//g;s/ *&& */|/g;p}' $TOYFILE | xargs | tr ' ' '|')"

  NAME=$(echo $cmd | tr a-z- A-Z_)
  make allnoconfig > /dev/null &&
  sed -ri -e '/CONFIG_TOYBOX/d' \
    -e "s/# (CONFIG_($NAME|${NAME}_.*${DEPENDS:+|$DEPENDS})) is not set/\1=y/" \
    "$KCONFIG_CONFIG" &&
  echo "# CONFIG_TOYBOX is not set" >> "$KCONFIG_CONFIG" &&
  grep "CONFIG_TOYBOX_" .config >> "$KCONFIG_CONFIG" &&
  mkdir -p $(dirname $out_path) &&
  scripts/make.sh $out_path || exit 1
done
