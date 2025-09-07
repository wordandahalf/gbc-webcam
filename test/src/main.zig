const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const pio = rp2xxx.pio;

const config = @import("config.zig");
const m64282fp = @import("m64282fp.zig");
const program = @import("pio/m64282fp.zig").program;
const packRegisters = @import("utils.zig").packRegisters;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{
        .PIO0_IRQ_0 = .{ .c = pio_ready_for_data },
        .PIO0_IRQ_1 = .{ .c = adc_sample_pixel },
    }
};

const pio0 = pio.num(0);
const sm = pio.StateMachine.sm0;
var device = m64282fp.init();

var pixel_buffer: [m64282fp.sensor_resolution]u12 = undefined;
var pixel_buffer_ptr: u32 = 0;

fn pio_ready_for_data() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    pixel_buffer_ptr = 0;
    pio0.sm_blocking_write(sm, m64282fp.sensor_resolution);
    pio0.sm_blocking_write(sm,  @as(u32, device.regs().exposure()) * config.m64282fp_clock_periods_per_exposure);

    pio0.sm_clear_interrupt(sm, .irq0, .statemachine);
}

fn adc_sample_pixel() callconv(.c) void {
    const cs = microzig.interrupt.enter_critical_section();
    defer cs.leave();

    pixel_buffer[pixel_buffer_ptr] = rp2xxx.adc.convert_one_shot_blocking(.ain0) catch blk: {
        break :blk 0;
    };
    pixel_buffer_ptr += 1;

    pio0.sm_clear_interrupt(sm, .irq1, .statemachine);
}

pub fn main() !void {
    microzig.cpu.interrupt.enable(.PIO0_IRQ_0);
    microzig.cpu.interrupt.enable(.PIO0_IRQ_1);

    for (0..6) |it| { pio0.gpio_init(gpio.num(@truncate(0 + it))); }
    pio0.sm_set_pindir(sm, 0, 6, .out);
    pio0.sm_set_pin(sm, 0, 6, 0);

    const options: pio.LoadAndStartProgramOptions = .{
        .clkdiv = pio.ClkDivOptions.from_float(config.m64282fp_pio_clock_divider),
        .pin_mappings = .{
            .set = .{ .base = 0, .count = 2 },
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

    pio0.sm_enable_interrupt(sm, .irq0, .statemachine);
    pio0.sm_load_and_start_program(sm, program, options) catch unreachable;

    var buffer: [3]u32 = undefined;
    packRegisters(device.registers.values, buffer[0..]);

    for (buffer) |it| {
        pio0.sm_blocking_write(sm, it);
    }

    pio0.sm_set_enabled(sm, true);
    while (true) {}
}
