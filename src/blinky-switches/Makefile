all: blinky_switches.bin

blinky_switches.json: blinky_switches.v
	yosys -p "synth_ice40 -top blinky_switches -json blinky_switches.json" blinky_switches.v

blinky_switches.asc: blinky_switches.json icebreaker.pcf
	nextpnr-ice40 --up5k --package sg48 --json blinky_switches.json --pcf icebreaker.pcf --asc blinky_switches.asc

blinky_switches.bin: blinky_switches.asc
	icepack blinky_switches.asc blinky_switches.bin

prog: blinky_switches.bin
	iceprog blinky_switches.bin

clean:
	rm -f blinky_switches.json blinky_switches.asc blinky_switches.bin
