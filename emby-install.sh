function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/emby-server ]]; then
        msg_error "No Emby Installation Found!"
        exit
    fi
    LATEST=$(curl -sL https://api.github.com/repos/MediaBrowser/Emby.Releases/releases | grep '"tag_name":' | cut -d'"' -f4)
    msg_info "Stopping Emby"
    systemctl stop emby-server
    msg_ok "Stopped Emby"

    msg_info "Updating Emby"
    wget https://github.com/MediaBrowser/Emby.Releases/releases/download/${LATEST}/emby-server-deb_${LATEST}_amd64.deb &>/dev/null
    dpkg -i emby-server-deb_${LATEST}_amd64.deb &>/dev/null
    rm emby-server-deb_${LATEST}_amd64.deb
    msg_ok "Updated Emby"

    msg_info "Starting Emby"
    systemctl start emby-server
    msg_ok "Started Emby"
    msg_ok "Updated Successfully"
    exit
}
