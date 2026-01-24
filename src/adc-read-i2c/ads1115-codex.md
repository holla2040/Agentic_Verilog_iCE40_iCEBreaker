# ADS1115 I2C ADC Reader Review (Codex)

## Scope

Review of `src/adc-read-i2c` focused on technical implementation and documentation quality.

## Findings (ordered by severity)

- Medium: I2C address is fixed at 0x48 in logic; pressing the address button (ADDR high -> 0x49) will NACK, but this behavior is not called out in docs. (`src/adc-read-i2c/top.v:50`, `src/adc-read-i2c/top.v:69`, `src/adc-read-i2c/README.md:18`)
- Medium: Config value in comments/docs is 0x96D5, while the implementation writes 0xC2C3. This inconsistency can cause misconfiguration or mistaken edits. (`src/adc-read-i2c/top.v:16`, `src/adc-read-i2c/top.v:77`, `src/adc-read-i2c/PLAN.md:62`)
- Low: Startup banner promises "\r\nads1115\r\n" but the buffer omits the trailing carriage return; strict CRLF consumers may misparse. (`src/adc-read-i2c/top.v:8`, `src/adc-read-i2c/top.v:176`)
- Low: README voltage range and examples imply 0-4V and negative codes; actual single-ended 3.3V input should be 0-3.3V and non-negative codes only. (`src/adc-read-i2c/README.md:32`, `src/adc-read-i2c/README.md:56`)
- Low: `ADC-READ-I2C.prd` is an agent instruction log rather than a spec; it is noisy for users and can be confusing. (`src/adc-read-i2c/ADC-READ-I2C.prd:1`)
- Low: No simulation or hardware verification checklist in-repo, so regressions are hardware-only to detect.

## Technical Implementation Review

- Top-level flow: `top.v` sequences I2C configuration, conversion pointer set, and periodic reads, then formats UART output. The FSM is linear and clear, with an explicit error state that outputs `E` on NACK. (`src/adc-read-i2c/top.v:125`)
- I2C master: `i2c_master.v` implements command-based START/STOP/WRITE/READ with open-drain SB_IO primitives and a 100 kHz timing model derived from 12 MHz. The ACK sampling is at the end of the SCL high period, matching standard practice. (`src/adc-read-i2c/i2c_master.v:30`, `src/adc-read-i2c/i2c_master.v:308`)
- Open-drain correctness: SDA and SCL are never driven high; `OUTPUT_ENABLE` is used to pull low or release the line, matching iCE40 SB_IO guidance. (`src/adc-read-i2c/i2c_master.v:88`)
- UART: `uart_tx.v` is a straightforward 8N1 transmitter at 115200 baud (12 MHz / 104). The top-level message formatting is clear, with a hex nibble helper. (`src/adc-read-i2c/uart_tx.v:1`, `src/adc-read-i2c/top.v:158`)
- Timing: 200 ms interval for 5 Hz sampling is derived correctly from the 12 MHz clock. (`src/adc-read-i2c/top.v:56`)
- Address control: the ADDR pin is wired to the button, but the I2C address used is static. This matches a "force NACK" debug use case but contradicts the initial plan intent of dynamic address selection. (`src/adc-read-i2c/top.v:50`, `src/adc-read-i2c/PLAN.md:130`)

## Documentation Review

- README gives a clean overview, wiring, build steps, and a high-level architecture diagram, which helps onboarding. (`src/adc-read-i2c/README.md:5`)
- README and plan include clear I2C sequences and emphasize the SB_IO open-drain requirement, which is critical for iCE40. (`src/adc-read-i2c/README.md:103`, `src/adc-read-i2c/PLAN.md:72`)
- Key inconsistencies exist: configuration value mismatch and voltage range mismatch (see Findings), which should be corrected to avoid confusion.
- Plan is detailed but includes instructions that are now outdated (e.g., config value, step boundaries). If this is intended as historical record, it should be labeled as such; otherwise, it should be updated to match the final design.

## Gaps / Risks

- No testbench or I2C waveform validation. A basic simulation stub or a checklist (logic analyzer capture expectations) would reduce integration risk.
- Error handling is limited to emitting `E`; no recovery path or retry strategy is documented.

## Suggestions

- Align all docs/comments to the actual configuration value and input range.
- Clarify the intended use of the address button (dynamic address select vs. forced NACK test).
- Add a short verification checklist (expected UART lines, I2C waveforms, address toggle behavior) to the README.

## Summary

The implementation is clean, modular, and uses correct open-drain I2C techniques with a simple, command-driven interface. The largest issues are documentation mismatches and the unadvertised fixed I2C address, which can confuse users during bring-up. Addressing those and adding minimal verification guidance would make the project robust for new users.
