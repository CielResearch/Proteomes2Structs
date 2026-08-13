#!/bin/bash

# proteomes2structs.sh

# Given some UniProt Proteome Accession IDs, download one .pdb
# and/or one .mmCIF (.cif) file from AlphaFold DB per protein per proteome.


trap 'kill $(jobs -p) 2>/dev/null' EXIT # Kill background jobs on termination

VERSION="0.2.0a1"



# =================================================================================
#     HELP TEXT + VERSION
# =================================================================================

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF

proteomes2structs $VERSION
Download structural files for UniProt proteomes

Author: Ciel Ivy-Lee Baumann
Last updated: Aug 2026
License: CC-BY-NC-4.0

=========================================================================

Given some UniProt Proteome Accession IDs, this script downloads
one .pdb and/or one .mmCIF file from AlphaFold DB per protein per proteome.
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
  --mmcif                  Download mmCIF files
  --pdb                    Download PDB files

Source options:
  --from-afdb              Download structures from AlphaFold DB (set by default)
  --from-pdb               Download structures from PDB archive (future feature)
  --afdb-version VERSION   AlphaFold DB version to use (default: 4)

Parallelism options:
  --parallel-proteomes N   Number of proteomes to process in parallel (default: 3)
  --threads-per-proteome N Number of download threads per proteome (default: 4)

Other options:
  --keep-fasta             Do not automatically delete downloaded FASTA files

Notes:
  - At least one file format flag must be enabled (--mmcif or --pdb).
  - Parallelism defaults result in 12 concurrent downloads (3 × 4), which is safe for AFDB/PDB.
  - The program has only been tested on AlphaFold DB version 4.
  - Future versions may support --from-pdb for PDB archive downloads.

EOF
    exit 0
fi

if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo "proteomes2structs version $VERSION"
    exit 0
fi




# ==========================================================================
#     PARSE ARGS
# ==========================================================================

# Set defaults
MMCIF=false
PDB=false
FROM_AFDB=true
FROM_PDB=false
AFDB_VERSION=4
PARALLEL_PROTEOMES=3
THREADS_PER_PROTEOME=4
KEEP_FASTA=false

# Process flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mmcif)
            MMCIF=true
            shift
            ;;
        --pdb)
            PDB=true
            shift
            ;;
        --from-afdb)
            FROM_AFDB=true
            shift
            ;;
        --afdb-version)
            AFDB_VERSION="$2"
            shift 2
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
# At least one of --mmcif and --pdb must be specified
if ! $MMCIF && ! $PDB; then
    echo "Error: must specify at least one of --mmcif or --pdb"
    exit 1
fi
# Raise an error if --from-pdb is True because this is not implemented
if $FROM_PDB; then
    echo "Error: --from-pdb is not implemented"
    exit 1
fi

# Store remaining positional arguments
PROTEOMES_STR="$1"
OUTDIR="$2"

# Assign and set up argument-dependent and other globals
BULK_AFDB_ARCHIVE_URL="https://ftp.ebi.ac.uk/pub/databases/alphafold/${AFDB_VERSION}/"
UNIPROT_FASTA_URL_BASE="https://rest.uniprot.org/uniprotkb/stream?compressed=true&format=fasta&query="
TEMPDIR="${OUTDIR}/temp/"
FASTADIR="${OUTDIR}/fasta/"
AFDBDIR="${OUTDIR}/afdb_v${AFDB_VERSION}/"
mkdir -p "$TEMPDIR" "$FASTADIR" "$AFDBDIR"




# =======================================================================
#     INFO / SETUP
# =======================================================================

welcome () {
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    cat <<EOF

   proteomes2structs ("$VERSION")

Run initiated at $(date)
Processing "$PARALLEL_PROTEOMES" proteomes in parallel with "$THREADS_PER_PROTEOME" threads per proteome

EOF
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    echo
}

