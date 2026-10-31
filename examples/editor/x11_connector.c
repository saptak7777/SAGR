/* ========================================================================
 * examples/editor/x11_connector.c
 * Simple SAGR X11 Display Connector (1:1 Native Resolution)
 *
 * Architecture:
 * - SAGR renders an authentic 640x360 TrueColor RGBA buffer.
 * - This connector opens an exact 640x360 native X11 window.
 * - DEFAULT_SCALE is strictly 1: 1 SAGR pixel = 1 physical monitor pixel.
 * - Zero GUI libraries: no Qt, no GTK, no Tkinter. Pure X11 blitter.
 *
 * Hardened Systems Programming Safeguards:
 * 1. Event Loop Multiplexing: poll() on ConnectionNumber(dpy) + child pipe
 *    (blocks cleanly, zero CPU spin, never starves window manager).
 * 2. Process Tree Isolation: prctl(PR_SET_PDEATHSIG, SIGTERM) guarantees
 *    the child terminates if parent crashes. Zero zombie processes.
 * 3. Signal Teardown: sigaction handler ensures XCloseDisplay() and child
 *    cleanup on SIGINT, SIGTERM, SIGHUP, SIGQUIT, and SIGSEGV.
 * 4. Runaway PID Protection: flock advisory single-instance lock and
 *    crash-cooldown timer protect against rapid respawning loops.
 * ======================================================================== */

#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>

#define SAGR_W 640
#define SAGR_H 360
#define DEFAULT_SCALE 1
#define LOCK_PATH "/tmp/sagr_editor.lock"

typedef struct {
    Display *dpy;
    int screen;
    Window win;
    GC gc;
    int scale;
    int win_w;
    int win_h;
    uint32_t *scaled_fb;
    XImage *ximg;
    int to_sagr_fd;   // pipe to SAGR stdin
    int from_sagr_fd; // pipe from SAGR stdout
    pid_t sagr_pid;
} X11Context;

static X11Context g_ctx;
static int g_lock_fd = -1;
static struct timespec g_start_time;

static void cleanup_and_exit(int sig) {
    // Terminate child if alive
    if (g_ctx.sagr_pid > 0) {
        kill(g_ctx.sagr_pid, SIGTERM);
        waitpid(g_ctx.sagr_pid, NULL, WNOHANG);
        g_ctx.sagr_pid = -1;
    }

    if (g_ctx.to_sagr_fd > 0) {
        close(g_ctx.to_sagr_fd);
        g_ctx.to_sagr_fd = -1;
    }
    if (g_ctx.from_sagr_fd > 0) {
        close(g_ctx.from_sagr_fd);
        g_ctx.from_sagr_fd = -1;
    }

    // Clean up X11 window and display socket
    if (g_ctx.dpy) {
        if (g_ctx.win) {
            XDestroyWindow(g_ctx.dpy, g_ctx.win);
            g_ctx.win = 0;
        }
        XCloseDisplay(g_ctx.dpy);
        g_ctx.dpy = NULL;
    }

    if (g_ctx.scaled_fb) {
        free(g_ctx.scaled_fb);
        g_ctx.scaled_fb = NULL;
    }

    // Release instance lock
    if (g_lock_fd >= 0) {
        flock(g_lock_fd, LOCK_UN);
        close(g_lock_fd);
        g_lock_fd = -1;
    }

    // Crash cooldown guard: if exited abnormally within 500ms, sleep briefly to prevent rapid respawn
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    long elapsed_ms = (now.tv_sec - g_start_time.tv_sec) * 1000 + (now.tv_nsec - g_start_time.tv_nsec) / 1000000;
    if (elapsed_ms < 500 && sig != 0) {
        usleep(500000);
    }

    _exit(sig == 0 ? 0 : 128 + sig);
}

static void sig_handler(int sig) {
    cleanup_and_exit(sig);
}

static int load_sagr_ppm(const char *path, uint8_t *rgb_out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    char magic[3];
    int w, h, maxv;
    if (fscanf(f, "%2s\n%d %d\n%d\n", magic, &w, &h, &maxv) != 4) {
        fclose(f);
        return -1;
    }
    if (w != SAGR_W || h != SAGR_H) {
        fclose(f);
        return -1;
    }
    size_t n = fread(rgb_out, 1, SAGR_W * SAGR_H * 3, f);
    fclose(f);
    return (n == SAGR_W * SAGR_H * 3) ? 0 : -1;
}

