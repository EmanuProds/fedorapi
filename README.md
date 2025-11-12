# Fedora Post-Installation Script 💻

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)
[![Fedora](https://img.shields.io/badge/Fedora-39+-blue.svg)](https://getfedora.org/)
[![Version](https://img.shields.io/badge/Version-2.0.0-green.svg)]()

> 🚀 **Modern, interactive post-installation setup for Fedora Linux** - Transform your fresh Fedora installation into a fully-featured development workstation with just a few clicks!

## ✨ Features

- 🔍 **Automatic Fedora Version Detection** - Works seamlessly across Fedora versions (39+)
- 🎯 **Interactive Menu System** - User-friendly interface with clear options
- 🛡️ **Comprehensive Error Handling** - Robust logging and failure recovery
- 📦 **Modern Package Management** - DNF + Flatpak integration
- 🎨 **Development Fonts** - Fira Code, JetBrains Mono, and more
- 🛠️ **Development Tools** - VS Code, Git, Node.js, Python, and essential utilities
- 🎵 **Multimedia Applications** - Music, video, and productivity apps via Flatpak
- 🔧 **GNOME Extensions** - AppIndicator, Caffeine, GSConnect, and more
- 🧹 **System Cleanup** - Remove bloatware and optimize performance
- 📋 **Detailed Logging** - Complete installation logs for troubleshooting

## 🎯 What's Included

### System Updates & Cleanup
- ✅ System package updates
- 🗑️ Bloatware removal (Rhythmbox, Totem, etc.)
- 📚 Additional repositories (RPM Fusion, COPR)

### Development Environment
- 💻 **Visual Studio Code** - Microsoft's powerful code editor
- 🐙 **Git** - Version control system
- 🟢 **Node.js & NPM** - JavaScript runtime and package manager
- 🐍 **Python** - Programming language with pip
- 🔧 **Essential Tools** - GParted, GameMode, and more

### Fonts & Typography
- 🔥 **Fira Code** - Monospaced font with programming ligatures
- ✈️ **JetBrains Mono** - Carefully crafted monospace font

### GNOME Desktop Enhancements
- 🔌 **AppIndicator Support** - Tray icons for various applications
- ☕ **Caffeine** - Prevent screen lock and sleep
- 📱 **GSConnect** - KDE Connect integration for Android devices
- 🎛️ **GNOME Tweaks** - Advanced desktop customization

### Flatpak Applications
- 🧩 **Extension Manager** - Manage GNOME extensions easily
- 🔒 **Flatseal** - Manage Flatpak permissions
- 🎵 **Decibels** - Audio player for GNOME
- 🔄 **Converter** - Unit conversion tool
- 🌙 **Insomnia** - REST API client
- 🗄️ **DBeaver** - Universal database tool

## 🚀 Quick Start

### Prerequisites
- ✅ Fresh Fedora installation (39+)
- ✅ Internet connection
- ✅ Sudo privileges
- ✅ Bash 4.0+

### Installation & Usage

1. **Download the script:**
   ```bash
   git clone https://github.com/EmanuProds/post-installation_fedora.git
   cd post-installation_fedora
   ```

2. **Make it executable:**
   ```bash
   chmod +x fedoraPI.sh
   ```

3. **Run the script:**
   ```bash
   ./fedoraPI.sh
   ```

4. **Follow the interactive menu** to choose what to install!

## 📖 Menu Options

The script provides an intuitive **graphical menu system** using `dialog`:

1. **System Update & Cleanup** - Update packages, remove bloatware, add repositories
2. **Install Fonts** - Development fonts (Fira Code, JetBrains Mono)
3. **Install Development Tools** - VS Code, Git, Node.js, and essential utilities
4. **Setup Flatpak & Install Apps** - Flatpak ecosystem and applications
5. **Run Complete Setup** - Install everything automatically
6. **Exit** - Quit the script

### Interface Features
- 🎯 **Confirmation dialogs** for all operations
- 📊 **Progress bars** during installations
- ✅ **Success notifications** after each task
- 🚫 **Cancel/Escape support** to exit anytime
- 🖥️ **Terminal-based GUI** - works in any terminal environment

## 🔧 Technical Details

### Automatic Version Detection
The script automatically detects your Fedora version and configures repositories accordingly:

- **Fedora 39-41**: Legacy compatibility mode
- **Fedora 42+**: Full feature support
- **Future versions**: Automatic adaptation

### Repository Management
- **RPM Fusion**: Free and Non-Free repositories
- **Microsoft VS Code**: Official repository
- **COPR**: Community repositories (linuxtoys)

### Error Handling
- Comprehensive logging to `/tmp/fedora_pi_*.log`
- Graceful failure handling with detailed error messages
- Network connectivity checks
- Repository availability validation

### Security Features
- Non-root execution (uses sudo when needed)
- GPG key verification for repositories
- Safe package removal (checks before removing)

## 📋 Requirements

### System Requirements
- **OS**: Fedora Linux 39 or later
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 10GB free space
- **Network**: Active internet connection

### Software Dependencies
- `bash` 4.0+
- `sudo` privileges
- `dnf` package manager
- `curl` for repository validation
- `flatpak` (installed automatically if missing)

## 🐛 Troubleshooting

### Common Issues

**"No internet connection detected"**
- Check your network settings
- Ensure DNS resolution is working
- Try `ping 8.8.8.8` to test connectivity

**"Repository not available"**
- The script automatically handles unavailable repositories
- Check the log file for details
- Some features may be limited for older Fedora versions

**"Permission denied"**
- Ensure you're running as a regular user (not root)
- Check that sudo is configured correctly

### Log Files
All operations are logged to `/tmp/fedora_pi_*.log`. Check this file for detailed error information.

### Getting Help
1. Check the log file for error details
2. Ensure all prerequisites are met
3. Try running individual menu options instead of complete setup

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
