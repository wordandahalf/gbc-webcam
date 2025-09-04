pub const EdgeProcessType = enum(u1) {
    enhancement = 0, extraction
};

pub const EdgeProcessDirection = enum(u2) {
    none = 0, horizontal, vertical, both
};

pub const EdgeProcessRatio = enum(u3) {
    @"50%" = 0, @"75%", @"100%", @"125%", @"200%", @"300%", @"400%", @"500%"
};

pub const ZeroCalibrationType = enum(u2) {
    none = 0, negative, positive, _
};

pub const NamedRegisters = packed struct(u64) {
    output_reference: u6,                   // A sign-magnitude encoded value for adjusting the offset of the read pixel data in 32 mV steps.
    zero_point: ZeroCalibrationType,        // "It calibrates the zero value by setting the dark level output signal to Vref." (11.6.4)

    output_gain: u5,                        // A value for configuring the output gain. Its lower four bits increase the gain by 1.5 dB starting at 14 dB.
                                            // Setting the MSB increases the total gain by a flat 6 dB.
    edge_operation: EdgeProcessDirection,   // Configures which edge directions have edge_process applied.
    override_kernel: u1,                    // See 11.6.1. Overrides kernel values specifically for vertical edge processing.

    exposure_time_high: u8,                 // High byte, configuring the exposure time in 4.096 ms increments.
    exposure_time_low: u8,                  // Low byte, configuring the exposure time in 16 us increments.

    pixel_coefficient: u8,                  // Multiplier applied to pixel value for filtering kernel.
    neighbor_coefficient: u8,               // Multipler applied to 4-neighbors for filtering kernel.
    unknown_coefficient: u8,                // (part of 1D kernel, not well explained in datasheet)

    output_bias: u3,                        // A value for configuring the output node voltage (Vref) in 500 mV steps starting at 0 V.
    invert_output: u1,                      // Inverts the output when high.
    edge_process_ratio: EdgeProcessRatio,   // Sets additional mutiplier applied to term depending on value of edge_operation.
                                            // See datasheet for exact expression (11.5).
    edge_process: EdgeProcessType,          // Configures the type of edge post-processing (ibid).

    /// Returns the full 16-bit exposure value from exposure_time_high and exposure_time_low.
    pub fn exposure(self: NamedRegisters) callconv(.@"inline") u16 {
        return (@as(u16, self.exposure_time_high) << 8) | self.exposure_time_low;
    }
};

pub const Registers = union {
    values: [8]u8, named: NamedRegisters,
};

pub const M64282fp = struct {
    registers: Registers,

    pub fn init() M64282fp {
        return .{ .registers = .{ .values = undefined } };
    }

    /// Convenience function for `self.registers.named`.
    pub fn regs(self: M64282fp) callconv(.@"inline") NamedRegisters {
        return self.registers.named;
    }
};