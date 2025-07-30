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
    local all_versions
    all_versions=$(fetch_available_versions)
    local top_majors
    top_majors=$(echo "$all_versions" | awk -F. '{print $1}' | uniq | head -n 5 | xargs)
    echo "$all_versions" | awk -F. -v majors="$top_majors" '
        BEGIN {
            split(majors, mlist, " ")
            for (i in mlist) keep[mlist[i]]
        }
        keep[$1]
    '
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
    ls "$VERSIONS_DIR" 2>/dev/null || echo "  (none)"
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
    if ! curl -fsSL "$tarball_url" -o "$temp_file"; then
        echo "Failed to download $tarball_url"
        rm -f "$temp_file"
        rm -rf "$version_dir"
        return 1
    fi
    if ! tar -xzf "$temp_file" --strip-components=1 -C "$version_dir"; then
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
    [[ "$version" == "latest" ]] && version=$(ls -v "$VERSIONS_DIR" | head -n 1)
    [[ ! -d "$VERSIONS_DIR/$version" ]] && { echo "Node.js $version is not installed."; return; }
    echo "Are you sure you want to remove Node.js $version? [y/N]"
    read -r confirm
    [[ "$confirm" != "y" ]] && { echo "Aborted."; return; }
    rm -rf "$VERSIONS_DIR/$version"
    echo "Node.js $version removed."
}

use_version() {
    local version=$1
    if [[ "$version" == "latest" ]]; then
        version=$(ls -v "$VERSIONS_DIR" | head -n 1)
    fi
    if [[ ! -d "$VERSIONS_DIR/$version" ]]; then
        echo "Node.js $version is not installed. Installing..."
        install_version "$version"
    fi
    local bin_path="$VERSIONS_DIR/$version/bin"
    # Remove any other nds node bins from PATH
    export PATH="$bin_path:$(echo $PATH | tr ':' '\n' | grep -v "$VERSIONS_DIR/.*/bin" | paste -sd ':')"
    echo "Now using Node.js $version in this shell."
}

set_default_version() {
    local version=$1
    [[ "$version" == "latest" ]] && version=$(ls -v "$VERSIONS_DIR" | head -n 1)
    [[ ! -d "$VERSIONS_DIR/$version" ]] && { echo "Node.js $version is not installed. Installing..."; install_version "$version"; }
    ln -sfn "$VERSIONS_DIR/$version" "$DEFAULT_NODE_SYMLINK"
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

# -------- Shell Integration --------

nds_init() {
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    local nds_path_line='if [ -d "$HOME/.config/nds/default/bin" ]; then export PATH="$HOME/.config/nds/default/bin:$PATH"; fi'
    local func_line='
nds() {
  if [ "$1" = "use" ] && [ -n "$2" ]; then
    export PATH="$HOME/.config/nds/versions/$2/bin:$(echo $PATH | tr ":" "\n" | grep -v "$HOME/.config/nds/versions/.*/bin" | paste -sd ":")"
    echo "Now using Node.js $2 in this shell."
  else
    command nds "$@"
  fi
}
'
    local updated=0

    add_to_shell_config() {
        local shellrc="$1"
        if [[ -f "$shellrc" ]]; then
            if ! grep -Fxq "$nds_path_line" "$shellrc"; then
                echo "$nds_path_line" >> "$shellrc"
                echo "Added nds PATH initialization to $shellrc"
                updated=1
            fi
            # Only add function if not already present
            if ! grep -q "nds() {" "$shellrc" 2>/dev/null; then
                echo "$func_line" >> "$shellrc"
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
  nds list                   List all installed Node.js versions
  nds available              List available Node.js versions (latest 5 majors)
  nds install <version>      Install a specific version (e.g., 22.2.0, 18, latest)
  nds install pick           Interactively pick a Node.js version to install (from latest 5 majors)
  nds latest                 Install the latest Node.js version
  nds use <version>          Use a Node.js version in the current shell
  nds set <version>          Set the default Node.js version for new shells
  nds remove <version>       Remove a specific Node.js version
  nds auto [off]             Enable or disable automatic switching with .nvm/.nds files
  nds init                   Add PATH and shell integration to your shell config
  nds help, -h, --help       Show this help message

EXAMPLES:
  nds available
  nds install 22
  nds use 20.13.1
  nds set latest
  nds remove 18.17.1
  nds install pick

NOTES:
- 'nds available' and 'nds install pick' list only the latest 5 major Node.js versions.
- You can still install and use *any* Node.js version explicitly, e.g. 'nds install 14.21.3'.
- After running 'nds init', restart your shell or source your shell config.
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
        list_installed_versions
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
            echo "Auto-switching OFF (not implemented in this script yet)."
        else
            echo "Auto-switching ON (not implemented in this script yet)."
        fi
        ;;
    init)
        nds_init
        ;;
    *)
        nds_help
        ;;
esac
