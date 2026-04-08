#!/bin/bash

START_TIME=$(date +%s)

# Usage: 
#   ./humanbegone.sh /path/to/fastq_dir --single|--dual [--skip-fastp]
#   ./humanbegone.sh samplesheet.csv --single|--dual [--skip-fastp]

INPUT=""
MODE=""
SKIP_FASTP=false
THREADS=8
K2_DB=""
BT2_INDEX=""
OUTPUT_DIR=""

print_help() {
    echo "Usage: $0 <input_dir_or_samplesheet_csv> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help menu"
    echo "  --single | --dual         (required) Set processing mode"
    echo "  --kraken-db <path>        (required) Path to Kraken2 database directory"
    echo "  --bowtie-index <path>     (required) Path to Bowtie2 index prefix"
    echo "  --output-dir <path>       Custom directory to output Results folder (default: directory of input)"
    echo "  --skip-fastp              Skip FastP processing"
    echo "  --threads <int>           Number of threads (default: 8)"
    exit 0
}

# Parse arguments cleanly allowing for dynamic flags and key-value pairs
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help ;;
        --single) MODE="--single"; shift ;;
        --dual) MODE="--dual"; shift ;;
        --skip-fastp) SKIP_FASTP=true; shift ;;
        --run-fastp) SKIP_FASTP=false; shift ;;
        --threads) THREADS="$2"; shift 2 ;;
        --kraken-db) K2_DB="$2"; shift 2 ;;
        --bowtie-index) BT2_INDEX="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        *)
            if [ -z "$INPUT" ]; then
                INPUT="$1"
            else
                echo "Unknown argument/input: $1"
                echo "Run with --help for more information."
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$INPUT" ] || [ -z "$MODE" ] || [ -z "$K2_DB" ] || [ -z "$BT2_INDEX" ]; then
    echo "Error: Missing required arguments."
    echo "Run with --help for more information."
    exit 1
fi

# Preserve original directory context to evaluate relative paths safely
ORIGINAL_DIR="$PWD"

