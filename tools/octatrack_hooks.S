@ Minimal Octatrack mode only: channel banks from Pattern+steps and one extra low octave.
.equ STOCK_PRESS,   0x080500d8
.equ STOCK_RELEASE, 0x0804e700
.equ STOCK_KEY_REC, 0x080108a4
.equ GLOBAL_SET,    0x0800e694
.equ LED_FLUSH,     0x08054c2c
.equ LED_SET,       0x08053eb8
.equ ID_SHIFT,      1
.equ ID_PATTERN,    7
.equ ID_OCT_DOWN,   5
.equ ID_OCT_UP,     6
.equ ID_STEP1,      0x2e
.equ OT_MODE_ID,    118
.equ OT_CHAN_BASE,  75
.equ OT_DRUM_CHAN,  79
.equ GLOBALS,       0x20000874
.equ SEL_TRACK,     0x200001a4
.equ SEQ_PTR,       0x20001498
.equ CUR_PROJECT,   0x20004dad
.equ HAL_TICK,      0x20006218
.equ PAD_STATE,     0xc01ef800
.equ PAD_MAGIC,     0x3731464f      @ OF17: reset the minimal-mode state
.equ ST_LOW,        4               @ per-track lower-octave flags (tracks 1-4)
.equ ST_BANK,       8               @ channel bank 0-3
.equ ST_SHIFT,      9
.equ ST_SW,         10              @ intercepted button whose release is also swallowed

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
    mov     r0, r10
    movs    r1, #OT_CHAN_BASE
    adds    r1, r9
    movs    r2, #1
    mov     r3, r2
    mov     r2, r0
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

4:  @ Pattern + first four steps picks channel 1-4 in the active bank.
    subs    r0, r5, #ID_STEP1
    cmp     r0, #3
    bhi     7f
    mov     r9, r0
    mov     r0, r4
    movs    r1, #ID_PATTERN
    bl      ot_held
    cbz     r0, 7f
    ldr     r0, =SEL_TRACK
    ldrb    r8, [r0]
    movs    r11, #0
    cmp     r8, #4
    bne     8f
    movs    r8, #0
    movs    r11, #1
8:  cmp     r8, #3
    bhi     7f
    ldrb    r10, [r7, #ST_BANK]
    lsls    r10, r10, #2
    adds    r10, r9
    movs    r1, #OT_CHAN_BASE
    adds    r1, r8
    cmp     r11, #0
    beq     9f
    movs    r1, #OT_DRUM_CHAN
9:  ldr     r0, =GLOBALS
    mov     r2, r10
    movs    r3, #1
    call_abs GLOBAL_SET
    strb    r5, [r7, #ST_SW]
    b       press_done

7:  cmp     r5, #ID_OCT_UP
    bne     10f
    ldr     r0, =SEL_TRACK
    ldrb    r8, [r0]
    cmp     r8, #4
    it      eq
    moveq   r8, #0
    add     r0, r7, r8
    ldrb    r0, [r0, #ST_LOW]
    cbz     r0, 10f
    add     r0, r7, r8
    movs    r1, #0
    strb    r1, [r0, #ST_LOW]
    strb    r5, [r7, #ST_SW]
    b       press_done
10: cmp     r5, #ID_OCT_DOWN
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
    push    {r4-r6, lr}
    mov     r4, r0
    ldr     r5, =PAD_STATE
    ldr     r0, [r5]
    ldr     r1, =PAD_MAGIC
    cmp     r0, r1
    bne     1f
    ldr     r0, =GLOBALS
    ldrb    r0, [r0, #4 + OT_MODE_ID]
    cmp     r0, #1
    bne     1f
    ldr     r0, =SEL_TRACK
    ldrb    r6, [r0]
    cmp     r6, #4
    it      eq
    moveq   r6, #0
    cmp     r6, #3
    bhi     1f
    add     r0, r5, r6
    ldrb    r0, [r0, #ST_LOW]
    cbz     r0, 1f
    ldr     r0, =HAL_TICK
    ldr     r2, [r0]
    lsrs    r2, r2, #12
    and     r2, r2, #1
    movs    r1, #5
    movs    r3, #8
    sub     sp, #8
    movs    r0, #0
    str     r0, [sp]
    str     r0, [sp, #4]
    mov     r0, r4
    call_abs LED_SET
    add     sp, #8
1:  mov     r0, r4
    pop     {r4-r6, lr}
    ldr     r12, =(LED_FLUSH + 1)
    bx      r12
.size led_flush, .-led_flush
.ltorg
