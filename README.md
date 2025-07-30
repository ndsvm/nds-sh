# Nodes (nds)

A simple, fast, dependency-free Node.js version manager, written in Bash.

- **Install, switch, and remove Node.js versions with ease**
- **Automatic project version switching using `.nvmrc or .nds`**
- **Optional `fzf` support for interactive version picking**
- **Zero magic, just robust and clean shell scripting**

## 🚀 Quick Install

Paste this in your terminal to download and install `nds` to `~/.local/bin` and add it to your PATH:

```sh
curl -fsSL https://raw.githubusercontent.com/ndsvm/nds-sh/main/nds.sh -o ~/.local/bin/nds
chmod +x ~/.local/bin/nds
# Add to PATH if not already present
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
  export PATH="$HOME/.local/bin:$PATH"
fi
nds init
```

> If you want to install somewhere else, just change the path.

## 🛠️ Features

- **Install any Node.js version:**\
  `nds install <version>` (e.g. `22.2.0`, `18`, `latest`)
- **Switch version for current shell:**\
  `nds use <version>`
- **Set a default Node.js for new shells:**\
  `nds set <version>`
- **Auto-switch on entering directories with `.nvmrc or .nds`**\
  `nds auto`
- **Interactive pickers with `fzf`**\
  `nds install pick`, `nds list pick`
- **Clean removal:**\
  `nds remove <version>`

## 🧑‍💻 Usage

| Command                 | Description                                       |
| ----------------------- | ------------------------------------------------- |
| `nds list`              | List all installed Node.js versions               |
| `nds list pick`         | Interactively remove installed versions           |
| `nds available`         | Show available Node.js versions (latest 5 majors) |
| `nds install <version>` | Install a Node.js version                         |
| `nds install pick`      | Interactively pick a version to install           |
| `nds use <version>`     | Use a Node.js version in the current shell        |
| `nds set <version>`     | Set default Node.js version and use it now        |
| `nds remove <version>`  | Remove a Node.js version                          |
| `nds auto`              | Enable automatic switching with `.nvmrc`/`.nds`   |
| `nds auto off`          | Disable auto-switch and remove shell hooks        |
| `nds init`              | Add PATH and shell integration to your shell      |
| `nds help`              | Show help                                         |

### Examples

```sh
nds install 22
nds use 20.13.1
nds set latest
nds remove 18.17.1
nds available
nds list pick
nds install pick
nds auto
```

## 🎯 Project Version Auto-Switching

- Run `nds auto` to enable auto-switching on directory change.
- Works with `.nvmrc` or `.nds` in your project root.
- To disable, run `nds auto off`.
- **Restart your shell after enabling/disabling.**

## 📝 Requirements

- `bash`
- `curl`
- [`fzf`](https://github.com/junegunn/fzf) (optional, for interactive pickers)

## 💾 Uninstall

To remove `nds`, simply delete:

```sh
rm -rf ~/.config/nds
rm -f ~/.local/bin/nds
```

And optionally remove the shell lines from your `.bashrc` or `.zshrc` if you used `nds init` or `nds auto`.

## ❤️ Contributing

Pull requests, bug reports, and ideas are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) if available, or open an issue or PR.

## 📄 License

MIT License — see [LICENSE](LICENSE)

---

## 🙏 Credits

Inspired by [nvm](https://github.com/nvm-sh/nvm), but intentionally minimal and blazing fast.
