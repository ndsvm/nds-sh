#!/bin/bash

set -e

NDS_DIR="$HOME/.config/nds"
VERSIONS_DIR="$NDS_DIR/versions"
CONFIG_FILE="$NDS_DIR/nds.conf"
DEFAULT_NODE_SYMLINK="$NDS_DIR/default"
NODE_SOURCE_URL="https://nodejs.org/download/release"

mkdir -p "$VERSIONS_DIR"

# OS/ARCH detection
OS="$(uname -s)"
case "$OS" in
    Linux*)   NODE_OS="linux";;
    Darwin*)  NODE_OS="darwin";;
    *) echo "Unsupported OS: $OS"; exit 1;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  NODE_ARCH="x64";;
    arm64|aarch64) NODE_ARCH="arm64";;
    *) echo "Unsupported architecture: $ARCH"; exit 1;;
esac

# -------- Version Fetching and Listing --------

fetch_available_versions() {
    curl -s "$NODE_SOURCE_URL/index.tab" | awk 'NR > 1 {print $1}' | sed 's/^v//' | sort -Vr
}

fetch_available_versions_limited() {
    local all_versions top_majors
    all_versions=$(fetch_available_versions)
    top_majors=$(echo "$all_versions" | awk -F. '{print $1}' | uniq | head -n 5)
    local awk_regex="^($(echo "$top_majors" | paste -sd '|' -))\\."
    echo "$all_versions" | grep -E "$awk_regex"
}

get_latest_version() {
    fetch_available_versions | head -n 1
}

get_latest_major_version() {
    local major=$1
    fetch_available_versions | grep "^$major\." | head -n 1
}

list_installed_versions() {
    echo "Installed Node.js versions:"
    if [[ -d "$VERSIONS_DIR" ]]; then
        local versions default_version current_version count
        versions=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort -V)
        count=$(echo "$versions" | wc -l)
        [[ $count -eq 0 ]] && { echo "  (none)"; return; }

        # Find default version (symlink target)
        if [[ -L "$DEFAULT_NODE_SYMLINK" ]]; then
            default_version=$(readlink "$DEFAULT_NODE_SYMLINK" | sed 's|.*/||')
        fi

        # Find current shell version
        current_version=$(node --version 2>/dev/null | sed 's/^v//')

        # Print with annotations
        while IFS= read -r version; do
            marker=""
            [[ "$version" == "$default_version" ]] && marker="${marker}[default]"
            [[ "$version" == "$current_version" ]] && marker="${marker}[current]"
            printf "  %s %s\n" "$version" "$marker"
        done <<< "$versions"
    else
        echo "  (none)"
    fi
}

interactive_remove_installed_versions() {
    local versions
    versions=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort -V)
    if [[ -z "$versions" ]]; then
        echo "No Node.js versions are installed."
        return 0
    fi
    if ! command -v fzf &>/dev/null; then
        echo "fzf not found. Please install fzf for interactive removal."
        echo "Installed versions:"
        echo "$versions"
        echo "You can remove with: nds remove <version>"
        return 1
    fi

    echo "$versions" | fzf --multi --prompt="Select version(s) to remove (Tab to mark, Enter to confirm, ESC to cancel): " > /tmp/nds-pick-$$
    local picked
    picked=$(cat /tmp/nds-pick-$$)
    rm /tmp/nds-pick-$$
    if [[ -z "$picked" ]]; then
        echo "No versions selected. Nothing removed."
        return 0
    fi

    echo "You selected:"
    for version in $picked; do
        echo "  - $version"
    done
    echo
    echo "Are you sure you want to remove ALL of the above version(s)? [y/N]"
    read -r confirm
    if [[ "$confirm" == "y" ]]; then
        for version in $picked; do
            remove_version "$version" no_confirm
        done
    else
        echo "Aborted."
    fi
}

# -------- Extraction Progress Bar --------

extract_with_fake_progress_bar() {
    local tarfile="$1"
    local dest="$2"
    local width=30
    local duration=3  # estimated seconds for extraction
    local interval=0.1
    local steps=$((duration * 10))
    local i=0

    (
        while (( i < steps )); do
            local fill=$((width * i / steps))
            local empty=$((width - fill))
            printf "\rExtracting... ["
            printf "%0.s=" $(seq 1 $fill)
            printf "%0.s " $(seq 1 $empty)
            printf "]"
            sleep "$interval"
            ((i++))
        done
    ) &
    local bar_pid=$!

    # Actual extraction in parallel
    tar -xzf "$tarfile" --strip-components=1 -C "$dest" >/dev/null 2>&1
    local result=$?

    kill "$bar_pid" >/dev/null 2>&1
    wait "$bar_pid" 2>/dev/null
    printf "\rExtracting... [==============================] done\n"
    return $result
}