if [ -d "$INPUT" ] || [ -f "$INPUT" ]; then
    if [[ "$INPUT" != /* ]]; then INPUT="$ORIGINAL_DIR/$INPUT"; fi
fi
if [[ -n "$K2_DB" && "$K2_DB" != /* ]]; then K2_DB="$ORIGINAL_DIR/$K2_DB"; fi
if [[ -n "$BT2_INDEX" && "$BT2_INDEX" != /* ]]; then BT2_INDEX="$ORIGINAL_DIR/$BT2_INDEX"; fi
if [[ -n "$OUTPUT_DIR" && "$OUTPUT_DIR" != /* ]]; then OUTPUT_DIR="$ORIGINAL_DIR/$OUTPUT_DIR"; fi

if [ -d "$INPUT" ]; then
    BASE_INPUT_DIR="$INPUT"
    WORK_DIR="${INPUT}/work"
else
    BASE_INPUT_DIR="$(dirname "$INPUT")"
    WORK_DIR="${BASE_INPUT_DIR}/work"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit 1

# Initialize Summary File
SUMMARY_FILE="scrubbing_summary_$(date +%Y%m%d_%H%M%S).csv"
echo "Sample_Name,Initial_Pairs,After_fastp,Kraken_Human_Removed,Bowtie2_Human_Removed,Final_Clean_Pairs,Percent_Scrubbed" > "$SUMMARY_FILE"

echo "==========================================="
echo "   HumanBeGone: Automated Decontamination"
echo "==========================================="

# --- PRE-FLIGHT CHECK ---
TOOLS="kraken2 bowtie2 awk"
if [ "$SKIP_FASTP" = false ]; then
    TOOLS="$TOOLS fastp gojq"
fi

for tool in $TOOLS; do
	if ! command -v "$tool" &> /dev/null; then
		echo "ERROR: $tool is not installed or not in PATH. Are you skipping fastp?"
		exit 1
	fi
done

# --- CORE SCRUBBING FUNCTION ---
process_sample() {
	local NAME=$1
	local R1=$2
	local R2=$3
	local IS_PE=$4

    # Resolve relative paths relative to the Input file's directory ($BASE_INPUT_DIR)
    if [[ ! -z "$R1" && "$R1" != /* ]]; then
        R1="${BASE_INPUT_DIR}/$R1"
    fi
    if [[ "$IS_PE" = true && ! -z "$R2" && "$R2" != /* ]]; then
        R2="${BASE_INPUT_DIR}/$R2"
    fi

    echo "-------------------------------------------"
	echo "Variable Check for Sample: $NAME"
	echo "R1 Path  = '$R1'"
	echo "R2 Path  = '$R2'"
    echo "Mode PE  = $IS_PE"
	echo "-------------------------------------------"

	echo "==========================================="
	echo "Processing: $NAME"
	echo "==========================================="

	# 0. Initial Count
	local TOTAL_LINES=$(zcat -f "$R1" | wc -l | xargs)
	local INITIAL_PAIRS=$((TOTAL_LINES / 4))

    # 1. fastp
    local AFTER_FASTP_PAIRS=0
    local K2_IN_R1=""
    local K2_IN_R2=""

    if [ "$SKIP_FASTP" = true ]; then
        echo "Skipping FastP. Files proceeding directly to Kraken2."
        AFTER_FASTP_PAIRS=$INITIAL_PAIRS
        K2_IN_R1="$R1"
        if [ "$IS_PE" = true ]; then
            K2_IN_R2="$R2"
        fi
    else
        if [ "$IS_PE" = true ]; then
            fastp -i "$R1" -I "$R2" -o "${NAME}_trimmed_R1.fq.gz" -O "${NAME}_trimmed_R2.fq.gz" --html "${NAME}_fastp.html" --json "${NAME}_fastp.json" --thread $THREADS 2> "${NAME}_fastp.log"
        else
            fastp -i "$R1" -o "${NAME}_trimmed_R1.fq.gz" --html "${NAME}_fastp.html" --json "${NAME}_fastp.json" --thread $THREADS 2> "${NAME}_fastp.log"
        fi
        
        local AFTER_FASTP=$(gojq '.summary.after_filtering.total_reads' "${NAME}_fastp.json")
        if [ "$IS_PE" = true ]; then
            AFTER_FASTP_PAIRS=$((AFTER_FASTP / 2))
        else
            AFTER_FASTP_PAIRS=$AFTER_FASTP
        fi
        K2_IN_R1="${NAME}_trimmed_R1.fq.gz"
        K2_IN_R2="${NAME}_trimmed_R2.fq.gz"
    fi
  
    # 2. Kraken2
	if [ "$IS_PE" = true ]; then
		kraken2 --db "$K2_DB" --threads $THREADS --paired "$K2_IN_R1" "$K2_IN_R2" --confidence 0.05 --unclassified-out "${NAME}_k2_clean#.fq" --report "${NAME}_k2_report.txt" > "${NAME}_k2.log" 2>&1
	else
		kraken2 --db "$K2_DB" --threads $THREADS "$K2_IN_R1" --confidence 0.05 --unclassified-out "${NAME}_k2_clean_1.fq" --report "${NAME}_k2_report.txt" > "${NAME}_k2.log" 2>&1
	fi
	local K2_REMOVED=$(grep " sequences classified" "${NAME}_k2.log" | awk '{print $1}' | head -n 1)
	local AFTER_K2=$(grep " sequences unclassified" "${NAME}_k2.log" | awk '{print $1}' | head -n 1)

    # 3. Bowtie2
	if [[ "$MODE" == "--dual" && "$IS_PE" = true ]]; then
		bowtie2 -x "$BT2_INDEX" -1 "${NAME}_k2_clean_1.fq" -2 "${NAME}_k2_clean_2.fq" --very-sensitive-local --un-conc-gz "${NAME}_final.fq.gz" -p $THREADS 2> "${NAME}_bt2.log" > /dev/null
		local FINAL_PAIRS=$(grep "aligned concordantly 0 times" "${NAME}_bt2.log" | sed 's/^[[:space:]]*//' | awk '{print $1}' | head -n 1)
	else
		bowtie2 -x "$BT2_INDEX" -U "${NAME}_k2_clean_1.fq" --very-sensitive-local -p $THREADS --un "${NAME}_bt2_R1.fq" 2> "${NAME}_bt1.log" > /dev/null
		if [ "$IS_PE" = true ]; then
			bowtie2 -x "$BT2_INDEX" -U "${NAME}_k2_clean_2.fq" --very-sensitive-local -p $THREADS --un "${NAME}_bt2_R2.fq" 2> "${NAME}_bt2.log" > /dev/null
			mkdir -p "tmp_${NAME}"
			seqkit pair -1 "${NAME}_bt2_R1.fq" -2 "${NAME}_bt2_R2.fq" -O "tmp_${NAME}" -f -j $THREADS > /dev/null 2>&1
			gzip -c "tmp_${NAME}"/*_bt2_R1.fq > "${NAME}_final_1.fq.gz"
			gzip -c "tmp_${NAME}"/*_bt2_R2.fq > "${NAME}_final_2.fq.gz"
			local FINAL_PAIRS=$(zcat "${NAME}_final_1.fq.gz" | wc -l | xargs)
			FINAL_PAIRS=$((FINAL_PAIRS / 4))
			rm -rf "tmp_${NAME}" "${NAME}_bt2_R1.fq" "${NAME}_bt2_R2.fq"
		else
			gzip -c "${NAME}_bt2_R1.fq" > "${NAME}_final.fq.gz"
			local FINAL_PAIRS=$(( $(zcat "${NAME}_final.fq.gz" | wc -l) / 4 ))
			rm "${NAME}_bt2_R1.fq"
		fi
	fi

    # Calculations for Summary
	local BT2_REMOVED=$(awk "BEGIN {print $AFTER_K2 - $FINAL_PAIRS}")
	local TOTAL_REMOVED=$((INITIAL_PAIRS - FINAL_PAIRS))
	local PCT=$(awk "BEGIN {if ($INITIAL_PAIRS > 0) printf \"%.2f\", ($TOTAL_REMOVED/$INITIAL_PAIRS)*100; else print \"0\"}")

    # Append to Summary File
	echo "$NAME,$INITIAL_PAIRS,$AFTER_FASTP_PAIRS,$K2_REMOVED,$BT2_REMOVED,$FINAL_PAIRS,$PCT%" >> "$SUMMARY_FILE"

    # Cleanup
	rm -f "${NAME}_k2_clean_1.fq" "${NAME}_k2_clean_2.fq"
}

# --- INPUT ROUTING ---
if [[ -d "$INPUT" ]]; then
	for file in "$INPUT"/*_R1_*.fastq*; do
		if [[ "$file" =~ ^(.+)/([^/]+)_S[0-9_L]+_R1_[0-9]+\.fastq(\.gz)?$ ]]; then
			NAME="${BASH_REMATCH[2]}"
			[[ -f "${file/_R1_/_R2_}" ]] && process_sample "$NAME" "$file" "${file/_R1_/_R2_}" true || process_sample "$NAME" "$file" "" false
		fi
	done
elif [[ -f "$INPUT" && "$INPUT" == *.csv ]]; then
  sed -i 's/\r//g' "$INPUT"
	while IFS=',' read -r col1 col2 col3; do
		[[ "$col1" =~ ^Sample_[Nn]ame$ ]] && continue
		[[ -n "$col3" ]] && process_sample "$col1" "$col2" "$col3" true || process_sample "$col1" "$col2" "" false
	done < "$INPUT"
fi

echo -e "\nScrubbing complete. Final summary saved to: $SUMMARY_FILE"
column -s, -t < "$SUMMARY_FILE"  # Displays the CSV nicely in the terminal

# --- HTML REPORT GENERATION MODULE ---
REPORT_FILE="scrubbing_report_$(date +%Y%m%d_%H%M%S).html"
echo -e "\nGenerating HTML report: $REPORT_FILE"

cat << 'EOF' > "$REPORT_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HumanBeGone processing Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Inter', sans-serif; margin: 40px; background-color: #f8f9fa; color: #333; }
        .container { background-color: white; padding: 30px; border-radius: 12px; box-shadow: 0 10px 15px rgba(0,0,0,0.05); max-width: 1200px; margin: auto; }
        h1 { text-align: center; color: #2c3e50; font-weight: 600; margin-bottom: 20px; }
        .controls { text-align: center; margin-bottom: 20px; }
        button { background-color: #3498db; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: bold; transition: background-color 0.2s; }
        button:hover { background-color: #2980b9; }
        .chart-container { position: relative; height: 60vh; width: 100%; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Scrubbing Summary Report</h1>
        <div class="controls">
            <button id="toggleViewBtn">Switch to Percentage View</button>
        </div>
        <div class="chart-container">
            <canvas id="scrubChart"></canvas>
        </div>
    </div>
    <script>
        const data = [
EOF

# Parse the summary file to generate JSON-like data handling edge cases
tail -n +2 "$SUMMARY_FILE" | while IFS=',' read -r name initial after_fastp kraken bowtie final pct; do
    # Calculate FastP removed
    fastp_removed=$((initial - after_fastp))
    
    # Fallback to 0 if variables are empty just in case
    fastp_removed=${fastp_removed:-0}
    kraken=${kraken:-0}
    bowtie=${bowtie:-0}
    final=${final:-0}
    initial=${initial:-0}
    
    # Calculate percentages
    if [ "$initial" -gt 0 ]; then
        p_fastp=$(awk -v f="$fastp_removed" -v i="$initial" 'BEGIN { printf "%.2f", (f/i)*100 }')
        p_kraken=$(awk -v k="$kraken" -v i="$initial" 'BEGIN { printf "%.2f", (k/i)*100 }')
        p_bowtie=$(awk -v b="$bowtie" -v i="$initial" 'BEGIN { printf "%.2f", (b/i)*100 }')
        p_final=$(awk -v f="$final" -v i="$initial" 'BEGIN { printf "%.2f", (f/i)*100 }')
    else
        p_fastp=0 p_kraken=0 p_bowtie=0 p_final=0
    fi
    
    echo "            { label: '$name', count: { fastp: $fastp_removed, kraken: $kraken, bowtie: $bowtie, final: $final }, pct: { fastp: $p_fastp, kraken: $p_kraken, bowtie: $p_bowtie, final: $p_final } }," >> "$REPORT_FILE"
done

cat << 'EOF' >> "$REPORT_FILE"
        ];

        const labels = data.map(d => d.label);
        let isCountView = true;
        
        function getDatasets(viewType) {
            return [
                { 
                    label: 'Final Clean Reads', 
                    data: data.map(d => d[viewType].final), 
                    backgroundColor: 'rgba(75, 192, 192, 0.8)',
                    borderColor: 'rgba(75, 192, 192, 1)',
                    borderWidth: 1
                },
                { 
                    label: 'Lost in Bowtie2', 
                    data: data.map(d => d[viewType].bowtie), 
                    backgroundColor: 'rgba(255, 205, 86, 0.8)',
                    borderColor: 'rgba(255, 205, 86, 1)',
                    borderWidth: 1
                },
                { 
                    label: 'Lost in Kraken2', 
                    data: data.map(d => d[viewType].kraken), 
                    backgroundColor: 'rgba(255, 159, 64, 0.8)',
                    borderColor: 'rgba(255, 159, 64, 1)',
                    borderWidth: 1
                },
                { 
                    label: 'Lost in FastP', 
                    data: data.map(d => d[viewType].fastp), 
                    backgroundColor: 'rgba(255, 99, 132, 0.8)',
                    borderColor: 'rgba(255, 99, 132, 1)',
                    borderWidth: 1
                }
            ];
        }

        const ctx = document.getElementById('scrubChart').getContext('2d');
        const chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: getDatasets('count')
            },
            options: {
                indexAxis: 'y', // Renders the bar chart horizontally
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        stacked: true,
                        title: { display: true, text: 'Number of Read Pairs', font: { weight: 'bold' } },
                        grid: { color: 'rgba(0,0,0,0.05)' }
                    },
                    y: {
                        stacked: true,
                        title: { display: true, text: 'Samples', font: { weight: 'bold' } },
                        grid: { display: false }
                    }
                },
                plugins: {
                    title: { display: false },
                    tooltip: { mode: 'index', intersect: false },
                    legend: { position: 'top' }
                }
            }
        });
        
        document.getElementById('toggleViewBtn').addEventListener('click', function() {
            isCountView = !isCountView;
            this.textContent = isCountView ? "Switch to Percentage View" : "Switch to Count View";
            
            chart.data.datasets = getDatasets(isCountView ? 'count' : 'pct');
            chart.options.scales.x.title.text = isCountView ? 'Number of Read Pairs' : 'Percentage of Reads (%)';
            if (!isCountView) {
                chart.options.scales.x.max = 100;
            } else {
                delete chart.options.scales.x.max;
            }
            chart.update();
        });
    </script>
</body>
</html>
EOF

echo "Done! You can view the report dynamically in your browser."

echo "==========================================="
echo "   Organizing outputs into Results directory"
echo "==========================================="
mkdir -p Results/Reports
mv "$SUMMARY_FILE" "$REPORT_FILE" Results/Reports/ 2>/dev/null || true

# Parse summary file to organize by sample
if [ -f "Results/Reports/$SUMMARY_FILE" ]; then
    tail -n +2 "Results/Reports/$SUMMARY_FILE" | while IFS=',' read -r name initial after_fastp kraken bowtie final pct; do
        # Create subfolders for each individual sample
        mkdir -p "Results/Fastp/$name" "Results/Kraken/$name" "Results/Bowtie/$name"
        
        # Move file outputs securely matching this sample
        mv "${name}_fastp"* "${name}_trimmed_"*.fq.gz "Results/Fastp/$name/" 2>/dev/null || true
        mv "${name}_k2_report.txt" "${name}_k2.log" "Results/Kraken/$name/" 2>/dev/null || true
        mv "${name}_bt1.log" "${name}_bt2.log" "${name}_final"*.fq* "Results/Bowtie/$name/" 2>/dev/null || true
    done
fi

if [ -z "$OUTPUT_DIR" ]; then
    if [ -d "$INPUT" ]; then
        OUTPUT_DIR="${INPUT}/Results"
    else
        OUTPUT_DIR="$(dirname "$INPUT")/Results"
    fi
fi

# Cleanly resolve output directory path to prevent moving into itself
ABS_LOCAL=$(readlink -f ./Results)
mkdir -p "$OUTPUT_DIR"
ABS_FINAL=$(readlink -f "$OUTPUT_DIR")

if [ "$ABS_LOCAL" != "$ABS_FINAL" ]; then
    echo "Relocating Results to output directory: $OUTPUT_DIR"
    mv Results/* "$OUTPUT_DIR/" 2>/dev/null || true
    rmdir Results 2>/dev/null || true
fi

# Exit the temporary work directory and remove it
cd "$ORIGINAL_DIR" || exit 1
rm -rf "$WORK_DIR"

echo "Cleanup complete! All files logically sorted in $OUTPUT_DIR/"

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
RUNTIME_H=$((RUNTIME / 3600))
RUNTIME_M=$(((RUNTIME % 3600) / 60))
RUNTIME_S=$((RUNTIME % 60))
echo "Runtime : ${RUNTIME_H}h ${RUNTIME_M}m ${RUNTIME_S}s"
