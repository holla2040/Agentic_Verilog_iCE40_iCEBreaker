all: pwm_breathe.bin

pwm_breathe.json: pwm_breathe.v
	yosys -p "synth_ice40 -top pwm_breathe -json pwm_breathe.json" pwm_breathe.v

pwm_breathe.asc: pwm_breathe.json icebreaker.pcf
	nextpnr-ice40 --up5k --package sg48 --json pwm_breathe.json --pcf icebreaker.pcf --asc pwm_breathe.asc

pwm_breathe.bin: pwm_breathe.asc
	icepack pwm_breathe.asc pwm_breathe.bin

prog: pwm_breathe.bin
	iceprog pwm_breathe.bin

clean:
	rm -f pwm_breathe.json pwm_breathe.asc pwm_breathe.bin
