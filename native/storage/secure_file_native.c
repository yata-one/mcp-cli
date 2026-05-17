#include "moonbit.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

MOONBIT_EXPORT int32_t moonbit_utf8_len_from_utf16(moonbit_string_t src, int32_t src_offset, int32_t src_length);
MOONBIT_EXPORT int32_t moonbit_utf8_encode_from_utf16(moonbit_string_t src, int32_t src_offset, int32_t src_length, moonbit_bytes_t dst, int32_t dst_offset);

static char *mcpx_mbt_string_to_utf8(moonbit_string_t input, int32_t *out_len) {
  int32_t len16 = Moonbit_array_length(input);
  int32_t len8 = moonbit_utf8_len_from_utf16(input, 0, len16);
  if (len8 < 0) {
    return NULL;
  }
  char *out = (char *)malloc((size_t)len8 + 1);
  if (out == NULL) {
    return NULL;
  }
  int32_t written = moonbit_utf8_encode_from_utf16(
      input, 0, len16, (moonbit_bytes_t)out, 0);
  if (written < 0) {
    free(out);
    return NULL;
  }
  out[len8] = '\0';
  if (out_len != NULL) {
    *out_len = len8;
  }
  return out;
}

static int mcpx_mkdir_p_private(const char *dir) {
  if (dir == NULL || dir[0] == '\0') {
    return 0;
  }

  char *tmp = strdup(dir);
  if (tmp == NULL) {
    return -1;
  }

  size_t len = strlen(tmp);
  if (len == 0) {
    free(tmp);
    return 0;
  }
  if (tmp[len - 1] == '/') {
    tmp[len - 1] = '\0';
  }

  for (char *p = tmp + 1; *p != '\0'; ++p) {
    if (*p == '/') {
      *p = '\0';
      if (mkdir(tmp, 0700) != 0 && errno != EEXIST) {
        free(tmp);
        return -1;
      }
      (void)chmod(tmp, 0700);
      *p = '/';
    }
  }

  if (mkdir(tmp, 0700) != 0 && errno != EEXIST) {
    free(tmp);
    return -1;
  }
  (void)chmod(tmp, 0700);
  free(tmp);
  return 0;
}

static int mcpx_ensure_parent_private(const char *path) {
  char *copy = strdup(path);
  if (copy == NULL) {
    return -1;
  }
  char *slash = strrchr(copy, '/');
  if (slash == NULL) {
    free(copy);
    return 0;
  }
  if (slash == copy) {
    free(copy);
    return 0;
  }
  *slash = '\0';
  int rc = mcpx_mkdir_p_private(copy);
  free(copy);
  return rc;
}

static int mcpx_write_all(int fd, const char *contents, int32_t len) {
  int32_t offset = 0;
  while (offset < len) {
    ssize_t written = write(fd, contents + offset, (size_t)(len - offset));
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
    if (written == 0) {
      errno = EIO;
      return -1;
    }
    offset += (int32_t)written;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int mcpx_secure_write_private_atomic(
    moonbit_string_t path_value, moonbit_string_t contents_value) {
  int32_t contents_len = 0;
  char *path = mcpx_mbt_string_to_utf8(path_value, NULL);
  char *contents = mcpx_mbt_string_to_utf8(contents_value, &contents_len);
  if (path == NULL || contents == NULL) {
    free(path);
    free(contents);
    return -1;
  }

  if (mcpx_ensure_parent_private(path) != 0) {
    free(path);
    free(contents);
    return -1;
  }

  size_t path_len = strlen(path);
  const char *suffix = ".tmp.XXXXXX";
  char *tmp_path = (char *)malloc(path_len + strlen(suffix) + 1);
  if (tmp_path == NULL) {
    free(path);
    free(contents);
    return -1;
  }
  memcpy(tmp_path, path, path_len);
  strcpy(tmp_path + path_len, suffix);

  int fd = mkstemp(tmp_path);
  if (fd < 0) {
    free(tmp_path);
    free(path);
    free(contents);
    return -1;
  }

  int ok = 0;
  if (fchmod(fd, 0600) != 0) {
    ok = -1;
  }
  if (ok == 0 && mcpx_write_all(fd, contents, contents_len) != 0) {
    ok = -1;
  }
  if (ok == 0 && fsync(fd) != 0) {
    ok = -1;
  }
  if (close(fd) != 0) {
    ok = -1;
  }

  if (ok == 0 && rename(tmp_path, path) != 0) {
    ok = -1;
  }
  if (ok == 0 && chmod(path, 0600) != 0) {
    ok = -1;
  }
  if (ok != 0) {
    (void)unlink(tmp_path);
  }

  free(tmp_path);
  free(path);
  free(contents);
  return ok;
}

MOONBIT_FFI_EXPORT int mcpx_secure_file_mode(moonbit_string_t path_value) {
  char *path = mcpx_mbt_string_to_utf8(path_value, NULL);
  if (path == NULL) {
    return -1;
  }
  struct stat st;
  if (stat(path, &st) != 0) {
    free(path);
    return -1;
  }
  free(path);
  return (int)(st.st_mode & 0777);
}
