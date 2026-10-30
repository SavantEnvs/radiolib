#include <RadioLib.h>

extern "C" int FuzzLoRaWANPersistBuffer(const uint8_t* data, size_t size);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if(size < RADIOLIB_LORAWAN_SESSION_BUF_SIZE) { return(-1); }
  FuzzLoRaWANPersistBuffer(data, size);
  return(0);
}
