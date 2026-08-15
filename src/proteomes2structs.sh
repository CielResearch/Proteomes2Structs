#!/bin/bash


# ==================================================================================

# proteomes2structs.sh

# Given some UniProt Proteome Accession IDs, download one .pdb
# and/or one .cif file from AlphaFold DB per protein per proteome.



# ==================================================================================

trap 'kill $(jobs -p) 2>/dev/null' EXIT # Kill background jobs on termination

VERSION="0.2.2a1"
SECONDS=0







# =================================================================================
#     HELP TEXT
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


Pipeline mode selection:
  --mode=download  (default)
      Run the main pipeline. Downloads all files for the selected proteomes
      and writes metadata and failure logs. Use this for the initial run.
  --mode=retry  (future mode)
      Run the retry pipeline. Only retries downloads that failed previously.
      Requires an output directory created by an earlier --mode=download run.
      Does not repeat successful downloads.


File format options:
  --cif                    Download .cif files
  --pdb                    Download .pdb files

Other options:
  --threads N              Number of download threads (default: 12)
  --keep-fasta             Do not automatically delete downloaded FASTA files
  --sui                    Status update interval in minutes (default: 5)


Notes:
  - At least one file format flag must be enabled (--cif or --pdb).
  - Only one mode flag may be enabled. If no mode flags are provided,
      defaults to --mode=download.

===========================================================================

Citation (APA 7):
Baumann, C. I.-L. (2026). Proteomes2Structs [Shell]. Zenodo. https://doi.org/10.5281/zenodo.21850698


EOF
    exit 0
fi





# =========================================================================
#     VERSION
# =========================================================================

if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo "proteomes2structs $VERSION"
    echo "Author: Ciel Ivy-Lee Baumann"
    echo "DOI: 10.5281/zenodo.21850698"
    echo "License: CC-BY-NC-4.0"
    exit 0
fi






# ==========================================================================
#     PARSE USER INPUT
# ==========================================================================

# Set defaults
CIF=false
PDB=false
THREADS=12
KEEP_FASTA=false
SUI=5
DOWNLOAD_MODE=false
RETRY_MODE=false

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
        --mode=download)
            DOWNLOAD_MODE=true
            shift
            ;;
        --mode=retry)
            RETRY_MODE=true
            shift
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


# Store remaining positional arguments
PROTEOMES_STR="$1"
OUTDIR="$2"





# =========================================================================
#      VALIDATE USER INPUT
# =========================================================================

# Check that positional arguments exist
if [[ -z "$PROTEOMES_STR" || -z "$OUTDIR" ]]; then
    echo "ERROR: missing required positional arguments: PROTEOME_LIST and OUTPUT_DIR" >&2
    exit 1
fi

# At least one of --cif and --pdb must be specified
if ! $CIF && ! $PDB; then
    echo "ERROR: must specify at least one of --cif or --pdb" >&2
    exit 1
fi

# Allow only one mode at a time
if $DOWNLOAD_MODE && $RETRY_MODE; then
    echo "ERROR: only one mode may be enabled at a time" >&2
    exit 1
fi

# Ensure threads is a positive integer
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS <= 0 )); then
    echo "ERROR: --threads must be a positive integer" >&2
    exit 1
fi






# ======================================================================
#    ASSIGN INITIAL GLOBALS
# ======================================================================


# Default to download mode if mode unspecified
if ! $DOWNLOAD_MODE && ! $RETRY_MODE; then
    DOWNLOAD_MODE=true
fi

# Assign and set up argument-dependent and other globals
FASTA_ENDPOINT_BASE="https://rest.uniprot.org/uniprotkb/stream?compressed=true&format=fasta&query=proteome:"
AFDB_ENDPOINT="https://alphafold.ebi.ac.uk/api/prediction/"
mkdir -p "${OUTDIR}"







# =======================================================================
#     PROTEOME INPUT PARSING
# =======================================================================

parse_proteomes() {
    # Simple for now but may extend to file input in future so
    # keeping this as a function
    read -a PROTEOMES <<< "$PROTEOMES_STR"
    # Should also add a deduplication step in future
}


# Create a directory for each proteome with defined structure
create_proteome_directories() {
    local proteome base
    for proteome in "${PROTEOMES[@]}"; do
        base="${OUTDIR}/${proteome}"
        mkdir -p "${base}/json" "${base}/structures" "${base}/logs"
    done
}







# =======================================================================
#     PROTEIN ACCESSION RETRIEVAL FUNCTIONS
# =======================================================================


