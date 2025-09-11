const std = @import("std");
const microzig = @import("microzig");
const chip = microzig.chip;
const rp2xxx = microzig.hal;
const adc = rp2xxx.adc;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const pio = rp2xxx.pio;
const dma = rp2xxx.dma;
const multicore = rp2xxx.multicore;

const config = @import("config.zig");
const m64282fp = @import("m64282fp.zig");
const program = @import("pio/m64282fp.zig").program;
const serial = @import("usb/serial_cdc.zig");
const utils = @import("utils.zig");
const packRegisters = utils.packRegisters;

const led = gpio.num(25);

pub const microzig_options: microzig.Options = .{
    .interrupts = .{
        .IO_IRQ_BANK0 = .{ .c = adc_begin_sampling }
    },
    .log_level = .debug,
    .logFn = rp2xxx.uart.log,
};

const read_pin = gpio.num(0);

const pio0 = pio.num(0);
const sm = pio.StateMachine.sm0;
var device = m64282fp.init();

const pixel_data_channel = dma.channel(0);
var pixel_buffer: [m64282fp.sensor_resolution]u8 = undefined;

var read_data = false;
fn adc_begin_sampling() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    chip.peripherals.IO_BANK0.INTR0.modify(.{
        .GPIO0_EDGE_HIGH = 1
    });

    read_data = true;
    pixel_data_channel.setup_transfer_raw(
        @intFromPtr(pixel_buffer[0..]),
        @intFromPtr(&microzig.chip.peripherals.ADC.FIFO),
        m64282fp.sensor_resolution,
        .{
            .data_size = .size_8,
            .dreq = .adc,
            .enable = true,
            .write_increment = true,
            .read_increment = false,
            .trigger = true
        }
    );
    rp2xxx.adc.start(.free_running);

    led.toggle();
}

fn configure_pio() void {
    read_pin.set_direction(.in);
    read_pin.set_pull(.up);
    chip.peripherals.PPB.NVIC_ISER.modify(.{ .SETENA = 1 << 0 });
    chip.peripherals.IO_BANK0.PROC0_INTE0.modify(.{ .GPIO0_EDGE_HIGH = 1 });
    microzig.cpu.interrupt.enable(.IO_IRQ_BANK0);

    // initialize pins used in PIO, see m64282fp
    // todo: parameterize this so we can use other sensors in the same family
    for (1..6) |it| { pio0.gpio_init(gpio.num(@truncate(it))); }
    pio0.sm_set_pindir(sm, 1, 5, .out);
    pio0.sm_set_pin(sm, 1, 5, 0);

    const options: pio.LoadAndStartProgramOptions = .{
        .clkdiv = pio.ClkDivOptions.from_float(config.m64282fp_pio_clock_divider),
        .pin_mappings = .{
            .set = .{ .base = 1, .count = 1 },
            .side_set = .{ .base = 2, .count = 3 },
            .out = .{ .base = 5, .count = 1 }
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 0,
            .join_tx = true,
        },
    };

    pio0.sm_load_and_start_program(sm, program, options) catch unreachable;

    read_pin.set_input_enabled(true);
}

fn configure_adc() void {
    adc.configure_gpio_pin_num(.ain0);
    adc.select_input(.ain0);
    adc.apply(.{
        .sample_frequency = config.xck,
        .temp_sensor_enabled = false,
        .round_robin = null,
        .fifo = .{
            .dreq_enabled = true,
            .thresh = 1,
            .shift = true
        }
    });

    pixel_data_channel.setup_transfer_raw(
        @intFromPtr(pixel_buffer[0..]),
        @intFromPtr(&microzig.chip.peripherals.ADC.FIFO),
        m64282fp.sensor_resolution,
        .{
            .data_size = .size_8,
            .dreq = .adc,
            .enable = true,
            .write_increment = true,
            .read_increment = false,
            .trigger = true
        }
    );
}

pub fn main() !void {
    @memset(&pixel_buffer, 0);

    // The on-board LED to used for showing how often a frame is captured.
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);

    serial.init();

    configure_adc();
    configure_pio();

    var buffer: [3]u32 = undefined;
    packRegisters(device.registers.values, buffer[0..]);
    for (buffer) |it| {
        pio0.sm_write(sm, it);
    }

    pio0.sm_set_enabled(sm, true);

    while (true) {
        serial.task(false);

        if (read_data) {
            read_data = false;

            // todo: investigate USB CDC serial behavior, dump data
        }
    }
}
