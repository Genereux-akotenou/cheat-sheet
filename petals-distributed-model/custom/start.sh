#!/bin/bash
# Path on host with your fork (must contain setup/pyproject or be pip-installable)
PETALS_SRC="/home/workshop/LLMLAB/2025/Petals/petals-fork"  # <-- your repo root
DATA_DIR="/home/workshop/LLMLAB/2025/Petals/petals-data"
HF_TOKEN="hf_xxx..."
LAN_IP="10.52.88.17"
PORT=31330
CUSTOM_MODEL="swiss-ai/Apertus-8B-Instruct-2509"

mkdir -p "$DATA_DIR"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

docker run --rm --gpus all --ipc host \
  -p ${PORT}:${PORT} \
  -v "$DATA_DIR":/data \
  -v "$PETALS_SRC":/workspace/petals \
  -e HUGGING_FACE_HUB_TOKEN \
  --entrypoint bash \
  learningathome/petals:main \
  -lc "
    pip install --no-cache-dir -e /workspace/petals && \
    python -m petals.cli.run_server ${CUSTOM_MODEL} \
      --host_maddrs /ip4/${LAN_IP}/tcp/${PORT} \
      --identity_path /data/server1.id \
      --new_swarm
  "
