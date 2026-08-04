.setcpu "65C02"

.include "lynx.inc"

.import _set_irq
.import _get_irq

.export _run_tests
.export _g_results

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 18

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Wait for vertical blank
;===================================================================
.proc WaitVBlank
    ; 1) If already at 0, wait until it reloads
@wait_not0:
    lda TIM2CNT
    beq @wait_not0      ; if at 0, wait until it reloads

    ; 2) Wait for counter to reach 0 (counts down)
@wait_0:
    lda TIM2CNT
    bne @wait_0         ; wait until it reaches 0

    ; 3) Wait for reload (0 -> non-zero = actual VBlank start)
@wait_reload:
    lda TIM2CNT
    beq @wait_reload    ; wait until it reloads to high value
    rts
.endproc

;===================================================================
; Reset Math registers to known state
;===================================================================
.proc ResetMath
    lda #$04
    sta SPRSYS
    stz MATHM
    rts
.endproc

;===================================================================
; Test 1: Basic multiplication test
; AB * CD = EFGH
; 00002 * 00FF = 000001FE
;===================================================================
.proc Test1
    jsr ResetMath

    lda #$FF
    sta $FC12           ; MATHD mirror, MATHC = $00
    lda #$02
    sta $FC14           ; MATHB mirror, MATHA = $00

    lda #$00
    sta MATHA           ; Start multiplication

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting EFGH = $000001FE
    ldx #$00
    lda $FC23           ; MATHE mirror
    cmp #$00
    bne @fail

    ldx #$01
    lda $FC22           ; MATHF mirror
    cmp #$00
    bne @fail

    ldx #$02
    lda $FC21           ; MATHG mirror
    cmp #$01
    bne @fail

    ldx #$03
    lda $FC20           ; MATHH mirror
    cmp #$FE
    bne @fail

    ldx #$04
    lda SPRSYS
    and #$64
    cmp #$04            ; No overflow expected, unsafe is always set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 0  ; $FF indicates success
    stz _g_results + 1
    rts

@fail:
    sta _g_results + 1  ; read value
    txa
    sta _g_results + 0  ; failing stage
    rts
.endproc

;===================================================================
; Test 2: Accumulator + overflow multiplication test
; Accumulator: JKLM
; AB * CD = EFGH
; 0010 * 0010 = 00000100
; FFFFFFF0 + 00000100 = 000000F0 (with overflow)
;===================================================================
.proc Test2
    jsr ResetMath

    ; JKLM = $FFFFFFF0
    lda #$FF
    sta $FC2E           ; MATHK mirror, MATHJ = $00
    lda #$FF
    sta $FC2F           ; MATHJ mirror
    lda #$F0
    sta $FC2C           ; MATHM mirror, MATHL = $00 and clears overflow
    lda #$FF
    sta $FC2D

    lda #$40
    sta SPRSYS          ; Accumulate on

    ; AB = $0010, CD = $0010
    lda #$10
    sta $FC12           ; MATHD mirror, MATHC = $00
    lda #$10
    sta $FC14           ; MATHB mirror, MATHA = $00

    lda #$00
    sta MATHA           ; Start multiplication

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting EFGH = $00000100
    ldx #$00
    lda $FC23           ; MATHE mirror
    cmp #$00
    bne @fail

    ldx #$01
    lda $FC22           ; MATHF mirror
    cmp #$00
    bne @fail

    ldx #$02
    lda $FC21           ; MATHG mirror
    cmp #$01
    bne @fail

    ldx #$03
    lda $FC20           ; MATHH mirror
    cmp #$00
    bne @fail

    ; Expecting JKLM = $000000F0
    ldx #$04
    lda $FC2F           ; MATHJ mirror
    cmp #$00
    bne @fail

    ldx #$05
    lda $FC2E           ; MATHK mirror
    cmp #$00
    bne @fail

    ldx #$06
    lda $FC2D           ; MATHL mirror
    cmp #$00
    bne @fail

    ldx #$07
    lda $FC2C           ; MATHM mirror
    cmp #$F0
    bne @fail

    ldx #$08
    lda SPRSYS
    and #$64
    cmp #$64            ; Overflow expected, unsafe and last carry set
    bne @fail

    ldx #$09
    stz MATHM           ; Clear overflow
    lda SPRSYS
    and #$64
    cmp #$24            ; No overflow now, unsafe and last carry set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 2  ; $FF indicates success
    stz _g_results + 3
    rts

