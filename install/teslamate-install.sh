#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aaron-vaz
# License: MIT | https://github.com/aaron-vaz/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/teslamate-org/teslamate

export APPLICATION="TeslaMate"
export APP="TeslaMate"

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

if [[ -n "$var_minimal_install" ]]; then
  use_existing_pg="false"
  use_existing_grafana="false"
  use_existing_mqtt="false"
else
  BACKTITLE="TeslaMate Installation"
  
  if command -v whiptail &>/dev/null && [[ -t 1 || -t 0 ]]; then
    SELECTED=$(whiptail --backtitle "$BACKTITLE" --title "Select Components to Install" --checklist \
      "Choose which components to install locally. Select 'No' to use existing service." 15 60 4 \
      "POSTGRES" "PostgreSQL Database" ON \
      "GRAFANA" "Grafana Dashboards" ON \
      "MQTT" "MQTT Broker" ON 3>&1 1>&2 2>&3)
    
    use_existing_pg="true"
    use_existing_grafana="true"
    use_existing_mqtt="true"
    
    if [[ "$SELECTED" == *"POSTGRES"* ]]; then
      use_existing_pg="false"
    fi
    if [[ "$SELECTED" == *"GRAFANA"* ]]; then
      use_existing_grafana="false"
    fi
    if [[ "$SELECTED" == *"MQTT"* ]]; then
      use_existing_mqtt="false"
    fi
  else
    echo ""
    echo "TeslaMate Installation Options"
    echo "=============================="
    echo ""
    printf "Install PostgreSQL locally? (default: yes) [y/n]: "
    read -r response
    if [[ "$response" =~ ^[Nn]|^[Nn][Oo]$ ]]; then
      use_existing_pg="true"
    else
      use_existing_pg="false"
    fi
    
    printf "Install Grafana locally? (default: yes) [y/n]: "
    read -r response
    if [[ "$response" =~ ^[Nn]|^[Nn][Oo]$ ]]; then
      use_existing_grafana="true"
    else
      use_existing_grafana="false"
    fi
    
    printf "Install MQTT Broker locally? (default: yes) [y/n]: "
    read -r response
    if [[ "$response" =~ ^[Nn]|^[Nn][Oo]$ ]]; then
      use_existing_mqtt="true"
    else
      use_existing_mqtt="false"
    fi
  fi
fi

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  gnupg \
  sudo \
  erlang \
  elixir \
  inotify-tools \
  apt-transport-https
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

if [[ "$use_existing_pg" == "true" ]]; then
  PG_HOST=$(whiptail --backtitle "$BACKTITLE" --title "PostgreSQL Configuration" --inputbox "PostgreSQL Host:" 10 60 "localhost" 3>&1 1>&2 2>&3) || exit 1
  PG_PORT=$(whiptail --backtitle "$BACKTITLE" --title "PostgreSQL Configuration" --inputbox "PostgreSQL Port:" 10 60 "5432" 3>&1 1>&2 2>&3) || exit 1
  PG_DB_NAME=$(whiptail --backtitle "$BACKTITLE" --title "PostgreSQL Configuration" --inputbox "Database Name:" 10 60 "teslamate" 3>&1 1>&2 2>&3) || exit 1
  PG_DB_USER=$(whiptail --backtitle "$BACKTITLE" --title "PostgreSQL Configuration" --inputbox "Database User:" 10 60 "teslamate" 3>&1 1>&2 2>&3) || exit 1
  PG_DB_PASS=$(whiptail --backtitle "$BACKTITLE" --title "PostgreSQL Configuration" --passwordbox "Database Password:" 10 60 3>&1 1>&2 2>&3) || exit 1

  msg_info "Testing PostgreSQL Connection"
  export PGPASSWORD="$PG_DB_PASS"
  if ! psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_DB_USER" -d "$PG_DB_NAME" -c "SELECT 1" >/dev/null 2>&1; then
    msg_error "Cannot connect to PostgreSQL database"
    exit 1
  fi
  msg_ok "Connected to PostgreSQL"
else
  PG_VERSION="17" setup_postgresql

  msg_info "Setting up PostgreSQL Database"
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD sudo -u postgres psql -c "CREATE ROLE teslamate WITH LOGIN PASSWORD '$DB_PASS' SUPERUSER;"
  $STD sudo -u postgres psql -c "CREATE DATABASE teslamate WITH OWNER teslamate ENCODING 'UTF8' TEMPLATE template0;"
  $STD sudo -u postgres psql -d teslamate -c "CREATE EXTENSION IF NOT EXISTS cube;"
  $STD sudo -u postgres psql -d teslamate -c "CREATE EXTENSION IF NOT EXISTS earthdistance;"
  PG_DB_USER="teslamate"
  PG_DB_PASS="$DB_PASS"
  PG_DB_NAME="teslamate"
  PG_HOST="127.0.0.1"
  PG_PORT="5432"
  msg_ok "Set up PostgreSQL Database"
