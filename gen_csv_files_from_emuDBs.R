# script to produce files in 
# data/LibriSpeech_phoneme_csv_files 
# which are a part of this repo
# the emuDBs needed to produce them
# are currently not publicly available.
# The emuDBs where produced using: https://clarin.phonetik.uni-muenchen.de/BASWebServices/interface
library(emuR)
library(tidyverse)

# get inventory from:
# http://clarin.phonetik.uni-muenchen.de/BASWebServices/services/runMAUSGetInventar?LANGUAGE=*
# add column containing coding chars
# and save to data/maus_inventory_*.csv file 
dir_of_this_script = dirname(rstudioapi::getSourceEditorContext()$path)
inv_path = file.path(dir_of_this_script, "data/maus_inventory_deu-DE.csv")
if(!file.exists(inv_path)){
  maus_inv_raw = readr::read_file(
    file = "http://clarin.phonetik.uni-muenchen.de/BASWebServices/services/runMAUSGetInventar?LANGUAGE=deu-DE"
  )
  
  maus_inv = readr::read_tsv(maus_inv_raw, comment = "%")
  
  expand.grid(p1 = letters, p2 = letters, stringsAsFactors = F) %>%
    dplyr::group_by(p1, p2) %>%
    dplyr::summarise(combind = paste0(p1, p2)) %>%
    dplyr::ungroup() -> coding_chars
  
  coding_chars = coding_chars$combind
  
  maus_inv$unique_coding_char = coding_chars[1:nrow(maus_inv)]
  readr::write_csv(maus_inv, file = inv_path)
} else {
  maus_inv = readr::read_csv(inv_path)
}

###############################
# create csv files for train/dev/test

emuDBnames = c("dev","test", "train")

for(dbname in emuDBnames){
  
  print(dbname)
  # do this for dev, test, train
  db = load_emuDB(file.path(dir_of_this_script, "data/CV/de/", paste0(dbname, "_emuDB")))
  # list_bundles(db)
  sl = query(db, "MAU =~ .*")
  # table(sl$labels)
  sl_new = sl
  
  # remove silence and noise symbols by setting the mapping to empty strings
  maus_inv$unique_coding_char[c(1, 2, 3, 4, 73, 74, 76)] = ""
  
  # replace labels with utf8 values
  coding_char_vals = maus_inv$unique_coding_char
  
  names(coding_char_vals) = maus_inv$MAUS
  # this is slow but I can't be bothered finding a quicker way right now
  # it also only has to be called once... so... will prob. bite me in the A 
  for(idx in 1:length(coding_char_vals)){
    sl_new$labels[names(coding_char_vals)[idx] == sl_new$labels] = coding_char_vals[idx]
  }
  
  # try it with single phonemes as "words"
  sl_out = sl_new %>%
    group_by(bundle) %>%
    mutate(transcript = paste0(labels, collapse = " ")) %>%
    mutate(wav_filename = paste0(bundle, ".wav")) %>%
    mutate(db_base_path = db$basePath) %>%
    select(db_base_path, bundle, session, wav_filename, transcript) %>%
    distinct() %>%
    mutate(wav_filesize = file.size(file.path(db_base_path, paste0(session, "_ses"), paste0(bundle, "_bndl"), paste0(bundle, ".wav")))) %>%
    ungroup() %>%
    select(wav_filename, wav_filesize, transcript)
  
  # sl_out_mini = sl_out[1:10,]
  # stringr::str_split(sl_out_mini$transcript, pattern = " ")
  
  # bad files: common_voice_de_19066852
  
  # replace with trigrams
  # for(idx in 1:nrow(sl_out)){
  #   sstA = stringr::str_split(string = sl_out$transcript[idx], 
  #                             pattern = "",)[[1]]
  #   
  #   sl_out$transcript[idx] = paste0(paste0(sstA[c(TRUE, FALSE, FALSE)], 
  #                                          sstA[c(FALSE, TRUE, FALSE)], 
  #                                          sstA[c(FALSE, FALSE, TRUE)]), collapse = " ")
  # }
  
  
  readr::write_csv(sl_out, 
                   file = file.path(dir_of_this_script, 
                                    "data/CV/de", 
                                    dbname, 
                                    paste0(dbname, ".csv")))
  
  #readr::write_csv(sl_out, 
  #                 path = paste0("~/", paste0(dbname, ".csv")))
  
  #file.copy(from = paste0("~/scripts/docker/DeepSpeechPhonemeAlign//data/LibriSpeech_phoneme_csv_files/", paste0(dbname, ".csv")),
  #          to = file.path("/home/raphywink/scripts/docker/DeepSpeechPhonemeAlign/data/LibriSpeech", dbname))
}

################################
# create alphabet.txt
# as training data is last sl_out contains those labels

header = "# Each line in this file represents the codepoint (ASCII encoded)
# associated with a MAUS label.
# A line that starts with # is a comment. You can escape it with \\# if you wish
# to use '#' as a label."

readr::write_lines(header,
                   file = file.path(dir_of_this_script, "data/alphabet.txt"))

readr::write_lines(c(letters, "|", " "),
                   file = file.path(dir_of_this_script, "data/alphabet.txt"),
                   append = T)

footer = "# The last (non-comment) line needs to end with a newline."

readr::write_lines(footer,
                   file = file.path(dir_of_this_script, "data/alphabet.txt"),
                   append = T)

##############################
# use training phoneme seq. to produce txt file for language model
# as training data is last sl_out contains those labels


path2phonemeSeqs = file.path(dir_of_this_script, "data/coded_phoneme_seqs.txt")
unlink(path2phonemeSeqs)

readr::write_lines(x = sl_out$transcript,
                   path2phonemeSeqs,
                   append = T)


# trigrams:
# for(idx in 1:length(sl_out$transcript)){
#   sstA = stringr::str_split(string = sl_out$transcript[idx], 
#                             pattern = "",)[[1]]
#   trigramA = paste0(sstA[c(TRUE, FALSE, FALSE)], 
#                     sstA[c(FALSE, TRUE, FALSE)], 
#                     sstA[c(FALSE, FALSE, TRUE)])

#   sstB = sstA[2:length(sstA)]
#   trigramB = paste0(sstB[c(TRUE, FALSE, FALSE)], 
#                     sstB[c(FALSE, TRUE, FALSE)], 
#                     sstB[c(FALSE, FALSE, TRUE)])

#   sstC = sstB[2:length(sstB)]
#   trigramC = paste0(sstC[c(TRUE, FALSE, FALSE)], 
#                     sstC[c(FALSE, TRUE, FALSE)], 
#                     sstC[c(FALSE, FALSE, TRUE)])


#   readr::write_lines(x = paste(trigramA, collapse = " "),
#                      path2phonemeSeqs, 
#                      append = T)

#   readr::write_lines(x = paste(trigramB, collapse = " "),
#                      path2phonemeSeqs, 
#                      append = T)

#   readr::write_lines(x = paste(trigramC, collapse = " "),
#                      path2phonemeSeqs, 
#                      append = T)

# }

# readr::write_lines(x = sl_out$transcript,
#                    file = path2phonemeSeqs)
