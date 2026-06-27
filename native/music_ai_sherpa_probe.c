#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "c-api.h"

static double now_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s MODEL_DIR\n", argv[0]);
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
  config.model_config.debug = 1;
  config.model_config.model_type = "zipformer2";

  config.decoding_method = "modified_beam_search";
  config.max_active_paths = 10;

  printf("CREATING_RECOGNIZER\n");
  fflush(stdout);

  const double started = now_seconds();
  const SherpaOnnxOnlineRecognizer *recognizer =
      SherpaOnnxCreateOnlineRecognizer(&config);

  if (!recognizer) {
    fprintf(stderr, "CREATE_RECOGNIZER_RETURNED_NULL\n");
    return 10;
  }

  printf("RECOGNIZER_CREATED_SECONDS=%.3f\n", now_seconds() - started);
  fflush(stdout);

  const SherpaOnnxOnlineStream *stream =
      SherpaOnnxCreateOnlineStream(recognizer);

  if (!stream) {
    fprintf(stderr, "CREATE_STREAM_RETURNED_NULL\n");
    SherpaOnnxDestroyOnlineRecognizer(recognizer);
    return 11;
  }

  float *silence = (float *)calloc(16000, sizeof(float));
  if (!silence) {
    fprintf(stderr, "MEMORY_ALLOCATION_FAILED\n");
    SherpaOnnxDestroyOnlineStream(stream);
    SherpaOnnxDestroyOnlineRecognizer(recognizer);
    return 12;
  }

  printf("RUNNING_ONE_SECOND_SILENCE_INFERENCE\n");
  fflush(stdout);

  SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, silence, 16000);
  free(silence);
  SherpaOnnxOnlineStreamInputFinished(stream);

  int32_t decode_steps = 0;
  while (SherpaOnnxIsOnlineStreamReady(recognizer, stream)) {
    SherpaOnnxDecodeOnlineStream(recognizer, stream);
    ++decode_steps;

    if (decode_steps > 10000) {
      fprintf(stderr, "DECODE_LOOP_GUARD_TRIGGERED\n");
      SherpaOnnxDestroyOnlineStream(stream);
      SherpaOnnxDestroyOnlineRecognizer(recognizer);
      return 13;
    }
  }

  const SherpaOnnxOnlineRecognizerResult *result =
      SherpaOnnxGetOnlineStreamResult(recognizer, stream);

  if (!result) {
    fprintf(stderr, "GET_RESULT_RETURNED_NULL\n");
    SherpaOnnxDestroyOnlineStream(stream);
    SherpaOnnxDestroyOnlineRecognizer(recognizer);
    return 14;
  }

  printf("DECODE_STEPS=%d\n", decode_steps);
  printf("SILENCE_TEXT=%s\n", result->text ? result->text : "");
  SherpaOnnxDestroyOnlineRecognizerResult(result);

  SherpaOnnxDestroyOnlineStream(stream);
  SherpaOnnxDestroyOnlineRecognizer(recognizer);

  printf("PROBE_OK\n");
  return 0;
}
