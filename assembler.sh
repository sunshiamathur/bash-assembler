#!/bin/bash

# --- Step 1: Argument validation ---

if [[ $# -ne 1 ]]; then
    echo "Error: exactly one argument required. Usage: bash assembler.sh <filename.vsc>"
    exit 1
fi

filename="$1"

if [[ ! -f "$filename" ]]; then
    echo "Error: file '$filename' does not exist."
    exit 1
fi

if [[ "$filename" != *.vsc ]]; then
    echo "Error: file must have a .vsc extension."
    exit 1
fi

echo "Argument validation passed for: $filename"
