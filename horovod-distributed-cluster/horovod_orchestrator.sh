#!/usr/bin/env bash
set -euo pipefail

echo "== Enter your password to install sshpass =="
sudo apt-get install -y sshpass

# -----------------------------
# Config you can change
# -----------------------------
SSH_PORT=12345
IMAGE="horovod/horovod:latest"
MASTER_CONTAINER_NAME="hmaster"
JUPYTER_CONTAINER_NAME="hjupyter"
WORKER_CONTAINER_NAME="hworker"
JUPYTER_PORT=8888
JUPYTER_TOKEN="lab"

# -----------------------------
# Helpers
# -----------------------------
have() { command -v "$1" >/dev/null 2>&1; }
ask() { local q="$1" d="${2:-}"; read -rp "$q${d:+ [$d]}: " ans || true; echo "${ans:-$d}"; }
ask_secret() {
  local prompt="$1" val
  read -rsp "$prompt: " val
  echo >&2
  printf '%s' "$val"
}
yesno() { local q="$1" d="${2:-y}" a; while true; do read -rp "$q [y/n] (default: $d): " a || true; a="${a:-$d}"; a="${a,,}"; [[ "$a" =~ ^y|yes$ ]] && return 0; [[ "$a" =~ ^n|no$ ]] && return 1; done; }
need_tools() {
  for t in ssh scp sshpass docker; do
    if ! have "$t"; then echo "Missing required tool on controller: $t"; exit 1; fi
  done
}

rcmd() {  # remote non-sudo
  local host="$1" user="$2" pass="$3" cmd="$4"
  sshpass -p "$pass" ssh -q -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$user@$host" "$cmd"
}

test_sudo() {  # returns 0 if sudo works with given password
  local host="$1" user="$2" pass="$3"
  sshpass -p "$pass" ssh -q -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$user@$host" "sudo -k; printf '%s\n' '$pass' | sudo -S -p '' id >/dev/null 2>&1"
}

rsudo() {  # remote sudo with safe quoting
  local host="$1" user="$2" pass="$3" cmd="$4"
  sshpass -p "$pass" ssh -q -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$user@$host" "sudo -k; printf '%s\n' '$pass' | sudo -S -p '' bash -lc 'set -e; $cmd'"
}

rcopy_put() { # scp put
  local src="$1" host="$2" user="$3" pass="$4" dst="$5"
  sshpass -p "$pass" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$src" "$user@$host:$dst"
}


# -----------------------------
# 1) Collect MASTER info
# -----------------------------
need_tools
echo "== MASTER node info =="
MASTER_HOST=$(ask "Master IP/host")
MASTER_USER=$(ask "Master SSH username" "workshop")
MASTER_PASS=$(ask_secret "Master SSH password")
SSH_DIR="/home/$MASTER_USER/.horovod_ssh"

# Workspace path on MASTER host to mount to /workspace
MASTER_CODE=$(ask "Path to your project folder ON MASTER (host path to mount at /workspace)" "/home/$MASTER_USER/HOROVOD/project_0")
if [[ -z "$MASTER_CODE" ]]; then MASTER_CODE="/home/$MASTER_USER/HOROVOD/project_0"; fi

# -----------------------------
# 2) Collect WORKERS
# -----------------------------
WORKERS_HOSTS=() ; WORKERS_USERS=() ; WORKERS_PASS=()

echo
echo "== Add WORKER nodes (IP/user/password). Leave host empty to finish. =="
while true; do
  W_HOST=$(ask "Worker IP/host (empty to stop)" "")
  [[ -z "$W_HOST" ]] && break
  W_USER=$(ask "SSH username for $W_HOST" "$MASTER_USER")
  W_PASS=$(ask_secret "SSH password for $W_USER@$W_HOST")
  WORKERS_HOSTS+=("$W_HOST"); WORKERS_USERS+=("$W_USER"); WORKERS_PASS+=("$W_PASS")
  yesno "Add another worker?" "y" || break