@fail:
    sta _g_results + 3  ; read value
    txa
    sta _g_results + 2  ; failing stage
    rts
.endproc

;===================================================================
; Test 3: Signed multiplication test
; Part 1: FFFD * 0005 = FFFFFFF1 (-3 * 5 = -15)
; Part 2: Verify writing MATHD does NOT trigger signCD.
;         After part 1, math_sign_C = true (CD was negative).
;         Writing only MATHD (not MATHC) should preserve stale sign.
;         0003 * 0005 with stale sign = FFFFFFF1 (-(3*5))
;===================================================================
.proc Test3
    jsr ResetMath

    lda #$80
    sta SPRSYS          ; Signed multiply

    lda #$FD
    sta $FC12           ; MATHD mirror
    lda #$FF
    sta $FC13           ; MATHC mirror
    lda #$05
    sta $FC14           ; MATHB mirror
    lda #$00
    sta MATHA           ; Start multiplication

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting EFGH = $FFFFFFF1
    ldx #$00
    lda $FC23           ; MATHE mirror
    cmp #$FF
    bne @fail

    ldx #$01
    lda $FC22           ; MATHF mirror
    cmp #$FF
    bne @fail

    ldx #$02
    lda $FC21           ; MATHG mirror
    cmp #$FF
    bne @fail

    ldx #$03
    lda $FC20           ; MATHH mirror
    cmp #$F1
    bne @fail

    ldx #$04
    lda SPRSYS
    and #$64
    cmp #$24            ; No overflow expected, unsafe and last carry set
    bne @fail

    ; --- Part 2: MATHD write must NOT trigger signCD ---
    ; math_sign_C is true from the FFFD multiply above.
    ; Write only MATHD (zeros MATHC). If signCD fires, sign resets to false.

    lda #$05
    sta $FC12           ; MATHD mirror, CD = $0005 (MATHC zeroed). Should NOT run signCD.

    lda #$03
    sta $FC14           ; MATHB mirror, AB low = $03 (MATHA zeroed)

    lda #$00
    sta MATHA           ; Start signed multiply (AB = $0003)

@wait_done2:
    lda SPRSYS
    and #$80
    bne @wait_done2

    ; Expecting EFGH = $FFFFFFF1 (stale math_sign_C = true)
    ; Bug would give $0000000F (signCD reset math_sign_C to false)
    ldx #$05
    lda $FC23           ; MATHE mirror
    cmp #$FF
    bne @fail

    ldx #$06
    lda $FC22           ; MATHF mirror
    cmp #$FF
    bne @fail

    ldx #$07
    lda $FC21           ; MATHG mirror
    cmp #$FF
    bne @fail

    ldx #$08
    lda $FC20           ; MATHH mirror
    cmp #$F1
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 4  ; $FF indicates success
    stz _g_results + 5
    rts

@fail:
    sta _g_results + 5  ; read value
    txa
    sta _g_results + 4  ; failing stage
    rts
.endproc

;===================================================================
; Test 4: $8000 multiplication bug
; AB * CD = EFGH
; 8000 * 0002 = 00010000 (should be -65536, math bug gives +65536)
;===================================================================
.proc Test4
    jsr ResetMath

    lda #$80
    sta SPRSYS          ; Signed multiply

    lda #$00
    sta $FC12           ; MATHD mirror
    lda #$80
    sta $FC13           ; MATHC mirror
    lda #$02
    sta $FC14           ; MATHB mirror
    lda #$00
    sta MATHA           ; Start multiplication

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting EFGH = $00010000
    ldx #$00
    lda $FC23           ; MATHE mirror
    cmp #$00
    bne @fail

    ldx #$01
    lda $FC22           ; MATHF mirror
    cmp #$01
    bne @fail

    ldx #$02
    lda $FC21           ; MATHG mirror
    cmp #$00
    bne @fail

    ldx #$03
    lda $FC20           ; MATHH mirror
    cmp #$00
    bne @fail

    ldx #$04
    lda SPRSYS
    and #$64
    cmp #$04            ; unsafe is always set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 6  ; $FF indicates success
    stz _g_results + 7
    rts

