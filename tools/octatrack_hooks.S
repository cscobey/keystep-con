@ Minimal Octatrack mode only: row arrows select MIDI channels while Track is held;
@ Shift+Octave changes the channel bank; Octave Down at the lowest range adds C0-B0.
.equ STOCK_PRESS,   0x080500d8
.equ STOCK_RELEASE, 0x0804e700
.equ STOCK_KEY_REC, 0x080108a4
.equ GLOBAL_SET,    0x0800e694
.equ LED_FLUSH,     0x08054c2c
.equ LED_SET,       0x08053eb8
.equ UI_UPDATE,     0x0801f96c
.equ POPUP,         0x08025274
.equ ID_SHIFT,      1
.equ ID_OCT_DOWN,   5
.equ ID_OCT_UP,     6
.equ ID_PATTERN_DOWN,0x12
.equ ID_TRACK,      0x17
.equ OT_MODE_ID,    118
.equ OT_CHAN_BASE,  75
.equ OT_DRUM_CHAN,  79
.equ GLOBALS,       0x20000874
.equ SEL_TRACK,     0x200001a4
.equ SEQ_PTR,       0x20001498
.equ CUR_PROJECT,   0x20004dad
.equ BUTTONS_PTR,   0x200014b8
.equ HAL_TICK,      0x20006218
.equ UI_PTR,        0x20001510
.equ POPUP_CTX,     0x200017f8
.equ POPUP_GATE,    0x200014d7
.equ POPUP_TABLE,   0x08020e4e
.equ TEXT,          0xc01eff00
.equ PAD_STATE,     0xc01ef800
.equ PAD_MAGIC,     0x3831464f      @ OF18 resets earlier transient state
.equ ST_LOW,        4               @ 4 lower-octave flags, one per track
.equ ST_BANK,       8               @ channel bank 0-3
.equ ST_SHIFT,      9
.equ ST_SW,         10              @ intercepted button whose release is swallowed
.equ ST_LAST,       12              @ last Track-held channel popup tick

.syntax unified
.thumb
.macro call_abs target
    ldr     r12, =((\target) + 1)
    blx     r12
.endm

