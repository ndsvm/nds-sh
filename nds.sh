#!/bin/bash

NDS_DIR="$HOME/.config/nds"
VERSIONS_DIR="$NDS_DIR/versions"
CONFIG_FILE="$NDS_DIR/nds.conf"
DEFAULT_NODE_SYMLINK="$NDS_DIR/default"
NODE_SOURCE_URL="https://nodejs.org/download/release"

# Ensure nds directories exist
mkdir -p "$VERSIONS_DIR"

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux*)   NODE_OS="linux";;
    Darwin*)  NODE_OS="darwin";;
    *) echo "Unsupported OS: $OS"; exit 1;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  NODE_ARCH="x64";;
    arm64)   NODE_ARCH="arm64";;
    aarch64) NODE_ARCH="arm64";;
    *) echo "Unsupported architecture: $ARCH"; exit 1;;
esac

list_installed_versions() {
    echo "Installed Node.js versions:"
    ls "$VERSIONS_DIR" 2>/dev/null || echo "No versions installed."
}

fetch_available_versions() {
    curl -s $NODE_SOURCE_URL/ | grep -oP '(?<=href="v)[^/"]+' | sort -V
}

get_latest_version() {
    fetch_available_versions | tail -n 1
}

get_latest_major_version() {
    local major=$1
    fetch_available_versions | grep "^$major\." | tail -n 1
}

install_version() {
    local version=$1

    if [[ "$version" == "latest" ]]; then
        version=$(get_latest_version)
    elif [[ "$version" =~ ^[0-9]+$ ]]; then
        version=$(get_latest_major_version "$version")
    fi

    if [[ -z "$version" ]]; then
        echo "Could not determine latest version for '$1'."
        return 1
    fi

    local version_dir="$VERSIONS_DIR/$version"
    if [[ -d "$version_dir" ]]; then
        echo "Node.js $version is already installed."
        return
    fi

    echo "Installing Node.js $version..."
    mkdir -p "$version_dir"

    tarball_url="$NODE_SOURCE_URL/v$version/node-v$version-$NODE_OS-$NODE_ARCH.tar.gz"

    temp_file=$(mktemp)
    curl -fsSL "$tarball_url" -o "$temp_file"
    tar -xzf "$temp_file" --strip-components=1 -C "$version_dir"
    rm "$temp_file"

    if [[ $? -eq 0 ]]; then
        echo "Node.js $version installed successfully."
    else
        echo "Failed to install Node.js $version."
        rm -rf "$version_dir"
    fi
}

remove_version() {
    local version=$1

    if [[ "$version" == "latest" ]]; then
        version=$(ls -v "$VERSIONS_DIR" | tail -n 1)
    fi

    if [[ ! -d "$VERSIONS_DIR/$version" ]]; then
        echo "Node.js $version is not installed."
        return
    fi

    echo "Are you sure you want to remove Node.js $version? [y/N]"
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        return
    fi

    rm -rf "$VERSIONS_DIR/$version"
    echo "Node.js $version removed."
}

use_version() {
    local version=$1

    if [[ "$version" == "latest" ]]; then
        version=$(ls -v "$VERSIONS_DIR" | tail -n 1)
    fi

    if [[ ! -d "$VERSIONS_DIR/$version" ]]; then
        echo "Node.js $version is not installed. Installing..."
        install_version "$version"
    fi

    export PATH="$VERSIONS_DIR/$version/bin:$PATH"
    echo "Using Node.js $version in this shell."
}

set_default_version() {
    local version=$1

    if [[ "$version" == "latest" ]]; then
        version=$(ls -v "$VERSIONS_DIR" | tail -n 1)
    fi

    if [[ ! -d "$VERSIONS_DIR/$version" ]]; then
        echo "Node.js $version is not installed. Installing..."
        install_version "$version"
    fi

    ln -sfn "$VERSIONS_DIR/$version" "$DEFAULT_NODE_SYMLINK"
    echo "Default Node.js version set to $version."
}

interactive_version_picker() {
    local available_versions
    available_versions=$(fetch_available_versions)

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

check_and_use_directory_version() {
    if [[ -f ".nvm" ]]; then
        version=$(cat .nvm | tr -d '[:space:]')
    elif [[ -f ".nds" ]]; then
        version=$(cat .nds | tr -d '[:space:]')
    else
        return
    fi

    if [[ -n "$version" ]]; then
        echo "Detected .nvm/.nds file: Switching to Node.js $version"
        use_version "$version"
    fi
}

enable_auto_switch() {
    echo "AUTO_SWITCH=true" > "$CONFIG_FILE"
    echo "Auto-switching enabled. Restart your terminal or source your shell config."
}

disable_auto_switch() {
    echo "AUTO_SWITCH=false" > "$CONFIG_FILE"
    echo "Auto-switching disabled."
}

load_auto_switch_setting() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        AUTO_SWITCH="false"
    fi
}

# Hook into shell to detect directory changes (if enabled)
nds_auto_switch() {
    load_auto_switch_setting
    if [[ "$AUTO_SWITCH" == "true" ]]; then
        check_and_use_directory_version
    fi
}

# Add to PROMPT_COMMAND for Bash
if [[ $SHELL == *"bash"* ]]; then
    PROMPT_COMMAND="nds_auto_switch; $PROMPT_COMMAND"
fi

# Add to precmd for Zsh
if [[ $SHELL == *"zsh"* ]]; then
    precmd_functions+=(nds_auto_switch)
fi

case "$1" in
    list)
        list_installed_versions
        ;;
    available)
        fetch_available_versions
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
    *)
        echo "Usage: nds {list|available|latest|install <version>|use <version>|set <version>|remove <version>|auto [off]}"
        ;;
esac
