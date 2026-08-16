# Changelog

## v0.3.0a1 - 2026-08-17
A major architectural upgrade introducing a fully rewritten AFDB download pipeline, structured metadata logging, environment validation, simplified parallelism, and significant improvements to reliability, testability, and error handling.

### New Features
- Automatic download of AFDB protein JSON metadata snapshots for transparency and reproducibility
- Creation of proteome‑level metadata JSON files summarising timestamps, organism info, taxa ID, success/failure counts by category, and mode
- Structured per-proteome failure logs for fasta, metadata, and structure file download failures with timestamps, endpoints, and error messages
- Input validation: warns about duplicate proteome accessions and terminates if proteome accessions or output directory arguments are missing
- Environment validation: check for curl, jq, internet connection, and write permissions to output directory
- Automatically disable status thread when ran in non-interactive mode

### Pipeline & Architectural Improvements
- Replaced old multi-layer parallelism with a clean job dispatcher
- Rewrote AFDB download mechanism to use the /api/prediction/<accession> endpoint for metadata and consequent structure file retrieval instead of the old S3 bucket
- Added retry pipeline scaffolding (not yet enabled)
- Status thread now subshell-safe: no more zombie threads and job-control noise

### Metadata & Directory Structure
Now uses a consistent directory layout:
```
proteome/
    json/
    structures/
    logs/
        failures_fasta.txt
        failures_metadata.txt
        failures_structures.txt
    metadata.json
```

### Bug Fixes
- Fixed “NoSuchKey” XML error by switching to the new AFDB endpoint, and setting up explicit catch for this error

### Removed
- Removed obsolete --afdb-version flag
- Removed --parallel-proteomes and --threads-per-proteome, and replaced with --threads (default 12)
- Removed --mmcif flag and all references to .mmcif and replacecd with --cif flag and references to .cif to maintain consistency with AFDB conventions
- Removed legacy parallelism code and replaced with a simpler model.

### Testing & Reliability
- Added a basic end-to-end Bats test using UP000464024 (SARS-CoV-2) which runs cleanly
- More descriptive and actionable error messages in logs
- Tested with proteomes2structs.sh --cif --sui 5 --threads 16 "UP000000625 UP000002670 UP000008816 UP000001974 UP000002311 UP000001711" data
    - Completed in 17 minutes on home laptop in WSL terminal.
    - Viral (bacteriophage lambda) proteome download failed - AFDB does not appear to host viral proteins except for SARS-CoV-2 proteins.
    - Only errors were "Absent JSON file" errors as expected.
    - Excluding bacteriophage lambda downloads, the average metadata download failure rate was around 0.4%, and no structure files failed to download, except those that were not downloaded due to missing metadata files.


## v0.2.2a1 - 2026-08-14
- Update wrapper script for bioconda compatibility

## v0.2.1a1 - 2026-08-13
- Added citation to -h and DOI to -h and -v

## v0.2.0a1 - 2026-08-13

Removed
- Removed bulk archive (.tar.gz) download mechanism for AlphaFold DB proteomes.

Added
- Support for downloading .mmCIF/.cif files from AlphaFold DB
- Optional retention of fasta files (`--keep-fasta`)
- User-customisable parallelisation
    - `--threads-per-proteome`
    - `--parallel-proteomes`
- Status update interval flag (`--sui <minutes>`)
- AlphaFold model version customisation (`--afdb-version`)
- Welcome banner including:
    - Selected file formats (.mmcif, .pdb)
    - AlphaFold DB model version
    - Status update interval
    - Number of proteomes and threads per proteome
- Runtime report in end-of-run summary (hours + minutes)

Improved
- General UX polish across progress reporting, timestamps, and completion messages.
- Internal simplifications and readability improvements after removing bulk archive logic.

## v0.1.2 - 2026-08-08 - Initial Release
- Support for downloading .pdb files from AlphaFold DB
