#!/bin/bash

# ==============================
# Bash script to install Docker, 
# Docker Compose, and run a 
# Windows 10 container
# ==============================

# Update package list
echo "Updating system packages..."
sudo apt update -y

# Install Docker and Docker Compose
echo "Installing Docker and Docker Compose..."
sudo apt install -y docker.io docker-compose

# Ensure Docker service is running
echo "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Create directory for docker-compose file
DIR="dockercomp"
if [ ! -d "$DIR" ]; then
    echo "Creating directory $DIR..."
    mkdir "$DIR"
fi
cd "$DIR"

# Create docker-compose YAML file
YAML_FILE="windows10.yml"
echo "Creating docker-compose file $YAML_FILE..."

cat > $YAML_FILE <<EOL
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "10"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "4G"
      CPU_CORES: "4"
      DISK_SIZE: "400G"
      DISK2_SIZE: "100G"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    stop_grace_period: 2m
EOL

# Run docker-compose
echo "Launching Windows 10 container..."
sudo docker-compose -f $YAML_FILE up -d

echo "Done! Container 'windows' should now be running."


