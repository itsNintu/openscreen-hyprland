// openscreen-tap-bridge: Openscreen records clicks by reading mouse devices directly, so touchpad
// *taps* (which only exist inside libinput/the compositor) never reach it. This watches tap-capable
// touchpads through libinput (same tap logic Hyprland uses), and for every tap presses BTN_LEFT on a
// virtual uinput mouse. A udev rule sets LIBINPUT_IGNORE_DEVICE on that mouse, so the compositor never
// acts on it; only raw readers like Openscreen see it. Physical presses are skipped (Openscreen already
// sees those on the touchpad itself).
//
// Build: gcc -O2 -Wall -o tap-bridge tap-bridge.c $(pkg-config --cflags --libs libinput libudev)

#include <errno.h>
#include <stdarg.h>
#include <fcntl.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define BRIDGE_NAME "Openscreen tap bridge"
#define MAX_PADS 8

struct pad {
    struct libinput_device* dev;
    int                     rawfd;        // second, raw view of the same device, to spot physical presses
    long long               lastPhysical; // ms of last raw BTN_* press
    int                     physicalDown;
    int                     tapDown[3];   // left/right/middle taps currently held
};

static struct pad pads[MAX_PADS];
static int        uifd = -1;
static volatile sig_atomic_t running = 1;

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int open_restricted(const char* path, int flags, void* data) {
    int fd = open(path, flags);
    return fd < 0 ? -errno : fd;
}
static void close_restricted(int fd, void* data) {
    close(fd);
}
static const struct libinput_interface iface = {open_restricted, close_restricted};

static void quiet_log(struct libinput* li, enum libinput_log_priority p, const char* fmt, va_list args) {
    (void)li, (void)p, (void)fmt, (void)args; // devices we may not open (keyboards) are expected to fail
}

static void emit(int type, int code, int value) {
    struct input_event ev = {0};
    ev.type  = type;
    ev.code  = code;
    ev.value = value;
    if (write(uifd, &ev, sizeof(ev)) < 0)
        perror("uinput write");
}

static void click(int value) {
    emit(EV_KEY, BTN_LEFT, value);
    emit(EV_SYN, SYN_REPORT, 0);
}

static int setup_uinput(void) {
    uifd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (uifd < 0) {
        perror("open /dev/uinput");
        return -1;
    }
    ioctl(uifd, UI_SET_EVBIT, EV_KEY);
    ioctl(uifd, UI_SET_KEYBIT, BTN_LEFT);
    ioctl(uifd, UI_SET_KEYBIT, BTN_RIGHT);
    ioctl(uifd, UI_SET_EVBIT, EV_REL); // REL_X/Y make udev classify it as a mouse
    ioctl(uifd, UI_SET_RELBIT, REL_X);
    ioctl(uifd, UI_SET_RELBIT, REL_Y);

    struct uinput_setup us = {0};
    us.id.bustype = BUS_VIRTUAL;
    us.id.vendor  = 0x1209;
    us.id.product = 0x7a9b;
    snprintf(us.name, sizeof(us.name), BRIDGE_NAME);
    if (ioctl(uifd, UI_DEV_SETUP, &us) < 0 || ioctl(uifd, UI_DEV_CREATE) < 0) {
        perror("uinput create");
        return -1;
    }
    return 0;
}

static struct pad* find_pad(struct libinput_device* dev) {
    for (int i = 0; i < MAX_PADS; i++)
        if (pads[i].dev == dev)
            return &pads[i];
    return NULL;
}

