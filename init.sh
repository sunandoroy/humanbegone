#!/bin/bash

# ======================================================================
# HumanBeGone Initialization and Setup Script
# Run this once to setup the conda environment and download required databases.
# ======================================================================

# Stop execution if any critical command fails
set -e

# Always execute relative to the script's physical location
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "=========================================================="
echo "   Initializing HumanBeGone Environment & Databases"
echo "=========================================================="

# 1. Create the Conda Environment
echo -e "\n[1/4] Setting up the Conda environment from humanbegone.yml..."
if [ -f "humanbegone.yml" ]; then
    conda env create -f humanbegone.yml
    echo "-> Conda environment initialized successfully."
else
    echo "ERROR: humanbegone.yml not found in $DIR"
    exit 1
fi

# Placeholder Zenodo URLs
# Update these links with your actual Zenodo URLs once published.
URL_BOWTIE="https://zenodo.org/records/19374761/files/bowtie_index.tar.gz"
URL_KRAKEN="https://zenodo.org/records/19374761/files/kraken_index.tar.gz"
URL_TEST_FILES="https://zenodo.org/records/19374761/files/Test.tar.gz"

# 2. Download and Extract Bowtie2 Index
echo -e "\n[2/4] Downloading Bowtie2 Index..."
wget "$URL_BOWTIE" -O bowtie_index.tar.gz
echo "Extracting Bowtie2 Index..."
tar -xvzf bowtie_index.tar.gz
rm bowtie_index.tar.gz

# 3. Download and Extract Kraken2 Index
echo -e "\n[3/4] Downloading Kraken2 Index..."
wget "$URL_KRAKEN" -O kraken_index.tar.gz
echo "Extracting Kraken2 Index..."
tar -xvzf kraken_index.tar.gz
rm kraken_index.tar.gz

# 4. Download and Extract Test Files
echo -e "\n[4/4] Downloading Test Files..."
wget "$URL_TEST_FILES" -O test_files.tar.gz
echo "Extracting Test Files..."
tar -xvzf test_files.tar.gz
rm test_files.tar.gz

echo "=========================================================="
echo "   Initialization Complete!"
echo "   Access your databases and test files in:"
echo "   $DIR"
echo "=========================================================="
