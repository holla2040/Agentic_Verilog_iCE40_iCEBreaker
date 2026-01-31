# UART TX - How It Works

## State Machine

```mermaid
stateDiagram-v2
    [*] --> IDLE

    IDLE --> START : start_i pulse
    START --> DATA : after 1 bit period
    DATA --> DATA : bits 0-6
    DATA --> STOP : after bit 7
    STOP --> IDLE : after 1 bit period

    note right of IDLE
        tx_o = HIGH (idle)
        ready_o = HIGH
    end note

    note right of START
        tx_o = LOW (start bit)
        ready_o = LOW
    end note

    note right of DATA
        tx_o = data bit (LSB first)
        ready_o = LOW
    end note

    note right of STOP
        tx_o = HIGH (stop bit)
        ready_o = LOW
    end note
```

## UART Frame Format

```mermaid
gantt
    title UART 8N1 Frame (115200 baud = ~8.68µs per bit)
    dateFormat X
    axisFormat %s

    section TX Line
    IDLE (HIGH)     :done, 0, 1
    START BIT (LOW) :active, 1, 2
    D0 (LSB)        :3, 3
    D1              :3, 4
    D2              :4, 5
    D3              :5, 6
    D4              :6, 7
    D5              :7, 8
    D6              :8, 9
    D7 (MSB)        :9, 10
    STOP BIT (HIGH) :done, 10, 11
    IDLE (HIGH)     :done, 11, 12
```

## Timing Diagram

```
                    1 bit period = 104 clocks @ 12MHz
                    |<--------->|

    IDLE    START      D0   D1   D2   D3   D4   D5   D6   D7   STOP   IDLE
            ┌────┐
    tx_o ───┘    └────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬───────
            LOW       │    │    │    │    │    │    │    │HIGH│
                     LSB ─────────────────────────────> MSB

    ready_o ──┐                                                  ┌─────────
              └──────────────────────────────────────────────────┘

    start_i ──┐
              └┐ (single clock pulse)
               └──────────────────────────────────────────────────────────
```

## Signal Flow

```mermaid
flowchart LR
    subgraph Inputs
        clk_i[clk_i<br/>12 MHz]
        rst_i[rst_i<br/>reset]
        data_i[data_i<br/>8 bits]
        start_i[start_i<br/>trigger]
    end

    subgraph UART_TX[uart_tx module]
        direction TB
        SM[State Machine<br/>IDLE→START→DATA→STOP]
        BC[Baud Counter<br/>0 to 103]
        BI[Bit Index<br/>0 to 7]
        SR[Shift Register<br/>tx_byte]
    end

    subgraph Outputs
        ready_o[ready_o<br/>HIGH=idle]
        tx_o[tx_o<br/>serial out]
    end

    clk_i --> SM
    rst_i --> SM
    data_i --> SR
    start_i --> SM
    SM --> ready_o
    SR --> tx_o
```

## How to Send a Byte

```mermaid
sequenceDiagram
    participant User
    participant UART_TX
    participant TX_Pin

    User->>UART_TX: Check ready_o
    UART_TX-->>User: ready_o = 1 (idle)

    User->>UART_TX: Set data_i = 0x55
    User->>UART_TX: Pulse start_i

    UART_TX-->>User: ready_o = 0 (busy)

    UART_TX->>TX_Pin: START bit (LOW)
    Note over TX_Pin: 104 clocks

    loop 8 data bits (LSB first)
        UART_TX->>TX_Pin: Data bit
        Note over TX_Pin: 104 clocks each
    end

    UART_TX->>TX_Pin: STOP bit (HIGH)
    Note over TX_Pin: 104 clocks

    UART_TX-->>User: ready_o = 1 (done!)
```

## Example: Sending 0x55 (binary 01010101)

```
Byte: 0x55 = 0b01010101

Transmitted LSB first:
  D0=1, D1=0, D2=1, D3=0, D4=1, D5=0, D6=1, D7=0

TX Line:
         START  D0   D1   D2   D3   D4   D5   D6   D7  STOP
    HIGH ─┐     ┌───┐    ┌───┐    ┌───┐    ┌───┐    ┌──────
          └─────┘   └────┘   └────┘   └────┘   └────┘
         LOW   1    0    1    0    1    0    1    0   HIGH
```

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLOCKS_PER_BIT` | 104 | Clock cycles per bit period |

**Baud rate calculation:**
```
CLOCKS_PER_BIT = System_Clock / Baud_Rate
104 = 12,000,000 / 115,200
```

**Common values @ 12 MHz:**
| Baud Rate | CLOCKS_PER_BIT |
|-----------|----------------|
| 9600 | 1250 |
| 19200 | 625 |
| 38400 | 313 |
| 57600 | 208 |
| 115200 | 104 |
