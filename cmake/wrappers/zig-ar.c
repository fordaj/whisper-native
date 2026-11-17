// zig-ar — thin wrapper so CMake's <CMAKE_AR>/<CMAKE_RANLIB> can be a
// single executable and every archive is produced by `zig ar`.
//
// Why this exists: the Windows platform modules set CMAKE_<LANG>_ARCHIVE_*
// unconditionally to "<CMAKE_AR> qc <TARGET> <LINK_FLAGS> <OBJECTS>" and
// "<CMAKE_RANLIB> <TARGET>", and pass the object list through a response
// file (@file). CMAKE_AR must therefore name a runnable program on the
// build host. This wrapper:
//
//   zig-ar    qc <archive> @objects.rsp [more objs]  ->  zig ar rcs <archive> <objs expanded>
//   zig-ar    q  <archive> <objs...>                 ->  zig ar r   <archive> <objs>
//   zig-ranlib <archive>                             ->  zig ar s   <archive>
//
// Response files (@file) are expanded inline; double-quoted tokens are
// handled, which is how CMake writes them.
//
// Build (from the repository root):
//   zig cc -target x86_64-windows-gnu -O2 -static -o cmake/wrappers/zig-ar-windows-x86_64.exe    cmake/wrappers/zig-ar.c
//   zig cc -target aarch64-windows-gnu -O2 -static -o cmake/wrappers/zig-ar-windows-arm64.exe    cmake/wrappers/zig-ar.c
//   cp cmake/wrappers/zig-ar-windows-x86_64.exe cmake/wrappers/zig-ranlib-windows-x86_64.exe
//   cp cmake/wrappers/zig-ar-windows-arm64.exe cmake/wrappers/zig-ranlib-windows-arm64.exe

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <process.h>
#define EXECVP _execvp
#define EXEC_ARG(p) ((const char *const *)(p))
#else
#include <unistd.h>
#define EXECVP execvp
#define EXEC_ARG(p) ((char *const *)(p))
#endif

// Growable string buffer for one argument list slot.
struct argvbuf {
    char **items;
    size_t len, cap;
};

static void ab_push(struct argvbuf *b, const char *s) {
    if (b->len == b->cap) {
        b->cap = b->cap ? b->cap * 2 : 16;
        b->items = realloc(b->items, b->cap * sizeof(char *));
        if (!b->items) {
            fprintf(stderr, "zig-ar: out of memory\n");
            exit(127);
        }
    }
    b->items[b->len++] = strdup(s);
}

// Append a token to an argvbuf; the argv array stays owned by the buffer.
static void add_arg(struct argvbuf *b, const char *tok) { ab_push(b, tok); }

// Expand a response file, pushing tokens into `b`.
// CMake writes tab/space-separated double-quoted tokens.
static void expand_rsp(struct argvbuf *b, const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "zig-ar: cannot open response file: %s\n", path);
        exit(127);
    }
    char tok[4096];
    size_t tlen = 0;
    int in_quotes = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        if (in_quotes) {
            if (c == '"') {
                in_quotes = 0;
                tok[tlen] = '\0';
                add_arg(b, tok);
                tlen = 0;
                continue;
            }
            if (c == '\\') { // escaped char inside quotes
                c = fgetc(f);
                if (c == EOF) break;
            }
            if (tlen < sizeof(tok) - 1) tok[tlen++] = (char)c;
            continue;
        }
        if (c == '"') {
            in_quotes = 1;
            tlen = 0;
            continue;
        }
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            continue;
        }
        if (tlen < sizeof(tok) - 1) tok[tlen++] = (char)c;
    }
    if (tlen > 0) {
        tok[tlen] = '\0';
        add_arg(b, tok);
    }
    fclose(f);
}

static const char *base_name(const char *path) {
    const char *a = strrchr(path, '/');
    const char *b = strrchr(path, '\\');
    const char *s = a > b ? a : b;
    return s ? s + 1 : path;
}

// Terminate the argument vector with NULL (no copy).
static void *ab_finish(struct argvbuf *b) {
    if (b->len == b->cap) {
        b->cap = b->cap ? b->cap * 2 : 16;
        b->items = realloc(b->items, b->cap * sizeof(char *));
        if (!b->items) {
            fprintf(stderr, "zig-ar: out of memory\n");
            exit(127);
        }
    }
    b->items[b->len] = NULL;
    return b->items;
}

int main(int argc, char **argv) {
    const char *prog = base_name(argv[0]);
    int is_ranlib = strstr(prog, "ranlib") != NULL;

    struct argvbuf b = {0};
    ab_push(&b, "zig");
    ab_push(&b, "ar");

    if (is_ranlib) {
        if (argc != 2) {
            fprintf(stderr, "zig-ranlib: expected <archive>\n");
            return 127;
        }
        ab_push(&b, "s");
        add_arg(&b, argv[1]);
        EXECVP("zig", EXEC_ARG(ab_finish(&b)));
        perror("zig");
        return 127;
    }

    // zig-ar: first arg is an ar mode string from CMake (qc/q); drop it.
    int i = 1;
    if (i < argc && (strcmp(argv[i], "qc") == 0 || strcmp(argv[i], "q") == 0 ||
                     strcmp(argv[i], "rcs") == 0)) {
        i++;
    }
    if (i >= argc) {
        fprintf(stderr, "zig-ar: expected <archive> and objects\n");
        return 127;
    }
    // Archive name, then remaining tokens (objects or @rsp).
    ab_push(&b, "rcs");
    add_arg(&b, argv[i++]);
    for (; i < argc; i++) {
        if (argv[i][0] == '@') {
            expand_rsp(&b, argv[i] + 1);
        } else {
            add_arg(&b, argv[i]);
        }
    }
    EXECVP("zig", EXEC_ARG(ab_finish(&b)));
    perror("zig");
    return 127;
}
