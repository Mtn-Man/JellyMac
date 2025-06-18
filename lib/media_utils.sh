#!/bin/bash

# lib/media_utils.sh
# Contains utility functions for media file processing,
# including filename parsing, sanitization, and category determination.
# Simplified: Defaults to "Movies", specifically identifies "Shows".

# This script primarily provides functions that return values via echo.
# Logging within these functions should be minimal (e.g., debug logs if necessary),
# allowing the calling script (process_media_item.sh) to handle main logging.

# Ensure logging_utils.sh is sourced, as this script uses log_debug_event
if ! command -v log_debug_event &>/dev/null; then
    # Attempt to source it relative to this script's directory if SCRIPT_DIR is not set.
    # This is a fallback for direct execution or sourcing from unexpected contexts.
    # The main jellymac.sh script will have already sourced it.
    _MEDIA_UTILS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    if [[ -f "${_MEDIA_UTILS_LIB_DIR}/logging_utils.sh" ]]; then
        # shellcheck source=logging_utils.sh
        # shellcheck disable=SC1091
        source "${_MEDIA_UTILS_LIB_DIR}/logging_utils.sh"
    fi

fi

#==============================================================================
# Function: is_valid_media_year
# Description: Validates if a year is within reasonable range for media content
# Checks if the provided year is a 4-digit number within the valid range for media content (1920-2029).
# Parameters: $1: year - Year to validate (4-digit string)
# Returns: 0 if valid, 1 if invalid
#==============================================================================
is_valid_media_year() {
    local year_to_check="$1"
    
    # Check if it's a 4-digit number
    if [[ ! "$year_to_check" =~ ^[0-9]{4}$ ]]; then
        return 1
    fi
    
    # Check if within valid range (1920-2029)
    if [[ "$year_to_check" -ge 1920 && "$year_to_check" -le 2029 ]]; then
        return 0
    else
        return 1
    fi
}

#==============================================================================
# Function: sanitize_filename
# Description: Sanitizes a string for use as a valid filename
# Replaces common problematic characters with underscores or removes them.
# Handles specific characters that cause issues in filenames across different operating systems.
# Parameters: $1: input_string - String to sanitize, $2: default_string - (Optional) Default string if input is empty after sanitization
# Returns: Sanitized string suitable for use as filename
# Dependencies: None
#==============================================================================
sanitize_filename() {
    local input_string="$1"
    local default_string="${2:-sanitized_name}"
    local sanitized_string

    # Remove leading/trailing whitespace
    sanitized_string=$(echo "$input_string" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Handle specific problematic characters for filenames
    # Added colon removal, which is important for macOS/Windows compatibility in paths
    # Using Bash parameter expansion for better performance
    sanitized_string="${sanitized_string//|/—}"
    sanitized_string="${sanitized_string//&/ and }"
    sanitized_string="${sanitized_string//\"/}"
    sanitized_string="${sanitized_string//\'/}"
    sanitized_string="${sanitized_string//:/}"
    sanitized_string="${sanitized_string//\//}"
    sanitized_string="${sanitized_string//\\/}"
    sanitized_string="${sanitized_string//\*/ }"
    sanitized_string="${sanitized_string//\?/ }"
    sanitized_string="${sanitized_string//</}"
    sanitized_string="${sanitized_string//>/}"

    # Replace multiple spaces with a single space
    sanitized_string=$(echo "$sanitized_string" | tr -s ' ')

    # Remove trailing dots and spaces (bash 3.2 compatible)
    # shellcheck disable=SC2001
    sanitized_string=$(echo "$sanitized_string" | sed 's/[. ]*$//')
    # Remove leading dots and spaces (bash 3.2 compatible)
    # shellcheck disable=SC2001
    sanitized_string=$(echo "$sanitized_string" | sed 's/^[. ]*//')

    # If, after all this, the string is empty, use the default
    if [[ -z "$sanitized_string" ]]; then
        sanitized_string="$default_string"
    fi

    echo "$sanitized_string"
}

#==============================================================================
# Function: determine_media_category
# Description: Determines media category (Movies/Shows) from item name
# Defaults to "Movies" if not identified as a "Show". Uses regex patterns to detect TV show indicators like SxxExx, Season xx, Episode xx formats.
# Parameters: $1: item_name - The basename of the torrent download or file
# Returns: "Movies" or "Shows" via echo
# Dependencies: None
#==============================================================================
determine_media_category() {
    local item_name_to_check="$1"
    local determined_category="Movies" # Default to Movies

    # --- Regex for TV Shows ---
    # Check for SxxExx, Season xx, Episode xx, Part xx, Series, Show, Season Pack
    # This regex is crucial for differentiating shows.
    if echo "$item_name_to_check" | grep -qE -i \
        '([Ss]([0-9]{1,3})[._ ]?[EeXx]([0-9]{1,4}))|([Ss]eason[._ ]?([0-9]{1,3}))|([Ee]pisode[._ ]?([0-9]{1,4}))|\b(Part|Pt)[._ ]?([0-9IVX]+)\b|\b(Series|Show)\b|\b(Season[._ ]Pack)\b'; then
        determined_category="Shows"
    fi

    echo "$determined_category"
}

#==============================================================================
# Function: _title_case_string
# Description: Converts a string to title case.
# Parameters: $1: input_string - The string to title case.
# Returns: Title-cased string via echo.
#==============================================================================
_title_case_string() {
    # awk: for each field, capitalize first letter, lowercase the rest.
    echo "$1" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}'
}

