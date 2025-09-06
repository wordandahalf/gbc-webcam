const pio = @import("microzig").hal.pio;

const program_source = @embedFile("m64282fp.pio");
const program_assembly = blk: {
    @setEvalBranchQuota(65536);
    break :blk pio.assemble(program_source, .{});
};

pub const program = program_assembly.get_program_by_name("m64282fp");

// todo: bug in microzig (see #671) prevents getting by name
pub const xck_multiplier = program.defines[0].value;