static void update_and_blit(X11Context *ctx, const uint8_t *src_rgb) {
    if (!ctx->dpy || !ctx->win || !ctx->scaled_fb) return;

    if (ctx->scale == 1) {
        // 1:1 Fast Direct Copy (1 SAGR pixel = 1 monitor pixel)
        for (int i = 0; i < SAGR_W * SAGR_H; i++) {
            uint8_t r = src_rgb[i * 3 + 0];
            uint8_t g = src_rgb[i * 3 + 1];
            uint8_t b = src_rgb[i * 3 + 2];
            ctx->scaled_fb[i] = (r << 16) | (g << 8) | b;
        }
    } else {
        for (int y = 0; y < ctx->win_h; y++) {
            int sy = y / ctx->scale;
            if (sy >= SAGR_H) sy = SAGR_H - 1;
            for (int x = 0; x < ctx->win_w; x++) {
                int sx = x / ctx->scale;
                if (sx >= SAGR_W) sx = SAGR_W - 1;
                int s_idx = (sy * SAGR_W + sx) * 3;
                uint8_t r = src_rgb[s_idx + 0];
                uint8_t g = src_rgb[s_idx + 1];
                uint8_t b = src_rgb[s_idx + 2];
                ctx->scaled_fb[y * ctx->win_w + x] = (r << 16) | (g << 8) | b;
            }
        }
    }
    XPutImage(ctx->dpy, ctx->win, ctx->gc, ctx->ximg, 0, 0, 0, 0, ctx->win_w, ctx->win_h);
    XFlush(ctx->dpy);
}

