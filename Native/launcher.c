// In-process macOS entry point for the pinned scrcpy client (Apache-2.0).
#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <fcntl.h>
#include <getopt.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "cli.h"
#include "events.h"
#include "options.h"
#include "scrcpy.h"
#include "util/log.h"
#include "util/net.h"

int sc_launcher_run(const char *serial, const char *adb, const char *server,
                    const char *icons, const char *log, const char *title);
void sc_launcher_stop(void);
void sc_launcher_press_power(void);

int
sc_launcher_run(const char *serial, const char *adb, const char *server,
                const char *icons, const char *log, const char *title) {
    if (!pthread_main_np()) {
        return -1; // Cocoa and SDL video must share the application's main thread.
    }
    int log_fd = open(log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (log_fd < 0) {
        return -2;
    }
    fflush(NULL);
    int saved_out = dup(STDOUT_FILENO);
    int saved_err = dup(STDERR_FILENO);
    dup2(log_fd, STDOUT_FILENO);
    dup2(log_fd, STDERR_FILENO);
    close(log_fd);

    // The caller owns these paths for the complete synchronous session.
    setenv("ADB", adb, 1);
    setenv("SCRCPY_SERVER_PATH", server, 1);
    setenv("SCRCPY_ICON_DIR", icons, 1);
    SDL_SetMainReady();
    SDL_SetAppMetadata("Scrcpy Launcher", "2.0", "dev.playphone.ScrcpyLauncher");
    sc_set_log_level(SC_LOG_LEVEL_INFO);
    sc_log_configure();
    struct scrcpy_cli_args args = {
        .opts = scrcpy_options_default,
        .pause_on_exit = SC_PAUSE_ON_EXIT_UNDEFINED,
    };
    // Use upstream argument normalization: raw defaults still contain AUTO
    // input/audio modes and cannot be passed straight to scrcpy().
    char *argv[] = {"ScrcpyLauncher", "-s", (char *) serial,
                    "--window-title", (char *) title, "--no-terminal-title", NULL};
    optreset = 1; // Darwin getopt state must also be reset between sessions.
    bool parsed = scrcpy_parse_args(&args, 6, argv);

    int result = SCRCPY_EXIT_FAILURE;
    if (parsed && net_init()) {
        if (sc_main_thread_init()) {
            result = scrcpy(&args.opts);
            sc_main_thread_destroy();
        }
        net_cleanup();
    }
    // scrcpy normally registers this with atexit(). In a host app, release SDL
    // after every session so closing/reopening or switching devices is safe.
    SDL_Quit();
    fflush(NULL);
    dup2(saved_out, STDOUT_FILENO);
    dup2(saved_err, STDERR_FILENO);
    close(saved_out);
    close(saved_err);
    return result;
}

void
sc_launcher_stop(void) {
    SDL_Event event = {.type = SDL_EVENT_QUIT};
    SDL_PushEvent(&event);
}

void
sc_launcher_press_power(void) {
    // Handle the complete short press inside the current session's event loop.
    sc_push_event(SC_EVENT_LAUNCHER_POWER);
}
