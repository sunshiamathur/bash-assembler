#!/bin/bash
# Automated regression tests for assembler.sh
# Run from the project root: bash tests/test_assembler.sh
#
# Section A checks the 7 official rubric test cases EXACTLY (exit code +
# exact stdout, byte-for-byte where a .bin file is produced), using the
# real fixture files supplied by the unit (tests/fixtures/).
# Section B adds extra edge-case coverage beyond the official rubric.

ASSEMBLER="./assembler.sh"
FIXTURES="tests/fixtures"
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# assert_exact <name> <expected_exit> <expected_stdout_exact> <command...>
assert_exact() {
    local name="$1" expected_exit="$2" expected_stdout="$3"
    shift 3
    local actual_stdout actual_exit
    actual_stdout=$("$@" 2>&1)
    actual_exit=$?
    if [[ "$actual_exit" -eq "$expected_exit" && "$actual_stdout" == "$expected_stdout" ]]; then
        echo "PASS [$name]"
        PASS=$((PASS+1))
    else
        echo "FAIL [$name]"
        echo "  expected exit $expected_exit, got $actual_exit"
        echo "  expected stdout: $(printf '%q' "$expected_stdout")"
        echo "  actual stdout:   $(printf '%q' "$actual_stdout")"
        FAIL=$((FAIL+1))
    fi
}

