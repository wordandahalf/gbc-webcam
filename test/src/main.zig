const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const pio = rp2xxx.pio;

const config = @import("config.zig");
const m64282fp = @import("m64282fp.zig");
const program = @import("pio/m64282fp.zig").program;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{ .PIO0_IRQ_0 = .{ .c = pio_ready_for_data } }
};

const pio0 = pio.num(0);
const sm = pio.StateMachine.sm0;
var device = m64282fp.init();

fn pio_ready_for_data() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    pio0.sm_blocking_write(sm,  @as(u32, device.regs().exposure()) * config.m64282fp_clock_periods_per_exposure - 2);
    pio0.sm_blocking_write(sm, m64282fp.sensor_resolution - 2);

    pio0.sm_clear_interrupt(sm, .irq0, .statemachine);
}

pub fn main() !void {
    microzig.cpu.interrupt.enable(.PIO0_IRQ_0);

    for (0..6) |it| { pio0.gpio_init(gpio.num(@truncate(0 + it))); }
    pio0.sm_set_pindir(sm, 0, 6, .out);

    const options: pio.LoadAndStartProgramOptions = .{
        .clkdiv = pio.ClkDivOptions.from_float(config.m64282fp_pio_clock_divider),
        .pin_mappings = .{
            .set = .{ .base = 0, .count = 4, },
            .out = .{ .base = 4, .count = 1, },
            .side_set = .{ .base = 5, .count = 1 },
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 0,
            .join_tx = true,
        },
    };

    pio0.sm_enable_interrupt(sm, .irq0, .statemachine);
    pio0.sm_load_and_start_program(sm, program, options) catch unreachable;

    // For my sanity, we waste 21 bits per FIFO word when encoding register values.
    // This is not ideal, but meticulously constructing the three FIFO words with the
    // 8 packed 11-bit address-value pairs is a pain in the ass since it is isn't byte-aligned.
    // Instead, we just use 11 bits per word and then discard the rest.
    for (0..8, device.registers.values) |i, it| {
        pio0.sm_blocking_write(sm, @as(u32, @as(u11, @truncate(i)) << 8 | it) << 21);
    }

    pio0.sm_set_enabled(sm, true);
    while (true) {}
}
