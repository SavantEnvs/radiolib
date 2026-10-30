#include <RadioLib.h>

extern "C" int FuzzPager(const uint8_t* data, size_t size);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if(size % 4) { return(-1); }
  FuzzPager(data, size);
  return(0);
}
