#!/bin/bash

# 用于样式的颜色
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_CYAN="\e[36m"
COLOR_RESET="\e[0m"

# 带有 emoji 支持的日志函数
log() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

# 带有 emoji 支持的错误处理
handle_error() {
    echo -e "${COLOR_RED}❌ 错误: $1${COLOR_RESET}"
    exit 1
}

# 检查文件是否存在的函数
check_file_exists() {
    if [ -f "$1" ]; then
        log "${COLOR_YELLOW}⚠️  文件 $1 已经存在，跳过下载。${COLOR_RESET}"
        return 1
    fi
    return 0
}

# 检查目录是否存在的函数
check_directory_exists() {
    if [ -d "$1" ]; then
        log "${COLOR_GREEN}📁 目录 $1 已经存在。${COLOR_RESET}"
    else
        log "${COLOR_YELLOW}📂 正在创建目录 $1...${COLOR_RESET}"
        mkdir -p "$1" || handle_error "创建目录 $1 失败。"
    fi
}

# 检查并安装未安装的软件包
check_and_install_package() {
    if ! dpkg -l | grep -qw "$1"; then
        log "${COLOR_YELLOW}📦 正在安装 $1...${COLOR_RESET}"
        sudo apt-get install -y "$1" || handle_error "安装 $1 失败。"
    else
        log "${COLOR_GREEN}✔️  $1 已安装！${COLOR_RESET}"
    fi
}

# 准备服务器：更新并安装必要的软件包
prepare_server() {
    log "${COLOR_BLUE}🔄 正在更新服务器并安装必要的软件包...${COLOR_RESET}"
    sudo apt-get update -y && sudo apt-get upgrade -y || handle_error "更新服务器失败。"

    local packages=("make" "build-essential" "pkg-config" "libssl-dev" "unzip" "tar" "lz4" "gcc" "git" "jq")
    for package in "${packages[@]}"; do
        check_and_install_package "$package"
    done
}

# 下载并解压 Fractal Node
download_and_extract() {
    local url="https://github.com/fractal-bitcoin/fractald-release/releases/download/v0.1.7/fractald-0.1.7-x86_64-linux-gnu.tar.gz"
    local filename="fractald-0.1.7-x86_64-linux-gnu.tar.gz"
    local dirname="fractald-0.1.7-x86_64-linux-gnu"

    check_file_exists "$filename"
    if [ $? -eq 0 ]; then
        log "${COLOR_BLUE}⬇️  正在下载 Fractal Node...${COLOR_RESET}"
        wget -q "$url" -O "$filename" || handle_error "下载 $filename 失败。"
    fi

    log "${COLOR_BLUE}🗜️  正在解压 $filename...${COLOR_RESET}"
    tar -zxvf "$filename" || handle_error "解压 $filename 失败。"

    check_directory_exists "$dirname/data"
    cp "$dirname/bitcoin.conf" "$dirname/data" || handle_error "复制 bitcoin.conf 到 $dirname/data 失败。"
}

# 检查钱包是否已经存在
check_wallet_exists() {
    if [ -f "$HOME/.bitcoin/wallets/wallet/wallet.dat" ]; then
        log "${COLOR_GREEN}💰 钱包已经存在，跳过创建钱包。${COLOR_RESET}"
        return 1
    fi
    return 0
}

# 创建新钱包
create_wallet() {
    log "${COLOR_BLUE}🔍 正在检查钱包是否存在...${COLOR_RESET}"
    check_wallet_exists
    if [ $? -eq 1 ]; then
        log "${COLOR_GREEN}✅ 钱包已经存在，无需创建新钱包。${COLOR_RESET}"
        return
    fi

    log "${COLOR_BLUE}💼 正在创建新钱包...${COLOR_RESET}"

    cd fractald-0.1.7-x86_64-linux-gnu/bin || handle_error "进入目录 bin 失败。"
    ./bitcoin-wallet -wallet=wallet -legacy create || handle_error "创建钱包失败。"

    log "${COLOR_BLUE}🔑 正在导出钱包私钥...${COLOR_RESET}"
    ./bitcoin-wallet -wallet=$HOME/.bitcoin/wallets/wallet/wallet.dat -dumpfile=$HOME/.bitcoin/wallets/wallet/MyPK.dat dump || handle_error "导出钱包私钥失败。"

    PRIVATE_KEY=$(awk -F 'checksum,' '/checksum/ {print "钱包私钥:" $2}' $HOME/.bitcoin/wallets/wallet/MyPK.dat)
    log "${COLOR_RED}$PRIVATE_KEY${COLOR_RESET}"
    log "${COLOR_YELLOW}⚠️  请务必记录好你的私钥！${COLOR_RESET}"
}

# 创建 Fractal Node 的 systemd 服务文件
create_service_file() {
    log "${COLOR_BLUE}🛠️  正在为 Fractal Node 创建系统服务...${COLOR_RESET}"

    if [ -f "/etc/systemd/system/fractald.service" ]; then
        log "${COLOR_YELLOW}⚠️  服务文件已存在，跳过创建。${COLOR_RESET}"
    else
        sudo tee /etc/systemd/system/fractald.service > /dev/null << EOF
[Unit]
Description=Fractal Node
After=network-online.target
[Service]
User=$USER
ExecStart=$HOME/fractald-0.1.7-x86_64-linux-gnu/bin/bitcoind -datadir=$HOME/fractald-0.1.7-x86_64-linux-gnu/data/ -maxtipage=504576000
Restart=always
RestartSec=5
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload || handle_error "执行 daemon-reload 失败。"
        sudo systemctl enable fractald || handle_error "启用 fractald 服务失败。"
    fi
}

# 启动 Fractal Node 服务
start_node() {
    log "${COLOR_BLUE}🚀 正在启动 Fractal Node...${COLOR_RESET}"
    sudo systemctl start fractald || handle_error "启动 fractald 服务失败。"
    log "${COLOR_GREEN}🎉 Fractal Node 已成功启动！${COLOR_RESET}"
    log "${COLOR_CYAN}📝 查看节点日志，请运行： ${COLOR_BLUE}sudo journalctl -u fractald -f --no-hostname -o cat${COLOR_RESET}"
}

# 主函数控制脚本执行流程
main() {
    prepare_server
    download_and_extract
    create_service_file
    create_wallet
    start_node
}

# 启动主流程
main
