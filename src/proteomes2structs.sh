#!/bin/bash

# proteomes2structs.sh

# Given some UniProt Proteome Accession IDs, download one .pdb
# and/or one .mmCIF file from AlphaFold DB per protein per proteome.


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

Notes:
  - At least one file format flag must be enabled (--mmcif or --pdb).
  - Parallelism defaults result in 12 concurrent downloads (3 × 4), which is safe for AFDB/PDB.
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
if ! "MMCIF" && ! "PDB"; then
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




# =======================================================================
#     INFO
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
    read -a PROTEOMES <<< $PROTEOMES_STR
}




# =======================================================================
#     GET FASTA FILES FROM UNIPROT
# =======================================================================

# Store all compressed fasta files for input protomes in fasta directory
fetch_fastas () {
    local proteomes=$1
    local base_url="https://rest.uniprot.org/uniprotkb/stream?compressed=true&format=fasta&query="
    for proteome_accession in "${PROTEOMES[@]}"; do
        local target_dir="${OUTDIR}/fasta/${proteome_accession}/"
        local fasta_gz_path="${target_dir}${proteome_accession}.fasta.gz"
        mkdir -p "${target_dir}"

        # Download FASTA file into target_dir
        curl -sSL --retry 5 --retry-delay 2 --continue-at - -o "${fasta_gz_path}" \
        "${base_url}(proteome:${proteome_accession})" || { \
            echo "$(date +%H:%M:%S) WARNING: Could not retrieve ${proteome_accession} FASTA"
            return 1
        }
    done
}

# Write UniProt protein accessions to temporary text file with same
# basename as proteome uniprot accession
extract_protein_uniprot_accessions () {
    for fasta in "${OUTDIR}/fasta/"*.fasta.gz; do
        proteome=$(basename $fasta .fasta.gz)
        # Extract protein accessions from compressed fasta
        mapfile -t protein_accessions < <(gunzip -c "${fasta}" \
            | grep "^>" | cut -d "|" -f 2)
        # Write protein accessions to file
        printf "%s\n" "${protein_accessions[@]}" > "${OUTDIR}/fasta/${proteome}.txt"
    done
}





# =======================================================================
#     Fetch AFDB Structure Data
# =======================================================================

# Get filenames of all UniProt Proteome accessions for which there exists
# a .tar archive of protein structure data for all proteins in that
# proteome
get_afdb_bulk_filenames () {
    local bulk_archive="https://ftp.ebi.ac.uk/pub/databases/alphafold/${AFDB_VERSION}/"
    local bulk_archive_html=$(curl -sSLq $bulk_archive)
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
    proteome=$1
}


# Fetch proteome proteins one after the other from AFDB
fetch_afdb_protein_data () {
    proteome=$1
}


# Return whether bulk data is available for proteome
bulk_afdb_data_exists () {
    proteome=$1
    bulk_filenames=$2
}


