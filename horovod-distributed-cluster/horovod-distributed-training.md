### Model Training using pytorch or tf on distributed machine

#### I. On single Node

```bash
sudo docker run --gpus all -it horovod/horovod:latest bash
root@node7:/horovod/examples/keras# cd keras
root@node7:/horovod/examples/keras# horovodrun -np 4 -H localhost:4 python keras_mnist_advanced.py
```

#### II. On many nodes

1. On master node, create RSA certificate for passwordless communication between nodes.

```bash
sudo mkdir -p /opt/horovod/ssh
sudo ssh-keygen -t rsa -b 4096 -N "" -f /opt/horovod/ssh/id_rsa
sudo cp /opt/horovod/ssh/id_rsa.pub /opt/horovod/ssh/authorized_keys
sudo chmod 700 /opt/horovod/ssh
sudo chmod 600 /opt/horovod/ssh/id_rsa /opt/horovod/ssh/authorized_keys
```

2. From mast to work(r8) share the public key

```bash
ssh -t workshop@r8 'sudo mkdir -p /opt/horovod/ssh && sudo chown -R root:root /opt/horovod/ssh && sudo chmod 700 /opt/horovod/ssh'
sudo scp /opt/horovod/ssh/id_rsa.pub workshop@r8:/tmp/horovod_id_rsa.pub
ssh -t workshop@r8 'sudo install -d -m 700 -o root -g root /opt/horovod/ssh && \
  sudo install -m 600 -o root -g root /tmp/horovod_id_rsa.pub /opt/horovod/ssh/authorized_keys && \
  sudo rm -f /tmp/horovod_id_rsa.pub'
```

3. Start the worker in background waiting for tasks

```bash
sudo docker rm -f hworker 2>/dev/null
sudo docker run -d --name hworker \
  --gpus all --network=host \
  -v /opt/horovod/ssh:/root/.ssh:ro \
  horovod/horovod:latest \
  /usr/sbin/sshd -p 12345 -D \
    -o PermitRootLogin=yes \
    -o PubkeyAuthentication=yes \
    -o PasswordAuthentication=no
```

4. From master open the container to run training

```bash
sudo docker run -it --rm --name hmaster \
  --gpus all --network=host \
  -v /opt/horovod/ssh:/root/.ssh:ro \
  horovod/horovod:latest bash
```

From inside the container:
a. Prove which host each rank is on

```bash
horovodrun -np 2 -H node7:1,node8:1 -p 12345 \
  python -c "import horovod.tensorflow as hvd, socket; hvd.init(); print('rank', hvd.rank(), 'on', socket.gethostname())"
```

b. Confirm GPU visibility per rank

```bash
horovodrun -np 2 -H node7:1,node8:1 -p 12345 \
  bash -lc 'echo RANK:$OMPI_COMM_WORLD_RANK on $(hostname); nvidia-smi -L'
```

c. Run code

```bash
cd keras
horovodrun -np 2 -H node7:1,node8:1 -p 12345 python keras_mnist_advanced.py
```

5. Run your own code on the master code. Chnage the path to mount your local project folder to the container.

```bash
sudo docker run -it --rm --name hmaster \
  --gpus all \
  --network=host \
  -v /opt/horovod/ssh:/root/.ssh:ro \
  -v /home/workshop/myproject:/workspace \
  -w /workspace \
  horovod/horovod:latest bash
```

MAGIC, isn't it?

### Use automatic script to orchestrate all:

- [horovod_orchestrator.sh](./horovod-distributed-cluster/horovod_orchestrator.sh)
