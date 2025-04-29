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
USING IT MAY OVERWRITE EXISTING CONFIGURATION. Press ctrl+c to cancel. Sleeping for 30s." && sleep 30

# Update package list
sudo apt-get update -q

# Install packages
sudo apt-get install -y -q build-essential make zip jq apt-transport-https ca-certificates curl software-properties-common

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
