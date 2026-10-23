#!/bin/sh
# Scan a directory (default: repo root) for strings that must not ship.
# Prints "LEAK <file>:<line>: <pattern>" per match of a built-in pattern, and
# "LEAK <file>:<line>: private pattern #<n>" per match of the private list
# (n = line number in the list file; the pattern text is never printed).
# Exit 1 on any match.
#
# The built-in patterns are generic (account IDs, resource IDs, ARNs, IPv4
# addresses, private keys). Named strings live in a private list file:
# Env QUANT_LEAK_LIST: file with one pattern per line. A line is a
# case-insensitive fixed string; a line starting "re:" is a case-insensitive
# extended regex; blank lines and lines starting "#" are ignored.
case ${QUANT_LEAK_LIST:-} in
  '' | /*) ;;
  *) QUANT_LEAK_LIST="$(pwd)/$QUANT_LEAK_LIST" ;;
esac
cd "${1:-.}" || exit 2
status=0

PATTERNS='\b[0-9]{12}\b
vpc-[0-9a-f]{8,}
subnet-[0-9a-f]{8,}
sg-[0-9a-f]{8,}
arn:aws:
-----BEGIN [A-Z ]*PRIVATE KEY-----'
IPV4='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
US=$(printf '\037')

list_files() {
  find . -type f \
    -not -path './.git/*' -not -path './.superpowers/*' \
    -not -path './tests/fixtures/*' -not -path './scripts/leak-check.sh' \
    -print0
}

# Read grep --null output ("file<NUL>line:text") with NUL turned into US.
# Print LEAK lines labelled with $1. File names may contain colons.
label() {
  tr '\000' "$US" | awk -F "$US" -v p="$1" '{
    split($2, rest, ":")
    print "LEAK " $1 ":" rest[1] ": " p
  }'
}

scan() { # pattern grep-mode(-E|-F) [label; default: the pattern]
  list_files | xargs -0 grep -HniI --null "$2" -e "$1" /dev/null 2>/dev/null |
    label "${3:-$1}"
}

scan_ipv4() {
  list_files | xargs -0 grep -HnoiIE --null -e "$IPV4" /dev/null 2>/dev/null |
    grep -av -e ':0\.0\.0\.0$' -e ':127\.0\.0\.1$' | label 'ipv4 address'
}

scan_patterns() {
  printf '%s\n' "$PATTERNS" | while IFS= read -r p; do
    scan "$p" -E
  done
}

# Private patterns are never printed: public CI logs would expose them.
scan_list_line() { # line number
  case $1 in
    '' | '#'*) ;;
    re:*) scan "${1#re:}" -E "private pattern #$2" ;;
    *) scan "$1" -F "private pattern #$2" ;;
  esac
}

scan_private_list() {
  [ -n "${QUANT_LEAK_LIST:-}" ] || return 0
  if [ ! -f "$QUANT_LEAK_LIST" ]; then
    echo "LEAK $QUANT_LEAK_LIST: list file not found"
    return 0
  fi
  n=0
  while IFS= read -r p || [ -n "$p" ]; do
    n=$((n + 1))
    scan_list_line "${p%"$(printf '\r')"}" "$n"
  done < "$QUANT_LEAK_LIST"
}

hits=$( { scan_patterns; scan_ipv4; scan_private_list; } | sort -u)
if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  status=1
fi
exit "$status"
