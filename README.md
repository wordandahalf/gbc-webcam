<img align="right" width="200" alt="image" src="https://github.com/user-attachments/assets/d1ae5e0c-01db-4336-be79-cb440a34b66e" />

### gbc-webcam
A color webcam made using the M64282FP silicon retina found in the Gameboy Camera. Using a trichroic prism salvaged from a Hitachi HV-C20 3CCD camera, three M64282FP sensors are combined with an STM32H755 Nucleo development board to create a fully functional USB webcam.

##### Structure
- `adapters/` contains the FreeCAD files for the shims to adapt the prism mounting system to the sensors.
- `analysis/` contains Typst source files to generate a report regarding the analysis of the silicon retnia.
- `calibration/` contains Python source files to perform the necessary color calibration of the three sensors.
- `firmware/` contains the STM32CubeIDE project for programming the STM32H755 development board with the USB webcam firmware.
