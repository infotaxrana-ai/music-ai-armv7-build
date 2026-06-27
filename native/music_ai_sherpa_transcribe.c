#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "c-api.h"

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "Usage: %s MODEL_DIR WAV_FILE\n", argv[0]);
    return 2;
  }

  char encoder[1024];
  char decoder[1024];
  char joiner[1024];
  char tokens[1024];

  snprintf(encoder, sizeof(encoder), "%s/encoder.onnx", argv[1]);
  snprintf(decoder, sizeof(decoder), "%s/decoder.onnx", argv[1]);
  snprintf(joiner, sizeof(joiner), "%s/joiner.onnx", argv[1]);
  snprintf(tokens, sizeof(tokens), "%s/tokens.txt", argv[1]);

  const SherpaOnnxWave *wave = SherpaOnnxReadWave(argv[2]);
  if (!wave) {
    fprintf(stderr, "FAILED_TO_READ_WAV=%s\n", argv[2]);
    return 3;
  }

  SherpaOnnxOnlineRecognizerConfig config;
  memset(&config, 0, sizeof(config));

  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;

  config.model_config.transducer.encoder = encoder;
  config.model_config.transducer.decoder = decoder;
  config.model_config.transducer.joiner = joiner;
  config.model_config.tokens = tokens;
  config.model_config.num_threads = 1;
  config.model_config.provider = "cpu";
  config.model_config.debug = 0;
  config.model_config.model_type = "zipformer2";

  config.decoding_method = "modified_beam_search";
  config.max_active_paths = 10;

  const SherpaOnnxOnlineRecognizer *recognizer =
      SherpaOnnxCreateOnlineRecognizer(&config);

  if (!recognizer) {
    fprintf(stderr, "CREATE_RECOGNIZER_RETURNED_NULL\n");
    SherpaOnnxFreeWave(wave);
    return 4;
  }

  const SherpaOnnxOnlineStream *stream =
      SherpaOnnxCreateOnlineStream(recognizer);

  if (!stream) {
    fprintf(stderr, "CREATE_STREAM_RETURNED_NULL\n");
    SherpaOnnxDestroyOnlineRecognizer(recognizer);
    SherpaOnnxFreeWave(wave);
    return 5;
  }

  const int32_t chunk = 3200;
  int32_t offset = 0;

  while (offset < wave->num_samples) {
    int32_t remaining = wave->num_samples - offset;
    int32_t count = remaining < chunk ? remaining : chunk;

    SherpaOnnxOnlineStreamAcceptWaveform(
        stream, wave->sample_rate, wave->samples + offset, count);

    while (SherpaOnnxIsOnlineStreamReady(recognizer, stream)) {
      SherpaOnnxDecodeOnlineStream(recognizer, stream);
    }

    offset += count;
  }

  float tail[4800] = {0};
  SherpaOnnxOnlineStreamAcceptWaveform(
      stream, wave->sample_rate, tail, 4800);
  SherpaOnnxOnlineStreamInputFinished(stream);

  while (SherpaOnnxIsOnlineStreamReady(recognizer, stream)) {
    SherpaOnnxDecodeOnlineStream(recognizer, stream);
  }

  const SherpaOnnxOnlineRecognizerResult *result =
      SherpaOnnxGetOnlineStreamResult(recognizer, stream);

  if (!result) {
    fprintf(stderr, "GET_RESULT_RETURNED_NULL\n");
    SherpaOnnxDestroyOnlineStream(stream);
    SherpaOnnxDestroyOnlineRecognizer(recognizer);
    SherpaOnnxFreeWave(wave);
    return 6;
  }

  printf("%s\n", result->text ? result->text : "");

  SherpaOnnxDestroyOnlineRecognizerResult(result);
  SherpaOnnxDestroyOnlineStream(stream);
  SherpaOnnxDestroyOnlineRecognizer(recognizer);
  SherpaOnnxFreeWave(wave);

  return 0;
}
