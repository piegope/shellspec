#!/bin/sh
#shellcheck disable=SC2004

# shellcheck source=lib/libexec.sh
. "${SHELLSPEC_LIB:-./lib}/libexec.sh"
load parser

i=0
specfile() {
  while read -r line; do
    is_example "${line%% *}" && i=$(($i + 1))
  done < "$1"
}
find_specfiles specfile "$@"

if [ "$SHELLSPEC_EXAMPLES_LOG" ]; then
  echo "$i" > "${SHELLSPEC_EXAMPLES_LOG}#"
  mv "${SHELLSPEC_EXAMPLES_LOG}#" "$SHELLSPEC_EXAMPLES_LOG"
fi

echo "$i"
