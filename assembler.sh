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

bin_filename="${filename%.vsc}.bin"

# --- Step 3: Handle n_values == 0 case ---

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

# --- Step 4: Handle n_values == 2 case (static values) ---

dataArray=()
next_line_index=1

if [[ "$line1" == "2" ]]; then
    if [[ ${#lines[@]} -lt 3 ]]; then
        echo "Error: when n_values is 2, the file must contain at least 3 lines (n_values, value1, value2)."
        exit 1
    fi

    for i in 1 2; do
        val="${lines[$i]}"

        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "Error: static value on line $((i+1)) ('$val') is not a valid non-negative integer."
            exit 1
        fi

        if [[ "$val" -ge 128 ]]; then
            echo "Error: static value on line $((i+1)) ('$val') must be in range [0, 128)."
            exit 1
        fi

        dataArray+=("$val")
    done

    next_line_index=3
fi

# --- Step 5: Instruction parsing loop ---

instructionBytes=()
instruction_count=0
found_quit=0

for ((idx=next_line_index; idx<${#lines[@]}; idx++)); do
    ins_line="${lines[$idx]}"

    # Skip trailing blank lines
    if [[ -z "$ins_line" ]]; then
        continue
    fi

    if [[ "$instruction_count" -ge 100 ]]; then
        echo "Error: program exceeds maximum capacity of 100 instructions."
        exit 1
    fi

    if [[ "${#ins_line}" -gt 11 ]]; then
        echo "Error: instruction line '$ins_line' exceeds maximum length of 11 characters."
        exit 1
    fi

    # Must have exactly 3 comma-separated fields
    IFS=',' read -r ins reg mem extra <<< "$ins_line"

    if [[ -z "$ins" || -z "$reg" || -z "$mem" || -n "$extra" ]]; then
        echo "Error: instruction line '$ins_line' must have exactly 3 comma-separated fields."
        exit 1
    fi

    case "$ins" in
        LOAD)  opcode=1 ;;
        STORE) opcode=2 ;;
        ADD)   opcode=3 ;;
        SUB)   opcode=4 ;;
        QUIT)  opcode=8 ;;
        PRINT) opcode=9 ;;
        *)
            echo "Error: unrecognised instruction '$ins' in line '$ins_line'."
            exit 1
            ;;
    esac

    if ! [[ "$reg" =~ ^[0-9]+$ ]] || [[ "$reg" -gt 3 ]]; then
        echo "Error: register field '$reg' in line '$ins_line' must be an integer 0-3."
        exit 1
    fi

    if ! [[ "$mem" =~ ^[0-9]+$ ]] || [[ "$mem" -gt 255 ]]; then
        echo "Error: memory address '$mem' in line '$ins_line' must be an integer 0-255."
        exit 1
    fi

    if [[ "$ins" == "QUIT" ]] && { [[ "$reg" -ne 0 ]] || [[ "$mem" -ne 0 ]]; }; then
        echo "Error: QUIT instruction in line '$ins_line' must be exactly QUIT,0,0."
        exit 1
    fi

    if [[ "$ins" == "PRINT" ]] && [[ "$mem" -ne 0 ]]; then
        echo "Error: PRINT instruction in line '$ins_line' must have memory address 0."
        exit 1
    fi

    byte1=$(( (opcode << 2) | reg ))
    byte2=$mem

    instructionBytes+=("$byte1")
    instructionBytes+=("$byte2")

    instruction_count=$((instruction_count+1))

    if [[ "$ins" == "QUIT" ]]; then
        found_quit=1
        break
    fi
done

if [[ "$found_quit" -eq 0 ]]; then
    echo "Error: program does not contain a terminating QUIT instruction."
    exit 1
fi

# --- Write output: static values first, then instructions ---

> "$bin_filename"
for b in "${dataArray[@]}"; do
    printf "$(printf '\\x%02x' "$b")" >> "$bin_filename"
done
for b in "${instructionBytes[@]}"; do
    printf "$(printf '\\x%02x' "$b")" >> "$bin_filename"
done

echo "Assembly successful. Generated $bin_filename"