int main(int argc, char **argv) {
    clock_gettime(CLOCK_MONOTONIC, &g_start_time);
    memset(&g_ctx, 0, sizeof(g_ctx));

    // 1. Single-instance lockfile protection
    g_lock_fd = open(LOCK_PATH, O_CREAT | O_RDWR, 0666);
    if (g_lock_fd >= 0) {
        if (flock(g_lock_fd, LOCK_EX | LOCK_NB) != 0) {
            fprintf(stderr, "[SAGR X11] Another editor instance is already running (%s locked). Exiting cleanly.\n", LOCK_PATH);
            close(g_lock_fd);
            return 0;
        }
    }

    // 2. Register signal handlers for clean teardown
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);

    g_ctx.scale = DEFAULT_SCALE;
    g_ctx.win_w = SAGR_W * g_ctx.scale;
    g_ctx.win_h = SAGR_H * g_ctx.scale;

    printf("[SAGR X11] Connecting to X11 display (DISPLAY=%s)...\n", getenv("DISPLAY"));
    g_ctx.dpy = XOpenDisplay(NULL);
    if (!g_ctx.dpy) {
        fprintf(stderr, "[SAGR X11 ERROR] Cannot open X11 display!\n");
        cleanup_and_exit(1);
    }

    g_ctx.screen = DefaultScreen(g_ctx.dpy);
    Window root = RootWindow(g_ctx.dpy, g_ctx.screen);

    g_ctx.win = XCreateSimpleWindow(
        g_ctx.dpy, root,
        150, 150,
        g_ctx.win_w, g_ctx.win_h,
        1,
        BlackPixel(g_ctx.dpy, g_ctx.screen),
        BlackPixel(g_ctx.dpy, g_ctx.screen)
    );

    XStoreName(g_ctx.dpy, g_ctx.win, "SAGR Simple Text Editor (1:1 Native Resolution, 640x360)");

    // Window Manager Close protocol
    Atom wm_delete = XInternAtom(g_ctx.dpy, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(g_ctx.dpy, g_ctx.win, &wm_delete, 1);

    XSelectInput(g_ctx.dpy, g_ctx.win, ExposureMask | KeyPressMask | ButtonPressMask | StructureNotifyMask);
    XMapWindow(g_ctx.dpy, g_ctx.win);

    g_ctx.gc = DefaultGC(g_ctx.dpy, g_ctx.screen);

    // Allocate 1:1 framebuffer
    g_ctx.scaled_fb = (uint32_t*)malloc(g_ctx.win_w * g_ctx.win_h * 4);
    Visual *visual = DefaultVisual(g_ctx.dpy, g_ctx.screen);
    g_ctx.ximg = XCreateImage(g_ctx.dpy, visual, 24, ZPixmap, 0, (char*)g_ctx.scaled_fb, g_ctx.win_w, g_ctx.win_h, 32, 0);

    // Create bi-directional pipes for SAGR process
    int pipe_in[2];  // X11 -> SAGR stdin
    int pipe_out[2]; // SAGR stdout -> X11
    if (pipe(pipe_in) != 0 || pipe(pipe_out) != 0) {
        perror("pipe");
        cleanup_and_exit(1);
    }

    g_ctx.sagr_pid = fork();
    if (g_ctx.sagr_pid == 0) {
        // Child: automatically receive SIGTERM if parent dies (prevents zombie/orphan processes)
        prctl(PR_SET_PDEATHSIG, SIGTERM);
        if (getppid() == 1) {
            _exit(1);
        }

        dup2(pipe_in[0], 0);
        dup2(pipe_out[1], 1);
        close(pipe_in[0]);
        close(pipe_in[1]);
        close(pipe_out[0]);
        close(pipe_out[1]);
        execl("./scratch/editor_bin", "./scratch/editor_bin", NULL);
        perror("execl");
        _exit(1);
    }

    close(pipe_in[0]);
    close(pipe_out[1]);
    g_ctx.to_sagr_fd = pipe_in[1];
    g_ctx.from_sagr_fd = pipe_out[0];

    fcntl(g_ctx.from_sagr_fd, F_SETFL, O_NONBLOCK);

    uint8_t sagr_rgb[SAGR_W * SAGR_H * 3];
    memset(sagr_rgb, 24, sizeof(sagr_rgb));

    // Wait 50ms for initial PPM dump from SAGR
    usleep(50000);
    load_sagr_ppm("scratch/editor.ppm", sagr_rgb);

    printf("[SAGR X11] Native window initialized (%dx%d, 1:1 scale).\n", g_ctx.win_w, g_ctx.win_h);
    printf("[SAGR X11] Non-blocking I/O multiplexing active via poll().\n");

    int running = 1;
    XEvent ev;

    while (running) {
        // 1. Drain all pending X11 events without sleeping
        while (XPending(g_ctx.dpy)) {
            XNextEvent(g_ctx.dpy, &ev);

            if (ev.type == ClientMessage) {
                if ((Atom)ev.xclient.data.l[0] == wm_delete) {
                    write(g_ctx.to_sagr_fd, "q", 1);
                    running = 0;
                    break;
                }
            }

            if (ev.type == Expose && ev.xexpose.count == 0) {
                load_sagr_ppm("scratch/editor.ppm", sagr_rgb);
                update_and_blit(&g_ctx, sagr_rgb);
            }

            if (ev.type == ButtonPress) {
                int px = ev.xbutton.x / g_ctx.scale;
                int py = ev.xbutton.y / g_ctx.scale;
                printf("[SAGR X11] Mouse Click at (%d, %d)\n", px, py);

                // Top Panel Title Bar Actions (y < 28)
                if (py < 28) {
                    // Close Circle (Red): center (18, 14), radius 6
                    if (px >= 10 && px <= 26) {
                        printf("[SAGR X11 ACTION] Clicked [CLOSE] button!\n");
                        write(g_ctx.to_sagr_fd, "q", 1);
                        running = 0;
                        break;
                    }
                    // Minimise Circle (Yellow): center (38, 14), radius 6
                    if (px >= 30 && px <= 46) {
                        printf("[SAGR X11 ACTION] Clicked [MINIMISE] button!\n");
                        XIconifyWindow(g_ctx.dpy, g_ctx.win, g_ctx.screen);
                    }
                    // Maximise Circle (Green): center (58, 14), radius 6
                    if (px >= 50 && px <= 66) {
                        printf("[SAGR X11 ACTION] Clicked [MAXIMISE] button!\n");
                    }
                    // [NEW] Button (x = 480..540)
                    if (px >= 480 && px <= 540) {
                        printf("[SAGR X11 ACTION] Clicked [NEW] button!\n");
                        write(g_ctx.to_sagr_fd, "np", 2);
                        usleep(10000);
                        load_sagr_ppm("scratch/editor.ppm", sagr_rgb);
                        update_and_blit(&g_ctx, sagr_rgb);
                    }
                    // [SAVE] Button (x = 550..620)
                    if (px >= 550 && px <= 620) {
                        printf("[SAGR X11 ACTION] Clicked [SAVE] button!\n");
                        write(g_ctx.to_sagr_fd, "sp", 2);
                        usleep(10000);
                        load_sagr_ppm("scratch/editor.ppm", sagr_rgb);
                        update_and_blit(&g_ctx, sagr_rgb);
                    }
                } else if (py >= 32 && py < 336 && px >= 48) {
                    int target_line = (py - 32) / 16;
                    int target_col = (px - 48) / 8;
                    if (target_line < 0) target_line = 0;
                    if (target_line > 17) target_line = 17;
                    if (target_col < 0) target_col = 0;
                    if (target_col > 71) target_col = 71;
                    printf("[SAGR X11] Set cursor position to Line %d, Col %d\n", target_line + 1, target_col + 1);
                }
            }

            if (ev.type == KeyPress) {
                KeySym ks;
                char buf[16];
                int len = XLookupString(&ev.xkey, buf, sizeof(buf), &ks, NULL);

                if (ks == XK_Escape) {
                    write(g_ctx.to_sagr_fd, "\x1b", 1);
                    running = 0;
                    break;
                } else if (ks == XK_Up) {
                    write(g_ctx.to_sagr_fd, "\x1b[Ap", 4);
                } else if (ks == XK_Down) {
                    write(g_ctx.to_sagr_fd, "\x1b[Bp", 4);
                } else if (ks == XK_Right) {
                    write(g_ctx.to_sagr_fd, "\x1b[Cp", 4);
                } else if (ks == XK_Left) {
                    write(g_ctx.to_sagr_fd, "\x1b[Dp", 4);
                } else if (ks == XK_BackSpace) {
                    char bs[2] = {127, 'p'};
                    write(g_ctx.to_sagr_fd, bs, 2);
                } else if (len > 0) {
                    if (buf[0] == 'q' || buf[0] == 'Q') {
                        write(g_ctx.to_sagr_fd, buf, 1);
                        running = 0;
                        break;
                    }
                    char send_buf[18];
                    memcpy(send_buf, buf, len);
                    send_buf[len] = 'p';
                    write(g_ctx.to_sagr_fd, send_buf, len + 1);
                }

                usleep(10000);
                load_sagr_ppm("scratch/editor.ppm", sagr_rgb);
                update_and_blit(&g_ctx, sagr_rgb);
            }
        }

        if (!running) break;

        // Drain any asynchronous output from SAGR child
        char discard[1024];
        while (read(g_ctx.from_sagr_fd, discard, sizeof(discard)) > 0) {}

        // 2. Non-blocking I/O multiplexing: sleep in kernel waiting on X11 or child
        struct pollfd fds[2];
        fds[0].fd = ConnectionNumber(g_ctx.dpy);
        fds[0].events = POLLIN;
        fds[1].fd = g_ctx.from_sagr_fd;
        fds[1].events = POLLIN | POLLHUP | POLLERR;

        int poll_res = poll(fds, 2, 50); // 50ms timeout ensures periodic liveness checks
        if (poll_res < 0 && errno == EINTR) {
            continue;
        }

        // Check if child exited or closed stdout
        if (fds[1].revents & (POLLHUP | POLLERR)) {
            running = 0;
            break;
        }

        int status;
        if (waitpid(g_ctx.sagr_pid, &status, WNOHANG) > 0) {
            running = 0;
            break;
        }
    }

    printf("[SAGR X11] Cleaning up and closing display...\n");
    cleanup_and_exit(0);
    return 0;
}
