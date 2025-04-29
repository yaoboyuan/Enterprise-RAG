#!/bin/bashi
RAG_HTTP_PROXY=$http_proxy
RAG_HTTPS_PROXY=$http_proxy
RAG_NO_PROXY=$no_proxy

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


sudo apt-get update -q
sudo apt-get install -y -q build-essential make zip jq apt-transport-https ca-certificates curl software-properties-common

# Install Docker if not already installed
if command_exists docker; then
    echo "Docker is already installed."
else
    sudo -E curl -fsSL https://get.docker.com -o get-docker.sh
    sudo -E bash get-docker.sh --version 25.0.1
    sudo rm get-docker.sh

    sudo usermod -aG docker "$USER"
    sudo systemctl restart docker

    if command_exists docker; then
        echo "Docker installation successful."
    else
        echo "Docker installation failed."
        exit 1
    fi
fi

# Configure Docker proxy settings if provided
if [[ -n "$RAG_HTTP_PROXY" || -n "$RAG_HTTPS_PROXY" || -n "$RAG_NO_PROXY" ]]; then
    export RAG_HTTP_PROXY
    export RAG_HTTPS_PROXY
    export RAG_NO_PROXY
    envsubst < tpl/config.json.tpl > tmp.config.json
    if [ -e ~/.docker/config.json ]; then
	rm tmp.config.json
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

