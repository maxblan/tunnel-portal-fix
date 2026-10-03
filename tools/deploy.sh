#!/usr/bin/env bash
# Copies mod folders into the Transport Fever 3 staging area (where the game loads local mods),
# or removes them again.
#
# Usage: tools/deploy.sh [--remove] <mod-dir>...
# The staging area is found automatically; set TF3_STAGING to override.
set -euo pipefail

remove=0
if [ "${1:-}" = "--remove" ]; then
	remove=1
	shift
fi
[ $# -gt 0 ] || { echo "usage: $0 [--remove] <mod-dir>..." >&2; exit 2; }

staging="${TF3_STAGING:-$(ls -d "/mnt/c/Program Files (x86)/Steam/userdata/"*/3493540/local/staging_area 2>/dev/null | head -n 1)}"
[ -d "$staging" ] || { echo "staging area not found; set TF3_STAGING" >&2; exit 1; }

for dir in "$@"; do
	name="$(basename "$dir")"
	rm -rf "${staging:?}/$name"
	if [ "$remove" -eq 1 ]; then
		echo "removed  $name"
	else
		cp -r "$dir" "$staging/$name"
		echo "deployed $name -> $staging/$name"
	fi
done
