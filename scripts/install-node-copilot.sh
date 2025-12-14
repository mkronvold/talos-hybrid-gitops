#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Versions
NVM_VERSION="v0.40.1"
NODE_VERSION="--lts"

echo -e "${GREEN}=== NVM, Node.js, and GitHub Copilot CLI Installer ===${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to source NVM
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
    fi
    if [ -s "$NVM_DIR/bash_completion" ]; then
        source "$NVM_DIR/bash_completion"
    fi
}

# Install NVM
install_nvm() {
    echo -e "${YELLOW}Installing NVM ${NVM_VERSION}...${NC}"
    
    # Download and run NVM installer
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    
    # Load NVM into current session
    load_nvm
    
    echo -e "${GREEN}✓ NVM installed${NC}"
}

# Install Node.js using NVM
install_node() {
    echo -e "${YELLOW}Installing Node.js (LTS)...${NC}"
    
    # Make sure NVM is loaded
    load_nvm
    
    # Install Node.js LTS
    nvm install ${NODE_VERSION}
    nvm use ${NODE_VERSION}
    nvm alias default ${NODE_VERSION}
    
    echo -e "${GREEN}✓ Node.js installed: $(node -v)${NC}"
    echo -e "${GREEN}✓ npm installed: $(npm -v)${NC}"
}

# Install GitHub Copilot CLI
install_copilot_cli() {
    echo -e "${YELLOW}Installing GitHub Copilot CLI...${NC}"
    
    # Make sure NVM is loaded
    load_nvm
    
    # Install Copilot CLI globally
    npm install -g @githubnext/github-copilot-cli
    
    echo -e "${GREEN}✓ GitHub Copilot CLI installed${NC}"
}

# Check and install NVM
echo -e "${GREEN}=== Checking NVM ===${NC}\n"

load_nvm

if command_exists nvm; then
    echo -e "NVM: ${GREEN}$(nvm --version)${NC}"
    read -p "Reinstall NVM? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_nvm
    fi
else
    install_nvm
fi

echo ""

# Check and install Node.js
echo -e "${GREEN}=== Checking Node.js ===${NC}\n"

load_nvm

if command_exists node; then
    echo -e "Node.js: ${GREEN}$(node -v)${NC}"
    echo -e "npm: ${GREEN}$(npm -v)${NC}"
    read -p "Reinstall Node.js? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_node
    fi
else
    install_node
fi

echo ""

# Check and install GitHub Copilot CLI
echo -e "${GREEN}=== Checking GitHub Copilot CLI ===${NC}\n"

load_nvm

if command_exists github-copilot-cli; then
    echo -e "GitHub Copilot CLI: ${GREEN}installed${NC}"
    read -p "Reinstall GitHub Copilot CLI? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_copilot_cli
    fi
else
    install_copilot_cli
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}\n"

# Load NVM for final summary
load_nvm

# Summary
echo -e "${GREEN}Installed tools:${NC}"
echo -e "  • NVM: $(nvm --version)"
echo -e "  • Node.js: $(node -v)"
echo -e "  • npm: $(npm -v)"
if command_exists github-copilot-cli; then
    echo -e "  • GitHub Copilot CLI: installed"
fi

echo ""
echo -e "${YELLOW}Important: NVM setup${NC}"
echo -e "  NVM has been installed to: ${GREEN}\$HOME/.nvm${NC}"
echo ""
echo -e "  The installer has added NVM initialization to your shell profile."
echo -e "  To use NVM in your current shell, run:"
echo -e "    ${GREEN}source ~/.bashrc${NC}  (for bash)"
echo -e "    ${GREEN}source ~/.zshrc${NC}   (for zsh)"
echo ""
echo -e "  Or simply open a new terminal window."
echo ""
echo -e "${YELLOW}GitHub Copilot CLI Setup:${NC}"
echo -e "  After reloading your shell, authenticate with:"
echo -e "    ${GREEN}github-copilot-cli auth${NC}"
echo ""
