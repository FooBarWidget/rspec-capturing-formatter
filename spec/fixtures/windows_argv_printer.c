#include <stdio.h>

/* The Wine test uses NUL separators so every command-line character remains observable. */
int main(int argc, char **argv) {
  int index;

  for (index = 1; index < argc; index++) {
    fputs(argv[index], stdout);
    fputc('\0', stdout);
  }
  return ferror(stdout) ? 1 : 0;
}