static void add_device(struct libinput_device* dev) {
    if (libinput_device_config_tap_get_finger_count(dev) == 0)
        return; // not a touchpad
    struct pad* p = find_pad(NULL);
    if (!p)
        return;

    // mirror Hyprland's touchpad tap settings
    libinput_device_config_tap_set_enabled(dev, LIBINPUT_CONFIG_TAP_ENABLED);
    libinput_device_config_tap_set_drag_enabled(dev, LIBINPUT_CONFIG_DRAG_ENABLED);
    libinput_device_config_tap_set_drag_lock_enabled(dev, LIBINPUT_CONFIG_DRAG_LOCK_DISABLED);
    libinput_device_config_tap_set_button_map(dev, LIBINPUT_CONFIG_TAP_MAP_LRM);

    memset(p, 0, sizeof(*p));
    p->dev   = libinput_device_ref(dev);
    p->rawfd = -1;
    struct udev_device* ud = libinput_device_get_udev_device(dev);
    if (ud) {
        const char* node = udev_device_get_devnode(ud);
        if (node)
            p->rawfd = open(node, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        udev_device_unref(ud);
    }
    fprintf(stderr, "tap-bridge: watching %s\n", libinput_device_get_name(dev));
}

static void remove_device(struct libinput_device* dev) {
    struct pad* p = find_pad(dev);
    if (!p)
        return;
    for (int b = 0; b < 3; b++)
        if (p->tapDown[b])
            click(0);
    if (p->rawfd >= 0)
        close(p->rawfd);
    libinput_device_unref(p->dev);
    memset(p, 0, sizeof(*p));
}

static void drain_raw(struct pad* p) {
    struct input_event ev;
    while (p->rawfd >= 0 && read(p->rawfd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_KEY && (ev.code == BTN_LEFT || ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE)) {
            if (ev.value == 1) {
                p->physicalDown++;
                p->lastPhysical = now_ms();
            } else if (ev.value == 0 && p->physicalDown > 0)
                p->physicalDown--;
        }
    }
}

static int button_index(uint32_t button) {
    return button == BTN_RIGHT ? 1 : button == BTN_MIDDLE ? 2 : 0;
}

static void handle_button(struct libinput_event_pointer* pe, struct pad* p) {
    drain_raw(p);
    const int b       = button_index(libinput_event_pointer_get_button(pe));
    const int pressed = libinput_event_pointer_get_button_state(pe) == LIBINPUT_BUTTON_STATE_PRESSED;

    if (pressed) {
        // a physical press shows up on the raw device first; taps never do
        if (p->physicalDown > 0 || now_ms() - p->lastPhysical < 300)
            return;
        p->tapDown[b] = 1;
        click(1);
    } else if (p->tapDown[b]) {
        p->tapDown[b] = 0;
        click(0);
    }
}

static void on_signal(int s) {
    (void)s;
    running = 0;
}

int main(void) {
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);

    if (setup_uinput() < 0)
        return 1;

    struct udev*     udev = udev_new();
    struct libinput* li   = libinput_udev_create_context(&iface, NULL, udev);
    if (!li) {
        fprintf(stderr, "tap-bridge: libinput context failed\n");
        return 1;
    }
    libinput_log_set_handler(li, quiet_log);
    if (libinput_udev_assign_seat(li, "seat0") != 0) {
        fprintf(stderr, "tap-bridge: assigning seat0 failed\n");
        return 1;
    }

    struct pollfd pfd = {.fd = libinput_get_fd(li), .events = POLLIN};
    while (running) {
        libinput_dispatch(li);
        struct libinput_event* ev;
        while ((ev = libinput_get_event(li))) {
            struct libinput_device* dev = libinput_event_get_device(ev);
            switch (libinput_event_get_type(ev)) {
                case LIBINPUT_EVENT_DEVICE_ADDED: add_device(dev); break;
                case LIBINPUT_EVENT_DEVICE_REMOVED: remove_device(dev); break;
                case LIBINPUT_EVENT_POINTER_BUTTON: {
                    struct pad* p = find_pad(dev);
                    if (p)
                        handle_button(libinput_event_get_pointer_event(ev), p);
                    break;
                }
                default: break;
            }
            libinput_event_destroy(ev);
        }
        if (poll(&pfd, 1, -1) < 0 && errno != EINTR)
            break;
    }

    for (int i = 0; i < MAX_PADS; i++)
        if (pads[i].dev)
            remove_device(pads[i].dev);
    libinput_unref(li);
    udev_unref(udev);
    ioctl(uifd, UI_DEV_DESTROY);
    close(uifd);
    return 0;
}
