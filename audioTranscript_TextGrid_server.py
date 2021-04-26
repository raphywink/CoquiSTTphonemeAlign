import sys
import os
import logging
import argparse
import subprocess
import shlex
import numpy as np
import wavTranscriber
import json
from flask import Flask, request, jsonify
import csv
import uuid
import tgt # TextGridTools


# Debug helpers
logging.basicConfig(stream=sys.stderr, level=logging.DEBUG)


def main(args):
    parser = argparse.ArgumentParser(description='Transcribe long audio files using webRTC VAD or use the streaming interface')
    parser.add_argument('--aggressive', type=int, choices=range(4), required=False,
                        help='Determines how aggressive filtering out non-speech is. (Interger between 0-3)')
    parser.add_argument('--audio', required=False,
                        help='Path to the audio file to run (WAV format)')
    parser.add_argument('--model', required=True,
                        help='Path to directory that contains all model files (output_graph and scorer)')
    parser.add_argument('--stream', required=False, action='store_true',
                        help='To use deepspeech streaming interface')
    args = parser.parse_args()

    # Point to a path containing the pre-trained models & resolve ~ if used
    dirName = os.path.expanduser(args.model)

    # Resolve all the paths of model files
    output_graph, scorer = wavTranscriber.resolve_models(dirName)

    # Load output_graph, alpahbet and scorer
    model_retval = wavTranscriber.load_model(output_graph, scorer)

    # load MAUS inventary mapping into dict
    maus_inventory_mapping = {}
    line_count = 0
    with open(os.path.join(dirName, 'maus_inventory_deu-DE.csv')) as csv_file:
        csv_reader = csv.reader(csv_file, delimiter=',')
        line_count = 0
        for row in csv_reader:
            if line_count != 0:
                maus_inventory_mapping[row[-1]] = row[0]
            line_count += 1

    print(maus_inventory_mapping)
    
    # define app
    app = Flask(__name__)

    @app.route('/', methods=['POST'])
    def process_file():
        print('vad aggressive value: ' + request.form.get('aggressive'))
        print(request.files['SIGNAL'])
        wav_path = './tmp/' + str(uuid.uuid4()) + ".wav"
        request.files['SIGNAL'].save(wav_path)

        inference_time = 0.0
        # Run VAD on the input file (segments contain all frames and have to be joined)
        segments, sample_rate, audio_length = wavTranscriber.vad_segment_generator(wav_path, int(request.form.get('aggressive')))
        # create empty tier
        tier_vad_chunks = tgt.core.IntervalTier(start_time=0, end_time=0, name='vadChunks', objects=None)
        ## currently 3 candidates are returned (hard coded)
        interval_tiers_alignement = {}
        interval_tiers_alignement[0] = tgt.core.IntervalTier(start_time=0, end_time=audio_length, name='alignCandi1', objects=None)
        interval_tiers_alignement[1] = tgt.core.IntervalTier(start_time=0, end_time=audio_length, name='alignCandi2', objects=None)
        interval_tiers_alignement[2] = tgt.core.IntervalTier(start_time=0, end_time=audio_length, name='alignCandi3', objects=None)

        point_tiers_alignement = {}
        point_tiers_alignement[0] = tgt.core.PointTier(start_time=0, end_time=audio_length, name='alignCand1-steps', objects=None)
        point_tiers_alignement[1] = tgt.core.PointTier(start_time=0, end_time=audio_length, name='alignCand2-steps', objects=None)
        point_tiers_alignement[2] = tgt.core.PointTier(start_time=0, end_time=audio_length, name='alignCand3-steps', objects=None)


        # loop through vad segs
        for i, segment in enumerate(segments):
            # Run deepspeech on the chunk that just completed VAD
            logging.debug("Processing chunk %002d" % (i,))
            audio = np.frombuffer(b''.join([f.bytes for f in segment]), dtype=np.int16)
            segment_transcript, segment_metadata_list, segment_inference_time = wavTranscriber.stt(model_retval[0], audio, sample_rate)
            inference_time += segment_inference_time
            # append vad_chunk as new interval in textgrid object
            logging.debug("vad_chunk_start %f" % (segment[0].timestamp))
            logging.debug("vad_chunk_end %f" % (segment[-1].timestamp + segment[-1].duration))
            # translate segment_transcript to human readable version
            # print("###############")
            # print(segment_transcript)
            for key in maus_inventory_mapping.keys():
                segment_transcript = segment_transcript.replace(key, maus_inventory_mapping[key] + " ")
            interval = tgt.core.Interval(
                start_time = segment[0].timestamp, 
                end_time = segment[-1].timestamp + segment[-1].duration, 
                text = segment_transcript
            )
            tier_vad_chunks.add_interval(interval)

            for j, segment_metadata_list_cand in enumerate(segment_metadata_list):
                curChar = ''
                charCounter = 0
                cur_seg_start_time = segment[0].timestamp # 0 is start of segment
                # print(segment_metadata_list)
            #     # print(type(segment_metadata_list))
            #     # print(j)
                for k, segment_metadata in enumerate(segment_metadata_list_cand):
                    # print(segment_metadata)
                    if(charCounter == 0):
                        # if not at beginning of vad_segment
                        # append new segment using start_time of current seg as end_time
                        if curChar != '':
                            interval = tgt.core.Interval(
                                start_time = cur_seg_start_time,
                                end_time = segment[0].timestamp + segment_metadata[2],
                                text = maus_inventory_mapping[curChar.strip()]
                            )
                            point = tgt.core.Point(
                                time = segment[0].timestamp + segment_metadata[2],
                                text = maus_inventory_mapping[curChar.strip()]
                            )

                            interval_tiers_alignement[j].add_interval(interval)
                            point_tiers_alignement[j].add_point(point)

                        cur_seg_start_time = segment[0].timestamp + segment_metadata[2]
                        curChar = segment_metadata[0] # this is always b'xe2'
                        charCounter += 1
                    elif (charCounter == 1):
                        curChar += segment_metadata[0]
                        charCounter += 1
                        point = tgt.core.Point(
                            time = segment[0].timestamp + segment_metadata[2],
                            text = "?"
                        )
                        point_tiers_alignement[j].add_point(point)

                    elif(charCounter == 2):
                        # reached end of code point entry in maus_inventory_mapping utf8 symbol
                        curChar += segment_metadata[0]
                        charCounter = 0
                        point = tgt.core.Point(
                            time = segment[0].timestamp + segment_metadata[2],
                            text = "?"
                        )
                        point_tiers_alignement[j].add_point(point)
                
                # append final intervals
                interval = tgt.core.Interval(
                                start_time = cur_seg_start_time,
                                end_time = segment[0].timestamp + segment_metadata[2],
                                text = maus_inventory_mapping[curChar.strip()]
                            )
                interval_tiers_alignement[j].add_interval(interval)

                interval = tgt.core.Interval(
                                start_time = segment[0].timestamp + segment_metadata[2],
                                end_time = segment[-1].timestamp + segment[-1].duration,
                                text = ""
                            )
                interval_tiers_alignement[j].add_interval(interval)



        logging.debug("total inference_time: %s" % inference_time)

        # add final empty interval to length of file
        # interval = tgt.core.Interval(
        #     start_time = segment[-1].timestamp + segment[-1].duration,  
        #     end_time = audio_length,
        #     text = segment_transcript)
        
        # tier_vad_chunks.add_interval(interval)

        tg = tgt.core.TextGrid()
        tg.add_tier(tier_vad_chunks)
        tg.add_tier(interval_tiers_alignement[0])
        tg.add_tier(point_tiers_alignement[0])
        tg.add_tier(interval_tiers_alignement[1])
        tg.add_tier(point_tiers_alignement[1])
        tg.add_tier(interval_tiers_alignement[2])
        tg.add_tier(point_tiers_alignement[2])
        tg = tgt.io.correct_start_end_times_and_fill_gaps(tg)

        # clean up
        os.remove(wav_path)
        return tgt.io.export_to_long_textgrid(tg)


    app.run(host='0.0.0.0', port=5000, debug=True)



if __name__ == '__main__':
    main(sys.argv[1:])
