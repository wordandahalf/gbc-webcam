#ifndef _M64282FP_H_
#define _M64282FP_H_

#define SENSOR_RESOLUTION 16384
#define XCLK 37500.0

typedef enum {
    EDGE_PROCESS_ENHANCE = 0,
    EDGE_PROCESS_EXTRACT = 1
} edge_process_type_t;

typedef enum {
    DIRECTION_NONE = 0,
    DIRECTION_HORZ = 1,
    DIRECTION_VERT = 2,
    DIRECTION_BOTH = 3,
} edge_process_dir_t;

typedef enum {
    RATIO_50    = 0,
    RATIO_75    = 1,
    RATIO_100   = 2,
    RATIO_200   = 3,
    RATIO_300   = 4,
    RATIO_400   = 5
} edge_process_ratio_t;

typedef enum {
    CALIBRATION_NONE     = 0,
    CALIBRATION_NEGATIVE = 1,
    CALIBRATION_POSITIVE = 2
} zero_calibration_type_t;

typedef struct __attribute__((packed)) {
    unsigned int            output_reference        : 6;
    zero_calibration_type_t zero_point              : 2;
    unsigned int            output_gain             : 5;
    edge_process_dir_t      edge_operation          : 2;
    unsigned int            override_kernel         : 1;
    unsigned int            exposure_high           : 8;
    unsigned int            exposure_low            : 8;
    unsigned int            pixel_coefficient       : 8;
    unsigned int            neighbor_coefficient    : 8;
    unsigned int            unknown_coefficient     : 8;
    unsigned int            output_bias             : 3;
    unsigned int            invert_output           : 1;
    edge_process_ratio_t    edge_process_ratio      : 3;
    edge_process_type_t     edge_process_type       : 1;
} m64282fp_registers_t;

m64282fp_registers_t default_values = {
    .output_reference = 40, .zero_point = CALIBRATION_POSITIVE,
    .output_gain = 4, .edge_operation = DIRECTION_NONE,
    .override_kernel = 0, .exposure_high = 0,
    .exposure_low = 0x3f, .pixel_coefficient = 1,
    .neighbor_coefficient = 0, .unknown_coefficient = 1,
    .output_bias = 0, .invert_output = 0, .edge_process_ratio = RATIO_50,
    .edge_process_type = EDGE_PROCESS_ENHANCE
};

inline unsigned short exposure(m64282fp_registers_t config) {
    return (config.exposure_high << 8) | config.exposure_low;
}

void camera_pack_registers(m64282fp_registers_t *registers, uint32_t *output) {
    uint8_t *input = (uint8_t*) registers;

    output[0] = 0x00040100 | (input[0] << 21) | (input[1] << 10) | (input[2] >> 1);
    output[1] = 0x30080140 | ((input[2] & 0x7f) << 31) | (input[3] << 20) | (input[4] << 9)| (input[5] >> 2);
    output[2] = 0x30070000 | ((input[5] & 0x3f) << 30) | (input[6] << 19) | (input[7] << 8);
}

#endif