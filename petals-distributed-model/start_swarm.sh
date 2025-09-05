#!/bin/bash
# Script to launch a Petals server for bigscience/bloom

# === CONFIGURE THESE VALUES ===
HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"                 # replace with your Hugging Face token
LAN_IP="10.52.88.17"                                             # replace with this machine's LAN IP
PORT=31330                                                       # change if you want another port
DATA_DIR="/home/workshop/LLMLAB/2025/Petals/petals-data"         # folder to store persistent identity

# === SCRIPT START ===
mkdir -p "$DATA_DIR"

export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

docker run --rm --gpus all --ipc host \
  -p ${PORT}:${PORT} \
  -v "$DATA_DIR":/data \
  -e HUGGING_FACE_HUB_TOKEN \
  learningathome/petals:main \
  python -m petals.cli.run_server bigscience/bloom \
    --host_maddrs /ip4/${LAN_IP}/tcp/${PORT} \
    --identity_path /data/server1.id \
    --new_swarm