# Main script for controlling bulk AFDB data retrieval
fetch_afdb () {
    local bulk_filenames=$(get_afdb_bulk_filenames)

    local proteome_pids=()
    for proteome in "${OUTDIR}/fasta/"*.txt; do
        # Wait for proteome job to become available
        while (( ${#proteome_pids[@]} >= PARALLEL_PROTEOMES )); do
            for i in "${!proteome_pids[@]}"; do
                if ! kill -0 "${proteome_pids[$i]}" 2>/dev/null; then
                    unset 'proteome_pids[i]' # Remove finished PID
                fi
            done
            sleep 1
        done

        # Download bulk data if available else do protein-by-protein fetch
        bulk_data_exists = $(bulk_afdb_data_exists proteome bulk_filenames)
        if $bulk_data_exists; then
            ( fetch_afdb_bulk_data proteome ) &
        else
            ( fetch_afdb_protein_data proteome ) &
        fi

        proteome_pids+=("$!")
    done
}






# =======================================================================
#     MAIN
# =======================================================================

welcome
PROTEOMES=$(parse_proteomes)
fetch_fastas PROTEOMES
extract_protein_uniprot_accessions
if $FROM_AFDB; then
    fetch_afdb
fi
end_of_script









# Attempt to retrieve and extract .pdb files from AlphaFold
# DB bulk proteome archive into a subdirectory of OUTDIR
# named after the reference proteome uniprot accession ID
fetch_archive () {
    local proteome_accession=$1
    for BULK_FILENAME in "${BULK_FILENAMES[@]}"; do
        if [[ "$BULK_FILENAME" == "${proteome_accession}"* ]]; then
            # Fetch and extract that file then return 0 (success)

	    local tar_path="${OUTDIR}/${BULK_FILENAME}"
            local extraction_dir="${OUTDIR}/${proteome_accession}/"
            mkdir -p $extraction_dir
            local endpoint="${BULK_ARCHIVE}${BULK_FILENAME}"
            local logfile="${extraction_dir}pv.log"

            # Start downloading archive .tar file
            curl -sSL --retry 5 --retry-delay 2 --continue-at - "$endpoint" -o "$tar_path" &
            curl_pid=$!

            # Periodically write progress update while curl job is still running
            while kill -0 "$curl_pid" 2>/dev/null; do
                local downloaded_bytes=$(stat -c%s "$tar_path" 2>/dev/null || echo 0)
                local downloaded_mb=$(( downloaded_bytes / (1024 * 1024) ))
                echo "$(date +%H:%M:%S) [${proteome_accession}] ${downloaded_mb} MB downloaded"
                sleep 150
            done

            # Extract .tar archive
            (
                tar -xf $tar_path -C $extraction_dir
                rm $tar_path; unset tar_path;
            ) || {
                echo "$(date +%H:%M:%S) WARNING: Could not extract archive to ${extraction_dir}"
                return 1
            }

            # Unzip individual .pdb.gz files and delete other files
            gzip -d "${extraction_dir}"*.pdb.gz || \
                { echo "$(date +%H:%M:%S) WARNING: Failed to unzip .pdb files in ${extraction_dir}"; return 1; }
            rm "${extraction_dir}"*.cif.gz || \
                { echo "$(date +%H:%M:%S) WARNING: Failed to delete .cif files in ${extraction_dir}"; return 1; }
            return 0 # Success!
        fi
    done
    return 1 # Failure - no bulk file available
}



# Fetch and parse individual uniprot protein accession IDs
# from uniprot .fasta file, then download individual .pdb
# files for each protein via AlphaFold DB API into a
# subdirectory of OUTDIR named after the reference proteome
# uniprot accession ID
fetch_individual_pdbs () {
    local proteome_accession=$1
    local target_dir="${OUTDIR}/${proteome_accession}/"
    local fasta_gz_path="${target_dir}${proteome_accession}.fasta.gz"
    mkdir -p "${target_dir}"
    local -a protein_accessions

    # Download and extract FASTA file into target_dir
    curl -sSL --retry 5 --retry-delay 2 --continue-at - -o "${fasta_gz_path}"  \
    "https://rest.uniprot.org/uniprotkb/stream?compressed=true&format=fasta&query=(proteome:${proteome_accession})" \
    || { echo "$(date +%H:%M:%S) WARNING: Could not retrieve ${proteome_accession} FASTA"; return 1; }
    mapfile -t protein_accessions < <(gunzip -c "${fasta_gz_path}" | grep "^>" | cut -d "|" -f 2)
    rm "${fasta_gz_path}"; unset fasta_gz_path;

    # For each protein accession, download the corresponding .pdb file from AlphaFold DB
    local total=${#protein_accessions[@]}
    local count=0
    for protein in "${protein_accessions[@]}";
    do
        if (( count % 500 == 0 )); then
            printf "%s [%s] %d/%d .pdb files downloaded\n" \
                "$(date +%H:%M:%S)" "$proteome_accession" "$count" "$total"
        fi
        (
            local endpoint="https://alphafold.ebi.ac.uk/files/AF-${protein}-F1-model_v4.pdb"
            local target_path="${target_dir}${protein}.pdb"
            curl -sSL --retry 5 --retry-delay 2 --continue-at - -o "${target_path}" "${endpoint}"
        ) || {
            echo "$(date +%H:%M:%S) WARNING: Could not retrieve ${protein} .pdb for proteome ${proteome_accession}"
        }
        count=$((count+1))
    done

    return 0
}


# Main loop
for PROTEOME_ACCESSION in "${PROTEOMES[@]}";
do
    while (( $(jobs -p | wc -l) >= MAXJOBS )); do
        sleep 30
    done

    (
        fetch_archive $PROTEOME_ACCESSION $OUTDIR || \
            fetch_individual_pdbs $PROTEOME_ACCESSION $OUTDIR

        TARGET_DIR="${OUTDIR}/${PROTEOME_ACCESSION}"
        if [[ -d "${TARGET_DIR}" ]]; then
            PDB_COUNT=$(find "${TARGET_DIR}" -maxdepth 1 -type f -name "*.pdb" | wc -l)
            NON_PDB_COUNT=$(find "${TARGET_DIR}" -maxdepth 1 -type f ! -name "*.pdb" | wc -l)
            echo
            echo "$(date +%H:%M:%S) Downloaded ${PDB_COUNT} AlphaFold DB .pdb files into ${TARGET_DIR}"
            if [[ $NON_PDB_COUNT -gt 0 ]]; then
                echo "$(date +%H:%M:%S) WARNING: ${NON_PDB_COUNT} non-.pdb files found in ${TARGET_DIR}"
            fi
            echo
        else
            echo
            echo "$(date +%H:%M:%S) WARNING: failed to download ${PROTEOME_ACCESSION} AlphaFold DB .pdb files - ${TARGET_DIR} was never created"
            echo
        fi
    ) &
done
wait


# End of Script
echo
printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
echo
echo "Downloaded files available in ${OUTDIR}"
echo
printf '%*s\n' "$(tput cols)" '' | tr ' ' '='
echo
