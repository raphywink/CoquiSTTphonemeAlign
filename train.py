#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import absolute_import, division, print_function
########################
# needed for GPU usage on my machine
import tensorflow as tf

config = tf.ConfigProto()
config.gpu_options.allow_growth = True
config.gpu_options.per_process_gpu_memory_fraction=0.5
sess = tf.Session(config=config)
#
########################
if __name__ == '__main__':
    try:
        from coqui_stt_training import train as ds_train
    except ImportError:
        print('Training package is not installed. See training documentation.')
        raise

    ds_train.run_script()