# Download compressed fasta files into proteome directories
fetch_fastas() {
    local thread_id=$1
    shift 2
    local proteome
    for proteome in "$@"; do
        local fasta_gz_path="${OUTDIR}/${proteome}/${proteome}.fasta.gz"
        local endpoint="${FASTA_ENDPOINT_BASE}${proteome}"
        local err=$(curl -sSLf --retry 5 --retry-delay 2 -o "${fasta_gz_path}" "${endpoint}" 2>&1) || {
            local failfile="${OUTDIR}/${proteome}/logs/failures_thread_${thread_id}.txt"
            echo "$(date +%H:%M:%S)|${proteome}|NULL|${endpoint}|${err}" >> "$failfile"
        }
    done
    return 0
}


# Write UniProt protein accessions to text files in proteome directories
extract_protein_uniprot_accessions() {
    local thread=$1
    shift 2
    local proteome
    for proteome in "$@"; do
        local fasta_gz_path="${OUTDIR}/${proteome}/${proteome}.fasta.gz"
        [[ -f "$fasta_gz_path" ]] || continue
        local target_path="${OUTDIR}/${proteome}/proteins.txt"
        local -a protein_accessions
        mapfile -t protein_accessions < <(gunzip -c "${fasta_gz_path}" | grep "^>" | cut -d "|" -f 2)
        printf "%s\n" "${protein_accessions[@]}" > "$target_path"
    done
    return 0
}


# Echo array of protein accessions for given proteome
read_protein_accessions() {
    local proteome=$1
    local -a proteins
    local protein_file="${OUTDIR}/${proteome}/proteins.txt"
    [[ -f "$protein_file" ]] && mapfile -t proteins < "$protein_file"
    printf "%s\n" "${proteins[@]}"
    return 0
}


# Remove FASTA files and proteins.txt from proteome directories
delete_fasta_files() {
    local thread_id=$1 # unused
    shift 2
    local proteome
    for proteome in "$@"; do
        local fasta_path="${OUTDIR}/${proteome}/${proteome}.fasta.gz"
        local protein_path="${OUTDIR}/${proteome}/proteins.txt"
        [[ -f "$fasta_path" ]] && rm "$fasta_path"
        [[ -f "$protein_path" ]] && rm "$protein_path"
    done
    return 0
}






# =======================================================================
#     FETCH AFDB FILES (.json, .cif, .pdb)
# =======================================================================


# Download protein metadata .json files
fetch_afdb_metadata() {
    local thread_id=$1
    local proteome=$2
    shift 2
    local protein
    for protein in "$@"; do
        json_endpoint="${AFDB_ENDPOINT}${protein}"
        json_path="${OUTDIR}/${proteome}/json/${protein}.json"
        local err=$(curl -sSLf --retry 5 --retry-delay 2 --continue-at - "$json_endpoint" -o "$json_path" 2>&1 ) || {
            local failfile="${OUTDIR}/${proteome}/logs/failures_thread_${thread_id}.txt"
            echo "$(date +%H:%M:%S)|${proteome}|${protein}|${json_endpoint}|${err}" >> "$failfile"
        }
    done
    return 0
}


# Download a structure (.cif / .pdb) file
download_structure_file() {
    local protein=$1
    local ext=$2
    local target_dir=$3
    local json_path=$4
    local proteome=$5

    # Get structure file endpoint
    local ext_no_dot="${ext#.}"
    local endpoint=$(jq -r ".${ext_no_dot}Url // empty" "$json_path")
    if [[ -z $endpoint ]]; then
        local err="${protein}${ext} endpoint not found"
        echo "$(date +%H:%M:%S)|${proteome}|${protein}|${endpoint}|${err}" >&2
        return 1
    fi
    local target_path="${target_dir}${protein}${ext}"

    # Download structure file
    local err=$(curl -sSLf --retry 5 --retry-delay 2 --continue-at - "$endpoint" -o "$target_path" 2>&1 >/dev/null) || {
        echo "$(date +%H:%M:%S)|${proteome}|${protein}|${endpoint}|${err}" >&2
        return 1
    }

    # Log failure and delete file if it contains <Error> on line 1 (see issue #8)
    local first_line=$(head -n 1 "$target_path")
    if [[ "$first_line" == "<Error>" ]]; then
        local error_code=$(grep -oP '(?<=<Code>).*?(?=</Code>)' "$target_path")
        local error_message=$(grep -oP '(?<=<Message>).*?(?=</Message>)' "$target_path")
        rm "$target_path"
        echo "$(date +%H:%M:%S)|${proteome}|${protein}|${endpoint}|${error_code}: ${error_message}" >&2
        return 1
    fi

    return 0
}


