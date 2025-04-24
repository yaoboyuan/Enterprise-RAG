#!/bin/bash

# === 彩色輸出工具 ===
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; }

ORIGINAL_DIR=$(pwd)
REPO_NAME="kubespray"
VENVDIR="kubespray-venv"
INVENTORY_DIR="inventory/mycluster"
HOSTS_FILE="$INVENTORY_DIR/hosts.ini"
NODE_IP=$(hostname -I | awk '{print $1}')
CURRENT_USER=$USER
ALL_YML="$INVENTORY_DIR/group_vars/all/all.yml"
ADDONS_YML="$INVENTORY_DIR/group_vars/k8s_cluster/addons.yml"
SUDOERS_FILE="/etc/sudoers.d/${CURRENT_USER}-nopasswd"
SUDOERS_ENTRY="${CURRENT_USER} ALL=(ALL) NOPASSWD:ALL"

if sudo grep -Fxq "$SUDOERS_ENTRY" "$SUDOERS_FILE" 2>/dev/null; then
    info "Sudo 免密已設定，跳過。"
else
    echo "$SUDOERS_ENTRY" | sudo tee "$SUDOERS_FILE" > /dev/null
    if sudo visudo -cf "$SUDOERS_FILE"; then
        success "sudoers 語法正確，免密已啟用。"
    else
        error "$SUDOERS_FILE 語法錯誤，請手動檢查！"
        sudo rm "$SUDOERS_FILE"
        exit 1
    fi
fi

info "更新系統並安裝必要套件..."
sudo apt update && sudo apt install -y python3-venv sshpass || { error "安裝失敗"; exit 1; }

if [ -d "$VENVDIR" ]; then
    info "已偵測到虛擬環境：$VENVDIR"
else
    info "建立新的虛擬環境：$VENVDIR"
    python3 -m venv "$VENVDIR" || { error "建立虛擬環境失敗"; exit 1; }
fi

source "$VENVDIR/bin/activate" || { error "啟動虛擬環境失敗"; exit 1; }

if [ -d "$REPO_NAME" ]; then
    info "Repo 已存在，跳過 Clone 步驟"
else
    info "下載 Kubespray Repo..."
    git clone https://github.com/kubernetes-sigs/kubespray.git || { error "Clone 失敗"; exit 1; }
fi

cd "$REPO_NAME" || { error "進入目錄失敗：$REPO_NAME"; exit 1; }
git checkout v2.27.0 || { error "切換分支失敗"; exit 1; }
pip install -U -r requirements.txt || { error "安裝 Python 依賴失敗"; exit 1; }

info "設定 Kubespray inventory..."
if [ -d "$INVENTORY_DIR" ]; then
    info "Inventory 已存在，跳過複製步驟"
else
    cp -r inventory/sample/ "$INVENTORY_DIR" || { error "複製 inventory 失敗"; exit 1; }
fi

cat > "$HOSTS_FILE" <<EOF
node1 ansible_host=$NODE_IP

[kube_control_plane]
node1

[etcd]
node1

[kube_node]
node1
EOF

info "hosts.ini 已建立，Kubespray 設定完成！"

info "設定 SSH 免密碼登入..."
if [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
    info "生成 SSH 金鑰..."
    ssh-keygen -t rsa -N "" -f "$HOME/.ssh/id_rsa" || { error "生成 SSH 金鑰失敗"; exit 1; }
fi

chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"
ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" "$CURRENT_USER@$NODE_IP" || { error "傳送公鑰失敗，請手動設定 SSH 免密碼登入"; exit 1; }

info "設定 SSH 配置..."
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "$NODE_IP" "$SSH_CONFIG"; then
    cat >> "$SSH_CONFIG" <<EOF

Host $NODE_IP
    IdentityFile "$HOME/.ssh/id_rsa"
    User $CURRENT_USER
EOF
    info "SSH 配置已更新"
else
    info "SSH 配置已存在，無需更新"
fi

info "測試 SSH 連線..."
ssh -o BatchMode=yes "$CURRENT_USER@$NODE_IP" exit && info "SSH 連線成功" || { error "SSH 連線失敗，請檢查設定"; exit 1; }

info "檢查 VPN 設定..."
if [[ -n "$http_proxy" || -n "$https_proxy" ]]; then
    info "偵測到系統 Proxy 設定，更新 all.yml..."
    sed -i "/^http_proxy:/d" "$ALL_YML"
    sed -i "/^https_proxy:/d" "$ALL_YML"
    echo -e "http_proxy: \"$http_proxy\"\nhttps_proxy: \"$https_proxy\"" >> "$ALL_YML"
    info "all.yml Proxy 設定已更新"
else
    warn "未偵測到 Proxy 設定，請手動確認 all.yml 設定"
fi

info "設定 CSI Driver..."
sed -i "/^local_path_provisioner_enabled:/d" "$ADDONS_YML"
echo "local_path_provisioner_enabled: true" >> "$ADDONS_YML"
echo "local_path_provisioner_claim_root: /mnt" >> "$ADDONS_YML"
success "CSI Driver 設定完成"

info "是否立即重置 Kubernetes 叢集？ (y/N)"
read -r choice
case "$choice" in
    y|Y ) ansible-playbook -i "$HOSTS_FILE" --become --become-user=root -e override_system_hostname=false reset.yml;;
    * ) info "跳過叢集重置";;
esac

info "是否立即安裝 Kubernetes 叢集？ (y/N)"
read -r choice
case "$choice" in
    y|Y ) ansible-playbook -i "$HOSTS_FILE" --become --become-user=root -e override_system_hostname=false cluster.yml;;
    * ) info "跳過 Kubernetes 叢集安裝";;
esac

success "Kubernetes 叢集安裝完成！"

info "設定 Kubernetes 使用者環境..."
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown -R $CURRENT_USER:$CURRENT_USER ~/.kube
success "Kubernetes 環境設定完成！"

info "驗證 Kubernetes 叢集..."
kubectl get pods -A
deactivate
cd "$ORIGINAL_DIR"

