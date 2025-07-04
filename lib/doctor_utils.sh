#!/bin/bash

# lib/doctor_utils.sh
# Contains utility functions specific to the JellyMac.sh watcher script,
# primarily for performing system health checks.
# This script should be sourced by JellyMac.sh AFTER
# logging_utils.sh, config_parser.sh, and common_utils.sh
# and SCRIPT_CURRENT_LOG_LEVEL is set.

# Ensure logging_utils.sh is sourced, as this script may use log_*_event functions
if ! command -v log_debug_event &>/dev/null; then # Using log_debug_event as a representative function
    _DOCTOR_UTILS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    if [[ -f "${_DOCTOR_UTILS_LIB_DIR}/logging_utils.sh" ]]; then
        # shellcheck source=logging_utils.sh
        # shellcheck disable=SC1091
        source "${_DOCTOR_UTILS_LIB_DIR}/logging_utils.sh"
    else
        # If logging_utils.sh is not found here, we rely on jellymac.sh having sourced it.
        # If not, log_*_event calls will fail, indicating a setup issue.
        echo "WARNING: doctor_utils.sh: logging_utils.sh not found at ${_DOCTOR_UTILS_LIB_DIR}/logging_utils.sh. Logging functions may be unavailable if not already sourced." >&2
    fi
    # If log_debug_event is still not found after this attempt, 
    # it implies a more significant issue with sourcing order or file availability,
    # which should be handled by the main script or result in command-not-found errors for log calls.
fi

# Function: normalize_user_response
# Description: Normalizes user input for yes/no prompts
# Parameters:
#   $1: user_response - The raw user input
# Returns: Echoes "yes", "no", or "invalid"
normalize_user_response() {
    local response="$1"
    
    # Convert to lowercase for easier matching
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    # Trim whitespace (basic approach for Bash 3.2)
    response=$(echo "$response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    case "$response" in
        ""|y|yes) echo "yes" ;;
        n|no) echo "no" ;;
        *) echo "invalid" ;;
    esac
}

# Function: install_missing_dependency
# Description: Checks if homebrew is available and installs missing dependencies
# Parameters:
#   $1: Package name to install
# Returns: 0 if dependency was installed, 1 if not
# Side Effects: May modify system by installing packages
install_missing_dependency() {
    local package_name="$1"
    local log_prefix="Doctor"
    
    # Early exit if auto-installation is disabled
    if [[ "${AUTO_INSTALL_DEPENDENCIES:-false}" != "true" ]]; then
        log_debug_event "$log_prefix" "Auto-install is disabled. Set AUTO_INSTALL_DEPENDENCIES=true in config to enable."
        return 1
    fi
    
    # Check if Homebrew is installed
    if ! command -v brew >/dev/null 2>&1; then
        log_warn_event "$log_prefix" "Homebrew not found. Cannot auto-install programs."
        log_warn_event "$log_prefix" "Please install Homebrew from https://brew.sh/ to enable auto-installation."
        return 1
    fi
    
    log_user_info "$log_prefix" "🍺 Auto-installing program: $package_name"
    
    # Attempt to install the package
    if brew install "$package_name"; then
        log_user_info "$log_prefix" "✅ Successfully installed: $package_name"
        return 0
    else
        log_error_event "$log_prefix" "❌ Failed to install: $package_name"
        return 1
    fi
}

# Define required dependencies for the application
# These will be checked during system health checks
REQUIRED_DEPENDENCIES=(
    "flock"
    "rsync"
    "curl"
)

# Define optional dependencies based on features enabled in config
# Will be populated during runtime in collect_missing_dependencies

