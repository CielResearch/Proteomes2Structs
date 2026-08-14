#!/bin/bash

# proteomes2structs.sh

# Given some UniProt Proteome Accession IDs, download one .pdb
# and/or one .cif file from AlphaFold DB per protein per proteome.


trap 'kill $(jobs -p) 2>/dev/null' EXIT # Kill background jobs on termination

VERSION="0.2.2a1"
SECONDS=0


# =================================================================================
#     HELP TEXT + VERSION
# =================================================================================

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF


proteomes2structs $VERSION
Download structural files for UniProt proteomes

Author: Ciel Ivy-Lee Baumann
DOI: 10.5281/zenodo.21850698
License: CC-BY-NC-4.0
Last updated: 13 Aug 2026

=========================================================================

Given some UniProt Proteome Accession IDs, this script downloads
one .pdb and/or one .cif file from AlphaFold DB per protein per proteome.
To do so, this script interacts with the following services:

- AlphaFold DB
Bertoni, D., Tsenkov, M., Magana, P., Nair, S., Pidruchna, I.,
Querino Lima Afonso, M., Midlik, A., Paramval, U., Lawal, D., Tanweer, A.,
Last, M., Patel, R., Laydon, A., Lasecki, D., Dietrich, N., Tomlinson, H.,
Žídek, A., Green, T., Kovalevskiy, O., … Velankar, S. (2026). AlphaFold
Protein Structure Database 2025: A redesigned interface and updated
structural coverage. Nucleic Acids Research, 54(D1), D358–D362.
https://doi.org/10.1093/nar/gkaf1226"

- UniProt
The UniProt Consortium. (2025). UniProt: The Universal Protein
Knowledgebase in 2025. Nucleic Acids Research, 53(D1), D609–D617.
https://doi.org/10.1093/nar/gkae1010

==========================================================================

Usage:
  proteomes2structs.sh [options] "PROTEOME_LIST" OUTPUT_DIR

Example:
  proteomes2structs.sh --cif "UP000000625 UP000007256" ../data


Required positional arguments:
  PROTEOME_LIST            Quoted space-separated UniProt proteome accessions
  OUTPUT_DIR               Directory where downloaded files will be stored

File format options:
  --cif                    Download .cif files
  --pdb                    Download .pdb files

Other options:
  --threads N              Number of download threads (default: 12)
  --keep-fasta             Do not automatically delete downloaded FASTA files
  --sui                    Status update interval in minutes (default: 5)


Notes:
  - At least one file format flag must be enabled (--cif or --pdb).

===========================================================================

Citation (APA 7):
Baumann, C. I.-L. (2026). Proteomes2Structs [Shell]. Zenodo. https://doi.org/10.5281/zenodo.21850698


EOF
    exit 0
fi


if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo "proteomes2structs $VERSION"
    echo "Author: Ciel Ivy-Lee Baumann"
    echo "DOI: 10.5281/zenodo.21850698"
    echo "License: CC-BY-NC-4.0"
    exit 0
fi




# ==========================================================================
#     PARSE ARGS
# ==========================================================================

# Set defaults
CIF=false
PDB=false
THREADS=12
KEEP_FASTA=false
SUI=5

# Process flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cif)
            CIF=true
            shift
            ;;
        --pdb)
            PDB=true
            shift
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --keep-fasta)
            KEEP_FASTA=true
            shift
            ;;
        --sui)
            SUI="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option: $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Evaluate flag combinations:
# At least one of --cif and --pdb must be specified
if ! $CIF && ! $PDB; then
    echo "Error: must specify at least one of --cif or --pdb"
    exit 1
fi

# Store remaining positional arguments
PROTEOMES_STR="$1"
OUTDIR="$2"

# Assign and set up argument-dependent and other globals
UNIPROT_FASTA_URL_BASE="https://rest.uniprot.org/uniprotkb/stream?compressed=true&format=fasta&query="
AFDB_ENDPOINT="https://alphafold.ebi.ac.uk/api/prediction/"
TEMPDIR="${OUTDIR}/temp/"
FASTADIR="${OUTDIR}/fasta/"
AFDBDIR="${OUTDIR}/afdb/"
mkdir -p "$TEMPDIR" "$FASTADIR" "$AFDBDIR"




# =======================================================================
#     INFO / SETUP
# =======================================================================

welcome () {
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='

    # Build description string
    if $CIF && $PDB; then
        DESC="Fetching .cif and .pdb files from AlphaFold DB using ${THREADS} threads"
    elif $CIF; then
        DESC="Fetching .cif files from AlphaFold DB using ${THREADS} threads"
    else
        DESC="Fetching .pdb files from AlphaFold DB using ${THREADS} threads"
    fi

    cat <<EOF

   proteomes2structs (${VERSION})

Run initiated at $(date)
$DESC

UniProt endpoint: https://rest.uniprot.org/uniprotkb/
AlphaFold DB endpoint: $AFDB_ENDPOINT

Status updates every $SUI minutes

EOF
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    echo
}



end_of_script () {

    runtime=$SECONDS
    hours=$(( runtime / 3600 ))
    minutes=$(( (runtime % 3600) / 60 ))

    echo
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    cat <<EOF

$(date)
Script completed in $hours hours $minutes minutes
Data files available in ${AFDBDIR}

EOF
    echo
}




# =======================================================================
#     PROTEOME INPUT PARSING
# =======================================================================

parse_proteomes () {
    # Simple for now but may extend to file input in future so
    # keeping this as a function
    read -a PROTEOMES <<< "$PROTEOMES_STR"
}




# =======================================================================
#     GET FASTA FILES FROM UNIPROT
# =======================================================================

# Store all compressed fasta files for input protomes in fasta directory
fetch_fastas () {
    for proteome_accession in "${PROTEOMES[@]}"; do
        local fasta_gz_path="${FASTADIR}${proteome_accession}.fasta.gz"

        # Download FASTA file
        curl -sSL --retry 5 --retry-delay 2 -o "${fasta_gz_path}" \
        "${UNIPROT_FASTA_URL_BASE}(proteome:${proteome_accession})" || { \
            echo "$(date +%H:%M:%S) WARNING: Could not retrieve ${proteome_accession} FASTA"
            return 1
        }
    done
}

# Write UniProt protein accessions to temporary text file with same
# basename as proteome uniprot accession
extract_protein_uniprot_accessions () {
    local -a protein_accessions
    for fasta in "${FASTADIR}/"*.fasta.gz; do
        local proteome=$(basename "$fasta" .fasta.gz)
        # Extract protein accessions from compressed fasta
        mapfile -t protein_accessions < <(gunzip -c "${fasta}" \
            | grep "^>" | cut -d "|" -f 2)
        # Write protein accessions to temp file
        printf "%s\n" "${protein_accessions[@]}" > "${TEMPDIR}/${proteome}/proteins.txt"
    done
}





# =======================================================================
#     Fetch AFDB Structure Data
# =======================================================================













# =======================================================================
#     MAIN
# =======================================================================

welcome
parse_proteomes
fetch_fastas
extract_protein_uniprot_accessions
fetch_afdb
[[ -d "$TEMPDIR" ]] && rm -r "$TEMPDIR"
if ! $KEEP_FASTA; then
    [[ -d "$FASTADIR" ]] && rm -r "$FASTADIR"
fi
end_of_script