#==============================================================================
# Function: _remove_bracketed_content
# Description: Helper function to remove bracketed content from a string.
# Removes content within square `[]` brackets.
# Parameters: $1: input_string - String to remove brackets from
# Returns: String with bracketed content removed
#==============================================================================
_remove_bracketed_content() {
    local input="$1"
    # Removes content within square brackets and any stray square brackets.
    echo "$input" | sed -E 's/\[[^\]]*\]//g' | sed -E 's/[\[\]]//g'
}

#==============================================================================
# Function: _remove_website_prefix
# Description: Removes website prefixes from the beginning of a filename.
# This MUST be called BEFORE any other sanitization that converts dots to spaces.
# Handles patterns like:
# - "www.Torrenting.com - "
# - "site.com - "
# - "www.site.com   -    "
# Parameters: $1: filename - The original filename
# Returns: Filename with website prefix removed
#==============================================================================
_remove_website_prefix() {
    local filename="$1"
    local result
    # Remove website prefix patterns from the beginning of the string
    # This regex handles:
    # - Optional "www." prefix
    # - Domain name with dots (e.g., "site.com", "torrenting.com")
    # - MUST have a separator (dash or multiple spaces) after the domain
    # - Leading/trailing whitespace
    # The key fix: require a separator after the domain to avoid matching show titles with dots
    result=$(echo "$filename" | sed -E 's/^[[:space:]]*([wW][wW][wW]\.)?[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}[[:space:]]*(-+[[:space:]]*|[[:space:]]{2,})//')
    
    # Debug logging for website prefix removal
    if [[ "$result" != "$filename" ]]; then
        log_debug_event "Media" "_remove_website_prefix: Removed prefix from '$filename' -> '$result'"
    fi
    
    echo "$result"
}

