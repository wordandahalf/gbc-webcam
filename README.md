<img align="right" width="200" alt="image" src="https://github.com/user-attachments/assets/d1ae5e0c-01db-4336-be79-cb440a34b66e" />

### gbc-webcam
A color webcam made using the M64282FP silicon retina found in the Gameboy Camera. It is under active development, aiming to use three separate sensors and a dichroic prism for color sensitivity. A realtime temporal demosaicking algorithm leverages the separate sensors for increased framerate.

#### Current Status
By disassembling a Hitachi HV-C20 3CCD camera, I have procured a suitable prism. In order to fit in the existing mounting brackets, about 2.5mm of material needs to be sanded off the PCB of the Game Boy Camera sensor module. The board is only two layers and the removed area only contains ground pour, so it poses little risk. My next steps are to purchase two additional GBCs and design mounting brackets in the meantime. For the final design, I plan on using a dual core STM32H7 part, so I will need to port the current Pico design to STM's toolchain. I should be able to leverage DMA to GPIO to sidestep bit-banging the camera configuration lines.