# -------- Installation, Removal, Use, Set --------

install_version() {
    local version=$1
    if [[ "$version" == "latest" ]]; then
        version=$(get_latest_version)
    elif [[ "$version" =~ ^[0-9]+$ ]]; then
        version=$(get_latest_major_version "$version")
    fi
    [[ -z "$version" ]] && { echo "Could not determine latest version for '$1'."; return 1; }

    local version_dir="$VERSIONS_DIR/$version"
    if [[ -d "$version_dir" ]]; then
        echo "Node.js $version is already installed."
        return 0
    fi

    echo "Installing Node.js $version..."
    mkdir -p "$version_dir"
    local tarball_url="$NODE_SOURCE_URL/v$version/node-v$version-$NODE_OS-$NODE_ARCH.tar.gz"
    local temp_file
    temp_file=$(mktemp)

    # Download with curl progress bar
    echo "Downloading $tarball_url"
    if ! curl --progress-bar -fSL "$tarball_url" -o "$temp_file"; then
        echo "Failed to download $tarball_url"
        rm -f "$temp_file"
        rm -rf "$version_dir"
        return 1
    fi

    # Extraction with fake progress bar
    if ! extract_with_fake_progress_bar "$temp_file" "$version_dir"; then
        echo "Failed to extract Node.js $version."
        rm -f "$temp_file"
        rm -rf "$version_dir"
        return 1
    fi

    rm "$temp_file"
    echo "Node.js $version installed successfully."
}

remove_version() {
    local version=$1
    local skip_confirm=$2
    [[ "$version" == "latest" ]] && version=$(ls -v "$VERSIONS_DIR" | head -n 1)
    [[ ! -d "$VERSIONS_DIR/$version" ]] && { echo "Node.js $version is not installed."; return; }
    if [[ "$skip_confirm" != "no_confirm" ]]; then
        echo "Are you sure you want to remove Node.js $version? [y/N]"
        read -r confirm
        [[ "$confirm" != "y" ]] && { echo "Aborted."; return; }
    fi
    rm -rf "$VERSIONS_DIR/$version"
    echo "Node.js $version removed."
}

use_version() {
    local input="$1"
    local version=""
    # Find highest matching installed version
    version=$(ls -1v "$VERSIONS_DIR" 2>/dev/null | grep "^$input" | tail -n 1)
    if [[ -z "$version" ]]; then
        echo "No installed Node.js version matching '$input'."
        return 1
    fi
    # Only print the bin path, do NOT export PATH in the script
    echo "$VERSIONS_DIR/$version/bin"
}

set_default_version() {
    local input="$1"
    local version=""
    version=$(ls -1v "$VERSIONS_DIR" 2>/dev/null | grep "^$input" | tail -n 1)
    if [[ -z "$version" ]]; then
        echo "No installed Node.js version matching '$input'."
        return 1
    fi
    ln -sfn "$VERSIONS_DIR/$version" "$DEFAULT_NODE_SYMLINK"
    echo "$VERSIONS_DIR/$version/bin"
    echo "Default Node.js version set to $version."
    echo
    echo "Add this to your .bashrc or .zshrc to use it automatically in new shells:"
    echo 'if [ -d "$HOME/.config/nds/default/bin" ]; then export PATH="$HOME/.config/nds/default/bin:$PATH"; fi'
}

interactive_version_picker() {
    local available_versions
    available_versions=$(fetch_available_versions_limited)
    local version
    if command -v fzf &> /dev/null; then
        version=$(echo "$available_versions" | fzf --prompt="Select Node.js version: ")
    else
        echo "fzf not found. Please install fzf for interactive selection."
        echo "Available versions:"
        echo "$available_versions"
        echo -n "Enter version manually: "
        read -r version
    fi
    [[ -n "$version" ]] && install_version "$version"
}

# -------- Auto-Switching Logic --------

auto_switch_to_project_version() {
    # Check config first
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        [[ "$AUTO_SWITCH" != "true" ]] && return
    fi
    # Find .nds or .nvmrc in current directory
    local version_file=""
    if [[ -f ".nds" ]]; then
        version_file=".nds"
    elif [[ -f ".nvmrc" ]]; then
        version_file=".nvmrc"
    fi
    if [[ -n "$version_file" ]]; then
        local version
        version=$(cat "$version_file" | tr -d '[:space:]')
        if [[ -n "$version" ]]; then
            local current_version
            current_version=$(node --version 2>/dev/null | sed 's/^v//')
            if [[ "$current_version" != "$version" ]]; then
                if [[ ! -d "$VERSIONS_DIR/$version" ]]; then
                    echo "[nds] Installing Node.js $version from $version_file"
                    install_version "$version"
                fi
                # Switch version for current shell
                local bin_path="$VERSIONS_DIR/$version/bin"
                export PATH="$bin_path:$(echo $PATH | tr ':' '\n' | grep -v "$VERSIONS_DIR/.*/bin" | paste -sd ':')"
                echo "[nds] Now using Node.js $version (from $version_file)"
            fi
        fi
    fi
}