end_of_script () {
    echo
    printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
    cat <<EOF

$(date)
Script complete. Data files available in "$OUTDIR"

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
        curl -sSL --retry 5 --retry-delay 2 --continue-at - -o "${fasta_gz_path}" \
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

# Get filenames of all UniProt Proteome accessions for which there exists
# a .tar archive of protein structure data for all proteins in that
# proteome
get_afdb_bulk_filenames () {
    local -a bulk_filenames
    local bulk_archive_html=$(curl -sSLq $BULK_AFDB_ARCHIVE_URL)
    mapfile -t bulk_filenames < <(
        printf "%s\n" "$bulk_archive_html" |
        grep -oE 'UP[0-9]{9}[^">]*\.tar' |
        sort -u
    )
    # "Return" list of bulk filenames by printing each on new line
    printf "%s\n" "${bulk_filenames[@]}"
}


# Download and extract .tar archive of protein structure data
fetch_afdb_bulk_data () {
    local proteome=$1
    local bulkfile=$2
    local targetdir="${AFDBDIR}/${proteome}/"
    local tar_path="${TEMPDIR}/${bulkfile}"
    local endpoint="${BULK_AFDB_ARCHIVE_URL}${bulkfile}"
    mkdir -p "$targetdir"

    # Start downloading archive .tar file
    curl -sSL --retry 5 --retry-delay 2 --continue-at - "$endpoint" -o "$tar_path" &
    curl_pid=$!

    # Periodically write progress update while curl job is still running
    while kill -0 "$curl_pid" 2>/dev/null; do
        local downloaded_bytes=$(stat -c%s "$tar_path" 2>/dev/null || echo 0)
        local downloaded_mb=$(( downloaded_bytes / (1024 * 1024) ))
        echo "$(date +%H:%M:%S) [${proteome}] ${downloaded_mb} MB downloaded"
        sleep 30
    done

    # Ensure tar file is more than 0 bytes (in case of network failure)
    if [[ ! -s "$tar_path" ]]; then
        echo "$(date +%H:%M:%S) [${proteome}] ERROR: Bulk download failed"
        return 1
    fi

    # Extract .tar archive
    tar -xf "$tar_path" -C "$targetdir" || {
        echo "$(date +%H:%M:%S) [${proteome}] WARNING: Could not extract archive to ${targetdir}"
        return 1
    }
    rm "$tar_path"

    # Unzip individual files
    if $PDB; then
        gzip -d "${targetdir}"*.pdb.gz 2>/dev/null
    else
        rm "${targetdir}"*.pdb.gz
    fi
    if $MMCIF; then
        gzip -d "${targetdir}"*.cif.gz 2>/dev/null
    else
        rm "${targetdir}"*.cif.gz
    fi

    echo
    echo "$(date +%H:%M:%S) [${proteome}] Download complete"
    echo
    return 0 # Success!
}


# Fetch one protein structure file from AFDB
fetch_afdb_structure_file () {
    local protein=$1
    local ext=$2
    local target_dir=$3
    local proteome=$4
    (
        local endpoint="https://alphafold.ebi.ac.uk/files/AF-${protein}-F1-model_v${AFDB_VERSION}${ext}"
        local target_path="${target_dir}${protein}${ext}"
        curl -sSL --retry 5 --retry-delay 2 --continue-at - -o "${target_path}" "${endpoint}"
    ) || {
        echo "$(date +%H:%M:%S) [${proteome}] WARNING: Could not retrieve ${protein}${ext}"
    }
}


# Download a batch of protein structure files (.pdb / .mmcif)
batch_download_protein_structure_files () {
    local target_dir=$1
    local proteome=$2
    local protein
    while read -r protein; do
        if $PDB; then
            fetch_afdb_structure_file $protein ".pdb" $target_dir $proteome
        fi
        if $MMCIF; then
            fetch_afdb_structure_file $protein ".cif" $target_dir $proteome
        fi
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
    local target_dir="${AFDBDIR}/${proteome}/"
    local -a proteins
    mapfile -t proteins < "${TEMPDIR}/${proteome}.txt"
    local num_proteins=${#proteins[@]}

    # Get number of expected files
    if [[ $MMCIF && $PDB ]]; then
        local num_files=$(( num_proteins * 2 ))
    else
        local num_files=num_proteins
    fi

    # Get chunk sizes
    local threads=$THREADS_PER_PROTEOME
    base=$(( num_proteins / threads ))
    rem=$(( num_proteins % threads ))
    chunk_sizes=()
    for ((i=0; i<threads; i++)); do
        if (( i < rem )); then
            chunk_sizes+=( $(( base + 1 )) )
        else
            chunk_sizes+=( $base )
        fi
    done

    # Start background download threads
    offset=0
    pids=()
    for size in "${chunk_sizes[@]}"; do
        batch=( "${proteins[@]:offset:size}" )
        (
            printf "%s\n" "${batch[@]}" |
            batch_download_protein_structure_files "$target_dir" "$proteome"
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
                sleep 30
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


# Print AFDB .tar filename for proteome if applicable
get_afdb_bulk_filename () {
    local proteome=$1
    local tarfile="${proteome}.tar.gz"

    # Read bulk filenames from stdin
    local fname
    while read -r fname; do
        if [[ $fname == $tarfile ]]; then
            echo $fname
            return 0 # match found
        fi
    done

    return 1 # no match found
}


# Main script for controlling AFDB proteome structure data retrieval
fetch_afdb () {
    local -a bulk_filenames
    mapfile -t bulk_filenames < <(get_afdb_bulk_filenames)

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

        # Download bulk data if available else do protein-by-protein fetch
        proteome=$(basename "$proteome_path" .txt)
        bulk_file=$(get_afdb_bulk_filename "$proteome" <<< "$(printf "%s\n" "${bulk_filenames[@]}")")
        if [[ -n "$bulk_file" ]]; then
            ( fetch_afdb_bulk_data "$proteome" "$bulk_file" || fetch_afdb_protein_data "$proteome" ) &
        else
            ( fetch_afdb_protein_data "$proteome" ) &
        fi

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
if $FROM_AFDB; then
    fetch_afdb
fi
[[ -d "$TEMPDIR" ]] && rm -r "$TEMPDIR"
if ! $KEEP_FASTA; then
    [[ -d "$FASTADIR" ]] && rm -r "$FASTADIR"
fi
end_of_script
