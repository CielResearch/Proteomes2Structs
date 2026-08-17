#!/usr/bin/env bats
# Run this from root dir

script="src/proteomes2structs.sh"

@test "proteomes2structs creates directory structure" {
    run "$script" --cif "UP000464024" tests/testout1
    [ "$status" -eq 0 ]
    [ -d "tests/testout1/UP000464024/json" ]
    [ -d "tests/testout1/UP000464024/structures" ]
    [ -d "tests/testout1/UP000464024/logs" ]
    [ -f "tests/testout1/UP000464024/metadata.json" ]
}
