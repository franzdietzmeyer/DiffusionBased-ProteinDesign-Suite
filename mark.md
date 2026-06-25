RFD3 ISNTALLATION

In the very first step we clone the github repo (https://github.com/RosettaCommons/foundry/):

git clone https://github.com/RosettaCommons/foundry.git
cd ./foundry



Now we create the new uv venv called foundry:

 uv venv foundry --python 3.12

Activate the venv using either the relative path from the current directory or the absolute path:

source foundry/bin/activate



Now we can install the foundry package using pip into this newly created venv:

If we want to install everything (RFD3, LigandMPNN, ProteinMPNN and RF3):


uv pip install 'rc-foundry[all]' # for zsh shell
# --cache-dir ./foundry/cache/

If we only want to install RFD3:

uv pip install rc-foundry[rfd3]

After this is finished, we need to download the checkpoints:

To download all checkpoints:

foundry install all --checkpoint-dir </path/to/ckpt/dir>

RFD3 specific checkpoints:

foundry install rfd3 --checkpoint-dir </path/to/ckpt/dir>



CHAI INSTALLATION

conda create -n chaiai061 python=3.10 -y
conda activate chaiai061
pip install git+https://github.com/chaidiscovery/chai-lab.git


LIGANDMPNN

git clone https://github.com/dauparas/LigandMPNN.git
cd LigandMPNN
bash get_model_params.sh "./model_params"

#setup your conda/or other environment
#conda create -n ligandmpnn_env python=3.11
#pip3 install -r requirements.txt
