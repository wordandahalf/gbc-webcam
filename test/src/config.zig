const std = @import("std");
const m64282fp = @import("m64282fp.zig");
const pio_xck_multiplier = @import("pio/m64282fp.zig").xck_multiplier;
const compileErrorFmt = @import("utils.zig").compileErrorFmt;

/// The configured CPU / board frequency.
/// todo: set frequency using this value
const board_frequency = 125_000_000;
const adc_frequency = 48_000_000;

/// The desired M64282fp Xck frequency. The datasheet indicates a maximum of 500kHz.
pub const xck = 62_500;

const m64282fp_pio_clock_frequency = pio_xck_multiplier * xck;

/// Requisite PIO clock divider for configured Xck.
pub const m64282fp_pio_clock_divider = @as(comptime_float, board_frequency) / @as(comptime_float, m64282fp_pio_clock_frequency);
