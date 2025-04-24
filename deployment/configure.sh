#!/bin/bash
# Copyright (C) 2024-2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e
set -o pipefail

usage() {
    echo "Usage: $0 [-p HTTP_PROXY] [-u HTTPS_PROXY] [-n NO_PROXY]"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# !TODO this should be changed to use non-positional parameters
# Parse command-line arguments
while getopts "p:u:n:" opt; do
    case $opt in
        p) RAG_HTTP_PROXY="$OPTARG";;
        u) RAG_HTTPS_PROXY="$OPTARG";;
        n) RAG_NO_PROXY="$OPTARG";;
        *) usage ;;
    esac
done

echo "USE WITH CAUTION THIS SCRIPT USES SUDO PRIVILAGES TO INSTALL NEEDED PACKAGES LOCALLY AND CONFIGURE THEM. \
USING IT MAY OVERWRITE EXISTING CONFIGURATION. Press ctrl+c to cancel. Sleeping for 5s." && sleep 5

# Update package list
sudo apt-get update -q

# Install packages
sudo apt-get install -y -q build-essential make zip jq apt-transport-https ca-certificates curl software-properties-common

# Install Docker if not already installed
if command_exists docker; then
    echo "Docker is already installed."
else
    sudo -E curl -fsSL https://get.docker.com -o get-docker.sh
    sudo -E bash get-docker.sh --version 25.0.1
    sudo rm get-docker.sh

    sudo usermod -aG docker "$USER"

    if command_exists docker; then
        echo "Docker installation successful."
    else
        echo "Docker installation failed."
        exit 1
    fi
fi
sudo systemctl restart docker

# 設定 Docker proxy
if [[ -n "$http_proxy" && -n "$https_proxy" ]]; then
    sudo mkdir -p /etc/systemd/system/docker.service.d/
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=$http_proxy"
Environment="HTTPS_PROXY=$https_proxy"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "Docker 代理設置完成"
else
    echo "沒有檢測到代理設置，跳過 Docker 代理配置"
fi


# if [ "$(docker ps -q -f name=registry)" ]; then
#     echo "✅ Local Docker registry is already running."
# else
#     # 檢查是否有名為 registry 的 container 停止了（但存在）
#     if [ "$(docker ps -aq -f name=registry)" ]; then
#         echo "🔄 Found stopped registry container. Starting it..."
#         docker start registry
#     else
#         echo "🚀 Starting new local Docker registry on port 5000..."
#         docker run -d -p 5000:5000 --restart=always --name registry registry:2
#     fi
# fi

# Configure Docker proxy settings if provided
if [[ -n "$RAG_HTTP_PROXY" || "$RAG_HTTPS_PROXY" || "$RAG_NO_PROXY" ]]; then
    export RAG_HTTP_PROXY
    export RAG_HTTPS_PROXY
    export RAG_NO_PROXY
    envsubst < tpl/config.json.tpl > tmp.config.json
    if [ -e ~/.docker/config.json ]; then
        echo "Warning! Docker config.json exists; continues using the existing file"
    else
        if [ ! -d ~/.docker/ ]; then
            mkdir ~/.docker
        fi
        mv tmp.config.json ~/.docker/config.json
        sudo systemctl restart docker
        echo "Created Docker config.json, restarting docker.service"
    fi
fi

# # Install Kubectl
# echo "starting installing kubectl"
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
# kubectl version --client
# echo "finish installation of kubecvtl"

# Install Helm if not already installed
if command_exists helm; then
    echo "Helm is already installed."
else
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    bash get_helm.sh --version 3.16.1
    rm get_helm.sh

    if command_exists helm; then
        echo "Helm installation successful."
    else
        echo "Helm installation failed."
        exit 1
    fi
fi

# OpenTelemetry contrib journals/systemd collector requires plenty of inotify instances or it fails
# without error occurs: "Insufficient watch descriptors available. Reverting to -n." (in journalctl receiver)
[[ $(sudo sysctl -n fs.inotify.max_user_instances) -lt 8000 ]] && sudo sysctl -w fs.inotify.max_user_instances=8192

echo "All installations and configurations are complete."
