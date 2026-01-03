all: blinky.bin

blinky.json: blinky.v
	yosys -p "synth_ice40 -top blinky -json blinky.json" blinky.v

blinky.asc: blinky.json icebreaker.pcf
	nextpnr-ice40 --up5k --package sg48 --json blinky.json --pcf icebreaker.pcf --asc blinky.asc

blinky.bin: blinky.asc
	icepack blinky.asc blinky.bin

prog: blinky.bin
	iceprog blinky.bin

clean:
	rm -f blinky.json blinky.asc blinky.bin
