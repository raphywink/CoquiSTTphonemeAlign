#!/bin/bash

cd data
mkdir LibriSpeech
cd LibriSpeech

echo "####### importing dev-clean"
wget http://www.openslr.org/resources/12/dev-clean.tar.gz
tar -xzvf dev-clean.tar.gz
mv LibriSpeech/* .
rm dev-clean.tar.gz
rm -r LibriSpeech
# move to top level dir and convert using sox
cd dev-clean
find . -name "*.flac" -exec mv {} . \;
find . -maxdepth 1 -type d -exec rm -r {} \;

for f in *.flac
do
    echo $f
    sox $f -r 16000 -b 16 "${f%.flac}.wav"
done

find . -name "*.flac" -exec rm -f {} \;
cp ../../LibriSpeech_phoneme_csv_files/dev.csv .
cd ..

echo "####### importing test-clean"
wget http://www.openslr.org/resources/12/test-clean.tar.gz
tar -xzvf test-clean.tar.gz
mv LibriSpeech/* .
rm test-clean.tar.gz
rm -r LibriSpeech
# move to top level dir and convert using sox
cd test-clean
find . -name "*.flac" -exec mv {} . \;
find . -maxdepth 1 -type d -exec rm -r {} \;

for f in *.flac
do
    echo $f
    sox $f -r 16000 -b 16 "${f%.flac}.wav"
done

find . -name "*.flac" -exec rm -f {} \;
cp ../../LibriSpeech_phoneme_csv_files/test.csv .
cd ..

echo "####### importing train-clean-100"
wget http://www.openslr.org/resources/12/train-clean-100.tar.gz
tar -xzvf train-clean-100.tar.gz
mv LibriSpeech/* .
rm train-clean-100.tar.gz
rm -r LibriSpeech
# move to top level dir and convert using sox
cd train-clean-100
find . -name "*.flac" -exec mv {} . \;
find . -maxdepth 1 -type d -exec rm -r {} \;

for f in *.flac
do
    echo $f
    sox $f -r 16000 -b 16 "${f%.flac}.wav"
done

find . -name "*.flac" -exec rm -f {} \;
cp ../../LibriSpeech_phoneme_csv_files/train.csv .
cd ..
