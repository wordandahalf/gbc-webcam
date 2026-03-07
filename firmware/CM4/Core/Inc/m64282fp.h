#ifndef _M64282FP_H_
#define _M64282FP_H_

#include "stdint.h"

#define M64282FP_REG_COUNT   8
#define M64282FP_ADDR_WIDTH  3
#define M64282FP_REG_WIDTH   8
#define M64282FP_FIELD_WIDTH (M64282FP_ADDR_WIDTH + M64282FP_REG_WIDTH)

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

inline unsigned short m64282fp_get_exposure(m64282fp_registers_t config) {
    return (config.exposure_high << 8) | config.exposure_low;
}

extern m64282fp_registers_t m64282fp_default_registers;

// Packs the initialization sequence configuring the provided registers into the ouput buffer.
// The output buffer should be written to the GPIO BSRR register to configure the M64282FP.
// It should be 91 words long.
void m64282fp_pack_bsrr(m64282fp_registers_t *registers, uint32_t *output);

#endif