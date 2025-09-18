from os import path
import json
import sys
from time import time
import tkinter as tk
from tkinter import ttk
import matplotlib.pyplot as plt
import numpy as np
from serial import Serial, SerialException
from serial.tools.list_ports import comports
from serial.threaded import Packetizer, ReaderThread

CONFIG_FILE = '.gbc-webcam.config.json'
DEVICE_DESCRIPTION = 'Pico - Board CDC'
BAUD = 115200

SENSOR_RESOLUTION = (128, 128)
WIDTH = SENSOR_RESOLUTION[0]
HEIGHT = SENSOR_RESOLUTION[1]
BACK_PORCH = 5
PADDING = 256

REGISTER_FIELDS = {
    'output_reference': (6, tk.Entry),
    'zero_point': (2, tk.Entry),
    'output_gain': (5, tk.Entry),
    'edge_operation': (2, tk.Entry),
    'override_kernel': (1, tk.Checkbutton),
    'exposure_high': (8, tk.Entry),
    'exposure_low': (8, tk.Entry),
    'pixel_coefficient': (8, tk.Entry),
    'neighbor_coefficient': (8, tk.Entry),
    'unknown_coefficient': (8, tk.Entry),
    'output_bias': (3, tk.Entry),
    'invert_output': (1, tk.Checkbutton),
    'edge_process_ratio': (3, tk.Entry),
    'edge_process_type': (1, tk.Checkbutton),
    'black_calibration': (-1, tk.Entry),
    'dma_shift_delay': (-1, tk.Entry),
}


def get_port():
    """Returns the first serial port with the description in DEVICE_DESCRIPTION, else None."""
    candidates = list(filter(lambda it: it.description == DEVICE_DESCRIPTION, comports()))

    if len(candidates) == 0:
        return None

    return Serial(port=candidates[0].device, baudrate=BAUD)


class SensorStream(Packetizer):
    """pySerial Packetizer that streams WIDTH x HEIGHT + PADDING frames, delimited by TERMINATOR"""
    TERMINATOR = bytes([0xaa, 0x55])
    viewer = None

    def connection_made(self, transport):
        print("Connected to device")
        viewer.send_buttton.config(state=tk.NORMAL)
        viewer.connect_button.config(state=tk.DISABLED)

    def handle_packet(self, packet):
        viewer.on_data(packet)

    def connection_lost(self, exc):
        if exc is not None:
            print(f"Lost connection: {exc}")
        else:
            print("Lost connection")
        viewer.send_buttton.config(state=tk.DISABLED)
        viewer.connect_button.config(state=tk.NORMAL)


