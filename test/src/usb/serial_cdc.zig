const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const usb = rp2xxx.usb;

pub const usb_dev = rp2xxx.usb.Usb(.{});

const usb_config_len = usb.templates.config_descriptor_len + usb.templates.cdc_descriptor_len;
const usb_config_descriptor =
usb.templates.config_descriptor(1, 2, 0, usb_config_len, 0xc0, 100) ++
    usb.templates.cdc_descriptor(0, 4, usb.Endpoint.to_address(1, .In), 8, usb.Endpoint.to_address(2, .Out), usb.Endpoint.to_address(2, .In), 64);

var driver_cdc: usb.cdc.CdcClassDriver(usb_dev) = .{};
var drivers = [_]usb.types.UsbClassDriver{driver_cdc.driver()};

// This is our device configuration
pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
    .device_descriptor = &.{
        .descriptor_type = usb.DescType.Device,
        .bcd_usb = 0x0200,
        .device_class = 0xEF,
        .device_subclass = 2,
        .device_protocol = 1,
        .max_packet_size0 = 64,
        .vendor = 0x2E8A,
        .product = 0x000a,
        .bcd_device = 0x0100,
        .manufacturer_s = 1,
        .product_s = 2,
        .serial_s = 3,
        .num_configurations = 1,
    },
    .config_descriptor = &usb_config_descriptor,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &usb.utils.utf8_to_utf16_le("Raspberry Pi"),
        &usb.utils.utf8_to_utf16_le("Pico Test Device"),
        &usb.utils.utf8_to_utf16_le("someserial"),
        &usb.utils.utf8_to_utf16_le("Board CDC"),
    },
    .drivers = &drivers,
};

var usb_tx_buff: [1024]u8 = undefined;

// Transfer data to host
// NOTE: After each USB chunk transfer, we have to call the USB task so that bus TX events can be handled
pub fn usb_cdc_write(comptime fmt: []const u8, args: anytype) void {
    var text = std.fmt.bufPrint(&usb_tx_buff, fmt, args) catch &.{};

    while (text.len > 0) {
        text = driver_cdc.write(text);
        usb_dev.task(false) catch unreachable;
    }
    // Short messages are not sent right away; instead, they accumulate in a buffer, so we have to force a flush to send them
    _ = driver_cdc.write_flush();
    usb_dev.task(false) catch unreachable;
}

pub fn usb_cdc_write_no_flush(data: []const u8) void {
    var buffer = data;

    while (buffer.len > 0) {
        buffer = driver_cdc.write(buffer);
        // usb_dev.task(false) catch unreachable;
    }
}

pub fn flush() void {
    _ = driver_cdc.write_flush();
    usb_dev.task(false) catch unreachable;
}

var usb_rx_buff: [1024]u8 = undefined;

// Receive data from host
// NOTE: Read code was not tested extensively. In case of issues, try to call USB task before every read operation
pub fn usb_cdc_read() []const u8 {
    var total_read: usize = 0;
    var read_buff: []u8 = usb_rx_buff[0..];

    while (true) {
        const len = driver_cdc.read(read_buff);
        read_buff = read_buff[len..];
        total_read += len;
        if (len == 0) break;
    }

    return usb_rx_buff[0..total_read];
}

pub fn task(debug: bool) void {
    usb_dev.task(debug) catch unreachable;
}

pub fn init() void {
    usb_dev.init_clk();
    usb_dev.init_device(&DEVICE_CONFIGURATION) catch unreachable;
}