# Function: install_missing_dependencies
# Description: Installs multiple missing dependencies at once
# Parameters:
#   $@: Array of package names to install
# Returns: 0 if all dependencies were installed, 1 if any failed
# Side Effects: May modify system by installing packages
install_missing_dependencies() {
    local deps=("$@")
    local all_succeeded=true
    
    for dep in "${deps[@]}"; do
        if ! install_missing_dependency "$dep"; then
            all_succeeded=false
        fi
    done
    
    if [[ "$all_succeeded" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Function: collect_missing_dependencies
# Description: Gathers a list of all missing dependencies based on enabled features
# Parameters: None
# Returns: Echoes names of missing dependencies, one per line
# Side Effects: None
collect_missing_dependencies() {
    local missing_deps=()
    local log_prefix="Doctor" # Added for consistency if any logging is needed here
    
    # Check core dependencies
    for dep in "${REQUIRED_DEPENDENCIES[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps[${#missing_deps[@]}]="$dep"
        fi
    done
    
    # Check feature-specific dependencies
    if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" ]]; then
        if ! command -v "yt-dlp" >/dev/null 2>&1; then
            missing_deps[${#missing_deps[@]}]="yt-dlp"
        fi
        # Add ffmpeg as a dependency if YouTube downloads are enabled
        if ! command -v "ffmpeg" >/dev/null 2>&1; then
            missing_deps[${#missing_deps[@]}]="ffmpeg"
        fi
    fi
    
    if [[ "${ENABLE_TORRENT_AUTOMATION:-false}" == "true" ]]; then
        local torrent_client_exe
        torrent_client_exe=$(basename "${TORRENT_CLIENT_CLI_PATH:-transmission-remote}")
        
        if [[ ! -x "${TORRENT_CLIENT_CLI_PATH:-}" ]] && ! command -v "$torrent_client_exe" >/dev/null 2>&1; then
            missing_deps[${#missing_deps[@]}]="transmission-cli"
        fi
    fi
    
    # Return the collected missing dependencies
    for dep in "${missing_deps[@]}"; do
        echo "$dep"
    done
}

# Function: enable_auto_install_and_install_deps
# Description: Updates config to enable AUTO_INSTALL_DEPENDENCIES and installs missing programs
# Parameters: $@: Array of missing dependency names
# Returns: 0 if successful, 1 if failed
enable_auto_install_and_install_deps() {
    local missing_deps=("$@")
    local log_prefix="Doctor"
    
    log_user_info "$log_prefix" "Enabling automatic program installation..."
    
    # The main jellymac.sh script must export JELLYMAC_PROJECT_ROOT for this to work.
    if [[ -z "$JELLYMAC_PROJECT_ROOT" ]]; then
        log_error_event "$log_prefix" "CRITICAL: JELLYMAC_PROJECT_ROOT is not set. Cannot find config file."
        return 1
    fi
    local config_file="${JELLYMAC_PROJECT_ROOT}/Configuration.txt"
    
    log_user_info "$log_prefix" "Attempting to update config file: '$config_file'"

    if [[ -f "$config_file" && -w "$config_file" ]]; then
        # Create a backup of the config file first
        cp "$config_file" "${config_file}.bak"
        log_debug_event "$log_prefix" "Created backup of config file: '${config_file}.bak'"
        
        # Use macOS-compatible sed syntax to change 'false' to 'true'.
        # This pattern handles potential whitespace around the equals sign.
        local sed_pattern='s/^[[:space:]]*AUTO_INSTALL_DEPENDENCIES[[:space:]]*=[[:space:]]*"false".*/AUTO_INSTALL_DEPENDENCIES="true"/'
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "$sed_pattern" "$config_file"
        else
            # Linux/other systems
            sed -i "$sed_pattern" "$config_file"
        fi
        
        # Verify that the change was successful
        if grep -q '^[[:space:]]*AUTO_INSTALL_DEPENDENCIES[[:space:]]*=[[:space:]]*"true"' "$config_file"; then
            log_user_success "$log_prefix" "✅ Config updated: AUTO_INSTALL_DEPENDENCIES set to true."
        else
            log_error_event "$log_prefix" "❌ Failed to update AUTO_INSTALL_DEPENDENCIES in '$config_file'."
            log_user_info "$log_prefix" "The script will proceed with installation for this session, but the setting was not saved."
        fi
        
        echo # For spacing in terminal output
        
        # Try installation with new setting
        AUTO_INSTALL_DEPENDENCIES="true"
        install_missing_dependencies "${missing_deps[@]}"
        local install_status=$?
        
        if [[ $install_status -eq 0 ]]; then
            echo
            log_user_success "$log_prefix" "✅ Successfully installed all programs!"
            log_user_info "$log_prefix" "JellyMac will now continue with startup..."
            log_user_info "$log_prefix" "In the future, any missing programs will be installed automatically."
            sleep 2
        fi
        
        return $install_status
    else
        log_error_event "$log_prefix" "❌ Could not update config file '$config_file'. File not found or not writable."
        log_user_info "$log_prefix" "Please ensure '$config_file' exists, has write permissions, and then set AUTO_INSTALL_DEPENDENCIES=\"true\" manually."
        return 1
    fi
}

# Function: handle_missing_dependencies_interactively
# Description: Presents user with options for installing missing dependencies
# Parameters:
#   $@: Array of missing dependency names
# Returns: 0 on success, 1 on failure or user chose to exit
# Side Effects: May modify system by installing packages or updating config
handle_missing_dependencies_interactively() {
    local missing_deps=("$@")
    local missing_count=${#missing_deps[@]}
    local log_prefix="Doctor" # Define log_prefix for this function

    if [[ $missing_count -eq 0 ]]; then
        return 0  # No missing dependencies
    fi
    
    # Clear screen for better presentation
    clear
    
    # Print welcome header with colorful border
    echo -e "\033[36m+----------------------------------------------------+\033[0m"
    echo -e "\033[36m|\033[0m       \033[1m\033[33mWelcome to JellyMac - First Time Setup\033[0m       \033[36m|\033[0m"
    echo -e "\033[36m+----------------------------------------------------+\033[0m"
    echo
    echo -e "We noticed this is your first time running JellyMac."
    echo -e "Before we can start automating your media library, we need to set up a few things."
    echo
    echo -e "Missing Programs:"
    
    # Print each missing dependency with package info
    for ((i=0; i<${#missing_deps[@]}; i++)); do
        local dep="${missing_deps[$i]}"
        echo "  • $dep"
    done
    
    echo
    echo -e "These helper programs are needed for JellyMac to work properly with your media files."
    echo
    
    # Present options
    echo -e "\033[1mHow would you like to proceed?\033[0m"
    echo -e "  \033[32m1)\033[0m Install missing programs now (just this once)"
    echo -e "  \033[32m2)\033[0m Auto-install programs now and future runs (recommended) \033[33m[DEFAULT]\033[0m"
    echo -e "  \033[32m3)\033[0m Skip and continue anyway (some features may not work)"
    echo -e "  \033[32m4)\033[0m Exit and read the Getting Started guide first"
    echo
    
    # Get user input with flexible handling
    local selection
    read -r -p "Select an option [1-4] (2): " selection
    
    # Normalize the response - empty string defaults to "2"
    case "$(echo "${selection:-2}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" in
        1|one)  # Install dependencies now (one-time)
            echo "Installing programs for this run only..."
            AUTO_INSTALL_DEPENDENCIES="true"
            install_missing_dependencies "${missing_deps[@]}"
            local install_status=$?
            AUTO_INSTALL_DEPENDENCIES="false"  # Reset to false after this run
            
            if [[ $install_status -eq 0 ]]; then
                echo
                echo -e "\033[32m✓\033[0m Successfully installed all programs!"
                echo "JellyMac will now continue with startup..."
                echo
                sleep 2
            fi
            
            return $install_status
            ;;
            
        ""|2|two)  # Enable automatic installation (permanent) - DEFAULT
            enable_auto_install_and_install_deps "${missing_deps[@]}"
            return $?
            ;;
            
        3|three)  # Skip and continue
            log_user_info "$log_prefix" "⚠️  Continuing without required programs. Some features may not work correctly."
            echo "You can install the missing programs later by running:"
            echo "  brew install ${missing_deps[*]}"
            echo
            sleep 2
            return 0
            ;;
            
        4|four)  # Exit and read guide
            log_user_info "$log_prefix" "Exiting JellyMac setup."
            echo
            echo "To get started, please read the Getting Started guide:"
            echo -e "  \033[36m$JELLYMAC_PROJECT_ROOT/Getting_Started.txt\033[0m"
            echo
            echo "This guide will walk you through:"
            echo "  • Setting up all required programs for JellyMac to work properly"
            echo "  • Configuring your media folders"
            echo "  • Connecting to your Jellyfin server"
            echo "  • And more!"
            echo
            echo "Once you're ready, run ./jellymac.sh again to start the setup."
            echo
            exit 1
            ;;
            
        *)  # Invalid selection - default to option 2
            log_user_info "$log_prefix" "Invalid selection. Defaulting to option 2 (recommended)."
            enable_auto_install_and_install_deps "${missing_deps[@]}"
            return $?
            ;;
    esac
}

# Improved volume checking function
is_volume_mounted() {
    local path="$1"
    local volume_name
    
    # Extract volume name from path (/Volumes/VOLUMENAME/...)
    if [[ "$path" =~ ^/Volumes/([^/]+) ]]; then
        volume_name="${BASH_REMATCH[1]}"
        if [[ -d "/Volumes/$volume_name" ]]; then
            return 0 # Volume is mounted
        else
            return 1 # Volume is not mounted
        fi
    fi
    # Not a /Volumes path
    return 0 
}

# Function: validate_config_filepaths
# Description: Checks if essential directories exist and are writable
# Parameters: None
# Returns:
#   0 if all validations pass
#   1 if any validation fails
# Side Effects: May create directories if AUTO_CREATE_MISSING_DIRS is true

validate_config_filepaths() {
    local log_prefix="Doctor"
    log_debug_event "$log_prefix" "🔍 Validating configuration filepaths, this may take a moment..."
    local validation_failed=false
    local first_run_setup=false # Renamed from IS_FIRST_RUN to be local to this function's scope
    
    # --- Required Directories ---
    # These must exist for the system to function
    local required_dirs=(
        "$DROP_FOLDER"              "Drop folder for media scanning"
        "$DEST_DIR_MOVIES"          "Destination folder for movies"
        "$DEST_DIR_SHOWS"           "Destination folder for TV shows"
        "$ERROR_DIR"                "Error/quarantine folder for problematic files"
        # STATE_DIR is checked separately as it's crucial for script operation itself
    )

    # Add Transmission incomplete sub-directory within JELLYMAC_PROJECT_ROOT if torrent automation is enabled
    # This directory will be created if it doesn't exist.
    if [[ "${ENABLE_TORRENT_AUTOMATION:-false}" == "true" ]]; then
        # Ensure JELLYMAC_PROJECT_ROOT is set (should be exported by main script)
        if [[ -z "$JELLYMAC_PROJECT_ROOT" ]]; then
            log_fatal_event "$log_prefix" "JELLYMAC_PROJECT_ROOT is not set. Cannot determine path for incomplete torrents."
            # This is a critical internal error, main script should handle JELLYMAC_PROJECT_ROOT
            # For safety, mark validation as failed.
            validation_failed=true
        else
            local project_incomplete_dir="${JELLYMAC_PROJECT_ROOT}/_incomplete_torrents"
            if [[ ! -d "$project_incomplete_dir" ]]; then
                if [[ "${AUTO_CREATE_MISSING_DIRS:-false}" == "true" ]]; then
                    log_user_info "$log_prefix" "Creating Transmission incomplete directory: $project_incomplete_dir"
                    if ! mkdir -p "$project_incomplete_dir"; then
                        log_error_event "$log_prefix" "❌ Failed to create Transmission incomplete directory: $project_incomplete_dir"
                        log_error_event "$log_prefix" "Please check permissions or create it manually."
                        validation_failed=true
                    else
                        log_user_info "$log_prefix" "✅ Created Transmission incomplete directory: $project_incomplete_dir"
                    fi
                else
                    log_warn_event "$log_prefix" "⚠️ Transmission incomplete directory does not exist: $project_incomplete_dir"
                    log_warn_event "$log_prefix" "   Enable AUTO_CREATE_MISSING_DIRS in config or create it manually."
                    # For first run, offer to create it
                    # IS_FIRST_RUN is a global variable set by jellymac.sh
                    if [[ "${IS_FIRST_RUN:-false}" == "true" ]] && [[ "${AUTO_INSTALL_DEPENDENCIES:-false}" != "true" ]]; then # Avoid double prompt if auto-install is on
                        echo
                        echo -e "\\033[1mThe Transmission incomplete directory is missing:\\033[0m"
                        echo -e "  \\033[36m$project_incomplete_dir\\033[0m"
                        echo
                        local create_response
                        read -r -p "Create this directory now? (Y/n, default: Y): " create_response
                        local normalized_create_response
                        normalized_create_response=$(normalize_user_response "$create_response")

                        if [[ "$normalized_create_response" == "yes" ]]; then
                            log_user_info "$log_prefix" "Creating Transmission incomplete directory: $project_incomplete_dir"
                            if ! mkdir -p "$project_incomplete_dir"; then
                                log_error_event "$log_prefix" "❌ Failed to create Transmission incomplete directory: $project_incomplete_dir"
                                validation_failed=true
                            else
                                log_user_info "$log_prefix" "✅ Created Transmission incomplete directory: $project_incomplete_dir"
                            fi
                        else
                            log_warn_event "$log_prefix" "User declined to create Transmission incomplete directory. Torrent automation may fail."
                            validation_failed=true # Treat as failure if user declines essential dir creation
                        fi
                    elif [[ "${IS_FIRST_RUN:-false}" != "true" ]]; then # Not first run, and auto-create is off
                         validation_failed=true
                    fi
                fi
            elif [[ ! -w "$project_incomplete_dir" ]]; then
                log_error_event "$log_prefix" "❌ Transmission incomplete directory is not writable: $project_incomplete_dir"
                validation_failed=true
            else
                log_debug_event "$log_prefix" "✅ Transmission incomplete directory exists and is writable: $project_incomplete_dir"
            fi
        fi
    fi
    
    # --- Optional Directories ---
    # These can be empty or missing, but if specified must be valid
    local optional_dirs=(
        "${DEST_DIR_YOUTUBE:-}"     "Destination folder for YouTube downloads (optional)"
    )
    
    # Check if this appears to be a first-time setup
    local missing_required_count=0
    for ((i=0; i<${#required_dirs[@]}; i+=2)); do
        local dir="${required_dirs[i]}"
        if [[ -n "$dir" && ! -d "$dir" ]]; then
            ((missing_required_count++))
        fi
    done
    
    # If multiple required dirs are missing, this is likely first-time setup
    if [[ $missing_required_count -ge 2 ]]; then
        first_run_setup=true
        echo
        log_user_info "$log_prefix" "🏗️  Setting up your media folders for the first time..."
        echo "Creating the following folders for your media library:"
    fi
    
    # Check each required directory
    for ((i=0; i<${#required_dirs[@]}; i+=2)); do
        local dir="${required_dirs[i]}"
        local description="${required_dirs[i+1]}"
        
        if [[ -z "$dir" ]]; then
            log_error_event "$log_prefix" "❌ Required folder path is empty: $description"
            log_user_info "$log_prefix" "Please set this path in your Configuration.txt file."
            validation_failed=true
            continue
        fi
        
        # Check if this is a path on a volume that needs mounting
        if [[ "$dir" == /Volumes/* ]] && ! is_volume_mounted "$dir"; then
            local volume_name
            [[ "$dir" =~ ^/Volumes/([^/]+) ]] && volume_name="${BASH_REMATCH[1]}"
            log_error_event "$log_prefix" "❌ Network folder '$volume_name' is not connected for: $dir ($description)"
            log_user_info "$log_prefix" "To connect: Open Finder → Go menu → Connect to Server (⌘K)"
            log_user_info "$log_prefix" "Or check if '$volume_name' appears in Finder's sidebar under 'Network'."
            validation_failed=true
            continue
        fi
        
        if [[ ! -d "$dir" ]]; then
            # Only attempt to create directories if NOT in /Volumes or if volume is mounted
            if [[ "$dir" != "/Volumes/"* ]] || is_volume_mounted "$dir"; then
                if [[ "${AUTO_CREATE_MISSING_DIRS:-false}" == "true" ]]; then
                    if [[ "$first_run_setup" == "true" ]]; then
                        log_user_info "$log_prefix" "  📁 $dir"
                    else
                        log_user_info "$log_prefix" "Creating folder: $dir ($description)"
                    fi
                    
                    if ! mkdir -p "$dir"; then
                        log_error_event "$log_prefix" "❌ Could not create folder: $dir"
                        if [[ "$dir" == /Volumes/* ]]; then
                            log_user_info "$log_prefix" "This might be due to permission settings on the network folder."
                            log_user_info "$log_prefix" "Try creating the folder manually in Finder first."
                        else
                            log_user_info "$log_prefix" "This might happen if:"
                            log_user_info "$log_prefix" "  • You don't have permission to create folders here"
                            log_user_info "$log_prefix" "  • The parent folder doesn't exist"
                            log_user_info "$log_prefix" "Try creating the folder manually in Finder first."
                        fi
                        validation_failed=true
                    fi
                else
                    log_error_event "$log_prefix" "❌ Folder does not exist: $dir ($description)"
                    log_user_info "$log_prefix" "Create this folder manually in Finder or set AUTO_CREATE_MISSING_DIRS=true in config."
                    validation_failed=true
                fi
            fi
        elif [[ ! -w "$dir" ]]; then
            log_error_event "$log_prefix" "❌ folder is not writable: $dir ($description)"
            log_user_info "$log_prefix" "Please check permissions on this folder."
            validation_failed=true
        fi
    done
    
    # Show completion message for first-run setup
    if [[ "$first_run_setup" == "true" && "$validation_failed" == "false" ]]; then
        echo
        log_user_info "$log_prefix" "✅ Media folders created successfully!"
    fi
    
    # Check each optional directory (only if they're specified)
    for ((i=0; i<${#optional_dirs[@]}; i+=2)); do
        local dir="${optional_dirs[i]}"
        local description="${optional_dirs[i+1]}"
        
        # Skip empty optional paths
        if [[ -z "$dir" ]]; then
            log_debug_event "$log_prefix" "Optional folder not configured: $description"
            continue
        fi
        
        # Check if this is a path on a volume that needs mounting
        if [[ "$dir" == /Volumes/* ]] && ! is_volume_mounted "$dir"; then
            local volume_name
            [[ "$dir" =~ ^/Volumes/([^/]+) ]] && volume_name="${BASH_REMATCH[1]}"
            log_user_info "$log_prefix" "💡 Network folder '$volume_name' is not connected for optional feature: $dir ($description)"
            log_user_info "$log_prefix" "Connect '$volume_name' in Finder if you want to use this feature."
            # Don't mark as failure for optional dirs, just inform
            continue
        fi
        
        if [[ ! -d "$dir" ]]; then
            # Only attempt to create directories if NOT in /Volumes or if volume is mounted
            if ! [[ "$dir" =~ ^/Volumes/ ]] || is_volume_mounted "$dir"; then
                if [[ "${AUTO_CREATE_MISSING_DIRS:-false}" == "true" ]]; then
                    log_user_info "$log_prefix" "Creating optional folder: $dir ($description)"
                    if ! mkdir -p "$dir"; then
                        log_error_event "$log_prefix" "❌ Failed to create optional folder: $dir"
                        if [[ "$dir" == /Volumes/* ]]; then
                            log_user_info "$log_prefix" "This may be due to permissions on the network folder. Check the folder's access rights."
                        fi
                        validation_failed=true
                    fi
                else
                    log_user_info "$log_prefix" "💡 Optional folder does not exist: $dir ($description)"
                    log_user_info "$log_prefix" "Create this folder manually or set AUTO_CREATE_MISSING_DIRS=true in config."
                    # Don't mark as failure for optional dirs
                fi
            fi
        elif [[ ! -w "$dir" ]]; then
            log_error_event "$log_prefix" "❌ Optional folder is not writable: $dir ($description)"
            log_user_info "$log_prefix" "Please check permissions on this folder."
            validation_failed=true
        fi
    done
    
    # Final validation result
    if [[ "$validation_failed" == "true" ]]; then
        log_error_event "$log_prefix" "❌ Configuration validation failed. Please fix the issues above."
        return 1
    else
        log_debug_event "$log_prefix" "✅ All configuration filepaths validated successfully."
        return 0
    fi
}

# Function: check_transmission_daemon
# Description: Tests if the Transmission daemon is running and responsive
# Parameters: None
# Returns:
#   0 if daemon is running or magnet handling is disabled
#   1 if daemon is not running and magnet handling is enabled
check_transmission_daemon() {
    local log_prefix="Doctor"
    
    # Skip check if magnet handling is disabled
    if [[ "${ENABLE_CLIPBOARD_MAGNET:-false}" != "true" ]]; then
        return 0
    fi
    
    local transmission_cli="${TORRENT_CLIENT_CLI_PATH:-transmission-remote}"
    local transmission_host="${TRANSMISSION_REMOTE_HOST:-localhost:9091}"
    
    log_debug_event "$log_prefix" "Checking if Transmission background service is running..."
    
    # Try to connect to Transmission daemon
    if ! "$transmission_cli" "$transmission_host" --list >/dev/null 2>&1; then
        log_warn_event "$log_prefix" "⚠️ Transmission background service appears to be offline."
        
        # Verify that transmission is actually installed before offering to enable it
        if command -v transmission-daemon >/dev/null 2>&1 || brew list transmission >/dev/null 2>&1; then
            offer_transmission_service_enablement
            return $?
        else
            log_user_info "$log_prefix" "Transmission not found. Install with: brew install transmission"
            log_user_info "$log_prefix" "Magnet link handling will be unavailable until Transmission is installed and running."
            return 1
        fi
    else
        log_debug_event "$log_prefix" "✅ Transmission background service is running and accessible."
        return 0
    fi
}

# Function: offer_transmission_service_enablement
# Description: Interactively prompts the user to enable Transmission service
# Parameters: None
# Returns:
#   0 if service was successfully started or user declined
#   1 if service failed to start
# Side Effects: May start Transmission service
offer_transmission_service_enablement() {
    local log_prefix="Doctor"
    # JELLYMAC_PROJECT_ROOT should be set and exported by the main script
    local project_incomplete_dir_display="${JELLYMAC_PROJECT_ROOT:-./}/_incomplete_torrents" # For display
    
    echo
    echo -e "\\033[33m⚠️  Transmission background service is not running\\033[0m"
    echo "Magnet link handling requires the Transmission background service to be active."
    echo
    echo -e "\\033[1mWould you like to enable Transmission as a background service?\\033[0m"
    echo "This will allow Transmission to start automatically on login."
    echo
    
    # Get user input with flexible handling
    local response
    read -r -p "Enable Transmission service? (Y/n): " response
    
    # Use our normalize_user_response function
    local normalized_response
    normalized_response=$(normalize_user_response "$response")
    
    case "$normalized_response" in
        "yes")
            log_user_info "$log_prefix" "🚀 Starting Transmission as a background service..."
            
            # Start the service
            if brew services start transmission; then
                log_user_info "$log_prefix" "✅ Transmission service started successfully"
                echo -e "\033[32m✓\033[0m Transmission service has been started and will run automatically on login."
                echo -e "\033[33m!\033[0m Note: You can manage the service with 'brew services stop transmission' if needed."
                log_user_info "$log_prefix" "Waiting 5 seconds for service to initialize..."
                sleep 5
                
                # Verify it's actually running now
                local transmission_cli="${TORRENT_CLIENT_CLI_PATH:-transmission-remote}"
                local transmission_host="${TRANSMISSION_REMOTE_HOST:-localhost:9091}"
                
                # Give it a moment to fully initialize
                sleep 2
                
                if "$transmission_cli" "$transmission_host" --list >/dev/null 2>&1; then
                    log_user_info "$log_prefix" "✅ Transmission background service is now accessible"
                    
                    # NEW: Offer automatic configuration
                    echo
                    echo -e "\\033[1m🎯 Complete Full Automation Setup\\033[0m"
                    echo "Configure Transmission to use a temporary download folder and move"
                    echo "completed torrents to your JellyMac drop folder?"
                    echo
                    echo "This will set Transmission to:"
                    echo -e "  1. Download to temporary folder: \\033[36m${project_incomplete_dir_display}\\033[0m"
                    echo -e "  2. Move completed torrents to: \\033[36m$DROP_FOLDER\\033[0m"
                    echo
                    echo "This enables the complete automation chain:"
                    echo "  📋 Copy magnet link → 🌐 Transmission downloads → 📁 JellyMac organizes → 📺 Library updated"
                    echo
                    
                    # Get user input with flexible handling
                    local config_response
                    read -r -p "Auto-configure Transmission paths? (Y/n): " config_response
                    
                    local normalized_config_response # Use a different variable name
                    normalized_config_response=$(normalize_user_response "$config_response")
                    
                    case "$normalized_config_response" in # Use the new variable name
                        "yes")
                            log_user_info "$log_prefix" "🔧 Configuring Transmission paths..."
                            
                            if configure_transmission_download_paths; then # Ensure this function name is correct
                                echo
                                echo -e "\\033[32m🎉 Perfect! Full automation is now enabled!\\033[0m"
                                echo -e "\\033[32m✓\\033[0m Transmission will download to: ${project_incomplete_dir_display}"
                                echo -e "\\033[32m✓\\033[0m Completed torrents moved to: $DROP_FOLDER"
                                echo -e "\\033[32m✓\\033[0m Your media library will be updated automatically"
                                echo
                                echo "🚀 You can now copy magnet links and watch the magic happen!"
                                echo "   The Transmission web interface is available at: http://${transmission_host}"
                            else
                                echo
                                echo -e "\\033[33m⚠️  Auto-configuration failed. Let's set it up manually:\\033[0m"
                                # Fall back to manual instructions
                                provide_manual_transmission_setup
                            fi
                            ;;
                            
                        "no")
                            echo
                            log_user_info "$log_prefix" "Skipping automatic configuration."
                            echo "You can configure Transmission manually when ready:"
                            provide_manual_transmission_setup
                            ;;
                            
                        "invalid")
                            log_user_info "$log_prefix" "Invalid response. Defaulting to 'yes' (recommended)."
                            log_user_info "$log_prefix" "🔧 Configuring Transmission paths..."
                            
                            if configure_transmission_download_paths; then # Ensure this function name is correct
                                echo
                                echo -e "\\033[32m🎉 Perfect! Full automation is now enabled!\\033[0m"
                                echo -e "\\033[32m✓\\033[0m Transmission will download to: ${project_incomplete_dir_display}"
                                echo -e "\\033[32m✓\\033[0m Completed torrents moved to: $DROP_FOLDER"
                                echo -e "\\033[32m✓\\033[0m Your media library will be updated automatically"
                                echo
                                echo "🚀 You can now copy magnet links and watch the magic happen!"
                                echo "   The Transmission web interface is available at: http://${transmission_host}"
                            else
                                echo
                                echo -e "\\033[33m⚠️  Auto-configuration failed. Let's set it up manually:\\033[0m"
                                # Fall back to manual instructions
                                provide_manual_transmission_setup
                            fi
                            ;;
                    esac
                    
                    return 0
                else
                    log_warn_event "$log_prefix" "⚠️ Transmission service started but background service is still not accessible"
                    echo -e "\033[33m⚠️  Transmission service was started but may need more time to initialize\033[0m"
                    echo "Please check its status manually in a few moments."
                    return 1
                fi
            else
                log_error_event "$log_prefix" "❌ Failed to start Transmission service"
                echo -e "\033[31m✗\033[0m Failed to start Transmission service. Please try manually:"
                echo "  brew services start transmission"
                return 1
            fi
            ;;
            
        "no"|"invalid")  # Handle both explicit "no" and invalid input
            if [[ "$normalized_response" == "invalid" ]]; then
                log_user_info "$log_prefix" "Invalid response. Defaulting to 'no'."
            fi
            log_user_info "$log_prefix" "User declined to start Transmission service"
            log_warn_event "$log_prefix" "⚠️ Magnet link handling will be unavailable until Transmission is running"
            log_user_info "$log_prefix" "You can start it manually later with: brew services start transmission"
            echo
            log_user_info "$log_prefix" "💡 When you do start Transmission, you can enable full automation by:"
            provide_manual_transmission_setup
            return 1
            ;;
    esac
}


# Function: configure_transmission_download_paths
# Description: Configures Transmission download directory, incomplete directory, and enables it.
# Parameters: None (relies on global config var: DROP_FOLDER and JELLYMAC_PROJECT_ROOT)
# Returns:
#   0 if configuration succeeded
#   1 if configuration failed
configure_transmission_download_paths() {
    local log_prefix="Doctor"
    
    if [[ -z "$JELLYMAC_PROJECT_ROOT" ]]; then
        log_fatal_event "$log_prefix" "JELLYMAC_PROJECT_ROOT is not set. Cannot configure Transmission paths."
        return 1
    fi
    local incomplete_dir_path="${JELLYMAC_PROJECT_ROOT}/_incomplete_torrents"
    local completed_dir="$DROP_FOLDER"

    # Ensure the project-based incomplete directory exists
    if [[ ! -d "$incomplete_dir_path" ]]; then
        log_user_info "$log_prefix" "Creating Transmission incomplete directory: $incomplete_dir_path"
        if ! mkdir -p "$incomplete_dir_path"; then
            log_error_event "$log_prefix" "❌ Failed to create Transmission incomplete directory: $incomplete_dir_path. Please check permissions."
            return 1
        fi
    fi

    log_debug_event "$log_prefix" "🔧 Configuring Transmission paths:"
    log_debug_event "$log_prefix" "   Incomplete Dir Enabled: true"
    log_debug_event "$log_prefix" "   Incomplete Dir Path: $incomplete_dir_path"
    log_debug_event "$log_prefix" "   Completed Dir Path (Download Dir): $completed_dir"
    
    # Build transmission-remote command using existing config variables
    local transmission_cli="${TORRENT_CLIENT_CLI_PATH:-transmission-remote}"
    local transmission_host="${TRANSMISSION_REMOTE_HOST:-localhost:9091}"
    
    # Log Transmission version and connectivity
    log_debug_event "$log_prefix" "Transmission version: $($transmission_cli --version 2>&1)"
    log_debug_event "$log_prefix" "Testing connectivity with: $transmission_cli $transmission_host --list"
    local output
    output=$("$transmission_cli" "$transmission_host" --list 2>&1)
    log_debug_event "$log_prefix" "Connectivity output: $output"
    
    # Base command arguments array
    declare -a cmd_args_base=("$transmission_host")
    [[ -n "$TRANSMISSION_REMOTE_AUTH" ]] && cmd_args_base+=("--auth" "$TRANSMISSION_REMOTE_AUTH")

    local success=true

    # 1. Enable incomplete directory feature (remove --boolean)
    log_debug_event "$log_prefix" "Running: $transmission_cli ${cmd_args_base[*]} --session-set incomplete-dir-enabled true"
    output=$("$transmission_cli" "${cmd_args_base[@]}" --session-set incomplete-dir-enabled true 2>&1)
    local exit_code=$?
    log_debug_event "$log_prefix" "Output: $output"
    log_debug_event "$log_prefix" "Exit code: $exit_code"
    if ! "$transmission_cli" "${cmd_args_base[@]}" --session-set incomplete-dir-enabled true >/dev/null 2>&1; then
        log_error_event "$log_prefix" "❌ Failed to enable Transmission incomplete directory feature."
        success=false
    else
        log_debug_event "$log_prefix" "✅ Enabled Transmission incomplete directory feature."
    fi

    # 2. Set incomplete directory path (this one is correct)
    if [[ "$success" == "true" ]]; then
        log_debug_event "$log_prefix" "Running: $transmission_cli ${cmd_args_base[*]} --session-set incomplete-dir \"$incomplete_dir_path\""
        output=$("$transmission_cli" "${cmd_args_base[@]}" --session-set incomplete-dir "$incomplete_dir_path" 2>&1)
        exit_code=$?
        log_debug_event "$log_prefix" "Output: $output"
        log_debug_event "$log_prefix" "Exit code: $exit_code"
        if ! "$transmission_cli" "${cmd_args_base[@]}" --session-set incomplete-dir "$incomplete_dir_path" >/dev/null 2>&1; then
            log_error_event "$log_prefix" "❌ Failed to set Transmission incomplete directory to: $incomplete_dir_path"
            success=false
        else
            log_debug_event "$log_prefix" "✅ Set Transmission incomplete directory to: $incomplete_dir_path"
        fi
    fi

    # 3. Set download directory (this one is correct)
    if [[ "$success" == "true" ]]; then
        log_debug_event "$log_prefix" "Running: $transmission_cli ${cmd_args_base[*]} --session-set download-dir \"$completed_dir\""
        output=$("$transmission_cli" "${cmd_args_base[@]}" --session-set download-dir "$completed_dir" 2>&1)
        exit_code=$?
        log_debug_event "$log_prefix" "Output: $output"
        log_debug_event "$log_prefix" "Exit code: $exit_code"
        if ! "$transmission_cli" "${cmd_args_base[@]}" --session-set download-dir "$completed_dir" >/dev/null 2>&1; then
            log_error_event "$log_prefix" "❌ Failed to set Transmission download (completed) directory to: $completed_dir"
            success=false
        else
            log_debug_event "$log_prefix" "✅ Set Transmission download (completed) directory to: $completed_dir"
        fi
    fi
    
    # 4. Enable seeding ratio limit (add this)
    if [[ "$success" == "true" ]]; then
        log_debug_event "$log_prefix" "Running: $transmission_cli ${cmd_args_base[*]} --session-set ratio-limit-enabled true"
        output=$("$transmission_cli" "${cmd_args_base[@]}" --session-set ratio-limit-enabled true 2>&1)
        exit_code=$?
        log_debug_event "$log_prefix" "Output: $output"
        log_debug_event "$log_prefix" "Exit code: $exit_code"
        if ! "$transmission_cli" "${cmd_args_base[@]}" --session-set ratio-limit-enabled true >/dev/null 2>&1; then
            log_error_event "$log_prefix" "❌ Failed to enable Transmission seeding ratio limit."
            success=false
        else
            log_debug_event "$log_prefix" "✅ Enabled Transmission seeding ratio limit."
        fi
    fi
    
    # 5. Set seeding ratio to 0 (add this)
    if [[ "$success" == "true" ]]; then
        log_debug_event "$log_prefix" "Running: $transmission_cli ${cmd_args_base[*]} --session-set ratio-limit 0"
        output=$("$transmission_cli" "${cmd_args_base[@]}" --session-set ratio-limit 0 2>&1)
        exit_code=$?
        log_debug_event "$log_prefix" "Output: $output"
        log_debug_event "$log_prefix" "Exit code: $exit_code"
        if ! "$transmission_cli" "${cmd_args_base[@]}" --session-set ratio-limit 0 >/dev/null 2>&1; then
            log_error_event "$log_prefix" "❌ Failed to set Transmission seeding ratio to 0."
            success=false
        else
            log_debug_event "$log_prefix" "✅ Set Transmission seeding ratio to 0."
        fi
    fi
    
    if [[ "$success" == "true" ]]; then
        log_debug_event "$log_prefix" "✅ Successfully configured all Transmission paths."
        return 0
    else
        log_error_event "$log_prefix" "❌ Failed to configure all Transmission paths."
        return 1
    fi
}

# Function: provide_manual_transmission_setup
# Description: Provides manual Transmission configuration instructions
# Parameters: None
# Returns: None
provide_manual_transmission_setup() {
    local log_prefix="Doctor"
    local web_portal_url="http://${TRANSMISSION_REMOTE_HOST:-localhost:9091}"
    # JELLYMAC_PROJECT_ROOT should be set and exported by the main script
    local project_incomplete_dir_manual="${JELLYMAC_PROJECT_ROOT:-./}/_incomplete_torrents" # For display
    
    echo
    log_user_info "$log_prefix" "⚙️ Manual Transmission Configuration for Full Automation:"
    log_user_info "$log_prefix" "   1. Open Transmission: ${web_portal_url}"
    log_user_info "$log_prefix" "   2. Click the hamburger menu (≡) at the top right, then 'Edit Preferences'."
    log_user_info "$log_prefix" "   3. Go to the 'Downloads' tab."
    log_user_info "$log_prefix" "   4. Check 'Keep incomplete torrents in:'"
    log_user_info "$log_prefix" "      Set path to: ${project_incomplete_dir_manual}"
    log_user_info "$log_prefix" "   5. Set 'Download to:' (this is where completed torrents go)"
    log_user_info "$log_prefix" "      Set path to: ${DROP_FOLDER}"
    log_user_info "$log_prefix" "   6. Save and close - you're all set!"
    echo
    log_user_info "$log_prefix" "Once configured, magnet links will be fully automated."
}

# Function: offer_iina_installation_and_default
# Description: Offers to install IINA and set it as default for .mkv/.mp4.
#              Defaults to "No" for the installation prompt.
# Parameters: None
# Returns: 0 (always, as this is an optional setup step)
# Side Effects: May install IINA, duti, and change default app associations if user opts in.
offer_iina_installation_and_default() {
    local log_prefix="Doctor"

    if [[ "$(uname)" != "Darwin" ]]; then
        log_debug_event "$log_prefix" "Skipping IINA offer, not on macOS."
        return 0
    fi

    # Check if this step has been completed before
    if [[ -f "${STATE_DIR}/.iina_setup_offered" ]]; then
        log_debug_event "$log_prefix" "IINA setup/offer has been processed in a previous session. Skipping."
        return 0
    fi

    echo # Add some spacing before this new section
    log_user_info "$log_prefix" "🎬 Optional: Enhance Your Media Playback on macOS"
    echo
    echo "QuickTime Player, the default macOS video player, has limitations with many"
    echo "modern video formats like HEVC (common in high-quality .mp4 files) and containers"
    echo "like .mkv (often used for movies and TV shows)."
    echo
    echo "IINA is a free, open-source, and powerful media player for macOS that supports"
    echo "a much wider range of video formats and codecs out-of-the-box."
    echo
    echo -e "\033[1mWould you like to install IINA and set it as the default player for .mkv and .mp4 files?\033[0m"
    echo "(This uses Homebrew: 'brew install --cask iina' and 'brew install duti')"
    
    local response
    read -r -p "Install IINA and set as default? (y/N): " response # Default to No
    local normalized_response
    normalized_response=$(normalize_user_response "$response") # "" will be "yes" due to normalize_user_response, so we handle "" explicitly

    if [[ -z "$response" ]]; then # If user just presses Enter, treat as "no"
        normalized_response="no"
    fi

    case "$normalized_response" in
        "yes")
            log_user_info "$log_prefix" "🚀 Proceeding with IINA installation and setup..."

            # Install IINA
            if brew list --cask iina &>/dev/null; then
                log_user_info "$log_prefix" "IINA media player is already installed."
            else
                log_user_info "$log_prefix" "Installing IINA media player (brew install --cask iina)..."
                if brew install --cask iina; then
                    log_user_info "$log_prefix" "✅ Successfully installed IINA."
                else
                    log_error_event "$log_prefix" "❌ Failed to install IINA. Skipping default player setup."
                    touch "${STATE_DIR}/.iina_setup_offered" # Mark as offered
                    return 0
                fi
            fi

            # Install duti (for setting default apps)
            if command -v duti &>/dev/null; then
                log_debug_event "$log_prefix" "'duti' utility is already installed."
            else
                log_user_info "$log_prefix" "'duti' utility not found. Attempting to install (brew install duti)..."
                if brew install duti; then
                    log_user_info "$log_prefix" "✅ Successfully installed 'duti'."
                else
                    log_error_event "$log_prefix" "❌ Failed to install 'duti'. Cannot set default applications automatically."
                    log_user_info "$log_prefix" "You can try installing 'duti' manually ('brew install duti') and then set IINA as default via Finder's 'Get Info' panel."
                    touch "${STATE_DIR}/.iina_setup_offered" # Mark as offered
                    return 0
                fi
            fi
            
            # Set IINA as default for .mkv and .mp4
            local iina_bundle_id="com.colliderli.iina"
            local types_to_set=(".mkv" ".mp4") # Could expand to more types if desired
            local all_set_successfully=true

            log_user_info "$log_prefix" "Attempting to set IINA as the default player..."
            for ext_type in "${types_to_set[@]}"; do
                log_debug_event "$log_prefix" "Setting IINA as default for ${ext_type} files..."
                if duti -s "$iina_bundle_id" "${ext_type}" all; then
                    log_user_info "$log_prefix" "✅ IINA set as default for ${ext_type} files."
                else
                    log_warn_event "$log_prefix" "⚠️ Failed to set IINA as default for ${ext_type} files using 'duti'."
                    all_set_successfully=false
                fi
            done

            if [[ "$all_set_successfully" == "true" ]]; then
                log_user_info "$log_prefix" "🎉 IINA should now be your default player for .mkv and .mp4 files!"
            else
                log_user_info "$log_prefix" "Some file types may not have been set. You can set IINA as the default player manually via Finder's 'Get Info' panel (select a file, press ⌘I, choose IINA under 'Open with:', and click 'Change All...')."
            fi
            ;;
        "no") # Explicit "no" or default due to empty input
            log_user_info "$log_prefix" "Skipping IINA installation and setup."
            echo
            echo "You can install IINA manually later if you wish (visit iina.io or use Homebrew)."
            echo "To set it as default: select an .mkv or .mp4 file, press ⌘I (Get Info),"
            echo "choose IINA under 'Open with:', and click 'Change All...'."
            ;;
        "invalid") # Should not happen with current normalize_user_response and explicit "" check
            log_user_info "$log_prefix" "Invalid response. Skipping IINA setup."
            ;;
    esac
    echo
    touch "${STATE_DIR}/.iina_setup_offered" # Mark as offered so it doesn't ask again
    return 0
}

# Function: perform_system_health_checks
# Description: Performs health checks for required and optional commands
# Parameters: None
# Returns:
#   0 if all checks pass (critical and optional)
#   2 if critical checks pass but optional ones are missing
# Side Effects: Exits with code 1 if any critical command is missing
perform_system_health_checks() {
    local log_prefix="Doctor"
    log_debug_event "$log_prefix" "💊 Performing system health checks..."
    local any_optional_missing=false

    # Collect all missing dependencies (using Bash 3.2 compatible approach)
    local missing_deps=()
    local IFS=$'\n'
    while read -r dep; do
        # Skip empty lines
        if [[ -n "$dep" ]]; then
            missing_deps+=("$dep")
        fi
    done < <(collect_missing_dependencies)
    
    local missing_count=${#missing_deps[@]}
    
   # If we have missing dependencies, handle them based on AUTO_INSTALL_DEPENDENCIES setting
if [[ $missing_count -gt 0 ]]; then
    if [[ "${AUTO_INSTALL_DEPENDENCIES:-false}" == "true" ]]; then
        log_debug_event "$log_prefix" "AUTO_INSTALL_DEPENDENCIES is enabled, skipping interactive prompts"
        log_user_info "$log_prefix" "🔧 Auto-installing missing programs (AUTO_INSTALL_DEPENDENCIES=true)..."
        for dep in "${missing_deps[@]}"; do
            log_user_info "$log_prefix" "  • $dep"
        done
        install_missing_dependencies "${missing_deps[@]}"
        local install_status=$?
        
        if [[ $install_status -eq 0 ]]; then
            log_user_info "$log_prefix" "✅ Successfully auto-installed all missing programs!"
        else
            log_warn_event "$log_prefix" "⚠️ Some programs failed to auto-install. Continuing with interactive setup..."
            handle_missing_dependencies_interactively "${missing_deps[@]}"
        fi
    else
        # Use interactive prompts when auto-install is disabled
        handle_missing_dependencies_interactively "${missing_deps[@]}"
    fi
        
        # Re-check dependencies after installation attempt (interactive or automatic) (using Bash 3.2 compatible approach)
        missing_deps=()
        local IFS=$'\n'
        while read -r dep; do
            # Skip empty lines
            if [[ -n "$dep" ]]; then
                missing_deps[${#missing_deps[@]}]="$dep"
            fi
        done < <(collect_missing_dependencies)
        
        missing_count=${#missing_deps[@]}
        
        # If still missing dependencies, determine if any are critical
        local critical_failure_detected=false
        if [[ $missing_count -gt 0 ]]; then
            log_user_info "$log_prefix" "Verifying critical dependencies after installation attempts..."
            for dep in "${missing_deps[@]}"; do
                local is_this_dep_critical=false
                local critical_reason=""

                # Check core required dependencies
                for core_req_dep in "${REQUIRED_DEPENDENCIES[@]}"; do
                    if [[ "$dep" == "$core_req_dep" ]]; then
                        is_this_dep_critical=true
                        critical_reason=" (core requirement)"
                        break 
                    fi
                done

                # Check YouTube dependencies
                if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" ]]; then
                    if [[ "$dep" == "yt-dlp" ]]; then
                        is_this_dep_critical=true
                        critical_reason=" (for YouTube)"
                    elif [[ "$dep" == "ffmpeg" ]]; then
                        is_this_dep_critical=true
                        critical_reason=" (for YouTube media processing)"
                    fi
                fi
                
                # Check Torrent dependencies
                if [[ "${ENABLE_TORRENT_AUTOMATION:-false}" == "true" ]]; then
                    # Assuming collect_missing_dependencies uses "transmission-cli" 
                    # as the placeholder name for the torrent client.
                    if [[ "$dep" == "transmission-cli" ]]; then 
                        is_this_dep_critical=true
                        critical_reason=" (for Torrents)"
                    fi
                fi

                if [[ "$is_this_dep_critical" == "true" ]]; then
                    log_error_event "$log_prefix" "CRITICAL program '$dep'$critical_reason is still missing."
                    critical_failure_detected=true
                fi
            done # End of loop through missing_deps

            if [[ "$critical_failure_detected" == "true" ]]; then
                log_error_event "$log_prefix" "One or more critical programs are missing. JellyMac cannot continue."
                log_user_info "$log_prefix" "Please review the errors above, install the missing programs (e.g., using 'brew install <program>'), or ensure AUTO_INSTALL_DEPENDENCIES is enabled in your config."
                return 1 
            else
                # If we are here, missing_count > 0 but no critical failures were detected.
                log_warn_event "$log_prefix" "Some optional programs are still missing. Certain non-critical features may not work."
                any_optional_missing=true
            fi
        fi
    fi

    # --- Validate Configuration Filepaths ---
    # This is a critical step. If paths are not valid or can't be created, we can't proceed.
    log_debug_event "$log_prefix" "Validating configured filepaths..."
    if ! validate_config_filepaths; then
        # validate_config_filepaths already logs detailed errors
        log_error_event "$log_prefix" "Critical configuration filepath validation failed. See details above."
        return 1 # Critical failure
    fi
    log_debug_event "$log_prefix" "✅ Configured filepaths validated."

    # Check if auto-installation is enabled and Homebrew is available
    if [[ "${AUTO_INSTALL_DEPENDENCIES:-false}" == "true" ]]; then
        if command -v brew >/dev/null 2>&1; then
            log_user_info "$log_prefix" "Automatic program installation is enabled and Homebrew is available."
        else
            log_warn_event "$log_prefix" "Automatic program installation is enabled but Homebrew is not found."
            log_warn_event "$log_prefix" "Please install Homebrew from https://brew.sh/ to enable auto-installation."
        fi
    fi

    # --- Check Core macOS Tools ---
    if [[ "$(uname)" == "Darwin" ]]; then
        log_debug_event "$log_prefix" "Checking core macOS tools..."
        
        # Define core macOS tools based on enabled features
        local core_tools=()
        
        # Always check these core tools
        core_tools[${#core_tools[@]}]="rsync"
        core_tools[${#core_tools[@]}]="curl"
        
        # Add clipboard tools if needed
        if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" || "${ENABLE_CLIPBOARD_MAGNET:-false}" == "true" ]]; then
            core_tools[${#core_tools[@]}]="pbpaste"
        fi
        
        # Add other macOS-specific tools
        core_tools[${#core_tools[@]}]="caffeinate"
        
        if [[ "${ENABLE_DESKTOP_NOTIFICATIONS:-false}" == "true" ]]; then
            core_tools[${#core_tools[@]}]="osascript"
        fi
        
        # Check all core tools
        for core_tool in "${core_tools[@]}"; do
            if ! command -v "$core_tool" >/dev/null 2>&1; then
                log_error_event "$log_prefix" "❌ Core macOS tool '$core_tool' is missing. This indicates a corrupted system."
                log_error_event "$log_prefix" "Please repair your macOS installation before using JellyMac."
                return 1
            fi
        done
        log_debug_event "$log_prefix" "✅ All core macOS tools available."
    fi
    
    # --- Check Transmission Daemon Status ---
    # Verify daemon is running if magnet link handling is enabled
    if [[ "${ENABLE_CLIPBOARD_MAGNET:-false}" == "true" ]]; then
        log_debug_event "$log_prefix" "Checking Transmission background service status..."
        if ! check_transmission_daemon; then
            log_warn_event "$log_prefix" "Magnet link handling is enabled, but the Transmission background service is not running."
            any_optional_missing=true
        fi
    fi

    # --- Offer IINA Installation ---
    offer_iina_installation_and_default
    
    log_debug_event "$log_prefix" "✅ System health checks passed."
    
    if [[ "$any_optional_missing" == "true" ]]; then
        log_warn_event "$log_prefix" "🩺 Some optional system health checks failed. Review warnings above."
        return 2
    else
        log_debug_event "$log_prefix" "🩺 All optional command checks also passed or were not applicable."
        return 0
    fi
}