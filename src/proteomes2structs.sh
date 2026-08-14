#!/bin/bash

# proteomes2structs.sh

# Given some UniProt Proteome Accession IDs, download one .pdb
# and/or one .mmCIF (.cif) file from AlphaFold DB per protein per proteome.


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
  proteomes2structs.sh --mmcif "UP000000625 UP000007256" ../data


Required positional arguments:
  PROTEOME_LIST            Quoted space-separated UniProt proteome accessions
  OUTPUT_DIR               Directory where downloaded files will be stored

File format options:
  --cif                    Download .cif files
  --pdb                    Download .pdb files

Parallelism options:
  --parallel-proteomes N   Number of proteomes to process in parallel (default: 3)
  --threads-per-proteome N Number of download threads per proteome (default: 4)

Other options:
  --keep-fasta             Do not automatically delete downloaded FASTA files
  --sui                    Status update interval in minutes (default: 5)


Notes:
  - At least one file format flag must be enabled (--cif or --pdb).
  - Parallelism defaults result in 12 concurrent downloads (3 × 4), which is safe for AFDB/PDB.

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
PARALLEL_PROTEOMES=3
THREADS_PER_PROTEOME=4
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
        --parallel-proteomes)
            PARALLEL_PROTEOMES="$2"
            shift 2
            ;;
        --threads-per-proteome)
            THREADS_PER_PROTEOME="$2"
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
        DESC="Fetching .cif and .pdb files from AlphaFold DB"
    elif $CIF; then
        DESC="Fetching .cif files from AlphaFold DB"
    else
        DESC="Fetching .pdb files from AlphaFold DB"
    fi

    cat <<EOF

   proteomes2structs (${VERSION})

Run initiated at $(date)
$DESC
Processing ${PARALLEL_PROTEOMES} proteomes in parallel with ${THREADS_PER_PROTEOME} threads per proteome

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
    for fasta in "${FASTADIR}/"*.fasta.gz; do
        proteome=$(basename $fasta .fasta.gz)
        # Extract protein accessions from compressed fasta
        mapfile -t protein_accessions < <(gunzip -c "${fasta}" \
            | grep "^>" | cut -d "|" -f 2)
        # Write protein accessions to temp file
        printf "%s\n" "${protein_accessions[@]}" > "${TEMPDIR}/${proteome}.txt"
    done
}





# =======================================================================
#     Fetch AFDB Structure Data
# =======================================================================

# Fetch protein metadata and structure files for one protein from AFDB
fetch_protein_files () {
    local protein=$1
    local target_dir=$2
    local proteome=$3

    # Download JSON metadata
    json_endpoint="${AFDB_ENDPOINT}{protein}"
    json_path="${target_dir}/jsondumps/${protein}.json"
    curl -sSLf --retry 5 --retry-delay 2 --continue-at - "$json_endpoint" -o "$json_path"

    # Download structure files using JSON metadata
    if $CIF; then
        local cif_url=$(jq -r '.cifUrl // empty' "$json_path")
        if [[ -z $cif_url ]]; then
            echo "$(date +%H:%M:%S) [$proteome] ${protein}.cif endpoint not found"
        fi
        local target_path="${target_dir}${protein}.cif"
        curl -sSLf --retry 5 --retry-delay 2 --continue-at - "$cif_url" -o "$target_path"

        # Notify if first line of file contains <Error> (see issue #8)
        first_line=$(head -n 1 "$target_path")
        if [[ "$first_line" == "<Error>" ]]; then
            local error_code=$(grep -oP '(?<=<Code>).*?(?=</Code>)' "$target_path")
            local error_message=$(grep -oP '(?<=<Message>).*?(?=</Message>)' "$target_path")
            echo "$(date +%H:%M:%S) [${proteome}] WARNING: could not download ${protein}.cif (${error_code} - ${error_message})"
        fi

    if $PDB; then
        local pdb_url=$(jq -r '.pdbUrl // empty' "$json_path")


                  # TODO =========================================
}


# Download a batch of protein structure and metadata files
batch_download_protein_files () {
    local target_dir=$1
    local proteome=$2
    local protein
    while read -r protein; do
        fetch_protein_files $protein $target_dir $proteome
    done
    return 0
}


# Print status update based on number files currently downloaded and number expected
report_afdb_download_status () {
    local proteome=$1
    local target_dir=$2
    local num_total_files=$3
    local num_downloaded_files=$(find "$target_dir" -maxdepth 1 -type f | wc -l)

    printf "%s [%s] %d/%d files downloaded\n" \
        "$(date +%H:%M:%S)" "$proteome" "$num_downloaded_files" "$num_total_files"
    return 0
}


# Fetch proteome proteins one after the other from AFDB
fetch_afdb_protein_data () {
    local proteome=$1
    local target_dir="${AFDBDIR}${proteome}/"
    local json_dump_dir="${target_dir}/jsondumps/"
    mkdir -p "$target_dir" "$json_dump_dir"
    local -a proteins
    mapfile -t proteins < "${TEMPDIR}/${proteome}.txt"
    local num_proteins=${#proteins[@]}

    # Get number of expected files
    if [[ $CIF && $PDB ]]; then
        local num_files=$(( num_proteins * 2 ))
    else
        local num_files=num_proteins
    fi

    # Get chunk sizes
    local threads=$THREADS_PER_PROTEOME
    local base=$(( num_proteins / threads ))
    local rem=$(( num_proteins % threads ))
    local chunk_sizes=()
    for ((i=0; i<threads; i++)); do
        if (( i < rem )); then
            chunk_sizes+=( $(( base + 1 )) )
        else
            chunk_sizes+=( $base )
        fi
    done

    # Start background download threads
    local offset=0
    local pids=()
    local size
    for size in "${chunk_sizes[@]}"; do
        batch=( "${proteins[@]:offset:size}" )
        (
            printf "%s\n" "${batch[@]}" |
            batch_download_protein_files "$target_dir" "$proteome"
        ) &
        pids+=( "$!" )
        offset=$(( offset + size ))
    done

    # Wait until all batches are downloaded
    local keep_waiting=true
    while $keep_waiting; do
        keep_waiting=false
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                keep_waiting=true # At least one job is still alive
                report_afdb_download_status $proteome $target_dir $num_files
                sleep $(( $SUI * 60 ))
                break
            fi
        done
    done

    # Remove temp proteome text file
    rm "${TEMPDIR}/${proteome}.txt"

    echo
    echo "$(date +%H:%M:%S) [${proteome}] Download complete"
    echo
    return 0
}


# Main script for controlling AFDB proteome structure data retrieval
fetch_afdb () {

    local proteome_pids=()
    for proteome_path in "${TEMPDIR}/"*.txt; do

        # Wait for proteome job to become available
        while (( ${#proteome_pids[@]} >= PARALLEL_PROTEOMES )); do
            for i in "${!proteome_pids[@]}"; do
                if ! kill -0 "${proteome_pids[$i]}" 2>/dev/null; then
                    unset 'proteome_pids[i]' # Remove finished PID
                fi
            done
            proteome_pids=( "${proteome_pids[@]}" ) # Remove "holes" in array
            sleep 5
        done

        # Download structural data for each protein in proteome in bg
        proteome=$(basename "$proteome_path" .txt)
        fetch_afdb_protein_data "$proteome" &
        proteome_pids+=("$!")

    done
    wait
    return 0
}




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
