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

lines=()
while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
done < "$filename"

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "Warning: input file '$filename' contains no lines. No .bin file will be produced."
    exit 1
fi

line1="${lines[0]}"

if [[ "$line1" != "0" && "$line1" != "2" ]]; then
    echo "Error: Line 1 must be exactly 0 or 2 (found: '$line1')."
    exit 1
fi

# --- Step 3: Handle n_values == 0 case ---

bin_filename="${filename%.vsc}.bin"

if [[ "$line1" == "0" ]]; then
    if [[ ${#lines[@]} -ne 2 ]]; then
        echo "Error: when n_values is 0, the file must contain exactly 2 lines."
        exit 1
    fi

    line2="${lines[1]}"

    if [[ "$line2" != "QUIT,0,0" ]]; then
        echo "Error: when n_values is 0, Line 2 must be exactly 'QUIT,0,0'."
        exit 1
    fi

    printf '\x20\x00' > "$bin_filename"

    echo "Assembly successful. Generated $bin_filename"
    exit 0
fi

echo "Argument validation passed for: $filename"
