#!/usr/bin/env bats

src="../src/proteomes2structs.sh"

@test "proteomes2structs creates directory structure" {
    run "$src" --cif "UP000464024" testout
    [ "$status" -eq 0 ]
    [ -d "testout/UP000464024/json" ]
    [ -d "testout/UP000464024/structures" ]
}
