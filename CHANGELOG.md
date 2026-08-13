# Changelog

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