enable_auto_switch() {
    echo "AUTO_SWITCH=true" > "$CONFIG_FILE"

    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    local func_code='
# >>> nds auto-switch start >>>
auto_switch_to_project_version() {
    if command -v nds >/dev/null 2>&1; then
        nds auto-switch-internal
    fi
}
# <<< nds auto-switch end <<<
'
    local bash_hook_code='
# >>> nds PROMPT_COMMAND auto-switch start >>>
if [[ "$PROMPT_COMMAND" != *auto_switch_to_project_version* ]]; then
    PROMPT_COMMAND="auto_switch_to_project_version; $PROMPT_COMMAND"
fi
# <<< nds PROMPT_COMMAND auto-switch end <<<
'
    local zsh_hook_code='
# >>> nds precmd auto-switch start >>>
autoload -U add-zsh-hook
add-zsh-hook precmd auto_switch_to_project_version
# <<< nds precmd auto-switch end <<<
'

    # Write function and hook to bashrc
    if [[ -f "$bashrc" ]]; then
        sed -i '/# >>> nds auto-switch start >>>/,/# <<< nds auto-switch end <<</d' "$bashrc"
        sed -i '/# >>> nds PROMPT_COMMAND auto-switch start >>>/,/# <<< nds PROMPT_COMMAND auto-switch end <<</d' "$bashrc"
        echo "$func_code" >> "$bashrc"
        echo "$bash_hook_code" >> "$bashrc"
        echo "Enabled nds auto-switching in $bashrc"
    fi

    # Write function and hook to zshrc
    if [[ -f "$zshrc" ]]; then
        sed -i '/# >>> nds auto-switch start >>>/,/# <<< nds auto-switch end <<</d' "$zshrc"
        sed -i '/# >>> nds precmd auto-switch start >>>/,/# <<< nds precmd auto-switch end <<</d' "$zshrc"
        echo "$func_code" >> "$zshrc"
        echo "$zsh_hook_code" >> "$zshrc"
        echo "Enabled nds auto-switching in $zshrc"
    fi

    echo "Auto-switching enabled. Please restart your shell or run: source ~/.bashrc or source ~/.zshrc"
}

disable_auto_switch() {
    echo "AUTO_SWITCH=false" > "$CONFIG_FILE"
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    if [[ -f "$bashrc" ]]; then
        sed -i '/# >>> nds auto-switch start >>>/,/# <<< nds auto-switch end <<</d' "$bashrc"
        sed -i '/# >>> nds PROMPT_COMMAND auto-switch start >>>/,/# <<< nds PROMPT_COMMAND auto-switch end <<</d' "$bashrc"
        echo "Disabled nds auto-switching in $bashrc"
    fi
    if [[ -f "$zshrc" ]]; then
        sed -i '/# >>> nds auto-switch start >>>/,/# <<< nds auto-switch end <<</d' "$zshrc"
        sed -i '/# >>> nds precmd auto-switch start >>>/,/# <<< nds precmd auto-switch end <<</d' "$zshrc"
        echo "Disabled nds auto-switching in $zshrc"
    fi
    echo "Auto-switching disabled. Please restart your shell or run: source ~/.bashrc or source ~/.zshrc"
}

# -------- Shell Integration (init command) --------

