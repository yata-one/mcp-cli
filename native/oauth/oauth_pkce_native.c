#include "moonbit.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT int mcpx_oauth_random_bytes(unsigned char *buf, int32_t len) {
  if (buf == NULL || len < 0) {
    return -1;
  }
  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) {
    return -1;
  }
  int32_t offset = 0;
  while (offset < len) {
    ssize_t n = read(fd, buf + offset, (size_t)(len - offset));
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      return -1;
    }
    if (n == 0) {
      close(fd);
      return -1;
    }
    offset += (int32_t)n;
  }
  close(fd);
  return 0;
}