class Viewer:
    reader = None

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Sensor Configuration")

        self.register_values = {}

        regs = None
        if path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r', encoding='utf-8') as fp:
                regs = json.load(fp=fp)

        for i, (name, (_, widget)) in enumerate(REGISTER_FIELDS.items()):
            ttk.Label(self.root, text=name).grid(row=i, column=0, sticky='w')
            if widget == tk.Entry:
                var = tk.StringVar(value=regs[name] if regs is not None and name in regs else "0")
                field = widget(self.root, textvariable=var, width=12)
                field.grid(row=i, column=1)
            elif widget == tk.Checkbutton:
                var = tk.IntVar(value=int(regs[name]) if regs is not None and name in regs else 0)
                field = widget(self.root, variable=var)
                field.grid(row=i, column=1)
            self.register_values[name] = var

        self.send_buttton = ttk.Button(self.root, text="Send", command=self.send_registers)
        self.send_buttton.grid(row=len(REGISTER_FIELDS), column=0, pady=10)
        self.send_buttton.config(state=tk.DISABLED)

        self.connect_button = ttk.Button(self.root, text="Connect", command=self.reconnect)
        self.connect_button.grid(row=len(REGISTER_FIELDS), column=1, pady=10)
        self.connect_button.config(state=tk.DISABLED)

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.__configure_pyplot__()
        self.root.after(16, self.__update_pyplot__)

        self.frame_counter_timestamp = np.floor(time() * 1e3)
        self.frame_count = 0

    def __configure_pyplot__(self):
        plt.ion()
        self.fig, (self.ax_image, self.ax_hist) = plt.subplots(1, 2, figsize=(10, 5))

        image = np.zeros((HEIGHT - BACK_PORCH, WIDTH), dtype=np.uint8)
        self.im_display = self.ax_image.imshow(image, cmap='gray', vmin=0, vmax=255)
        self.ax_image.set_title('Streamed Frames', y=1.055)
        self.ax_image_fps = self.ax_image.text(0.5, 1.02, f"0 fps", ha='center', fontsize=10, color='#555',
                           transform=self.ax_image.transAxes)
        self.ax_image.axis('off')

        self.hist_bins = np.arange(257)
        self.hist_data, _ = np.histogram(image, bins=self.hist_bins)
        self.hist_display = self.ax_hist.bar(self.hist_bins[:-1], self.hist_data, width=1.0, edgecolor='black')
        self.ax_hist.set_xlim(0, 255)
        self.ax_hist.set_ylim(0, np.prod(SENSOR_RESOLUTION) // 4)
        self.ax_hist.set_title('Intensity Histogram')
        self.ax_hist.set_xlabel('Pixel Intensity')
        self.ax_hist.set_ylabel('Count')
    
    def __update_pyplot__(self):
        now = np.floor(time() * 1e3)
        delta_t = (now - self.frame_counter_timestamp) / 1e3
        fps = self.frame_count / delta_t

        self.ax_image_fps.set_text(f"{fps:.0f} fps")

        if delta_t > 5:
            self.frame_counter_timestamp = now
            self.frame_count = 0

        self.fig.canvas.draw()
        self.fig.canvas.flush_events()
        self.root.after(16, self.__update_pyplot__)

    def start(self):
        self.root.mainloop()
    
    def on_close(self):
        if reader.is_alive():
            reader.close()

        self.root.destroy()
    
    def on_data(self, data):
        self.frame_count += 1

        frame = np.asarray(data, dtype=np.uint8)
        frame = np.append(frame, [frame[-1]] * 2)
        frame = np.copy(frame.reshape((HEIGHT + 2, WIDTH)))
        
        calib = list(map(float, self.register_values['black_calibration'].get().split(',')))
        if len(calib) != 2: calib = [1,0]
        frame = calib[0] * (np.roll(frame, shift=-int(self.register_values['dma_shift_delay'].get()))[0:(HEIGHT-BACK_PORCH), 0:WIDTH] + calib[1])

        self.im_display.set_data(frame)
        self.hist_data, _ = np.histogram(frame, bins=self.hist_bins)
        for rect, h in zip(self.hist_display, self.hist_data):
            rect.set_height(h)
        max_count = self.hist_data.max()
        if max_count > self.ax_hist.get_ylim()[1] * 0.9:
            self.ax_hist.set_ylim(0, max(100, max_count * 1.2))

    def send_registers(self):
        values = {}
        for name, (bits, widget_type) in REGISTER_FIELDS.items():
            if bits < 0: continue
            if widget_type == tk.Entry:
                values[name] = int(self.register_values[name].get())
            elif widget_type == tk.Checkbutton:
                values[name] = self.register_values[name].get()
        # Pack into 8 bytes as per struct layout
        raw = [0] * 8
        bit_offset = 0
        for name, (bits, widget_type) in REGISTER_FIELDS.items():
            if bits < 0: continue
            val = values[name]
            for b in range(bits):
                byte_index = (bit_offset + b) // 8
                bit_index = (bit_offset + b) % 8
                raw[byte_index] |= ((val >> b) & 1) << bit_index
            bit_offset += bits

        with open(CONFIG_FILE, 'w', encoding='utf-8') as out:
            regs = {}
            for name in self.register_values.keys():
                regs[name] = self.register_values[name].get()
            json.dump(regs, fp=out)

        try:
            for i in range(8):
                self.reader.write(bytes([0, i, raw[i]]))
            self.reader.write(bytes([2]))
        except SerialException as e:
            print(f"Failed to send registers: {e}")


    def reconnect(self):
        self.reader.close()
        try:
            new_reader = ReaderThread(get_port(), SensorStream)
            new_reader.start()
        except SerialException as e:
            print(f"Could not reconnect: {e}")
            return

        self.reader = new_reader


if __name__ == "__main__":
    viewer = Viewer()
    
    port = get_port()
    if port is None:
        print(f"No serial device found with description: '{DEVICE_DESCRIPTION}'")
        sys.exit(1)

    reader = ReaderThread(port, SensorStream)
    reader.viewer = viewer

    viewer.reader = reader

    reader.start()
    viewer.start()
