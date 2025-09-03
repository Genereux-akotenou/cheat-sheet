#### 1. Create the env
```bash
conda create -n LLMHub python=3.11 -y
```
#### 2. Install Pytorch

| System | GPU | Command |
|--------|---------|---------|
| Linux/WSL | NVIDIA | `pip install torch torchvision torchaudio` |
| Linux/WSL | CPU only | `pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu` |
| Linux | AMD | `pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm5.4.2` |
| MacOS + MPS | Any | `pip install torch torchvision torchaudio` |
| Windows | NVIDIA | `pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117` |
| Windows | CPU only | `pip install torch torchvision torchaudio` |

#### 3. Install transformers
```bash
pip install -U transformers & jupyterlab_widgets
pip install -U ipywidgets jupyterlab_widgets
```

#### 4. Install other requirements
```bash
pip -r requirements.llmenv.txt
```

#### 5. Auto-detect all conda envs
```bash
conda install -y ipykernel
python -m ipykernel install --user --name LLMHub --display-name "LLMHub"
```
OR
```bash
conda activate base
conda install -y nb_conda_kernels
```
