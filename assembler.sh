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

# --- Step 2: File structure validation ---

if [[ ! -s "$filename" ]]; then
    echo "Warning: input file '$filename' is empty. No .bin file will be produced."
    exit 1
fi

mapfile -t lines < "$filename"

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "Warning: input file '$filename' contains no lines. No .bin file will be produced."
    exit 1
fi

line1="${lines[0]}"

if [[ "$line1" != "0" && "$line1" != "2" ]]; then
    echo "Error: Line 1 must be exactly 0 or 2 (found: '$line1')."
    exit 1
fi

echo "Line 1 validation passed: n_values = $line1"
echo "Argument validation passed for: $filename"