.text
.balign 4
.type ot_state,%function
ot_state:
    ldr     r7, =PAD_STATE
    ldr     r0, [r7]
    ldr     r1, =PAD_MAGIC
    cmp     r0, r1
    beq     1f
    movs    r0, #0
    str     r0, [r7, #ST_LOW]
    strb    r0, [r7, #ST_BANK]
    strb    r0, [r7, #ST_SHIFT]
    strb    r0, [r7, #ST_SW]
    str     r0, [r7, #ST_LAST]
    str     r1, [r7]
1:  bx      lr
.size ot_state, .-ot_state

@ r0 = button object, r1 = ID; true if button is down
.type ot_held,%function
ot_held:
    add     r1, r1, r1, lsl #1
    add     r0, r0, r1
    ldrb    r0, [r0, #0x6e]
    eor     r0, r0, #1
    bx      lr
.size ot_held, .-ot_held

@ r0 = channel (1-16): show a brief popup in the same place as the stock bass popup.
.type ot_channel_popup,%function
ot_channel_popup:
    push    {r4-r7, lr}
    sub     sp, #4
    mov     r4, r0
    ldr     r5, =UI_PTR
    ldr     r5, [r5]
    ldrb    r0, [r5, #0xc]
    cmp     r0, #0x60
    bhi     9f
    ldr     r6, =POPUP_TABLE
    ldrb    r0, [r6, r0]
    cmp     r0, #0xa9
    beq     9f
    cmp     r0, #0x6c
    bne     1f
    ldr     r6, =POPUP_GATE
    ldrb    r0, [r6]
    cbnz    r0, 9f
1:  ldr     r6, =TEXT
    movs    r0, #77              @ MIDI CH
    strb    r0, [r6]
    movs    r0, #73
    strb    r0, [r6, #1]
    movs    r0, #68
    strb    r0, [r6, #2]
    movs    r0, #73
    strb    r0, [r6, #3]
    movs    r0, #32
    strb    r0, [r6, #4]
    movs    r0, #67
    strb    r0, [r6, #5]
    movs    r0, #72
    strb    r0, [r6, #6]
    movs    r0, #32
    strb    r0, [r6, #7]
    movs    r1, #10
    udiv    r2, r4, r1
    mls     r0, r2, r1, r4
    adds    r2, #48
    adds    r0, #48
    strb    r2, [r6, #8]
    strb    r0, [r6, #9]
    movs    r0, #0
    strb    r0, [r6, #10]
    mov     r0, r5
    movs    r1, #3
    call_abs UI_UPDATE
    mov     r0, r5
    movs    r1, #4
    call_abs UI_UPDATE
    mov     r0, r5
    movs    r1, #5
    call_abs UI_UPDATE
    mov     r0, r5
    movs    r1, #0x50
    call_abs UI_UPDATE
    ldr     r0, =POPUP_CTX
    ldr     r0, [r0]
    mov     r1, r6
    movw    r2, #1000
    call_abs POPUP
    movs    r0, #0xf
    strb    r0, [r5, #0xc]
9:  add     sp, #4
    pop     {r4-r7, pc}
.size ot_channel_popup, .-ot_channel_popup

.global pad_press
.type pad_press,%function
pad_press:
    push    {r3-r11, lr}
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2
    bl      ot_state
    ldr     r0, =GLOBALS
    ldrb    r0, [r0, #4 + OT_MODE_ID]
    cmp     r0, #1
    bne     press_stock

    cmp     r5, #ID_SHIFT
    bne     1f
    movs    r0, #1
    strb    r0, [r7, #ST_SHIFT]
    b       press_stock
1:  ldrb    r0, [r7, #ST_SHIFT]
    cbz     r0, 4f
    cmp     r5, #ID_OCT_DOWN
    beq     2f
    cmp     r5, #ID_OCT_UP
    bne     4f
    ldrb    r8, [r7, #ST_BANK]
    adds    r8, #1
    and     r8, r8, #3
    b       3f
2:  ldrb    r8, [r7, #ST_BANK]
    subs    r8, #1
    and     r8, r8, #3
3:  strb    r8, [r7, #ST_BANK]
    movs    r9, #0
5:  ldr     r0, =GLOBALS
    add     r0, r0, r9
    add     r0, #4 + OT_CHAN_BASE
    ldrb    r10, [r0]
    and     r10, r10, #3
    orr     r10, r10, r8, lsl #2
    mov     r2, r10
    movs    r1, #OT_CHAN_BASE
    adds    r1, r9
    movs    r3, #1
    ldr     r0, =GLOBALS
    call_abs GLOBAL_SET
    cmp     r9, #0
    bne     6f
    ldr     r0, =GLOBALS
    movs    r1, #OT_DRUM_CHAN
    mov     r2, r10
    movs    r3, #1
    call_abs GLOBAL_SET
6:  adds    r9, #1
    cmp     r9, #4
    blo     5b
    strb    r5, [r7, #ST_SW]
    b       press_done

4:  @ Track buttons still select their track; show that track's current MIDI channel.
    movs    r8, #0
10: movs    r0, #6
    mul     r0, r8, r0
    adds    r0, #ID_TRACK
    cmp     r5, r0
    beq     11f
    adds    r8, #1
    cmp     r8, #4
    blo     10b
    b       13f
11: mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    call_abs STOCK_PRESS
    ldr     r0, =GLOBALS
    add     r0, r0, r8
    add     r0, #4 + OT_CHAN_BASE
    ldrb    r0, [r0]
    adds    r0, #1
    ldr     r1, =HAL_TICK
    ldr     r1, [r1]
    str     r1, [r7, #ST_LAST]
    bl      ot_channel_popup
    b       press_done

13: @ Handle row Pattern +/- only when that row's Track button is held.
    movs    r8, #0
12: movs    r0, #6
    mul     r0, r8, r0
    adds    r0, #ID_PATTERN_DOWN
    cmp     r5, r0
    beq     14f
    adds    r0, #1
    cmp     r5, r0
    beq     15f
    adds    r8, #1
    cmp     r8, #4
    blo     12b
    b       20f
14: movs    r9, #0               @ Pattern down = previous MIDI channel
    b       16f
15: movs    r9, #1               @ Pattern up = next MIDI channel
16: mov     r0, r4
    movs    r1, #6
    mul     r1, r8, r1
    adds    r1, #ID_TRACK
    bl      ot_held
    cbz     r0, 20f
    ldr     r0, =GLOBALS
    add     r0, r0, r8
    add     r0, #4 + OT_CHAN_BASE
    ldrb    r10, [r0]
    and     r10, r10, #3
    cmp     r9, #0
    beq     17f
    adds    r10, #1
    b       18f
17: subs    r10, #1
18: and     r10, r10, #3
    ldrb    r0, [r7, #ST_BANK]
    orr     r10, r10, r0, lsl #2
    movs    r1, #OT_CHAN_BASE
    adds    r1, r8
    ldr     r0, =GLOBALS
    mov     r2, r10
    movs    r3, #1
    call_abs GLOBAL_SET
    cmp     r8, #0
    bne     19f
    ldr     r0, =GLOBALS
    movs    r1, #OT_DRUM_CHAN
    mov     r2, r10
    movs    r3, #1
    call_abs GLOBAL_SET
19: strb    r5, [r7, #ST_SW]
    ldr     r0, =HAL_TICK
    ldr     r0, [r0]
    str     r0, [r7, #ST_LAST]
    adds    r0, r10, #1
    bl      ot_channel_popup
    b       press_done

20: @ Extra octave below C1 only at the lowest stock octave.
    cmp     r5, #ID_OCT_UP
    bne     21f
    ldr     r0, =SEL_TRACK
    ldrb    r8, [r0]
    cmp     r8, #4
    it      eq
    moveq   r8, #0
    add     r0, r7, r8
    ldrb    r0, [r0, #ST_LOW]
    cbz     r0, press_stock
    add     r0, r7, r8
    movs    r1, #0
    strb    r1, [r0, #ST_LOW]
    strb    r5, [r7, #ST_SW]
    b       press_done
21: cmp     r5, #ID_OCT_DOWN
    bne     press_stock
    ldr     r0, =SEQ_PTR
    ldr     r0, [r0]
    ldr     r1, =CUR_PROJECT
    ldrb    r1, [r1]
    movw    r2, #0x0fec
    mla     r0, r1, r2, r0
    ldr     r1, =SEL_TRACK
    ldrb    r8, [r1]
    cmp     r8, #4
    it      eq
    moveq   r8, #0
    movs    r2, #0x16
    mla     r0, r8, r2, r0
    movw    r2, #0x1752
    add     r0, r0, r2
    ldrb    r0, [r0]
    and     r0, r0, #7
    cmp     r0, #0
    bne     press_stock
    add     r0, r7, r8
    movs    r1, #1
    strb    r1, [r0, #ST_LOW]
    strb    r5, [r7, #ST_SW]
press_done:
    pop     {r3-r11, pc}
press_stock:
    mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    pop     {r3-r11, lr}
    ldr     r12, =(STOCK_PRESS + 1)
    bx      r12
.size pad_press, .-pad_press

.global pad_release
.type pad_release,%function
pad_release:
    push    {r3-r11, lr}
    mov     r4, r0
    mov     r5, r1
    bl      ot_state
    cmp     r5, #ID_SHIFT
    bne     1f
    movs    r0, #0
    strb    r0, [r7, #ST_SHIFT]
1:  ldrb    r0, [r7, #ST_SW]
    cmp     r0, r5
    bne     release_stock
    movs    r0, #0
    strb    r0, [r7, #ST_SW]
    pop     {r3-r11, pc}
release_stock:
    mov     r0, r4
    mov     r1, r5
    pop     {r3-r11, lr}
    ldr     r12, =(STOCK_RELEASE + 1)
    bx      r12
.size pad_release, .-pad_release

.global key_rec
.type key_rec,%function
key_rec:
    push    {r0-r3}
    ldr     r0, =GLOBALS
    ldrb    r0, [r0, #4 + OT_MODE_ID]
    cmp     r0, #1
    bne     1f
    ldr     r0, =PAD_STATE
    ldr     r1, [r0]
    ldr     r2, =PAD_MAGIC
    cmp     r1, r2
    bne     1f
    ldr     r2, [sp, #12]
    ldrb    r2, [r2]
    add     r0, r0, r2
    ldrb    r0, [r0, #ST_LOW]
    cbz     r0, 1f
    ldr     r1, [sp, #4]
    ldrb    r2, [r1]
    cmp     r2, #12
    blo     1f
    subs    r2, #12
    strb    r2, [r1]
1:  pop     {r0-r3}
    ldr     r12, =(STOCK_KEY_REC + 1)
    bx      r12
.size key_rec, .-key_rec

.global led_flush
.type led_flush,%function
led_flush:
    push    {r4-r8, lr}
    mov     r4, r0
    bl      ot_state
    ldr     r0, =GLOBALS
    ldrb    r0, [r0, #4 + OT_MODE_ID]
    cmp     r0, #1
    bne     flush_stock
    ldr     r0, =BUTTONS_PTR
    ldr     r5, [r0]
    movs    r8, #0
22: movs    r0, #6
    mul     r0, r8, r0
    adds    r1, r0, #ID_TRACK
    mov     r0, r5
    bl      ot_held
    cbz     r0, 23f
    ldr     r0, =HAL_TICK
    ldr     r6, [r0]
    ldr     r0, [r7, #ST_LAST]
    subs    r0, r6, r0
    movw    r1, #7000
    cmp     r0, r1
    blo     flush_stock
    str     r6, [r7, #ST_LAST]
    ldr     r0, =GLOBALS
    add     r0, r0, r8
    add     r0, #4 + OT_CHAN_BASE
    ldrb    r0, [r0]
    adds    r0, #1
    bl      ot_channel_popup
    b       flush_stock
23: adds    r8, #1
    cmp     r8, #4
    blo     22b
flush_stock:
    mov     r0, r4
    pop     {r4-r8, lr}
    ldr     r12, =(LED_FLUSH + 1)
    bx      r12
.size led_flush, .-led_flush
.ltorg
