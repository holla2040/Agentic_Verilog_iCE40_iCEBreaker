all: led_chaser.bin

led_chaser.json: led_chaser.v
	yosys -p "synth_ice40 -top led_chaser -json led_chaser.json" led_chaser.v

led_chaser.asc: led_chaser.json icebreaker.pcf
	nextpnr-ice40 --up5k --package sg48 --json led_chaser.json --pcf icebreaker.pcf --asc led_chaser.asc

led_chaser.bin: led_chaser.asc
	icepack led_chaser.asc led_chaser.bin

prog: led_chaser.bin
	iceprog led_chaser.bin

clean:
	rm -f led_chaser.json led_chaser.asc led_chaser.bin
