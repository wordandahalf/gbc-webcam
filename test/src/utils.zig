const std = @import("std");

pub fn compileErrorFmt(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

pub fn packRegisters(input: [8]u8, output: []u32) void {
    var packed_value: u96 = 0;

    for (input, 0..) |it, i| {
        const addr: u96 = i & 0b111;
        const val:  u96 = it;
        const reg_bits = (addr << 8) | val;

        const shift: u7 = @truncate(85 - 11*i);
        packed_value |= reg_bits << shift;
    }

    output[0] = @truncate(packed_value >> 64);
    output[1] = @truncate(packed_value >> 32);
    output[2] = @truncate(packed_value >> 0);
}
