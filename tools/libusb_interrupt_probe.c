#include <libusb-1.0/libusb.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum {
    VendorID = 0x5566,
    ProductID = 0x0008,
    InterfaceNumber = 2,
    OutputEndpoint = 0x05,
    InputEndpoint = 0x85,
    FrameLength = 64,
    TransferTimeoutMilliseconds = 1000
};

static const uint8_t begin_transaction[FrameLength] = {
    0x55, 0x01
};

static const uint8_t get_lighting[FrameLength] = {
    0x55, 0x05, 0x00, 0x20, 0x20
};

static const uint8_t static_red[FrameLength] = {
    0x55, 0x06, 0x00, 0x6B, 0x20, 0x00, 0x00, 0x00,
    0x02, 0xAA, 0x03, 0x64, 0x01, 0x00, 0x00, 0x00,
    0xFF, 0x00, 0x00, 0x00, 0x64, 0x04, 0x00, 0xCB,
    0x04, 0x00, 0x01, 0x00
};

static const uint8_t commit_transaction[FrameLength] = {
    0x55, 0x02
};

static void print_bytes(const uint8_t *bytes, int length) {
    for (int index = 0; index < length; index++) {
        printf("%02X%s", bytes[index], index + 1 == length ? "" : " ");
    }
    putchar('\n');
}

static void print_libusb_result(const char *operation, int result, int transferred) {
    printf("%s: result=%d (%s), transferred=%d\n",
           operation,
           result,
           libusb_strerror(result),
           transferred);
}

static int send_interrupt(
    libusb_device_handle *handle,
    const char *label,
    const uint8_t packet[FrameLength]
) {
    int transferred = 0;
    int result = libusb_interrupt_transfer(
        handle,
        OutputEndpoint,
        (unsigned char *)packet,
        FrameLength,
        &transferred,
        TransferTimeoutMilliseconds
    );
    print_libusb_result(label, result, transferred);
    printf("  OUT 0x%02X: ", OutputEndpoint);
    print_bytes(packet, FrameLength);
    return result;
}

static int read_interrupt(libusb_device_handle *handle, const char *label) {
    uint8_t response[FrameLength] = {0};
    int transferred = 0;
    int result = libusb_interrupt_transfer(
        handle,
        InputEndpoint,
        response,
        FrameLength,
        &transferred,
        TransferTimeoutMilliseconds
    );
    print_libusb_result(label, result, transferred);
    if (transferred > 0) {
        printf("  IN  0x%02X: ", InputEndpoint);
        print_bytes(response, transferred);
    }
    return result;
}

static int run_step(libusb_device_handle *handle, const char *name, const uint8_t packet[FrameLength]) {
    char output_label[128];
    char input_label[128];

    snprintf(output_label, sizeof(output_label), "interrupt OUT 0x%02X (%s)", OutputEndpoint, name);
    snprintf(input_label, sizeof(input_label), "interrupt IN 0x%02X (%s)", InputEndpoint, name);

    int output_result = send_interrupt(handle, output_label, packet);
    int input_result = read_interrupt(handle, input_label);
    usleep(strcmp(name, "commit") == 0 ? 50000 : 20000);
    return output_result != LIBUSB_SUCCESS ? output_result : input_result;
}

int main(int argc, char **argv) {
    int static_red_test = 0;
    if (argc == 2 && strcmp(argv[1], "--static-red") == 0) {
        static_red_test = 1;
    } else if (argc > 1) {
        fprintf(stderr, "Usage: %s [--static-red]\n", argv[0]);
        return 64;
    }

    libusb_context *context = NULL;
    int result = libusb_init(&context);
    if (result != LIBUSB_SUCCESS) {
        print_libusb_result("libusb_init", result, 0);
        return 1;
    }

    printf("VID/PID: 0x%04X:0x%04X\n", VendorID, ProductID);
    printf("Interface: %d, OUT: 0x%02X interrupt, IN: 0x%02X interrupt\n",
           InterfaceNumber, OutputEndpoint, InputEndpoint);

    libusb_device_handle *handle = libusb_open_device_with_vid_pid(
        context,
        VendorID,
        ProductID
    );
    if (handle == NULL) {
        fprintf(stderr, "libusb_open_device_with_vid_pid: device not found or could not be opened\n");
        libusb_exit(context);
        return 2;
    }
    printf("libusb_open: success\n");

    int active = libusb_kernel_driver_active(handle, InterfaceNumber);
    if (active >= 0) {
        printf("libusb_kernel_driver_active(%d): %d\n", InterfaceNumber, active);
    } else {
        print_libusb_result("libusb_kernel_driver_active", active, 0);
    }

    result = libusb_claim_interface(handle, InterfaceNumber);
    print_libusb_result("libusb_claim_interface(2)", result, 0);
    if (result != LIBUSB_SUCCESS) {
        fprintf(stderr, "The macOS HID driver may own Interface 2; this probe does not detach it.\n");
        libusb_close(handle);
        libusb_exit(context);
        return 3;
    }

    printf("Probe: %s\n", static_red_test ? "01 -> 05 -> Static Red 06 -> 02" : "55 01 then read 0x85");
    int final_result = run_step(handle, "begin", begin_transaction);

    if (static_red_test) {
        final_result = run_step(handle, "get", get_lighting);
        final_result = run_step(handle, "static-red", static_red);
        final_result = run_step(handle, "commit", commit_transaction);
    }

    int release_result = libusb_release_interface(handle, InterfaceNumber);
    print_libusb_result("libusb_release_interface(2)", release_result, 0);
    libusb_close(handle);
    libusb_exit(context);
    return final_result == LIBUSB_SUCCESS || final_result == LIBUSB_ERROR_TIMEOUT ? 0 : 4;
}
