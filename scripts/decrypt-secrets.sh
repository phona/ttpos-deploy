#!/bin/bash
# SOPS Secrets Decryption Script for TTPOS
# scripts/decrypt-secrets.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
ENV="${1:-staging}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_DIR/environments/$ENV/secrets"

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") [ENVIRONMENT]

Decrypt SOPS-encrypted secrets for the specified environment.

Arguments:
    ENVIRONMENT    Target environment (default: staging)
                   Options: staging, production

Requirements:
    - SOPS must be installed: https://github.com/getsops/sops
    - SOPS_AGE_KEY environment variable must be set, or
    - .sops.yaml must be configured with cloud KMS

Examples:
    $(basename "$0") staging
    $(basename "$0") production
    SOPS_AGE_KEY=... $(basename "$0") production
EOF
    exit 0
}

# Check if SOPS is installed
check_sops() {
    if ! command -v sops &> /dev/null; then
        echo -e "${RED}Error: SOPS is not installed.${NC}"
        echo "Install SOPS: https://github.com/getsops/sops/releases"
        exit 1
    fi
}

# Validate environment
validate_env() {
    if [[ ! "$ENV" =~ ^(staging|production)$ ]]; then
        echo -e "${RED}Error: Invalid environment '$ENV'. Must be 'staging' or 'production'.${NC}"
        exit 1
    fi
}

# Check secrets directory
check_secrets_dir() {
    if [[ ! -d "$SECRETS_DIR" ]]; then
        echo -e "${YELLOW}No secrets directory found for $ENV environment.${NC}"
        echo "Expected: $SECRETS_DIR"
        exit 0
    fi
}

# Decrypt secrets
decrypt_secrets() {
    echo -e "${BLUE}Decrypting secrets for $ENV environment...${NC}"

    local encrypted_files=()
    local decrypted_count=0

    # Find all encrypted files
    while IFS= read -r -d '' file; do
        encrypted_files+=("$file")
    done < <(find "$SECRETS_DIR" -name "*.enc" -print0 2>/dev/null)

    if [[ ${#encrypted_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No encrypted files found in $SECRETS_DIR${NC}"

        # Also check for .yaml files that might be encrypted
        while IFS= read -r -d '' file; do
            if sops --is-encrypted "$file" 2>/dev/null; then
                encrypted_files+=("$file")
            fi
        done < <(find "$SECRETS_DIR" -name "*.yaml" -o -name "*.yml" -print0 2>/dev/null)
    fi

    if [[ ${#encrypted_files[@]} -eq 0 ]]; then
        echo -e "${GREEN}No secrets to decrypt.${NC}"
        exit 0
    fi

    # Decrypt each file
    for enc_file in "${encrypted_files[@]}"; do
        local dec_file="${enc_file%.enc}"

        echo -e "${BLUE}Decrypting: $(basename "$enc_file")${NC}"

        if sops --decrypt "$enc_file" > "$dec_file" 2>/dev/null; then
            chmod 600 "$dec_file"
            echo -e "${GREEN}✓ Decrypted: $(basename "$dec_file")${NC}"
            ((decrypted_count++))
        else
            echo -e "${RED}✗ Failed to decrypt: $(basename "$enc_file")${NC}"
            rm -f "$dec_file" 2>/dev/null || true
        fi
    done

    echo -e "${BLUE}======================================${NC}"
    echo -e "${GREEN}Decrypted $decrypted_count secret file(s)${NC}"
    echo -e "${BLUE}======================================${NC}"
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up decrypted files...${NC}"
    find "$SECRETS_DIR" -type f ! -name "*.enc" ! -name ".sops.yaml" -delete 2>/dev/null || true
}

# Main function
main() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
    fi

    check_sops
    validate_env
    check_secrets_dir
    decrypt_secrets
}

# Trap for cleanup on exit
trap cleanup EXIT

main "$@"
