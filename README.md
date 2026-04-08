# HumanBeGone 🧬

**HumanBeGone** is an automated, robust bioinformatics pipeline designed for highly efficient human sequence decontamination of FASTQ reads. It securely routes data through advanced pre-processing algorithms (FastP) and maps against large-scale human reference grids (Kraken2 & Bowtie2) to filter out human contamination.

## 🚀 Features
- Rapid QC and Adapter Trimming via **FastP**.
- Two-Tiered Human filtration utilizing the swiftness of **Kraken2** combined with the high-sensitivity of **Bowtie2** structural elimination.
- Intuitive structural logic wrapping all output analytics sequentially into highly organized, isolated Sample directories.
- Dynamic Reporting module that auto-generates a compiled CSV tracking matrix and an interactive **HTML dataset visualization (Chart.js)** to easily parse exact read eliminations cross-pipeline.

---

## 🛠️ Installation & Initialization 

HumanBeGone requires its core dependencies to be initialized prior to execution. A managed `init.sh` script is provided to automate this environment!

1. Clone this repository to your computational environment:
   ```bash
   git clone https://github.com/sunandoroy/humanbegone.git
   cd humanbegone
   ```
2. Run the initialization script. This utilizes the integrated `humanbegone.yml` to spin up a managed Anaconda environment, and simultaneously pulls down the required massive algorithmic indexing targets securely from Zenodo:
   ```bash
   ./init.sh
   ```
3. Activate the physical conda environment whenever attempting to invoke the execution suite:
   ```bash
   conda activate humanbegone
   ```

---

## 💻 Usage

HumanBeGone can natively digest direct physical directories or cleanly mapped CSV metadata files.

**Basic Invocation Structure**
```bash
./humanbegone.sh <input_data> [OPTIONS]
```

### 1. The Input Engine
The tool accepts reads via two unique ingestion formats:
* **Directory Pathing:** Pass the literal directory path (`/path/to/fastqs/`). The script will scan the folder organically for all standard `_R1` structured fastq files, pair them natively if `_R2` reads exist, and evaluate them automatically.
* **SampleSheet Matrix:** Alternatively, pass a targeted `.csv` tracking file.

#### SampleSheet Formatting Requirement
If submitting via a CSV, it must strictly be comma-separated and possess the explicit `Sample_Name` metadata headers logic:
```csv
Sample_Name,R1_Path,R2_Path
Sample01,sample01_R1.fastq.gz,sample01_R2.fastq.gz
Sample02,sample02_R1.fastq.gz,
```
*Relative paths provided in a SampleSheet will automatically resolve universally! Paired-End sequences strictly utilize both columns, while Single-End deployments only define R1.*

### 2. Available Options Matrix

Mandatory Flags:
* `--single` or `--dual` : Dictates the baseline processing logic if sequences are Single-End or Paired-End arrays.
* `--kraken-db <path>` : Targeted path specifying the Kraken2 database directory downloaded during `init.sh` execution.
* `--bowtie-index <path>` : The explicit string Prefix mapping the Bowtie2 indexing core downloaded during `init.sh`.

Optional Modifiers:
* `--skip-fastp` : Will physically bypass the entire FastP module. The script natively forwards original raw arrays precisely into Kraken2 logic. Graphical reporting analytics treat the FastP subset mapping perfectly as `0%`.
* `--threads <int>` : Computable parallel multithreading allowance limits. *(Default: 8)*.
* `--output-dir <path>` : Explicit custom endpoint destination. The pipeline spins up temporary processing environments directly mapping relative to operations to generate logs and metadata metrics organically before finally relocating the successfully compiled structural directories cleanly out to this Custom Output Director. *(Default: Input File Directory)*.

### 🌟 Full Example Execution
```bash
./humanbegone.sh mysamples.csv --dual \
    --threads 16 \
    --kraken-db ./kraken_T2T_db/ \
    --bowtie-index ./bowtie2_T2T_db/T2T_Bowtie2_Index \
    --skip-fastp \
    --output-dir /storage/cleaned_data/
```

---

## 📊 Pipeline Outputs

Once seamlessly processed, your finalized reads will neatly separate structurally into isolated component hubs:
* `Results/Fastp/<SampleName>/` *(QC metrics + Sub-HTML visualizations)*
* `Results/Kraken/<SampleName>/` *(Sequence Logs + Terminal Metrics)*
* `Results/Bowtie/<SampleName>/` *(Unmapped final stripped `.fastq.gz` dataset cleanly packaged)*
* `Results/Reports/` *(The final master accumulated `Summary.csv` structure and interactively togglable `processing_report.html` master visual document!)*
