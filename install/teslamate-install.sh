#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aaron-vaz
# License: MIT | https://github.com/aaron-vaz/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/teslamate-org/teslamate

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  erlang \
  elixir \
  inotify-tools \
  apt-transport-https
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

PG_VERSION="17" PG_EXTENSIONS="cube,earthdistance" setup_postgresql
PG_DB_NAME="teslamate" PG_DB_USER="teslamate" PG_DB_EXTENSIONS="cube,earthdistance" setup_postgresql_db

msg_info "Installing Grafana"
wget -qO- https://apt.grafana.com/gpg.key | gpg --dearmor >/usr/share/keyrings/grafana.gpg 2>/dev/null
cat <<EOF >/etc/apt/sources.list.d/grafana.list
deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main
EOF
$STD apt update
$STD apt install -y grafana
systemctl enable -q --now grafana-server
msg_ok "Installed Grafana"

get_lxc_ip

fetch_and_deploy_gh_release "teslamate" "teslamate-org/teslamate" "tarball" "latest" "/opt/teslamate"

msg_info "Building ${APP}"
cd /opt/teslamate
$STD MIX_ENV=prod mix local.hex --force
$STD MIX_ENV=prod mix local.rebar --force
$STD mix deps.get --only prod
$STD npm install --prefix ./assets
$STD npm run deploy --prefix ./assets
$STD MIX_ENV=prod mix do phx.digest, release --overwrite
msg_ok "Built ${APP}"

msg_info "Configuring ${APP}"
ENCRYPTION_KEY=$(openssl rand -hex 32)
cat <<EOF >/opt/teslamate/.env
LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
TZ=Etc/UTC
PORT=4000
ENCRYPTION_KEY=${ENCRYPTION_KEY}
DATABASE_USER=${PG_DB_USER}
DATABASE_PASS=${PG_DB_PASS}
DATABASE_NAME=${PG_DB_NAME}
DATABASE_HOST=127.0.0.1
DISABLE_MQTT=true
EOF
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
  -d @/tmp/datasource.json || msg_warn "Datasource may already exist or failed to configure"
rm -f /tmp/datasource.json
msg_ok "Configured Grafana Datasource"

msg_info "Configuring Grafana Dashboards"
cp /opt/teslamate/grafana/dashboards.yml /etc/grafana/provisioning/dashboards/teslamate.yml
sed -i "s|path: /dashboards|path: /opt/teslamate/grafana/dashboards|g" /etc/grafana/provisioning/dashboards/teslamate.yml
sed -i "s|path: /dashboards_internal|path: /opt/teslamate/grafana/dashboards/internal|g" /etc/grafana/provisioning/dashboards/teslamate.yml
sed -i "s|path: /dashboards_reports|path: /opt/teslamate/grafana/dashboards/reports|g" /etc/grafana/provisioning/dashboards/teslamate.yml
$STD systemctl restart grafana-server
msg_ok "Configured Grafana Dashboards"

motd_ssh
customize
cleanup_lxc
