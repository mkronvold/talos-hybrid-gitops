#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Versions
TERRAFORM_VERSION="1.6.0"

# Installation directory
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo -e "${GREEN}=== Talos Hybrid GitOps - Dependency Installer ===${NC}\n"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "Detected OS: ${GREEN}$OS${NC}, Architecture: ${GREEN}$ARCH${NC}\n"

# Check if running as root for system-wide install
if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}Note: Installing to $INSTALL_DIR requires sudo privileges${NC}"
   USE_SUDO="sudo"
else
   USE_SUDO=""
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


# Check if mg is installed
if ! command_exists mg; then
    echo -e "${YELLOW}Installing mg...${NC}"
    $USE_SUDO apt install -y mg
    echo -e "${GREEN}✓ mg installed${NC}\n"
else
    echo -e "mg: ${GREEN}already installed${NC}\n"
fi

# Function to get installed version
get_version() {
    local cmd=$1
    local version_flag=${2:---version}
    
    if command_exists "$cmd"; then
        $cmd $version_flag 2>&1 | head -n1 || echo "unknown"
    else
        echo "not installed"
    fi
}

# Install Terraform
install_terraform() {
    echo -e "${YELLOW}Installing Terraform $TERRAFORM_VERSION...${NC}"

    # Check if Unzip is installed
    if ! command_exists unzip; then
        echo -e "${YELLOW}Installing Unzip...${NC}"
        $USE_SUDO apt install -y unzip
        echo -e "${GREEN}✓ Unzip installed${NC}\n"
    else
        echo -e "Unzip: ${GREEN}already installed${NC}\n"
    fi

    local tmpdir=$(mktemp -d)
    cd "$tmpdir"
    
    curl -Lo terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
    unzip -q terraform.zip
    $USE_SUDO mv terraform "$INSTALL_DIR/"
    $USE_SUDO chmod +x "$INSTALL_DIR/terraform"
    
    cd - >/dev/null
    rm -rf "$tmpdir"
    
    echo -e "${GREEN}✓ Terraform installed: $(terraform version | head -n1)${NC}"
}

# Install kubectl
install_kubectl() {
    echo -e "${YELLOW}Installing kubectl...${NC}"
    
    local version=$(curl -L -s "https://dl.k8s.io/release/stable.txt")
    
    curl -Lo kubectl "https://dl.k8s.io/release/${version}/bin/${OS}/${ARCH}/kubectl"
    $USE_SUDO mv kubectl "$INSTALL_DIR/"
    $USE_SUDO chmod +x "$INSTALL_DIR/kubectl"
    
    echo -e "${GREEN}✓ kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
}

# Install Flux
install_flux() {
    echo -e "${YELLOW}Installing Flux CD...${NC}"
    
    curl -s https://fluxcd.io/install.sh | $USE_SUDO bash
    
    echo -e "${GREEN}✓ Flux installed: $(flux version --client)${NC}"
}

# Install Omni CLI
install_omnictl() {
    echo -e "${YELLOW}Installing Omni CLI...${NC}"
    
    curl -Lo omnictl "https://github.com/siderolabs/omni/releases/latest/download/omnictl-${OS}-${ARCH}"
    $USE_SUDO mv omnictl "$INSTALL_DIR/"
    $USE_SUDO chmod +x "$INSTALL_DIR/omnictl"
    
    echo -e "${GREEN}✓ Omni CLI installed: $(omnictl version --short 2>/dev/null || omnictl version)${NC}"
}

# Install Talosctl
install_talosctl() {
    echo -e "${YELLOW}Installing talosctl...${NC}"
    
    curl -Lo talosctl "https://github.com/siderolabs/talos/releases/latest/download/talosctl-${OS}-${ARCH}"
    $USE_SUDO mv talosctl "$INSTALL_DIR/"
    $USE_SUDO chmod +x "$INSTALL_DIR/talosctl"
    
    echo -e "${GREEN}✓ talosctl installed: $(talosctl version --short --client)${NC}"
}

# Check and install each tool
echo -e "${GREEN}=== Checking installed tools ===${NC}\n"

# Terraform
if command_exists terraform; then
    echo -e "Terraform: ${GREEN}$(get_version terraform)${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_terraform
    fi
else
    install_terraform
fi

echo ""

# kubectl
if command_exists kubectl; then
    echo -e "kubectl: ${GREEN}$(get_version kubectl version --client --short 2>/dev/null || echo "$(kubectl version --client 2>&1 | head -n1)")${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_kubectl
    fi
else
    install_kubectl
fi

echo ""

# Flux
if command_exists flux; then
    echo -e "Flux: ${GREEN}$(flux version --client 2>&1 | grep "flux:" || echo "installed")${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_flux
    fi
else
    install_flux
fi

echo ""

# Omni CLI
if command_exists omnictl; then
    echo -e "Omni CLI: ${GREEN}$(get_version omnictl version --short 2>/dev/null || omnictl version 2>&1 | head -n1)${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_omnictl
    fi
else
    install_omnictl
fi

echo ""

# Talosctl
if command_exists talosctl; then
    echo -e "talosctl: ${GREEN}$(talosctl version --short --client 2>&1 | head -n1)${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_talosctl
    fi
else
    install_talosctl
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}\n"

# Summary
echo -e "${GREEN}Installed tools:${NC}"
echo -e "  • Terraform: $(terraform version | head -n1)"
echo -e "  • kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -n1)"
echo -e "  • Flux: $(flux version --client 2>&1 | grep "flux:" || echo "installed")"
echo -e "  • Omni CLI: $(omnictl version --short 2>/dev/null || omnictl version 2>&1 | head -n1)"
echo -e "  • talosctl: $(talosctl version --short --client 2>&1 | head -n1)"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Set Omni credentials:"
echo -e "     ${GREEN}source ~/omni.sh${NC}"
echo -e "     ${GREEN}# Or add to ~/.bashrc for automatic loading${NC}"
echo ""
echo -e "  2. Configure site:"
echo -e "     ${GREEN}./scripts/new-site.sh <site-code> <platform> --location \"<location>\"${NC}"
echo ""
echo -e "  3. Deploy infrastructure:"
echo -e "     ${GREEN}./scripts/deploy-infrastructure.sh <site-code> clusters/omni/<site-code>/<cluster>.yaml${NC}"
echo ""
