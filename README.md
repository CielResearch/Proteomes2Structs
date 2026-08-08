# Proteomes2Structs
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/CielResearch/Proteomes2Structs)
![License: CC-BY-NC-4.0](https://img.shields.io/badge/license-CC--BY--NC--4.0-lightgrey)
![Shell](https://img.shields.io/badge/language-shell-green)
<!-- ![Bioconda](https://img.shields.io/conda/vn/bioconda/proteomes2structs) -->

Given some UniProt proteome accession IDs, Proteomes2Structs downloads one .pdb file from AlphaFold DB (v4) per protein per proteome.

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
Provide a list of UniProt proteome accession IDs in a string for the first argument, and the output directory for the second argument.
```bash
proteomes2structs "UP000000625 UP000005640" ../data
```

## Flags/Options
See usage example.

## References

Bertoni, D., Tsenkov, M., Magana, P., Nair, S., Pidruchna, I., Querino Lima Afonso, M., Midlik, A., Paramval, U., Lawal, D., Tanweer, A., Last, M., Patel, R., Laydon, A., Lasecki, D., Dietrich, N., Tomlinson, H., Žídek, A., Green, T., Kovalevskiy, O., … Velankar, S. (2026). AlphaFold Protein Structure Database 2025: A redesigned interface and updated structural coverage. *Nucleic Acids Research, 54*(D1), D358–D362. https://doi.org/10.1093/nar/gkaf1226

The UniProt Consortium. (2025). UniProt: The Universal Protein Knowledgebase in 2025. *Nucleic Acids Research, 53*(D1), D609–D617. https://doi.org/10.1093/nar/gkae1010

## Citation

## License
This tool is licensed under Creative Commons Attribution–NonCommercial 4.0 International (CC BY‑NC 4.0). 
Commercial use and patenting are prohibited. Academic use is permitted with citation.
