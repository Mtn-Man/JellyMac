#!/bin/bash

# lib/parsing_utils.sh
# This script provides a function to parse the plain-text 'Configuration.txt' file.
# It is designed to be sourced by the main jellymac.sh script.

# Global arrays that will be populated by the parser function
YTDLP_OPTS=()
MAIN_MEDIA_EXTENSIONS=()
ASSOCIATED_FILE_EXTENSIONS=()

#==============================================================================
# Function: _parse_and_export_config
# Description: Reads the specified config file, parses key-value pairs and
#              special multi-line blocks, and exports the variables into the
#              calling shell's environment.
#
# Parameters:
#   $1 - The absolute path to the configuration file to parse.
#
# Returns:
#   0 - On successful parsing.
#   1 - If the configuration file cannot be found or read.
#
# Side Effects:
#   - Exports all standard KEY="VALUE" settings as environment variables.
#   - Populates the YTDLP_OPTS array in the calling script's scope.
#   - Populates the MAIN_MEDIA_EXTENSIONS array in the calling script's scope.
#   - Populates the ASSOCIATED_FILE_EXTENSIONS array in the calling script's scope.
#
# Usage (from the main script):
#   source "lib/parser_utils.sh"
#   _parse_and_export_config "/path/to/your/Configuration.txt"
#
#==============================================================================
_parse_and_export_config() {
    local config_file="$1"

    if [[ ! -r "$config_file" ]]; then
        echo "CONFIG_PARSER_ERROR: Configuration file not found or not readable at '$config_file'" >&2
        return 1
    fi

    # Clear arrays before parsing
    YTDLP_OPTS=()
    MAIN_MEDIA_EXTENSIONS=()
    ASSOCIATED_FILE_EXTENSIONS=()
    local in_ytdlp_block="false"
    local in_main_extensions_block="false"
    local in_associated_extensions_block="false"

    # Read the file line by line to preserve whitespace within values.
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading and trailing whitespace from the line.
        local trimmed_line
        trimmed_line="$(echo -E "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # Skip empty lines and full-line comments.
        if [[ -z "$trimmed_line" || "${trimmed_line:0:1}" == "#" ]]; then
            continue
        fi

        # --- Handle Special Blocks ---
        if [[ "$trimmed_line" == "BEGIN_YTDLP_OPTS" ]]; then
            in_ytdlp_block="true"
            continue
        elif [[ "$trimmed_line" == "END_YTDLP_OPTS" ]]; then
            in_ytdlp_block="false"
            continue
        elif [[ "$trimmed_line" == "BEGIN_MAIN_MEDIA_EXTENSIONS" ]]; then
            in_main_extensions_block="true"
            continue
        elif [[ "$trimmed_line" == "END_MAIN_MEDIA_EXTENSIONS" ]]; then
            in_main_extensions_block="false"
            continue
        elif [[ "$trimmed_line" == "BEGIN_ASSOCIATED_FILE_EXTENSIONS" ]]; then
            in_associated_extensions_block="true"
            continue
        elif [[ "$trimmed_line" == "END_ASSOCIATED_FILE_EXTENSIONS" ]]; then
            in_associated_extensions_block="false"
            continue
        fi

        if [[ "$in_ytdlp_block" == "true" ]]; then
            # Inside the yt-dlp block, treat each whitespace-separated token as a
            # separate option so that flags and their parameters are passed as
            # distinct arguments (e.g. "--merge-output-format mp4").
            if [[ "${trimmed_line:0:1}" != "#" ]]; then
                # Bash 3.2 compatible tokenisation
                for _token in ${trimmed_line}; do
                    YTDLP_OPTS[${#YTDLP_OPTS[@]}]="$_token"
                done
            fi
            continue
        elif [[ "$in_main_extensions_block" == "true" ]]; then
            # Inside the main media extensions block, add each line as an extension
            if [[ "${trimmed_line:0:1}" != "#" ]]; then
                MAIN_MEDIA_EXTENSIONS[${#MAIN_MEDIA_EXTENSIONS[@]}]="$trimmed_line"
            fi
            continue
        elif [[ "$in_associated_extensions_block" == "true" ]]; then
            # Inside the associated file extensions block, add each line as an extension
            if [[ "${trimmed_line:0:1}" != "#" ]]; then
                ASSOCIATED_FILE_EXTENSIONS[${#ASSOCIATED_FILE_EXTENSIONS[@]}]="$trimmed_line"
            fi
            continue
        fi

        # --- Parse Standard Key-Value Pairs ---
        # Before parsing, strip any inline comments and re-trim trailing whitespace.
        local clean_line="${trimmed_line%%#*}"
        clean_line="$(echo -E "$clean_line" | sed -e 's/[[:space:]]*$//')"

        # Check if the line looks like a KEY="VALUE" pair.
        if [[ "$clean_line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
            local key="${clean_line%%=*}"
            local value="${clean_line#*=}"

            # Remove potential surrounding quotes from the value.
            # This handles 'VALUE', "VALUE", and VALUE.
            # Using a Bash 3.2 compatible method.
            if [[ ${#value} -ge 2 ]]; then
                local first_char="${value:0:1}"
                local last_char="${value:${#value}-1}"
                if { [[ "$first_char" == '"' && "$last_char" == '"' ]] || \
                     [[ "$first_char" == "'" && "$last_char" == "'" ]]; }; then
                    # Remove the first and last character
                    value="${value:1:${#value}-2}"
                fi
            fi

            # Safely expand $HOME to the user's home directory path.
            # This avoids using 'eval'.
            if [[ "$value" == "\$HOME" ]]; then
                value="$HOME"
            elif [[ "$value" == "\$HOME/"* ]]; then
                value="$HOME/${value#\$HOME/}"
            elif [[ "$value" == "\$JELLYMAC_ROOT" ]]; then
                # JELLYMAC_PROJECT_ROOT is exported from the main script.
                value="$JELLYMAC_PROJECT_ROOT"
            elif [[ "$value" == "\$JELLYMAC_ROOT/"* ]]; then
                # JELLYMAC_PROJECT_ROOT is exported from the main script.
                value="$JELLYMAC_PROJECT_ROOT/${value#\$JELLYMAC_ROOT/}"
            fi
            
            # Export the variable to the environment, making it available
            # to the main script and any child processes it launches.
            export "$key=$value"
        fi
    done < "$config_file"

    # The YTDLP_OPTS, MAIN_MEDIA_EXTENSIONS, and ASSOCIATED_FILE_EXTENSIONS arrays
    # are now populated and will be available in the shell that sourced this script.
    # Note: Arrays cannot be exported to subshells in Bash, so child scripts must
    # source this parser directly to access the arrays.

    return 0
}
