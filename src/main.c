#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/dma.h"
#include "pico/multicore.h"
#include "pico/time.h"
#include "hardware/pio.h"
#include "m64282fp.h"
#include "pio/m64282fp.pio.h"

#define READ_PIN 0

PIO pio; uint sm; uint offset; pio_sm_config sm_config;
uint chan; dma_channel_config dma_config;

char pixel_buffer[SENSOR_RESOLUTION + 256];

volatile int i = 0;
static void adc_prime_dma();
static void adc_begin_sampling(uint gpio, uint32_t events) {
    multicore_fifo_push_blocking(1);
    adc_prime_dma(); adc_run(true);
    gpio_put(PICO_DEFAULT_LED_PIN, !gpio_get_out_level(PICO_DEFAULT_LED_PIN));
}

static void configure_pio() {
    gpio_init(READ_PIN);
    gpio_set_dir(READ_PIN, GPIO_IN);
    gpio_set_pulls(READ_PIN, false, true);
    gpio_set_irq_enabled_with_callback(READ_PIN, GPIO_IRQ_EDGE_RISE, true, &adc_begin_sampling);

    bool rc = pio_claim_free_sm_and_add_program(&m64282fp_program, &pio, &sm, &offset);
    hard_assert(rc);

    sm_config = m64282fp_program_get_default_config(offset);
    sm_config_set_clkdiv(&sm_config, 125000000.0f / (m64282fp_xck_multiplier * XCLK));

    for (int i = 1; i < 6; i++) pio_gpio_init(pio, i);
    sm_config_set_set_pins(&sm_config, 1, 1);
    sm_config_set_sideset_pin_base(&sm_config, 2);
    sm_config_set_out_pins(&sm_config, 5, 1);
    pio_sm_set_consecutive_pindirs(pio, sm, 1, 5, true);

    sm_config_set_out_shift(&sm_config, false, true, 32);
    sm_config_set_fifo_join(&sm_config, PIO_FIFO_JOIN_TX);
}

static void adc_prime_dma() {
    dma_channel_configure(chan, &dma_config, &pixel_buffer, &adc_hw->fifo, sizeof(pixel_buffer), true);
}

static void configure_adc() {
    adc_init();
    adc_gpio_init(26);
    adc_select_input(0);
    adc_set_clkdiv(48000000.0f / XCLK - 1);
    adc_set_temp_sensor_enabled(false);
    adc_set_round_robin(0);
    adc_fifo_setup(true, true, 1, false, true);

    chan = dma_claim_unused_channel(true);

    dma_config = dma_channel_get_default_config(chan);
    channel_config_set_transfer_data_size(&dma_config, DMA_SIZE_8);
    channel_config_set_dreq(&dma_config, DREQ_ADC);
    channel_config_set_enable(&dma_config, true);
    channel_config_set_write_increment(&dma_config, true);
    channel_config_set_read_increment(&dma_config, false);

    adc_prime_dma();
}

void frame_transfer_watchdog() {
    while (true) {
        if (multicore_fifo_rvalid()) {
            multicore_fifo_drain();
            pixel_buffer[SENSOR_RESOLUTION + 254] = 0xAA;
            pixel_buffer[SENSOR_RESOLUTION + 255] = 0x55;
            stdio_put_string(pixel_buffer, sizeof(pixel_buffer), false, false);
        }
    }
}

void camera_start(uint32_t *values, size_t len) {
    pio_sm_init(pio, sm, offset, &sm_config);
    pio_sm_clear_fifos(pio, sm);
    for (size_t i = 0; i < len; i++)
        pio_sm_put_blocking(pio, sm, values[i]);
    pio_sm_set_enabled(pio, sm, true);
}

int main() {
    stdio_init_all();
    for (int i = 0; i < 6; i++) gpio_init(i);

    gpio_set_function(PICO_DEFAULT_LED_PIN, GPIO_FUNC_SIO);
    gpio_set_dir(PICO_DEFAULT_LED_PIN, true);
    gpio_put(PICO_DEFAULT_LED_PIN, true);

    m64282fp_registers_t registers = default_values;
    uint32_t buffer[3];
    camera_pack_registers(&registers, buffer);

    multicore_launch_core1(&frame_transfer_watchdog);
    configure_adc();
    configure_pio();

    camera_start(buffer, 3);

    while (true) {
        switch (stdio_getchar_timeout_us(0)) {
            case 0:
                int reg = stdio_getchar_timeout_us(0);
                if (reg == PICO_ERROR_TIMEOUT) break;

                int val = stdio_getchar_timeout_us(0);
                if (reg == PICO_ERROR_TIMEOUT) break;

                ((uint8_t*) &registers)[(uint8_t) reg] = (uint8_t) val;
                break;
            case 1:
                registers = default_values;
                break;
            case 2:
                adc_run(false); dma_channel_abort(chan);
                configure_adc();
                camera_pack_registers(&registers, buffer);
                camera_start(buffer, 3);
                break;
            default:
                break;
        }
        sleep_ms(1);
    }
}