fi

if [[ "$use_existing_grafana" == "true" ]]; then
  GRAFANA_URL=$(whiptail --backtitle "$BACKTITLE" --title "Grafana Configuration" --inputbox "Grafana URL (e.g. http://192.168.1.100:3000):" 10 60 "http://localhost:3000" 3>&1 1>&2 2>&3) || exit 1
  GRAFANA_USER=$(whiptail --backtitle "$BACKTITLE" --title "Grafana Configuration" --inputbox "Grafana Username:" 10 60 "admin" 3>&1 1>&2 2>&3) || exit 1
  GRAFANA_PASSWORD=$(whiptail --backtitle "$BACKTITLE" --title "Grafana Configuration" --passwordbox "Grafana Password:" 10 60 3>&1 1>&2 2>&3) || exit 1
else
  msg_info "Installing Grafana"
  wget -qO- https://apt.grafana.com/gpg.key | gpg --dearmor >/usr/share/keyrings/grafana.gpg 2>/dev/null
  cat <<EOF >/etc/apt/sources.list.d/grafana.list
deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main
EOF
  $STD apt update
  $STD apt install -y grafana
  systemctl enable -q --now grafana-server
  msg_ok "Installed Grafana"
  GRAFANA_URL="http://localhost:3000"
  GRAFANA_USER="admin"
  GRAFANA_PASSWORD="admin"
fi

if [[ "$use_existing_mqtt" == "true" ]]; then
  MQTT_HOST=$(whiptail --backtitle "$BACKTITLE" --title "MQTT Configuration" --inputbox "MQTT Host:" 10 60 "localhost" 3>&1 1>&2 2>&3) || exit 1
  MQTT_PORT=$(whiptail --backtitle "$BACKTITLE" --title "MQTT Configuration" --inputbox "MQTT Port:" 10 60 "1883" 3>&1 1>&2 2>&3) || exit 1
  MQTT_USERNAME=$(whiptail --backtitle "$BACKTITLE" --title "MQTT Configuration" --inputbox "MQTT Username (leave empty for anonymous):" 10 60 "" 3>&1 1>&2 2>&3) || exit 1
  if [[ -n "$MQTT_USERNAME" ]]; then
    MQTT_PASSWORD=$(whiptail --backtitle "$BACKTITLE" --title "MQTT Configuration" --passwordbox "MQTT Password:" 10 60 3>&1 1>&2 2>&3) || exit 1
  fi
fi

get_lxc_ip

fetch_and_deploy_gh_release "teslamate" "teslamate-org/teslamate" "tarball" "latest" "/opt/teslamate"

msg_info "Building ${APP}"
cd /opt/teslamate
export MIX_ENV=prod
$STD mix local.hex --force
$STD mix local.rebar --force
$STD mix deps.get --only prod
$STD npm install --prefix ./assets
$STD npm run deploy --prefix ./assets
$STD mix do phx.digest, release --overwrite
msg_ok "Built ${APP}"

msg_info "Configuring ${APP}"
ENCRYPTION_KEY=$(openssl rand -hex 32)

if [[ "$use_existing_mqtt" == "true" ]]; then
  cat <<EOF >/opt/teslamate/.env
LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
TZ=Etc/UTC
PORT=4000
ENCRYPTION_KEY=${ENCRYPTION_KEY}
DATABASE_USER=${PG_DB_USER}
DATABASE_PASS=${PG_DB_PASS}
DATABASE_NAME=${PG_DB_NAME}
DATABASE_HOST=${PG_HOST}
DATABASE_PORT=${PG_PORT}
MQTT_HOST=${MQTT_HOST}
MQTT_PORT=${MQTT_PORT}
EOF
  if [[ -n "$MQTT_USERNAME" ]]; then
    echo "MQTT_USERNAME=${MQTT_USERNAME}" >> /opt/teslamate/.env
    echo "MQTT_PASSWORD=${MQTT_PASSWORD}" >> /opt/teslamate/.env
  fi
else
  cat <<EOF >/opt/teslamate/.env
LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
TZ=Etc/UTC
PORT=4000
ENCRYPTION_KEY=${ENCRYPTION_KEY}
DATABASE_USER=${PG_DB_USER}
DATABASE_PASS=${PG_DB_PASS}
DATABASE_NAME=${PG_DB_NAME}
DATABASE_HOST=${PG_HOST}
DATABASE_PORT=${PG_PORT}
DISABLE_MQTT=true
EOF
fi

chmod 600 /opt/teslamate/.env
msg_ok "Configured ${APP}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/teslamate.service
[Unit]
Description=TeslaMate
After=network.target postgresql.service

[Service]
Type=simple
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/teslamate/.env
WorkingDirectory=/opt/teslamate
ExecStartPre=/opt/teslamate/_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
ExecStart=/opt/teslamate/_build/prod/rel/teslamate/bin/teslamate start
ExecStop=/opt/teslamate/_build/prod/rel/teslamate/bin/teslamate stop

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now teslamate
msg_ok "Created Service"

if [[ "$use_existing_grafana" == "true" ]]; then
  msg_info "Configuring Grafana Datasource (External)"
  cat <<EOF >/tmp/datasource.json
{
  "name": "TeslaMate",
  "type": "postgres",
  "access": "proxy",
  "url": "${PG_HOST}:${PG_PORT}",
  "database": "${PG_DB_NAME}",
  "user": "${PG_DB_USER}",
  "password": "${PG_DB_PASS}",
  "isDefault": true,
  "jsonData": {
    "sslmode": "disable",
    "postgresVersion": 1700
  }
}
EOF
  $STD curl -sf -X POST "${GRAFANA_URL}/api/datasources" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d @/tmp/datasource.json || msg_warn "Datasource may already exist"
  rm -f /tmp/datasource.json
  msg_ok "Configured Grafana Datasource"

  msg_info "Configuring Grafana Dashboards (External)"
  cat /opt/teslamate/grafana/dashboards.yml | sed "s|path: /dashboards|path: /opt/teslamate/grafana/dashboards|g" | sed "s|path: /dashboards_internal|path: /opt/teslamate/grafana/dashboards/internal|g" | sed "s|path: /dashboards_reports|path: /opt/teslamate/grafana/dashboards/reports|g" | \
    $STD curl -sf -X POST "${GRAFANA_URL}/api/provisioning/dashboards" \
    -H "Content-Type: application/yaml" \
    -H "Authorization: Bearer ${GRAFANA_PASSWORD}" \
    --data-binary @- || msg_warn "Dashboards may already exist"
  msg_ok "Configured Grafana Dashboards"
else
  msg_info "Waiting for Grafana to start"
  for i in {1..30}; do
    if curl -sf "http://localhost:3000/api/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! curl -sf "http://localhost:3000/api/health" >/dev/null 2>&1; then
    msg_error "Grafana failed to start"
    exit 1
  fi
  msg_ok "Grafana is ready"

  msg_info "Configuring Grafana Datasource"
  cat <<EOF >/tmp/datasource.json
{
  "name": "TeslaMate",
  "type": "postgres",
  "access": "proxy",
  "url": "localhost:5432",
  "database": "${PG_DB_NAME}",
  "user": "${PG_DB_USER}",
  "password": "${PG_DB_PASS}",
  "isDefault": true,
  "jsonData": {
    "sslmode": "disable",
    "postgresVersion": 1700
  }
}
EOF
  $STD curl -sf -X POST "http://localhost:3000/api/datasources" \
    -H "Content-Type: application/json" \
    -u "admin:admin" \
    -d @/tmp/datasource.json || msg_warn "Datasource may already exist"
  rm -f /tmp/datasource.json
  msg_ok "Configured Grafana Datasource"

  msg_info "Configuring Grafana Dashboards"
  cp /opt/teslamate/grafana/dashboards.yml /etc/grafana/provisioning/dashboards/teslamate.yml
  sed -i "s|path: /dashboards|path: /opt/teslamate/grafana/dashboards|g" /etc/grafana/provisioning/dashboards/teslamate.yml
  sed -i "s|path: /dashboards_internal|path: /opt/teslamate/grafana/dashboards/internal|g" /etc/grafana/provisioning/dashboards/teslamate.yml
  sed -i "s|path: /dashboards_reports|path: /opt/teslamate/grafana/dashboards/reports|g" /etc/grafana/provisioning/dashboards/teslamate.yml
  $STD systemctl restart grafana-server
  msg_ok "Configured Grafana Dashboards"
fi

motd_ssh
customize
cleanup_lxc
