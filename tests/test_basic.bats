#!/usr/bin/env bats
# Run this from root dir

script="src/proteomes2structs.sh"

@test "proteomes2structs creates directory structure" {
    run "$script" --cif "UP000464024" testout
    [ "$status" -eq 0 ]
    [ -d "testout/UP000464024/json" ]
    [ -d "testout/UP000464024/structures" ]
    [ -d "testout/UP000464024/logs" ]
    [ -f "testout/UP000464024/metadata.json" ]
}