# run_test <name> <vsc_content> <expected_exit_code> <expected_stdout_substring> [expected_hex_bytes]
run_test() {
    local name="$1" content="$2" expected_exit="$3" expected_stdout="$4" expected_hex="$5"
    local vsc_file="$TMP_DIR/$name.vsc"
    local bin_file="$TMP_DIR/$name.bin"
    rm -f "$bin_file"
    printf '%s' "$content" > "$vsc_file"

    local actual_stdout actual_exit
    actual_stdout=$("$ASSEMBLER" "$vsc_file" 2>&1)
    actual_exit=$?
    local ok=1

    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        echo "FAIL [$name]: expected exit $expected_exit, got $actual_exit"
        ok=0
    fi
    if [[ "$actual_stdout" != *"$expected_stdout"* ]]; then
        echo "FAIL [$name]: expected stdout to contain '$expected_stdout', got '$actual_stdout'"
        ok=0
    fi
    if [[ -n "$expected_hex" ]]; then
        if [[ ! -f "$bin_file" ]]; then
            echo "FAIL [$name]: expected .bin file was not produced"
            ok=0
        else
            local actual_hex
            actual_hex=$(od -An -tx1 "$bin_file" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
            if [[ "$actual_hex" != "$expected_hex" ]]; then
                echo "FAIL [$name]: expected bytes '$expected_hex', got '$actual_hex'"
                ok=0
            fi
        fi
    elif [[ -f "$bin_file" ]]; then
        echo "FAIL [$name]: .bin file should NOT have been produced, but it was"
        ok=0
    fi

    if [[ "$ok" -eq 1 ]]; then
        echo "PASS [$name]"
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
}

echo "== Section A: official rubric tests (exact match, real fixtures) =="

assert_exact "rubric_1_no_args" 1 \
    "usage: no argument is provided" \
    "$ASSEMBLER"

assert_exact "rubric_2_too_many_args" 1 \
    "usage: more than one arguments are provided" \
    "$ASSEMBLER" a.vsc b.vsc

assert_exact "rubric_3_not_a_file" 1 \
    "usage: input is not a file or it does not exist" \
    "$ASSEMBLER" ~

touch "$TMP_DIR/a.vs"
assert_exact "rubric_4_wrong_extension" 1 \
    "usage: input does not have the extension .vsc" \
    "$ASSEMBLER" "$TMP_DIR/a.vs"

assert_exact "rubric_5_empty_file" 1 \
    "usage: the file is empty - no .bin file is produced" \
    "$ASSEMBLER" "$FIXTURES/empty.vsc"

cp "$FIXTURES/quit.vsc" "$TMP_DIR/quit.vsc"
assert_exact "rubric_6_quit_program" 0 \
    $'It is a QUIT program\nThe content of the .bin file is\n20\n00' \
    "$ASSEMBLER" "$TMP_DIR/quit.vsc"

quit_hex=$(od -An -tx1 "$TMP_DIR/quit.bin" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
if [[ "$quit_hex" == "20 00" ]]; then
    echo "PASS [rubric_6_quit_bin_bytes]"
    PASS=$((PASS+1))
else
    echo "FAIL [rubric_6_quit_bin_bytes]: expected '20 00', got '$quit_hex'"
    FAIL=$((FAIL+1))
fi

cp "$FIXTURES/add.vsc" "$TMP_DIR/add.vsc"
assert_exact "rubric_7_addsub_program" 0 \
    $'It is an ADD/SUB program\nThe content of the .bin file is\n7f\n0c\n04\n00\n0c\n01\n08\n0e\n24\n00\n20\n00' \
    "$ASSEMBLER" "$TMP_DIR/add.vsc"

add_hex=$(od -An -tx1 "$TMP_DIR/add.bin" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
if [[ "$add_hex" == "7f 0c 04 00 0c 01 08 0e 24 00 20 00" ]]; then
    echo "PASS [rubric_7_addsub_bin_bytes]"
    PASS=$((PASS+1))
else
    echo "FAIL [rubric_7_addsub_bin_bytes]: expected '7f 0c 04 00 0c 01 08 0e 24 00 20 00', got '$add_hex'"
    FAIL=$((FAIL+1))
fi

echo ""
echo "== Section B: extra edge-case coverage (beyond official rubric) =="

run_test "line1_invalid" $'1\nQUIT,0,0\n' 1 "Line 1 must be exactly 0 or 2"
run_test "quit_only_bad_args" $'0\nQUIT,0,1\n' 1 "must be exactly 'QUIT,0,0'"
run_test "quit_only_extra_line" $'0\nQUIT,0,0\nextra\n' 1 "exactly 2 lines"
run_test "static_values_negative" $'2\n-5\n40\nQUIT,0,0\n' 1 "not a valid non-negative integer"
run_test "static_values_too_big" $'2\n200\n40\nQUIT,0,0\n' 1 "range [0, 128)"
run_test "static_values_boundary_127" $'2\n127\n0\nQUIT,0,0\n' 0 "It is an ADD/SUB program" "7f 00 20 00"
run_test "bad_instruction_name" $'2\n20\n40\nLOADX,0,0\nQUIT,0,0\n' 1 "unrecognised instruction"
run_test "reg_out_of_range" $'2\n20\n40\nLOAD,5,0\nQUIT,0,0\n' 1 "must be an integer 0-3"
run_test "mem_out_of_range" $'2\n20\n40\nLOAD,0,300\nQUIT,0,0\n' 1 "must be an integer 0-255"
run_test "line_too_long" $'2\n20\n40\nLOAD,0,00000000000\nQUIT,0,0\n' 1 "exceeds maximum length"
run_test "missing_quit" $'2\n20\n40\nLOAD,0,0\n' 1 "terminating QUIT"
run_test "print_bad_mem" $'2\n20\n40\nPRINT,0,5\nQUIT,0,0\n' 1 "must have memory address 0"
run_test "quit_bad_reg" $'2\n20\n40\nQUIT,1,0\n' 1 "must be exactly QUIT,0,0"
run_test "too_few_fields" $'2\n20\n40\nLOAD,0\nQUIT,0,0\n' 1 "exactly 3 comma-separated fields"
run_test "too_many_fields" $'2\n20\n40\nLOAD,0,0,5\nQUIT,0,0\n' 1 "exactly 3 comma-separated fields"
run_test "blank_line_before_quit" $'2\n20\n40\nLOAD,0,0\n\nQUIT,0,0\n' 1 "exactly 3 comma-separated fields"
echo ""
echo "===================="
echo "Passed: $PASS   Failed: $FAIL"
echo "===================="

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
