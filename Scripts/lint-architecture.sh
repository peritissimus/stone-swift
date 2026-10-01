#!/usr/bin/env bash
# Checks the rules the package graph cannot: which modules each layer imports, and file homogeneity.
set -euo pipefail
cd "$(dirname "$0")/../Packages/StoneKit/Sources"

fail=0
check() { # layer, allowed-imports regex
  local bad
  bad=$(grep -rhn '^import ' "$1" | grep -Ev "^[0-9]+:import ($2)$" || true)
  if [[ -n "$bad" ]]; then echo "✘ $1 imports outside ($2):"; grep -rn '^import ' "$1" | grep -Ev "import ($2)$"; fail=1; fi
}

check StoneDomain      'Foundation'
check StoneApplication 'Foundation|StoneDomain'
check StoneAdaptersOut 'Foundation|StoneDomain'
check StoneUI          'Foundation|StoneDomain|AppKit|SwiftUI|Observation|Carbon\.HIToolbox'

# PascalCase files hold exactly one named type; camelCase files hold no types at all.
while IFS= read -r file; do
  name=$(basename "$file" .swift)
  types=$(grep -cE '^(public |final |private |fileprivate |internal )*(final )?(class|struct|enum|protocol|actor) ' "$file" || true)
  if [[ "$name" =~ ^[a-z] ]]; then
    [[ "$types" -eq 0 ]] || { echo "✘ $file: camelCase helper declares a type"; fail=1; }
  else
    grep -qE "(class|struct|enum|protocol|actor) $name\b" "$file" || { echo "✘ $file: no type named $name"; fail=1; }
  fi
done < <(find . -name '*.swift')

[[ $fail -eq 0 ]] && echo "✔ architecture lint clean"
exit $fail
