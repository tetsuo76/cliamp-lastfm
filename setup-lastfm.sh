#!/bin/bash

# Last.fm OAuth Setup Script for cliamp
# macOS-compatible version
#
# Fixes:
#   - GNU md5sum -> macOS md5
#   - GNU sed -i -> BSD/macOS sed -i ''
#   - Correct BSD sed append syntax
#   - Uses HTTPS for Last.fm API
#   - Verifies credentials were actually written

set -euo pipefail

API_URL="https://ws.audioscrobbler.com/2.0/"
CONFIG_FILE="$HOME/.config/cliamp/config.toml"
SECTION="[plugins.cliamp-lastfm]"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Last.fm OAuth Setup for cliamp${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_step() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to URL encode
urlencode() {
    local string="$1"
    printf '%s' "$string" | jq -sRr @uri
}

# Function to get MD5 hash
# macOS does not normally provide GNU md5sum.
md5_hash() {
    printf '%s' "$1" | md5
}

# Function to build API signature
get_api_sig() {
    local api_secret="$1"
    shift

    local keys=()

    # Sort parameters by key
    for param in "$@"; do
        keys+=("$param")
    done

    IFS=$'\n' sorted=($(sort <<<"${keys[*]}"))
    unset IFS

    local sig_str=""

    for param in "${sorted[@]}"; do
        sig_str+="$param"
    done

    sig_str+="$api_secret"

    md5_hash "$sig_str"
}

# Check if config file exists
check_config_file() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Config file not found: $CONFIG_FILE"
        print_info "Please create ~/.config/cliamp/config.toml first"
        exit 1
    fi
}

# Get or create plugin config section
setup_config_section() {
    if ! grep -q "^\[plugins\.cliamp-lastfm\]$" "$CONFIG_FILE"; then
        print_step "Adding [plugins.cliamp-lastfm] section to config..."
        printf '\n%s\n' "$SECTION" >> "$CONFIG_FILE"
        print_success "Section added"
    fi
}

# Update or add config value
#
# macOS uses BSD sed, which requires:
#   sed -i '' ...
#
# The append syntax also differs from GNU sed.
update_config() {
    local key="$1"
    local value="$2"

    # Escape backslashes first, then quotes.
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    if grep -q "^${key} = " "$CONFIG_FILE"; then
        # Update existing value.
        sed -i '' \
            "s|^${key} = .*|${key} = \"${value}\"|" \
            "$CONFIG_FILE"
    else
        # Add new value immediately after the plugin section.
        sed -i '' \
            "/^\[plugins\.cliamp-lastfm\]$/a\\
${key} = \"${value}\"
" \
            "$CONFIG_FILE"
    fi
}

# Verify a config value exists.
verify_config_value() {
    local key="$1"

    if ! grep -q "^${key} = " "$CONFIG_FILE"; then
        print_error "Failed to save ${key} to ${CONFIG_FILE}"
        return 1
    fi

    return 0
}

# Open URL in browser
open_browser() {
    local url="$1"

    if command -v open > /dev/null 2>&1; then
        open "$url"
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "$url"
    elif command -v start > /dev/null 2>&1; then
        start "$url"
    else
        print_info "Please open this URL in your browser:"
        echo "$url"
        return 1
    fi
}

print_header

# Step 1: Get API credentials
print_step "Step 1: Last.fm API Credentials"
print_info "Opening Last.fm API registration page..."
open_browser "https://www.last.fm/api/account/create"

echo ""

print_info "Register a new application with any app name (ignore callback URL)"
print_info "Copy your API Key and Secret"
echo ""

read -r -p "Enter your API Key: " api_key

if [[ -z "$api_key" ]]; then
    print_error "API Key cannot be empty"
    exit 1
fi

read -r -p "Enter your API Secret: " api_secret

if [[ -z "$api_secret" ]]; then
    print_error "API Secret cannot be empty"
    exit 1
fi

print_success "API credentials received"
echo ""

# Step 2: Get username
print_step "Step 2: Last.fm Username"

read -r -p "Enter your Last.fm username: " username

if [[ -z "$username" ]]; then
    print_error "Username cannot be empty"
    exit 1
fi

print_success "Username: $username"
echo ""

# Step 3: Get auth token
print_step "Step 3: Getting authorization token..."

response=$(curl -fsS \
    "$API_URL?method=auth.getToken&api_key=$api_key&format=json")

auth_token=$(echo "$response" | jq -r '.token // empty')

if [[ -z "$auth_token" ]]; then
    print_error "Failed to get auth token"
    print_info "Response: $response"
    exit 1
fi

print_success "Auth token received: $auth_token"
echo ""

# Step 4: Open browser for authorization
print_step "Step 4: Authorization"

auth_url="https://www.last.fm/api/auth/?api_key=$api_key&token=$auth_token"

print_info "Opening Last.fm authorization page..."
print_info "You'll need to click the 'ALLOW' button"
echo ""

if ! open_browser "$auth_url"; then
    echo ""
    echo "Auth URL:"
    echo "$auth_url"
fi

echo ""

read -r -p "Press Enter after you've authorized the application..."

echo ""

# Step 5: Exchange token for session key
print_step "Step 5: Getting session key..."

# Build signature
sig=$(get_api_sig \
    "$api_secret" \
    "api_key$api_key" \
    "methodauth.getSession" \
    "token$auth_token")

response=$(curl -fsS \
    "$API_URL?method=auth.getSession&api_key=$api_key&token=$auth_token&api_sig=$sig&format=json")

session_key=$(echo "$response" | jq -r '.session.key // empty')
username_from_api=$(echo "$response" | jq -r '.session.name // empty')

if [[ -z "$session_key" ]]; then
    error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')

    print_error "Failed to get session key: $error_msg"
    print_info "Make sure you clicked 'ALLOW' on the Last.fm page"
    print_info "Response: $response"

    exit 1
fi

print_success "Session key received"
print_success "Authenticated as: $username_from_api"
echo ""

# Step 6: Save to config file
print_step "Step 6: Saving credentials to config..."

check_config_file
setup_config_section

update_config "api_key" "$api_key"
update_config "api_secret" "$api_secret"
update_config "session_key" "$session_key"
update_config "username" "$username_from_api"

# Verify all four values were actually written.
verify_config_value "api_key"
verify_config_value "api_secret"
verify_config_value "session_key"
verify_config_value "username"

print_success "Credentials successfully saved to $CONFIG_FILE"
echo ""

# Summary
print_header

echo -e "${GREEN}Setup Complete!${NC}"
echo ""

echo "Configuration saved:"
echo "  API Key:      ${api_key:0:10}..."
echo "  Username:     $username_from_api"
echo "  Config file:  $CONFIG_FILE"
echo ""

print_success "Configuration verified successfully"
print_info "Restart cliamp to start scrobbling!"
echo ""
