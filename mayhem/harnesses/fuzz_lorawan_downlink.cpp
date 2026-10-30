#include <RadioLib.h>

extern "C" int FuzzLoRaWANDownlink(const uint8_t* data, size_t size);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if(size < 10) { return(-1); }
  FuzzLoRaWANDownlink(data, size);
  return(0);
}