#==============================================================================
# Function: _get_clean_lowercase_title
# Description: Performs common cleaning operations on a filename to get a base title.
# This centralized function handles website prefix, release group, media tags,
# and spacing normalization to produce a clean, lowercase title base.
# CRITICAL: Website prefix removal happens FIRST, before any other sanitization.
# Parameters: $1: filename - The original filename or folder name.
# Returns: Cleaned, lowercase title via echo.
#==============================================================================
_get_clean_lowercase_title() {
    local filename="$1"
    local cleaned_title

    log_debug_event "Media" "_get_clean_lowercase_title: Starting with '$filename'"

    # STAGE 1: Remove website prefix FIRST (before any other changes)
    # This is critical - must happen before dots are converted to spaces
    cleaned_title=$(_remove_website_prefix "$filename")
    log_debug_event "Media" "_get_clean_lowercase_title: After website prefix removal: '$cleaned_title'"
    
    # STAGE 2: Remove file extension
    cleaned_title="${cleaned_title%.*}"
    log_debug_event "Media" "_get_clean_lowercase_title: After extension removal: '$cleaned_title'"
    
    # STAGE 3: Spacing and separator normalization
    # Replace common separators with spaces
    cleaned_title="${cleaned_title//[._]/ }"
    log_debug_event "Media" "_get_clean_lowercase_title: After separator replacement: '$cleaned_title'"
    
    # STAGE 4: Remove release group (handles optional space before hyphen)
    cleaned_title=$(echo "$cleaned_title" | sed -E 's/[[:space:]]*-([a-zA-Z0-9]+)$//')
    log_debug_event "Media" "_get_clean_lowercase_title: After release group removal: '$cleaned_title'"

    # STAGE 5: Convert to lowercase for consistent tag matching
    cleaned_title=$(echo "$cleaned_title" | tr '[:upper:]' '[:lower:]')
    log_debug_event "Media" "_get_clean_lowercase_title: After lowercase: '$cleaned_title'"
    
    # STAGE 6: Remove media quality/source tags
    local config_tag_blacklist="${MEDIA_TAG_BLACKLIST:-2160p|1080p|720p|480p|web[- ]?dl|webrip|bluray|brrip|hdrip|ddp5?\\.1|aac|ac3|x265|x264|hevc|h\\.264|h\\.265|remux|neonoir|sdrip|re-encoded}"
    local tag_regex
    tag_regex="\\b($(echo "$config_tag_blacklist" | tr '[:upper:]' '[:lower:]'))\\b"
    local before_tag_removal="$cleaned_title"
    cleaned_title=$(echo "$cleaned_title" | sed -E "s/${tag_regex}//g" | tr -s ' ')
    
    # Debug logging for tag removal if tags were actually removed
    if [[ "$cleaned_title" != "$before_tag_removal" ]]; then
        log_debug_event "Media" "_get_clean_lowercase_title: Removed tags from '$before_tag_removal' -> '$cleaned_title'"
    fi

    # STAGE 7: Final cleanup
    # Remove bracketed content from start/end (handles both [] and ())
    cleaned_title=$(echo "$cleaned_title" | sed -E -e 's/^[\[\(][^\]\)]*[\]\)]//g' -e 's/[\[\(][^\]\)]*[\]\)]$//g')
    log_debug_event "Media" "_get_clean_lowercase_title: After bracket removal: '$cleaned_title'"
    # Collapse multiple spaces and trim leading/trailing whitespace
    cleaned_title=$(echo "$cleaned_title" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    log_debug_event "Media" "_get_clean_lowercase_title: After final cleanup: '$cleaned_title'"

    # STAGE 8: Validation - if the title is empty or too short, return a fallback
    if [[ -z "$cleaned_title" ]] || [[ ${#cleaned_title} -lt 2 ]]; then
        log_debug_event "Media" "_get_clean_lowercase_title: Title too short or empty, using fallback"
        cleaned_title="unknown title"
    fi

    log_debug_event "Media" "_get_clean_lowercase_title: Final result '$cleaned_title'"
    echo "$cleaned_title"
}

#==============================================================================
# Function: extract_and_sanitize_show_info
# Description: Extracts and sanitizes TV show title, year, and episode info from filename.
# Relies on helper functions for cleaning and focuses on S/E pattern matching.
# Example: "Show.Name.S01E05.720p.WEB-DL.mkv" -> "Show Name###2024###s01e05"
# Parameters: $1: original_name - The TV show filename to process
# Returns: Formatted string: "ShowTitle###Year###sXXeYY" (Year can be "NOYEAR")
#==============================================================================
extract_and_sanitize_show_info() {
    local original_name="$1"
    local raw_title_part=""
    local show_title=""
    local year="" 
    local season_episode_str="" 
    
    # Regex to find SxxExx patterns
    local se_regex_pattern_strict='[Ss]([0-9]{1,3})[._ ]?[EeXx]([0-9]{1,4})' 

    # --- Step 1: Isolate the title part and the S/E string ---
    if [[ "$original_name" =~ $se_regex_pattern_strict ]]; then
        local se_match_full="${BASH_REMATCH[0]}"
        local season_match="${BASH_REMATCH[1]}"
        local episode_match="${BASH_REMATCH[2]}" 

        raw_title_part="${original_name%%"${se_match_full}"*}"
        
        if [[ -n "$season_match" && -n "$episode_match" ]]; then
            local s_num_padded e_num_padded
            s_num_padded=$(printf "%02d" $((10#$season_match))) 
            e_num_padded=$(printf "%02d" $((10#$episode_match))) 
            season_episode_str="s${s_num_padded}e${e_num_padded}" 
        fi
    else
        raw_title_part="$original_name" 
    fi

    # --- Step 2: Clean the isolated title part using the shared function ---
    show_title=$(_get_clean_lowercase_title "$raw_title_part")

    # --- Step 3: Extract the year from the cleaned title ---
    local year_regex='(.*[[:space:]])([12][90][0-9]{2})$' 
    if [[ "$show_title" =~ $year_regex ]]; then
        local potential_title_part="${BASH_REMATCH[1]}"
        local potential_year="${BASH_REMATCH[2]}"
        
        # Avoid mistaking season numbers (e.g. "Show S01") for a year
        if is_valid_media_year "$potential_year"; then
            show_title="${potential_title_part}" 
            year="$potential_year"
        fi
    fi

    # --- Step 4: Finalize the title (Title Case and Sanitize) ---
    show_title=$(_remove_bracketed_content "$show_title") # Clean any remaining [stuff]
    show_title=$(_title_case_string "$show_title")
    show_title=$(sanitize_filename "$show_title" "Unknown Show") 

    # --- Step 5: Format and return the result ---
    log_debug_event "Media" "extract_and_sanitize_show_info: Title='$show_title', Year='$year', SE='$season_episode_str' (from '$original_name')"
    local formatted_string="${show_title:-Unknown Show}###${year:-NOYEAR}###${season_episode_str}"
    log_debug_event "Media" "extract_and_sanitize_show_info: Final output string: '$formatted_string'"
    echo "$formatted_string"
}

#==============================================================================
# Function: extract_and_sanitize_movie_info
# Description: Extracts and sanitizes movie title and year from filename.
# Relies on helper functions for cleaning and focuses on movie-specific year extraction.
# Example: "www.site.com-A.Minecraft.Movie.2025.1080p-NeoNoir.mkv" -> "A Minecraft Movie (2025)"
# Parameters: $1: filename - The movie filename to process
# Returns: Sanitized movie title with year in parentheses, or just the title.
#==============================================================================
extract_and_sanitize_movie_info() {
    local filename="$1"
    log_debug_event "Media" "extract_and_sanitize_movie_info: Starting with filename='$filename'"
    
    # --- Step 1: Get the base cleaned title (lowercase) from the shared function ---
    local cleaned_name
    cleaned_name=$(_get_clean_lowercase_title "$filename")
    log_debug_event "Media" "extract_and_sanitize_movie_info: After shared cleaning='$cleaned_name'"
    
    # --- Step 2: Movie-specific year extraction ---
    local year=""
    local title_part=""

    # Priority 1: Check for year in parentheses, e.g., "Movie Title (2025)"
    if [[ $cleaned_name =~ ^(.*[[:space:]])\(([12][0-9]{3})\)(.*)$ ]]; then
        local potential_title="${BASH_REMATCH[1]}"
        local potential_year="${BASH_REMATCH[2]}"
        
        if is_valid_media_year "$potential_year"; then
            title_part="$potential_title"
            year="$potential_year"
        else
            # If invalid year in parens, treat it as part of the title
            title_part="$cleaned_name"
        fi
    # Priority 2 (Fallback): Find the last 4-digit number that looks like a year
    elif [[ $cleaned_name =~ (.*[[:space:]])([12][0-9]{3})($|[[:space:]]) ]]; then
        local potential_year="${BASH_REMATCH[2]}"
        
        if is_valid_media_year "$potential_year"; then
            title_part="${cleaned_name%"$potential_year"*}"
            year="$potential_year"
        else
            # Not a valid year, so it's part of the title
            title_part="$cleaned_name"
        fi
    else
        # No year found, the whole thing is the title
        title_part="$cleaned_name"
    fi
    
    # --- Step 3: Finalize the title and format the output ---
    title_part=$(_remove_bracketed_content "$title_part")
    title_part=$(_title_case_string "$title_part")
    title_part=$(sanitize_filename "$title_part" "Unknown Movie")
    
    log_debug_event "Media" "extract_and_sanitize_movie_info: Final Title='$title_part', Final Year='$year'"
    
    if [[ -n "$year" ]]; then
        echo "$title_part ($year)"
    else
        echo "$title_part"
    fi
}
