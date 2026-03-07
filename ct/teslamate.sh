#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/aaron-vaz/ProxmoxVE/dev/contribution/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aaron-vaz
# License: MIT | https://github.com/aaron-vaz/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/teslamate-org/teslamate

APP="TeslaMate"
var_tags="${var_tags:-tesla;vehicle;tracking}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

export INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/aaron-vaz/ProxmoxVE/dev/contribution/install"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/teslamate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  source /opt/teslamate/.env
  
  local update_grafana=false
  local update_postgresql=false
  
  if systemctl is-active -q grafana-server 2>/dev/null; then
    update_grafana=true
  fi
  
  if [[ -z "$DATABASE_HOST" ]] || [[ "$DATABASE_HOST" == "127.0.0.1" ]] || [[ "$DATABASE_HOST" == "localhost" ]]; then
    if systemctl is-active -q postgresql 2>/dev/null; then
      update_postgresql=true
    fi
  fi

  if check_for_gh_release "teslamate" "teslamate-org/teslamate"; then
    msg_info "Stopping Service"
    systemctl stop teslamate
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/teslamate/.env /opt/teslamate_env_backup 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "teslamate" "teslamate-org/teslamate" "tarball" "latest" "/opt/teslamate"

    msg_info "Updating ${APP}"
    cd /opt/teslamate
    $STD mix local.hex --force
    $STD mix local.rebar --force
    $STD mix deps.get --only prod
    $STD npm install --prefix ./assets
    $STD npm run deploy --prefix ./assets
    $STD MIX_ENV=prod mix do phx.digest, release --overwrite
    msg_ok "Updated ${APP}"

    msg_info "Restoring Data"
    cp /opt/teslamate_env_backup /opt/teslamate/.env 2>/dev/null || true
    rm -f /opt/teslamate_env_backup
    msg_ok "Restored Data"

    if [[ "$update_grafana" == "true" ]]; then
      msg_info "Updating Grafana"
      $STD apt-get update
      $STD apt-get install -y grafana
      msg_ok "Updated Grafana"
    else
      msg_info "Skipping Grafana update (external)"
    fi

    if [[ "$update_postgresql" == "true" ]]; then
      msg_info "Updating PostgreSQL"
      $STD apt-get update
      $STD apt-get install -y postgresql
      msg_ok "Updated PostgreSQL"
    else
      msg_info "Skipping PostgreSQL update (external)"
    fi

    msg_info "Starting Service"
    systemctl start teslamate
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Grafana: http://${IP}:3000 (admin/admin)${CL}"
