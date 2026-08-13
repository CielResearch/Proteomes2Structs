# Proteomes2Structs
![Shell](https://img.shields.io/badge/language-shell-green)
![GitHub tag (latest)](https://img.shields.io/github/v/tag/CielResearch/Proteomes2Structs)
![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.21850698-blue)
![License: CC-BY-NC-4.0](https://img.shields.io/badge/license-CC--BY--NC--4.0-lightgrey)
<!-- ![Bioconda](https://img.shields.io/conda/vn/bioconda/proteomes2structs) -->

Given some UniProt proteome accession IDs, Proteomes2Structs downloads structural data from AlphaFold DB for each protein in each proteome.


## Installation
### Manual installation (until Bioconda package is available)
Clone the repository:
```bash
git clone https://github.com/CielResearch/Proteomes2Structs.git
cd Proteomes2Structs
```
Make the wrapper executable:
```bash
chmod +x bin/proteomes2structs
```
(Optional) Add the tool to your PATH:
```bash
export PATH="$PWD/bin:$PATH"
```
You can now run:
```bash
proteomes2structs --help
```
### Bioconda installation (coming soon)
Once the Bioconda recipe is accepted, you will be able to install Proteomes2Structs with:
```bash
conda install -c bioconda proteomes2structs
```

## Usage Examples
Usage: `proteomes2structs [options] "PROTEOME_LIST" OUTPUT_DIR`

Example: `proteomes2structs --mmcif "UP000000625 UP000007256" ../data`

### Required positional arguments:
| Positional Argument | Example                   | Notes                                               |
|---------------------|---------------------------|-----------------------------------------------------|
| "PROTEOME_LIST"     | "UP000000625 UP000007256" | Quoted space-separated UniProt proteome accession/s |
| OUTPUT_DIR          | ../data                   | Directory where downloaded files will be stored     |

### Flags/Options
| Category    | Flag/Option              | Default | Notes                                      |
|-------------|--------------------------|---------|--------------------------------------------|
| File format | `--mmcif`                |         | Download .mmCIF/.cif files                 |
| File format | `--pdb`                  |         | Download .pdb files                        |
| Source      | `--afdb-version`         | 4       | AlphaFold model version (v1-v4)            |
| Parallelism | `--parallel-proteomes`   | 3       | Number of proteomes to process in parallel |
| Parallelism | `--threads-per-proteome` | 4       | Number of download threads per proteome    |
| Other       | `--keep-fasta`           |         | Do not automatically delete FASTA files    |
| Other       | `--sui`                  | 5       | Status update interval in minutes          |

### Notes:
  - At least one file format flag must be enabled (`--mmcif` or `--pdb)`.
  - Parallelism defaults result in 12 concurrent downloads (3 × 4).


## Contributing / Issues
Please open an issue on GitHub for bug reports or feature requests.


## References

Bertoni, D., Tsenkov, M., Magana, P., Nair, S., Pidruchna, I., Querino Lima Afonso, M., Midlik, A., Paramval, U., Lawal, D., Tanweer, A., Last, M., Patel, R., Laydon, A., Lasecki, D., Dietrich, N., Tomlinson, H., Žídek, A., Green, T., Kovalevskiy, O., … Velankar, S. (2026). AlphaFold Protein Structure Database 2025: A redesigned interface and updated structural coverage. *Nucleic Acids Research, 54*(D1), D358–D362. https://doi.org/10.1093/nar/gkaf1226

The UniProt Consortium. (2025). UniProt: The Universal Protein Knowledgebase in 2025. *Nucleic Acids Research, 53*(D1), D609–D617. https://doi.org/10.1093/nar/gkae1010


## Citation

### APA 7
Baumann, C. I.-L. (2026). Proteomes2Structs [Shell]. Zenodo. https://doi.org/10.5281/zenodo.21850698

### BibTeX
@software{baumann_proteomes2structs_2026,
  author = {Baumann, Ciel Ivy-Lee},
  title = {Proteomes2Structs},
  doi = {10.5281/zenodo.21850698},
  url = {https://github.com/CielResearch/Proteomes2Structs},
  year = {2026}
}


## License
This tool is licensed under Creative Commons Attribution–NonCommercial 4.0 International (CC BY‑NC 4.0). 
Commercial use and patenting are prohibited. Academic use is permitted with citation.
