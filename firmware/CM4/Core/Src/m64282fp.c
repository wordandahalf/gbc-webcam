#include "m64282fp.h"
#include "main.h"

m64282fp_registers_t m64282fp_default_registers = {
    .output_reference = 40, .zero_point = CALIBRATION_POSITIVE,
    .output_gain = 4, .edge_operation = DIRECTION_NONE,
    .override_kernel = 0, .exposure_high = 0,
    .exposure_low = 0x3f, .pixel_coefficient = 1,
    .neighbor_coefficient = 0, .unknown_coefficient = 1,
    .output_bias = 0, .invert_output = 0, .edge_process_ratio = RATIO_50,
    .edge_process_type = EDGE_PROCESS_ENHANCE
};

static void bsrr_reset(uint32_t *arr, uint16_t mask) { *arr |= mask << 16; }
static void bsrr_set(uint32_t *arr, uint16_t mask) { *arr |= mask; }

void m64282fp_pack_bsrr(m64282fp_registers_t *registers, uint32_t *bsrr) {
    uint8_t *input = (uint8_t*) registers;

    // assemble the serial configuration bitstream
    uint32_t sin_bit_stream[3];
    sin_bit_stream[0] = 0x00040100 | (input[0] << 21) | (input[1] << 10) | (input[2] >> 1);
    sin_bit_stream[1] = 0x30080140 | ((input[2] & 0x7f) << 31) | (input[3] << 20) | (input[4] << 9)| (input[5] >> 2);
    sin_bit_stream[2] = 0x30070000 | ((input[5] & 0x3f) << 30) | (input[6] << 19) | (input[7] << 8);

    // pack the bsrr values
    bsrr_reset(bsrr++, PIN_RESET);
    bsrr_set(bsrr, PIN_RESET);

    for (int i = 0; i < M64282FP_REG_COUNT * (M64282FP_ADDR_WIDTH + M64282FP_REG_WIDTH); i++) {
        int bit = (sin_bit_stream[i / 32] >> (31 - (i % 32))) & 1;

        if (i % M64282FP_FIELD_WIDTH == 0) bsrr_reset(bsrr, PIN_LOAD);
        else if (i % M64282FP_FIELD_WIDTH == M64282FP_FIELD_WIDTH - 1) bsrr_set(bsrr, PIN_LOAD);

        if (bit) bsrr_set(bsrr++, PIN_SIN);
        else     bsrr_reset(bsrr++, PIN_SIN);
    }

    bsrr_reset(bsrr, PIN_LOAD | PIN_SIN);
    bsrr_set(bsrr++, PIN_START);

    bsrr_reset(bsrr, PIN_START);
}