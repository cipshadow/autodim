#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>

typedef CFTypeRef (*create_with_service_fn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*i2c_fn)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);

extern int DisplayServicesGetBrightness(uint32_t display, float *value) __attribute__((weak_import));
extern int DisplayServicesSetBrightness(uint32_t display, float value) __attribute__((weak_import));
static create_with_service_fn create_service;
static i2c_fn write_i2c;
static i2c_fn read_i2c;

bool autodim_builtin_get(uint32_t display, float *value) {
    return DisplayServicesGetBrightness != NULL && DisplayServicesGetBrightness(display, value) == 0;
}

bool autodim_builtin_set(uint32_t display, float value) {
    return DisplayServicesSetBrightness != NULL && DisplayServicesSetBrightness(display, value) == 0;
}

static void resolve_ddc(void) {
    if (create_service != NULL || write_i2c != NULL || read_i2c != NULL) return;
    create_service = (create_with_service_fn)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
    write_i2c = (i2c_fn)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
    read_i2c = (i2c_fn)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
}

bool autodim_ddc_available(void) {
    resolve_ddc();
    return create_service != NULL && write_i2c != NULL && read_i2c != NULL;
}

void *autodim_ddc_create(io_service_t service) {
    resolve_ddc();
    return create_service == NULL ? NULL : (void *)create_service(kCFAllocatorDefault, service);
}

void autodim_ddc_release(void *service) {
    if (service != NULL) CFRelease((CFTypeRef)service);
}

IOReturn autodim_ddc_write(void *service, void *bytes, uint32_t count) {
    resolve_ddc();
    return write_i2c == NULL ? kIOReturnUnsupported : write_i2c((CFTypeRef)service, 0x37, 0x51, bytes, count);
}

IOReturn autodim_ddc_read(void *service, void *bytes, uint32_t count) {
    resolve_ddc();
    return read_i2c == NULL ? kIOReturnUnsupported : read_i2c((CFTypeRef)service, 0x37, 0x51, bytes, count);
}