done

# -----------------------------
# 3) Prepare MASTER: docker check, create keypair under $SSH_DIR
# -----------------------------
echo
echo "== Preparing MASTER ($MASTER_HOST) =="
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "docker --version >/dev/null"
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "mkdir -p $SSH_DIR && chmod 700 $SSH_DIR && chown -R root:root $SSH_DIR"
# generate key if not exists
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "[ -f $SSH_DIR/id_rsa ] || ssh-keygen -t rsa -b 4096 -N \"\" -f $SSH_DIR/id_rsa"
# ensure authorized_keys exists containing our pubkey
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "cp -f $SSH_DIR/id_rsa.pub $SSH_DIR/authorized_keys; chmod 600 $SSH_DIR/id_rsa $SSH_DIR/authorized_keys $SSH_DIR/id_rsa.pub"

# grab the master's public key content to controller (safely)
PUBKEY_CONTENT=$(rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "cat $SSH_DIR/id_rsa.pub")

# -----------------------------
# 4) Prepare each WORKER: create $SSH_DIR, put authorized_keys, start worker container
# -----------------------------
if ((${#WORKERS_HOSTS[@]})); then
  echo
  echo "== Preparing WORKERS =="

  # ensure gnome-terminal exists (fallback note)
  if ! command -v gnome-terminal >/dev/null 2>&1; then
    echo "ERROR: gnome-terminal not found. Install it or use the tmux variant."
    exit 1
  fi

  for i in "${!WORKERS_HOSTS[@]}"; do
    H="${WORKERS_HOSTS[$i]}" ; U="${WORKERS_USERS[$i]}" ; P="${WORKERS_PASS[$i]}"
    echo "-- Worker $H"
    rsudo "$H" "$U" "$P" "docker --version >/dev/null"
    rsudo "$H" "$U" "$P" "mkdir -p $SSH_DIR && chown -R root:root $SSH_DIR && chmod 700 $SSH_DIR"
    # write master's pubkey to authorized_keys
    rsudo "$H" "$U" "$P" "printf '%s\n' \"$PUBKEY_CONTENT\" > $SSH_DIR/authorized_keys && chmod 600 $SSH_DIR/authorized_keys"

    # open a new GUI terminal, SSH in, sudo-auth, then run docker in foreground with a real TTY
    gnome-terminal -- bash -lc "
      sshpass -p '$P' ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $U@$H \
        \"sudo -k; \
         printf '%s\n' '$P' | sudo -S -p '' -v || exit 1; \
         sudo bash -lc 'docker rm -f $WORKER_CONTAINER_NAME 2>/dev/null || true; \
           docker run -it --name $WORKER_CONTAINER_NAME \
             --gpus all --network=host \
             -v $SSH_DIR:/root/.ssh:ro \
             $IMAGE \
             /usr/sbin/sshd -p $SSH_PORT -D \
               -o PermitRootLogin=yes \
               -o PubkeyAuthentication=yes \
               -o PasswordAuthentication=no'\"; \
      echo; echo '=== Worker $H session ended ==='; \
      exec bash"
    echo "   Worker $H started in a new terminal window (live logs visible)."
  done
else
  echo "No workers provided; you can still run single-node on the MASTER."
fi


# -----------------------------
# 5) Start JupyterLab on MASTER (detached), mount /workspace, show URL
# -----------------------------
echo
echo "== Starting JupyterLab on MASTER ($MASTER_HOST) =="
# make sure the master has the code path
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "[ -d '$MASTER_CODE' ] || mkdir -p '$MASTER_CODE'"

# kill old Jupyter container if any, then start a fresh one
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "
  docker rm -f $JUPYTER_CONTAINER_NAME 2>/dev/null || true
"
# start Jupyter; notebook root set to / so you see /horovod/examples AND /workspace
rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "
  docker run -d --name $JUPYTER_CONTAINER_NAME \
    --gpus all --network=host \
    -v $SSH_DIR:/root/.ssh:ro \
    -v $MASTER_CODE:/workspace \
    -w /srv/jlab \
    $IMAGE bash -lc \"set -e; \
      pip install -q jupyterlab && \
      mkdir -p /srv/jlab && \
      ln -sfn /horovod/examples /srv/jlab/examples && \
      ln -sfn /workspace        /srv/jlab/workspace && \
      curl -sSL -o /srv/jlab/start.ipynb https://raw.githubusercontent.com/Genereux-akotenou/cheat-sheet/030abb3c119b8b3b3963f83c6dbf21fb67ce6f26/horovod-distributed-cluster/start.ipynb && \
      curl -sSL -o /srv/jlab/start.note https://github.com/Genereux-akotenou/cheat-sheet/blob/2da85711a0d32396e154f3ae784c49d23d26eff1/horovod-distributed-cluster/start.note && \
      jupyter lab --ServerApp.root_dir=/srv/jlab \
                  --ip=0.0.0.0 --port=$JUPYTER_PORT \
                  --ServerApp.token=$JUPYTER_TOKEN \
                  --no-browser --allow-root\"
"
echo "   Waiting for Jupyter to come up (up to 10 min)..."
for i in {1..600}; do
  STATUS=$(rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" \
    "docker inspect -f '{{.State.Status}}' $JUPYTER_CONTAINER_NAME 2>/dev/null || echo dead")
  STATUS=${STATUS//$'\r'/}
  if [[ "$STATUS" != "running" ]]; then
    echo "!! Jupyter container not running (status: $STATUS). Last logs:"
    rsudo "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" "docker logs $JUPYTER_CONTAINER_NAME | tail -n 200" || true
    exit 1
  fi
  PORT_OPEN=$(rcmd "$MASTER_HOST" "$MASTER_USER" "$MASTER_PASS" \
    "ss -lnt 2>/dev/null | awk '\$4 ~ /:$JUPYTER_PORT\$/ {found=1} END{if(found) print \"open\"}' || true")
  if [[ "$PORT_OPEN" == "open" ]]; then
    break
  fi
  sleep 1
done
echo ">> Jupyter URL (MASTER): http://$MASTER_HOST:$JUPYTER_PORT/lab?token=$JUPYTER_TOKEN"

# -----------------------------
# 7) Print summary + Horovod host string
# -----------------------------
echo
echo "========== SUMMARY =========="
echo "MASTER: $MASTER_USER@$MASTER_HOST"
echo "MASTER workspace (host): $MASTER_CODE -> container:/workspace"
if ((${#WORKERS_HOSTS[@]})); then
  echo "WORKERS:"
  for i in "${!WORKERS_HOSTS[@]}"; do
    echo "  - ${WORKERS_USERS[$i]}@${WORKERS_HOSTS[$i]}"
  done
  # Build -H with 1 slot each by default
  HSTR=""
  for h in "${WORKERS_HOSTS[@]}"; do HSTR+="$h:1,"; done
  HSTR="${HSTR%,}"
  echo "Horovod host string: $HSTR"
  echo
  echo "From MASTER shell or Jupyter (!), you can test:"
  echo "  horovodrun -np ${#WORKERS_HOSTS[@]} -H $HSTR -p $SSH_PORT \\"
  echo "    bash -lc 'echo RANK:\$OMPI_COMM_WORLD_RANK on \$(hostname); nvidia-smi -L'"
  echo
  echo "Run your code (mounted at /workspace) e.g.:"
  echo "  horovodrun -np ${#WORKERS_HOSTS[@]} -H $HSTR -p $SSH_PORT python /workspace/train.py"
else
  echo "No workers; single-node possible on MASTER:"
  echo "  docker run -it --rm --gpus all -v $MASTER_CODE:/workspace -w /workspace $IMAGE bash"
  echo "  horovodrun -np 4 -H localhost:4 python train.py"
fi
echo "============================="