nds_init() {
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    local nds_path_line='if [ -d "$HOME/.config/nds/default/bin" ]; then export PATH="$HOME/.config/nds/default/bin:$PATH"; fi'
    local nds_func='
nds() {
  if [ "$1" = "use" ] && [ -n "$2" ]; then
    local VERSIONS_DIR="$HOME/.config/nds/versions"
    local version
    version=$(ls -1v "$VERSIONS_DIR" 2>/dev/null | grep "^$2" | tail -n 1)
    if [ -z "$version" ]; then
      echo "No installed Node.js version matching '\''$2'\''."
      return 1
    fi
    export PATH="$VERSIONS_DIR/$version/bin:$PATH"
    echo "Now using Node.js $version in this shell."
  elif [ "$1" = "set" ] && [ -n "$2" ]; then
    local VERSIONS_DIR="$HOME/.config/nds/versions"
    local version
    version=$(ls -1v "$VERSIONS_DIR" 2>/dev/null | grep "^$2" | tail -n 1)
    if [ -z "$version" ]; then
      echo "No installed Node.js version matching '\''$2'\''."
      return 1
    fi
    ln -sfn "$VERSIONS_DIR/$version" "$HOME/.config/nds/default"
    export PATH="$VERSIONS_DIR/$version/bin:$PATH"
    echo "Default Node.js version set to $version."
    echo
    echo "Add this to your .bashrc or .zshrc to use it automatically in new shells:"
    echo '\''if [ -d "$HOME/.config/nds/default/bin" ]; then export PATH="$HOME/.config/nds/default/bin:$PATH"; fi'\''
  else
    command nds "$@"
  fi
}
'

    local updated=0

    add_to_shell_config() {
        local shellrc="$1"
        if [[ -f "$shellrc" ]]; then
            # Remove old nds() definitions
            sed -i '' '/^nds()/,/^}/d' "$shellrc"
            # Add PATH line if missing
            if ! grep -Fxq "$nds_path_line" "$shellrc"; then
                echo "$nds_path_line" >> "$shellrc"
                echo "Added nds PATH initialization to $shellrc"
                updated=1
            fi
            # Add function if missing
            if ! grep -q "nds() {" "$shellrc" 2>/dev/null; then
                echo "$nds_func" >> "$shellrc"
                echo "Added nds shell function to $shellrc"
                updated=1
            fi
        fi
    }

    add_to_shell_config "$bashrc"
    add_to_shell_config "$zshrc"

    if [[ $updated -eq 1 ]]; then
        echo "Done! Please restart your terminal or run: source ~/.bashrc or source ~/.zshrc"
    else
        echo "No changes made (already initialized)."
    fi
}

# -------- Help --------

nds_help() {
cat <<'EOF'
nds - Simple Node.js Version Manager

USAGE:
  nds list                   List all installed Node.js versions, marking [default] and [current]
  nds list pick              Interactively pick and remove installed Node.js versions
  nds available              List available Node.js versions (latest 5 majors)
  nds install <version>      Install a specific version (e.g., 22.2.0, 18, latest)
  nds install pick           Interactively pick a Node.js version to install (from latest 5 majors)
  nds latest                 Install the latest Node.js version
  nds use <version>          Use a Node.js version in the current shell
  nds set <version>          Set the default Node.js version for new shells and your current shell
  nds remove <version>       Remove a specific Node.js version
  nds auto [on]              Enable automatic switching to Node.js version based on .nvmrc/.nds files
  nds auto off               Disable automatic switching and remove hooks from your shell config
  nds init                   Add PATH and shell integration to your shell config
  nds help, -h, --help       Show this help message

EXAMPLES:
  nds available
  nds install 22
  nds use 20.13.1
  nds set latest
  nds remove 18.17.1
  nds list pick
  nds install pick

NOTES:
- 'nds list' marks [default] and [current] versions for easy reference.
- 'nds available' and 'nds install pick' list only the latest 5 major Node.js versions.
- You can still install and use *any* Node.js version explicitly, e.g. 'nds install 14.21.3'.
- 'nds auto on' enables automatic switching based on .nvmrc or .nds file in your project directory.
- After running 'nds init' or 'nds auto', restart your shell or source your shell config.
- To use your default node version in every new shell, ensure your .bashrc/.zshrc includes:
    if [ -d "$HOME/.config/nds/default/bin" ]; then export PATH="$HOME/.config/nds/default/bin:$PATH"; fi
EOF
}

# -------- Command Dispatch --------

show_help_and_exit() {
    nds_help
    exit 0
}

if [[ $# -eq 0 ]] || [[ "$1" =~ ^(-h|--help|help)$ ]]; then
    show_help_and_exit
fi

case "$1" in
    list)
        if [[ "$2" == "pick" ]]; then
            interactive_remove_installed_versions
        else
            list_installed_versions
        fi
        ;;
    available)
        fetch_available_versions_limited
        ;;
    latest)
        install_version "latest"
        ;;
    install)
        if [[ "$2" == "pick" ]]; then
            interactive_version_picker
        else
            install_version "$2"
        fi
        ;;
    use)
        use_version "$2"
        ;;
    set)
        set_default_version "$2"
        ;;
    remove)
        remove_version "$2"
        ;;
    auto)
        if [[ "$2" == "off" ]]; then
            disable_auto_switch
        else
            enable_auto_switch
        fi
        ;;
    auto-switch-internal)
        auto_switch_to_project_version
        ;;
    init)
        nds_init
        ;;
    *)
        nds_help
        ;;
esac
