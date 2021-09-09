## Prereq. 

clone this repo and cd into it:

```bash
git clone https://github.com/raphywink/CoquiSTTphonemeAlign.git
cd CoquiSTTphonemeAlign
```

## Training in docker container

### setting up the docker container:

```bash
# get the SST code
git clone --recurse-submodules https://github.com/coqui-ai/STT
cd STT
# overwrite train.py with own version containing fix to make it work with my GPU (RTX 2060 on Ubuntu 20.10):
diff ../train.py train.py # see diff
cp ../train.py train.py 
# build docker container (this might take a while)
# the test train run it does at the end doesn't run on the GPU
docker build -f Dockerfile.train . -t stt-train:latest 
# so let us try it again using a GPU
# by running the docker image with --gpus all
docker run --gpus all -it stt-train:latest
# test that it works (check if training is done on GPU)
./bin/run-ldc93s1.sh
# exit running container
exit
```
### moving from the toy example on to bigger and better/worse things:

#### get and preprocess data

download preproc. german mozilla common voice data (the scripts that gen. the emuDBs are currently not part of this repo):

```bash
# create data dir
mkdir data
# get german CV data that was preprocessed by MAUS
cd data
wget https://www.phonetik.uni-muenchen.de/~raphael/data/CoquiSTTphonemeAlign/CV.zip
unzip CV.zip

# in case the unzip doesn't preserve the symlinks
# create symlinks to wav files in emuDBs to save space
# note: these have to be relative to work inside of the 
# docker container
cd CV/de/test
find ../test_emuDB/ -name '*.wav' -exec ln -s {} . \;
cd ../dev
find ../dev_emuDB/ -name '*.wav' -exec ln -s {} . \;
cd ../train
find ../train_emuDB/ -name '*.wav' -exec ln -s {} . \;
```


Gen. train/dev/test CSV files from emuDBs as well as alphabet.txt +  file:

- `Rscript ./gen_csv_files_from_emuDBs.R`



#### create language model/scorer:

```bash
# start the container and mount data volume
docker run --gpus all -it -v ${PWD}/data:/code/data_volume stt-train:latest
```

build the language model:

```bash

python3 data/lm/generate_lm.py \
--input_txt ./data_volume/coded_phoneme_seqs.txt \
--output_dir ./data_volume/lm/ \
--top_k 15 \
--kenlm_bins kenlm/build/bin/ \
--arpa_order 5 \
--max_arpa_memory "85%" \
--arpa_prune "0|0|1" \
--binary_a_bits 255 \
--binary_q_bits 8 \
--binary_type trie \
--discount_fallback

# get native client and generate scorer
cd data_volume/lm
curl -LO https://github.com/mozilla/DeepSpeech/releases/download/v0.9.3/native_client.amd64.cuda.linux.tar.xz
tar xvf native_client.*.tar.xz

cd /code
./data_volume/lm/generate_scorer_package \
--alphabet ./data_volume/alphabet.txt \
--lm ./data_volume/lm/lm.binary \
--vocab ./data_volume/lm/vocab-15.txt \
--package ./data_volume/lm/kenlm.scorer \
--default_alpha 0.931289039105002 \
--default_beta 1.1834137581510284

```


### perform transfer/fine-tuning learning (currently same alphabet but perf. transfer learning):

```bash
# start the container and mount data volume
docker run --gpus all -it -v ${PWD}/data:/code/data_volume stt-train:latest
```

get the current english checkpoints

```bash
cd /code/data_volume
wget https://github.com/coqui-ai/STT/releases/download/v0.9.3/coqui-stt-0.9.3-checkpoint.tar.gz
tar -xvf coqui-stt-0.9.3-checkpoint.tar.gz
cd /code/
```


```bash
# create dirs for checkpoints + exported model
mkdir ./data_volume/transfer_learning_checkpoints
mkdir ./data_volume/transfer_learning_model

# use the following if training/validation/test crashes
# because of bad files to find the bad ones: 
# head -n 30000 train.csv > train_tmp.csv
# # or
# sed -n '1p;10,50p' train.csv > train_tmp.csv
# head -n 4000 test.csv > test_tmp.csv
# etc.
# and update --train_files paths accordingly

# started with this: 
#    --drop_source_layers 3 \
#    --load_checkpoint_dir ./data_volume/deepspeech-0.9.3-checkpoint/ \

# train (to continue on from saved checkpoints, test only when done):
python3 train.py \
    --load_checkpoint_dir ./data_volume/transfer_learning_checkpoints \
    --alphabet_config_path ./data_volume/alphabet.txt \
    --save_checkpoint_dir ./data_volume/transfer_learning_checkpoints \
    --export_dir  ./data_volume/transfer_learning_model \
    --scorer_path ./data_volume/lm/kenlm.scorer \
    --train_files ./data_volume/CV/de/train/train.csv \
    --train_batch_size 20 \
    --dev_files   ./data_volume/CV/de/dev/dev.csv \
    --dev_batch_size 20 \
    --test_batch_size 20 \
    --test_files  ./data_volume/CV/de/test/test.csv \
    --epochs 1


```
### build pbmm file

still have to use DeepSpeech for this (https://deepspeech.readthedocs.io/en/r0.9/TRAINING.html#exporting-a-model-for-inference)

## inference: 

### start server that returns a TextGrid on request

```bash
# get model and scorer if you didn't train it yourself:
cd data/
wget https://www.phonetik.uni-muenchen.de/~raphael/data/CoquiSTTphonemeAlign/transfer_learning_model.zip
unzip transfer_learning_model.zip
cd ..
```

This example uses Deepspeech not Coqui. This works as the models are currently still interchangeable. This is on my TODO list to update...

- in the directory of this README.md file create a venv and install the requirements (not in Docker container)
- create: `python3 -m venv coqui-stt-venv`
- activate: `source coqui-stt-venv/bin/activate`
- install requirements: `pip install -r requirements.txt`
- create server tmp dir: `mkdir tmp` where the server saves the splits from the VAD chunker
- start server: `python3 audioTranscript_TextGrid_server.py --model ./data/transfer_learning_model`
- perform inference by using `curl` to send file to server to process: `curl -v -X POST -H 'content-type: multipart/form-data' -F aggressive=1 -F SIGNAL=@example_files/himmel_blau_16000.wav http://127.0.0.1:5000/`


## keep on training:

```bash
# get checkpoint if you didn't train:
cd data/
wget https://www.phonetik.uni-muenchen.de/~raphael/data/CoquiSTTphonemeAlign/transfer_learning_checkpoints.zip
unzip transfer_learning_checkpoints.zip
cd ..
```

same training code as above
