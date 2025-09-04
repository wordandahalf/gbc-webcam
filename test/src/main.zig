const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const pio = rp2xxx.pio;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{ .PIO0_IRQ_0 = .{ .c = pio_ready_for_data } }
};

const pio0 = pio.num(0);
const sm = pio.StateMachine.sm0;

fn pio_ready_for_data() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    // write exposure
    pio0.sm_blocking_write(sm, 32 - 2);

    // write read length
    pio0.sm_blocking_write(sm, 128 - 2);

    pio0.sm_clear_interrupt(sm, .irq0, .statemachine);
}

const program_sin_source = @embedFile("pio/m64282fp.pio");
const program_sin = blk: {
    @setEvalBranchQuota(65536);
    break :blk pio.assemble(program_sin_source, .{}).get_program_by_name("m64282fp");
};

pub fn main() !void {
    microzig.cpu.interrupt.enable(.PIO0_IRQ_0);

    for (0..6) |it| { pio0.gpio_init(gpio.num(@truncate(0 + it))); }
    pio0.sm_set_pindir(sm, 0, 6, .out);

    const options: pio.LoadAndStartProgramOptions = .{
        .clkdiv = pio.ClkDivOptions.from_float(15.625),
        .pin_mappings = .{
            .set = .{
                .base = 0,
                .count = 4,
            },
            .out = .{
                .base = 4,
                .count = 1,
            },
            .side_set = .{
                .base = 5,
                .count = 1
            },
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 0,
            .join_tx = true,
        },
    };

    pio0.sm_enable_interrupt(sm, .irq0, .statemachine);
    pio0.sm_load_and_start_program(sm, program_sin, options) catch unreachable;

    // For my sanity, we waste 21 bits per FIFO word when encoding register values.
     // This is not ideal, but meticulously constructing the three FIFO words with the
     // 8 packed 11-bit address-value pairs is a pain in the ass since it is isn't byte-aligned.
     // Instead, we just use 11 bits per word and then discard the rest.
    for (0..8) |it| {
        var word = @as(u11, @truncate(it)) << 8;
        if (it & 1 == 1) {
            word |= 0b01010101;
        } else {
            word |= 0b10101010;
        }
        pio0.sm_blocking_write(sm, @as(u32, word) << 21);
    }

    pio0.sm_set_enabled(sm, true);
    while (true) {}
}