@fail:
    sta _g_results + 7  ; read value
    txa
    sta _g_results + 6  ; failing stage
    rts
.endproc

;===================================================================
; Test 5: Simple division test
; EFGH / NP = ABCD, remainder (JK)LM
; 00010000 / 000A = 00001999, remainder 0006 (broken in hardware)
;===================================================================
.proc Test5
    jsr ResetMath

    lda #$0A
    sta $FC16           ; MATHP mirror
    lda #$00
    sta $FC17           ; MATHN mirror

    lda #$01
    sta $FC22           ; MATHF mirror
    lda #$00
    sta $FC21           ; MATHG mirror
    lda #$00
    sta $FC20           ; MATHH mirror
    lda #$00
    sta MATHE           ; Start division

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting ABCD = $00001999
    ldx #$00
    lda $FC15           ; MATHA mirror
    cmp #$00
    bne @fail

    ldx #$01
    lda $FC14           ; MATHB mirror
    cmp #$00
    bne @fail

    ldx #$02
    lda $FC13           ; MATHC mirror
    cmp #$19
    bne @fail

    ldx #$03
    lda $FC12           ; MATHD mirror
    cmp #$99
    bne @fail

    ; Expecting (JK)LM = $0006
    ldx #$04
    lda $FC2F           ; MATHJ mirror
    cmp #$00
    bne @fail

    ldx #$05
    lda $FC2E           ; MATHK mirror
    cmp #$00
    bne @fail

    ldx #$06
    lda $FC2D           ; MATHL mirror
    cmp #$00
    bne @fail

    ldx #$07
    lda $FC2C           ; MATHM mirror
    cmp #$06
    ;bne @fail

    ldx #$08
    lda SPRSYS
    and #$64
    cmp #$24            ; No overflow expected, last carry set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 8  ; $FF indicates success
    stz _g_results + 9
    rts

@fail:
    sta _g_results + 9  ; read value
    txa
    sta _g_results + 8  ; failing stage
    rts
.endproc

;===================================================================
; Test 6: Simple division with no remainder
; EFGH / NP = ABCD, remainder (JK)LM
; 0000FFFF / 00FF = 00000101, remainder 0000 (broken in hardware)
;===================================================================
.proc Test6
    jsr ResetMath

    lda #$FF
    sta $FC16           ; MATHP mirror
    lda #$00
    sta $FC17           ; MATHN mirror

    lda #$FF
    sta $FC20           ; MATHH mirror
    lda #$FF
    sta $FC21           ; MATHG mirror
    lda #$00
    sta $FC22           ; MATHF mirror
    lda #$00
    sta MATHE           ; Start division

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting ABCD = $00000101
    ldx #$00
    lda $FC15           ; MATHA mirror
    cmp #$00
    bne @fail

    ldx #$01
    lda $FC14           ; MATHB mirror
    cmp #$00
    bne @fail

    ldx #$02
    lda $FC13           ; MATHC mirror
    cmp #$01
    bne @fail

    ldx #$03
    lda $FC12           ; MATHD mirror
    cmp #$01
    bne @fail

    ; Expecting (JK)LM = $0000
    ldx #$04
    lda $FC2F           ; MATHJ mirror
    cmp #$00
    bne @fail

    ldx #$05
    lda $FC2E           ; MATHK mirror
    cmp #$00
    bne @fail

    ldx #$06
    lda $FC2D           ; MATHL mirror
    cmp #$00
    bne @fail

    ldx #$07
    lda $FC2C           ; MATHM mirror
    cmp #$00
    bne @fail

    ldx #$08
    lda SPRSYS
    and #$64
    cmp #$04             ; unsafe is always set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 10  ; $FF indicates success
    stz _g_results + 11
    rts

@fail:
    sta _g_results + 11  ; read value
    txa
    sta _g_results + 10  ; failing stage
    rts
.endproc