# Download protein structure file/s
fetch_afdb_structure_files() {
    local thread_id=$1
    local proteome=$2
    shift 2
    local failfile="${OUTDIR}/${proteome}/logs/failures_thread_${thread_id}.txt"
    local protein
    for protein in "$@"; do
        local json_path="${OUTDIR}/${proteome}/json/${protein}.json"
        [[ -f json_path ]] || continue
        local target_dir="${OUTDIR}/${proteome}/structures"
        if $CIF; then
            download_structure_file $protein .cif "$target_dir" "$json_path" $proteome 2>> "$failfile"
        fi
        if $PDB; then
            download_structure_file $protein .pdb "$target_dir" "$json_path" $proteome 2>> "$failfile"
        fi
    done
    return 0
}







# =======================================================================
#     DOWNLOAD METADATA FUNCTIONS
# =======================================================================


# For each proteome, condense thread-based failure logs into single log files
condense_failure_logs() {
    shift 2
    shopt -s nullglob
    local proteome
    for proteome in "$@"; do
        local log_path="${OUTDIR}/${proteome}/logs"
        log_files=("$log_path"/failures_thread_*.txt)
        if (( ${#log_files[@]} > 0 )); then
            cat "${log_files[@]}" > failures_all.txt
            rm "${log_files[@]}"
        fi
    done
    shopt -u nullglob
    return 0
}


# Create proteome-level metadata file containing species, number of protein
# files downloaded, number of proteins represented in downloads, number of
# proteins that could not be represented in any download, and datetime of
# download start and end.
write_proteome_metadata() {
    local thread_id=$1
    local proteome
    shift 2
    for proteome in "$@"; do
        ...
    done
    return 0
}


# Report metadata summaries
end_of_download() {
    ...
}








# =======================================================================
#     JOB DISPATCH FUNCTIONS
# =======================================================================


get_chunk_size() {
    local num_jobs=$1
    local threads=$THREADS
    # ceil(num_jobs / threads)
    echo $(( (num_jobs + threads - 1) / threads ))
}


job_dispatch() {
    local func=$1
    local proteome=$2 # or ""
    shift 2
    local -a items=("$@")
    local num_items=${#items[@]}

    local chunk_size
    chunk_size=$(get_chunk_size "$num_items")

    local -a chunk
    local i=0 thread_id
    while (( i < num_items )); do
        thread_id=$((i / chunk_size))
        chunk=( "${items[@]:i:chunk_size}" )
        "$func" "$thread_id" "$proteome" "${chunk[@]}" &
        i=$(( i + chunk_size ))
    done

    wait
}










# =======================================================================
#     INFO / SETUP
# =======================================================================


welcome() {
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='

    # Build description string
    if $CIF && $PDB; then
        DESC="Fetching .cif and .pdb files from AlphaFold DB using ${THREADS} threads"
    elif $CIF; then
        DESC="Fetching .cif files from AlphaFold DB using ${THREADS} threads"
    else
        DESC="Fetching .pdb files from AlphaFold DB using ${THREADS} threads"
    fi

    # Build mode string
    if $RETRY_MODE; then
        MODE="Mode: retry failed downloads"
    else
        MODE="Mode: download (default)"
    fi

    cat <<EOF

   proteomes2structs (${VERSION})

Run initiated at $(date)
$DESC
$MODE

UniProt endpoint: $FASTA_ENDPOINT_BASE
AlphaFold DB endpoint: $AFDB_ENDPOINT

Status updates every $SUI minutes

EOF
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    echo
}



end_of_script() {

    runtime=$SECONDS
    hours=$(( runtime / 3600 ))
    minutes=$(( (runtime % 3600) / 60 ))

    echo
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    cat <<EOF

$(date)
Script completed in $hours hours $minutes minutes
Data files available in ${OUTDIR}

EOF
    echo
}








# =======================================================================
#     MAIN
# =======================================================================


download_pipeline() {
    local proteome
    local -a proteins
    parse_proteomes
    create_proteome_directories
    job_dispatch fetch_fastas "" "${PROTEOMES[@]}"
    job_dispatch extract_protein_accessions "" "${PROTEOMES[@]}"
    for proteome in "${PROTEOMES[@]}"; do
        mapfile -t proteins < <(read_protein_accessions "$proteome")
        job_dispatch fetch_afdb_metadata "$proteome" "${proteins[@]}"
        job_dispatch fetch_afdb_structure_files "$proteome" "${proteins[@]}"
    done
    job_dispatch condense_failure_logs "" "${PROTEOMES[@]}"
    write_proteome_metadata "" "${PROTEOMES[@]}"
    if ! $KEEP_FASTA; then
        job_dispatch delete_fasta_files "" "${PROTEOMES[@]}"
    fi
    end_of_download
    return 0
}


retry_pipeline() {
    echo ""
    echo "Retry mode not yet implemented"
    echo
    exit 1
}


welcome
if $RETRY_MODE; then
    retry_pipeline
else
    download_pipeline
fi
end_of_script
