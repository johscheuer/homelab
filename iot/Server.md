# Raspberry Pi

Raspberry OS: https://www.raspberrypi.org/documentation/installation/installing-images/

## Tooling

### General

```bash
sudo apt-get install vim
```

Install golang:

```bash
curl -sLO https://dl.google.com/go/go1.11.4.linux-armv6l.tar.gz
sudo tar -C /usr/local -xzf go1.11.4.linux-armv6l.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.profile
source ~/.profile
```

Install NTP Daemon:

```bash
sudo apt-get install chrony
sudo systemctl status chronyd # ensure it's running and enabled
```

### Prometheus

More details can be found here: https://www.digitalocean.com/community/tutorials/how-to-install-prometheus-on-ubuntu-16-04

```bash
sudo useradd --no-create-home --shell /bin/false prometheus
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo mkdir /etc/prometheus
sudo mkdir /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

cd /tmp
export PROM_VER=2.6.0
export NODE_VER=0.17.0
curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-armv7.tar.gz
curl -LO https://github.com/prometheus/node_exporter/releases/download/v${NODE_VER}/node_exporter-${NODE_VER}.linux-armv7.tar.gz

# Unpack Prometheus Binaries
tar xvf prometheus-${PROM_VER}.linux-armv7.tar.gz
sudo cp prometheus-${PROM_VER}.linux-armv7/prometheus /usr/local/bin/
sudo cp prometheus-${PROM_VER}.linux-armv7/promtool /usr/local/bin/
sudo cp prometheus-${PROM_VER}.linux-armv7/prometheus.yml /etc/prometheus/prometheus.yml
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool
sudo chown -R prometheus:prometheus /etc/prometheus

# Unpack Node Exporter
sudo tar -C /usr/local/bin -xvf node_exporter-${NODE_VER}.linux-armv7.tar.gz --strip=1 node_exporter-${NODE_VER}.linux-armv7/node_exporter
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Remove the variables
unset PROM_VER NODE_VER

# Systemd unit for node exporter
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Systemd unit for Prometheus
sudo tee /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --storage.tsdb.retention 4w
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# ToDo we need some dynamic method!
sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'dht22_exporter'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:8080']
  - job_name: 'pihole_exporter'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:9311']
  - job_name: 'hue_exporter'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:9366']
EOF

sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
```

## Grafana

For more information see here: http://docs.grafana.org/installation/debian/ and here https://github.com/grafana/grafana/issues/12761

```bash
# Since we can't use the apt repo
sudo apt-get install -y adduser libfontconfig
wget https://dl.grafana.com/oss/release/grafana_5.4.2_armhf.deb
sudo dpkg -i grafana_5.4.2_armhf.deb

# Enable the systemd unit
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl status grafana-server
sudo systemctl enable grafana-server.service
```

## DHT22 exporter

```bash
go get github.com/johscheuer/dht22-exporter
go install github.com/johscheuer/dht22-exporter
sudo cp ~/go/bin/dht22-exporter /usr/local/bin/dht22-exporter

sudo useradd --no-create-home --shell /bin/false -G gpio dht22_exporter
sudo tee /etc/systemd/system/dht22_exporter.service <<EOF
[Unit]
Description=DHT22 Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=dht22_exporter
Group=dht22_exporter
Type=simple
ExecStart=/usr/local/bin/dht22-exporter
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start dht22_exporter
sudo systemctl enable dht22_exporter
```

## Pihole exporter

```bash
go get github.com/nlamirault/pihole_exporter
go install github.com/nlamirault/pihole_exporter
sudo cp ~/go/bin/pihole_exporter /usr/local/bin/

sudo useradd --no-create-home --shell /bin/false pihole_exporter
sudo tee /etc/systemd/system/pihole_exporter.service <<EOF
[Unit]
Description=https://github.com/nlamirault/pihole_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=pihole_exporter
Group=pihole_exporter
Type=simple
ExecStart=/usr/local/bin/pihole_exporter -pihole 'http://<redacted>'
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start pihole_exporter
sudo systemctl enable pihole_exporter
```

## Hue exporter

Install the binary

```bash
curl -sLO https://github.com/mitchellrj/hue_exporter/releases/download/v0.2.1/hue_exporter.arm7
sudo mv hue_exporter.arm7 /usr/local/bin/hue_exporter
chmod +x /usr/local/bin/hue_exporter
```

Fetch the API key:

```bash
export HUE_IP=...
curl --data "{\"devicetype\": \"hue_exporter#hue_exporter\"}" "http://${HUE_IP}/api"
..
```

Create the systemd unit:

```bash
sudo useradd --no-create-home --shell /bin/false hue_exporter
sudo mkdir -p /etc/hue_exporter
export HUE_IP=<redacted>
export API_KEY=<redacted>
sudo tee /etc/hue_exporter/hue_exporter.yml <<EOF
ip_address: ${HUE_IP}
api_key: "${API_KEY}"
sensors:
  match_names: true
  ignore_types:
  - CLIPGenericStatus
EOF

sudo tee /etc/systemd/system/hue_exporter.service <<EOF
[Unit]
Description=https://github.com/mitchellrj/hue_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=hue_exporter
Group=hue_exporter
Type=simple
ExecStart=/usr/local/bin/hue_exporter --config.file /etc/hue_exporter/hue_exporter.yml --listen.address :9366
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start hue_exporter
sudo systemctl enable hue_exporter
```

## morningpaper2remarkable

```bash
go get https://github.com/jessfraz/morningpaper2remarkable
sudo useradd --no-create-home --shell /bin/false remarkable
sudo mkdir -p /etc/remarkable

# We need to register the app once
sudo mv ./morningpaper2remarkable /usr/local/bin/morningpaper2remarkable
sudo -u remarkable morningpaper2remarkable --once

sudo tee /etc/systemd/system/remarkable.service <<EOF
[Unit]
Description=https://github.com/jessfraz/morningpaper2remarkable
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory=/home/remarkable
User=remarkable
Group=remarkable
Type=simple
ExecStart=/usr/local/bin/morningpaper2remarkable --once --debug
Restart=no

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/remarkable.timer <<EOF
[Unit]
Description=Run remarkable daily and on boot

[Timer]
OnBootSec=15min
OnUnitActiveSec=1d

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl start remarkable
sudo systemctl enable remarkable
```


# ToDo

- DNS discovery (PoC)
- TimescaleDB for Prometheus
