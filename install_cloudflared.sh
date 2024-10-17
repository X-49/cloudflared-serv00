#!/bin/sh

# Set variables
HOME_DIR="${HOME}/cloudflared-serv00"
LOG_FILE="${HOME_DIR}/cloudflared.log"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# Check Go compiler
check_go() {
    if ! command -v go >/dev/null 2>&1; then
        echo "Error: Go compiler is not installed, please install Go first."
        exit 1
    fi
}

# Download and install Cloudflare Tunnel
install_cloudflared() {
    echo "Starting the installation of cloudflared..."
    GITHUB_URI="https://github.com/cloudflare/cloudflared"
    PAGE_CONTENT=$(fetch -q -o - ${GITHUB_URI}/releases)
    VERSION=$(echo "${PAGE_CONTENT}" | grep -o "href=\"/cloudflare/cloudflared/releases/tag/[^\"]*" | head -n 1 | sed "s;href=\"/cloudflare/cloudflared/releases/tag/;;")
    
    fetch -o cloudflared.tar.gz "${GITHUB_URI}/archive/refs/tags/${VERSION}.tar.gz" || { echo "Failed to download."; exit 1; }
    tar zxf cloudflared.tar.gz || { echo "Unzip failed."; exit 1; }
    cd cloudflared-${VERSION#v} || { echo "Failed to enter directory."; exit 1; }
    
    go build -o cloudflared ./cmd/cloudflared || { echo "Compilation Failure"; exit 1; }
    mv -f ./cloudflared ${HOME_DIR}/cloudflared-freebsd || { echo "Failed to move file."; exit 1; }
    chmod +x ${HOME_DIR}/cloudflared-freebsd || { echo "Failed to modify permissions."; exit 1; }
    cd ${HOME_DIR}
    rm -rf cloudflared.tar.gz cloudflared-${VERSION#v}
    echo "Cloudflare Tunnel installation is complete."
}

# Get and validate user-entered token
get_and_verify_token() {
    while true; do
        printf "Please enter your Cloudflare Tunnel token: "
        read -r ARGO_AUTH
        if [ -z "$ARGO_AUTH" ]; then
            echo "No token is entered, the configuration step is skipped."
            return 1
        fi
        
        echo "Validating token..."
        ${HOME_DIR}/cloudflared-freebsd tunnel --edge-ip-version ipv4 --protocol quic --no-autoupdate run --token $ARGO_AUTH > /dev/null 2>&1 &
        CLOUDFLARED_PID=$!
        sleep 5
        
        if kill -0 $CLOUDFLARED_PID 2>/dev/null; then
            echo "Token authentication was successful!"
            kill $CLOUDFLARED_PID
            wait $CLOUDFLARED_PID 2>/dev/null
            return 0
        else
            echo "Token authentication failed. Please check your token and re-enter it."
        fi
    done
}

# Create a startup script
create_start_script() {
    cat <<EOF > ${HOME_DIR}/start_cloudflared.sh
#!/bin/sh
pkill -f cloudflared-freebsd 2>/dev/null
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ \$(stat -f %z "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
}
rotate_log
TZ='Europe/Moscow' nohup ${HOME_DIR}/cloudflared-freebsd tunnel --edge-ip-version ipv4 --protocol quic --no-autoupdate run --token $ARGO_AUTH >> ${LOG_FILE} 2>&1 &
EOF
    chmod +x ${HOME_DIR}/start_cloudflared.sh || { echo "Failed to create startup script."; exit 1; }
    echo "The startup script start_cloudflared.sh has been created."
}

# Add to the user's crontab
add_to_crontab() {
    (crontab -l 2>/dev/null | grep -v "@reboot cd ${HOME_DIR} && bash start_cloudflared.sh"; echo "@reboot cd ${HOME_DIR} && bash start_cloudflared.sh") | crontab - || { echo "Add to crontab failed."; exit 1; }
    echo "Has been added to the crontab, start_cloudflared.sh will run automatically after a system reboot."
}

# Uninstallation function
uninstall() {
    echo "Uninstalling cloudflared..."
    pkill -f cloudflared-freebsd
    rm -f ${HOME_DIR}/cloudflared-freebsd ${HOME_DIR}/start_cloudflared.sh ${LOG_FILE}
    crontab -l 2>/dev/null | grep -v "@reboot cd ${HOME_DIR} && bash start_cloudflared.sh" | crontab -
    echo "Cloudflare Tunnel has been uninstalled."
}

# Main Functions
main() {
    if [ "$1" = "uninstall" ]; then
        uninstall
        exit 0
    fi

    check_go
    mkdir -p ${HOME_DIR} || { echo "Failed to create directory."; exit 1; }
    cd ${HOME_DIR} || { echo "Failed to enter directory."; exit 1; }
    install_cloudflared
    
    echo "Cloudflare Tunnel is installed. Do you want to configure and run the tunnel now? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        if get_and_verify_token; then
            create_start_script
            add_to_crontab
            ${HOME_DIR}/start_cloudflared.sh
            echo "Cloudflared is configured and started. It will run automatically after a system reboot."
        else
            echo "No token is configured, you can configure and run cloudflared manually later."
        fi
    else
        echo "Skip configuration, you can configure and run cloudflared manually later."
    fi
}

# Running the main function
main "$@"
