#!/bin/bash
#
# assembler.sh - converts a .vsc (very-simple-computer) source file into
# its binary (.bin) equivalent for the hypothetical VSC CPU.
#
# Usage: bash assembler.sh <filename.vsc>

# --- Argument validation ---
# Two separate checks (rather than one "not exactly 1" check) because the
# required error messages differ depending on whether zero or multiple
# arguments were given.
if [[ $# -eq 0 ]]; then
    echo "usage: no argument is provided"
    exit 1
fi

if [[ $# -gt 1 ]]; then
    echo "usage: more than one arguments are provided"
    exit 1
fi

filename="$1"

# Check file existence/type BEFORE extension: a path that exists but isn't a
# regular file (e.g. a directory) must be reported as "not a file", while an
# existing file with the wrong extension must be reported as "wrong
# extension". Checking in the other order would misreport one of these cases.
if [[ ! -f "$filename" ]]; then
    echo "usage: input is not a file or it does not exist"
    exit 1
fi

if [[ "$filename" != *.vsc ]]; then
    echo "usage: input does not have the extension .vsc"
    exit 1
fi

# -s is true only if the file exists AND has size > 0.
if [[ ! -s "$filename" ]]; then
    echo "usage: the file is empty – no .bin file is produced"
    exit 1
fi

# Read the whole file into an indexed array, one element per line.
#   - `|| [[ -n "$line" ]]` ensures the final line is captured even if the
#     file doesn't end with a trailing newline.
#   - `${line%$'\r'}` strips a trailing carriage return, to tolerate
#     Windows-style CRLF line endings as well as Unix LF.
lines=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    lines+=("$line")
done < "$filename"

# Defensive backstop; the -s check above already rules out a true
# zero-byte file.
if [[ ${#lines[@]} -eq 0 ]]; then
    echo "usage: the file is empty – no .bin file is produced"
    exit 1
fi

line1="${lines[0]}"

# n_values (Line 1) may only be 0 (QUIT-only program) or 2 (program with
# two static data values) for this CPU model.
if [[ "$line1" != "0" && "$line1" != "2" ]]; then
    echo "Error: Line 1 must be exactly 0 or 2 (found: '$line1')."
    exit 1
fi

# Strip the .vsc suffix and append .bin to derive the output filename.
bin_filename="${filename%.vsc}.bin"

# --- Case: n_values == 0 (sentinel-only program) ---
if [[ "$line1" == "0" ]]; then
    # Both the exact line count and the exact string match matter: the
    # first rejects a stray extra line, the second rejects any malformed
    # variant such as QUIT,0,1.
    if [[ ${#lines[@]} -ne 2 ]]; then
        echo "Error: when n_values is 0, the file must contain exactly 2 lines."
        exit 1
    fi

    line2="${lines[1]}"

    if [[ "$line2" != "QUIT,0,0" ]]; then
        echo "Error: when n_values is 0, Line 2 must be exactly 'QUIT,0,0'."
        exit 1
    fi

    # QUIT's opcode is 8 (binary 001000). Packed as
    # (opcode << 2) | register = (8 << 2) | 0 = 32 = 0x20 for byte 1;
    # memory address is always 0 for QUIT, giving 0x00 for byte 2.
    printf '\x20\x00' > "$bin_filename"

    echo "It is a QUIT program"
    echo "The content of the .bin file is"
    printf '%02x\n' 32 0
    exit 0
fi

# --- Case: n_values == 2 (program with static data + instructions) ---

# Bytes are collected here rather than written immediately, so that if any
# later line turns out to be invalid we can abort with no output written
# at all - nothing touches disk until the whole file has validated.
dataArray=()

if [[ ${#lines[@]} -lt 3 ]]; then
    echo "Error: when n_values is 2, the file must contain at least 3 lines (n_values, value1, value2)."
    exit 1
fi

for i in 1 2; do
    val="${lines[$i]}"

    # Regex check must precede the numeric range check below: running a
    # numeric comparison on a non-numeric string would throw a bash
    # runtime error rather than failing gracefully.
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "Error: static value on line $((i+1)) ('$val') is not a valid non-negative integer."
        exit 1
    fi

    # Spec range for static values is [0, 128).
    if [[ "$val" -ge 128 ]]; then
        echo "Error: static value on line $((i+1)) ('$val') must be in range [0, 128)."
        exit 1
    fi

    dataArray+=("$val")
done

instructionBytes=()
instruction_count=0
found_quit=0

# Instructions start at index 3 (Line 4); indices 0-2 are n_values and the
# two static values, already consumed above.
for ((idx=3; idx<${#lines[@]}; idx++)); do
    ins_line="${lines[$idx]}"

    # 256 bytes of memory / 2 bytes per instruction caps a program at 100
    # instructions; reject before parsing rather than after.
    if [[ "$instruction_count" -ge 100 ]]; then
        echo "Error: program exceeds maximum capacity of 100 instructions."
        exit 1
    fi

    # 11 characters is the length of the longest valid instruction line
    # (e.g. "STORE,2,228"); anything longer cannot be valid, so it's
    # rejected before parsing.
    if [[ "${#ins_line}" -gt 11 ]]; then
        echo "Error: instruction line '$ins_line' exceeds maximum length of 11 characters."
        exit 1
    fi

    # Reading into 4 variables (not 3) catches both too few fields (reg or
    # mem ends up empty) and too many (the extra value lands in $extra).
    IFS=',' read -r ins reg mem extra <<< "$ins_line"

    if [[ -z "$ins" || -z "$reg" || -z "$mem" || -n "$extra" ]]; then
        echo "Error: instruction line '$ins_line' must have exactly 3 comma-separated fields."
        exit 1
    fi

    # Opcodes per the spec's instruction table; matching is case-sensitive.
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

    # Register field is 2 bits (4 registers: 0-3).
    if ! [[ "$reg" =~ ^[0-9]+$ ]] || [[ "$reg" -gt 3 ]]; then
        echo "Error: register field '$reg' in line '$ins_line' must be an integer 0-3."
        exit 1
    fi

    # Memory address field is 8 bits (256 bytes of memory: 0-255).
    if ! [[ "$mem" =~ ^[0-9]+$ ]] || [[ "$mem" -gt 255 ]]; then
        echo "Error: memory address '$mem' in line '$ins_line' must be an integer 0-255."
        exit 1
    fi

    # QUIT and PRINT have fixed operand constraints beyond the general
    # register/memory range checks above: QUIT must be exactly reg=0,
    # mem=0; PRINT's memory field must be 0 (its only real operand is
    # which register to print).
    if [[ "$ins" == "QUIT" ]] && { [[ "$reg" -ne 0 ]] || [[ "$mem" -ne 0 ]]; }; then
        echo "Error: QUIT instruction in line '$ins_line' must be exactly QUIT,0,0."
        exit 1
    fi

    if [[ "$ins" == "PRINT" ]] && [[ "$mem" -ne 0 ]]; then
        echo "Error: PRINT instruction in line '$ins_line' must have memory address 0."
        exit 1
    fi

    # Bit-pack per the spec's instruction format: byte 1 holds the 6-bit
    # opcode in its upper bits and the 2-bit register in its lower bits;
    # byte 2 is the memory address directly (already a full 8 bits).
    byte1=$(( (opcode << 2) | reg ))
    byte2=$mem

    instructionBytes+=("$byte1")
    instructionBytes+=("$byte2")

    instruction_count=$((instruction_count+1))

    # QUIT is the sentinel marking end-of-program; stop scanning as soon
    # as it's found, even if further lines exist in the file.
    if [[ "$ins" == "QUIT" ]]; then
        found_quit=1
        break
    fi
done

if [[ "$found_quit" -eq 0 ]]; then
    echo "Error: program does not contain a terminating QUIT instruction."
    exit 1
fi

# Static data bytes first, then instruction bytes - matches how the spec
# describes memory layout (data occupies the low addresses).
allBytes=("${dataArray[@]}" "${instructionBytes[@]}")

# Write every byte to the .bin file. printf '\\x%02x' converts a decimal
# value into the literal text "\xNN"; the outer printf then interprets
# that text as a format string, writing one raw byte per iteration.
> "$bin_filename"
for b in "${allBytes[@]}"; do
    printf "$(printf '\\x%02x' "$b")" >> "$bin_filename"
done

echo "It is an ADD/SUB program"
echo "The content of the .bin file is"
for b in "${allBytes[@]}"; do
    printf '%02x\n' "$b"
done
exit 0