;===================================================================
; Test 7: Division by zero
; EFGH / NP = ABCD, remainder (JK)LM
; 00001234 / 0000 = FFFFFFFF
;===================================================================
.proc Test7
    jsr ResetMath

    lda #$00
    sta $FC16           ; MATHP mirror
    lda #$00
    sta $FC17           ; MATHN mirror

    lda #$34
    sta $FC20           ; MATHH mirror
    lda #$12
    sta $FC21           ; MATHG mirror
    lda #$00
    sta $FC22           ; MATHF mirror
    lda #$00
    sta MATHE           ; Start division

@wait_done:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_done

    ; Expecting ABCD = $FFFFFFFF
    ldx #$00
    lda $FC15           ; MATHA mirror
    cmp #$FF
    bne @fail

    ldx #$01
    lda $FC14           ; MATHB mirror
    cmp #$FF
    bne @fail

    ldx #$02
    lda $FC13           ; MATHC mirror
    cmp #$FF
    bne @fail

    ldx #$03
    lda $FC12           ; MATHD mirror
    cmp #$FF
    bne @fail

    ldx #$04
    lda SPRSYS
    and #$64
    cmp #$64             ; div by zero, last carry and unsafe set
    bne @fail

@pass:
    lda #$FF
    sta _g_results + 12  ; $FF indicates success
    stz _g_results + 13
    rts

@fail:
    sta _g_results + 13  ; read value
    txa
    sta _g_results + 12  ; failing stage
    rts
.endproc

;===================================================================
; Test 8: Tinming test
;===================================================================
.proc Test8

.segment "ZEROPAGE"
    t0: .res 1
    t1: .res 1
    td: .res 1

.segment "CODE"
    jsr WaitVBlank
    jsr ResetMath

@mul_test:
    stz TIM6CTLA
    lda #$FF
    sta TIM6BKUP
    sta TIM6CNT
    stz TIM6CTLB

    lda #$FF
    sta $FC12           ; MATHD mirror
    lda #$FF
    sta $FC13           ; MATHC mirror
    lda #$02
    sta $FC14           ; MATHB mirror

    lda #$18
    sta TIM6CTLA        ; Start timer

    lda #$00
    sta MATHA           ; Start multiplication

    lda TIM6CNT
    sta t0

@wait_mul:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_mul

    lda TIM6CNT
    sta t1
    stz TIM6CTLA        ; Stop timer

    ldx #$00
    lda t0
    sec
    sbc t1              ; delta = t0 - t1 (timer counts down)
    sta td              ; save measured delta for reporting on failure
    cmp #$05            ; Minimum $05 ticks (inclusive)
    bcc @fail
    cmp #$08            ; Maximum $08 ticks (exclusive)
    bcs @fail

@div_test:
    stz TIM6CTLA
    lda #$FF
    sta TIM6BKUP
    sta TIM6CNT
    stz TIM6CTLB

    ;divide $12345678 by $1234
    lda #$34
    sta $FC16           ; MATHP mirror
    lda #$12
    sta $FC17           ; MATHN mirror

    lda #$78
    sta $FC20           ; MATHH mirror
    lda #$56
    sta $FC21           ; MATHG mirror
    lda #$34
    sta $FC22           ; MATHF mirror

    lda #$18
    sta TIM6CTLA        ; Start timer

    lda #$12
    sta MATHE           ; Start division

    lda TIM6CNT
    sta t0

@wait_div:
    lda SPRSYS          ; Poll until math is done
    and #$80
    bne @wait_div

    lda TIM6CNT
    sta t1
    stz TIM6CTLA        ; Stop timer

    ldx #$01
    lda t0
    sec
    sbc t1              ; delta = t0 - t1 (timer counts down)
    sta td              ; save measured delta for reporting on failure
    cmp #$10            ; Minimum $10 ticks (inclusive)
    bcc @fail
    cmp #$11            ; Maximum $11 ticks (exclusive)
    bcs @fail

@pass:
    lda #$FF
    sta _g_results + 14  ; $FF indicates success
    stz _g_results + 15
    rts

@fail:
    lda td
    sta _g_results + 15  ; measured tick delta
    txa
    sta _g_results + 14  ; failing stage
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    jsr Test2
    jsr Test3
    jsr Test4
    jsr Test5
    jsr Test6
    jsr Test7
    jsr Test8
    cli                 ; Re-enable interrupts
    rts
