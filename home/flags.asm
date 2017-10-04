
SECTION "Flag routines", ROM0

; Get flag with ID de in carry
; Format : XFFF FFFF FFFF FFFF (F = flag ID bit, X is ignored)
; Flags are grouped by eight in a byte, of course

; Returns :
; - Prev WRAM bank in B
; - C = 0
; - A = byte rolled a few times
; - D has bit 7 reset THEN rolled right three times
; - E = number of times A has been rolled
; - HL points to byte (wrong WRAM bank though)
GetFlag::
	ld a, [rSVBK]
	ld b, a
	ld a, BANK(wFlags)
	ld [rSVBK], a
	
	ld a, e
	and $07
	ld c, a ; Bit ID within byte
	
	; Shift de right three times
	res 7, d ; Force ignoring bit 7 !!
REPT 3
	srl d
	rl e
ENDR
	ld hl, wFlags
	add hl, de ; Add base ptr to point to byte (cannot overflow, btw)
	ld a, [hl]
	inc c ; Inc bit ID to get num of rot's
	ld e, c ; Save this for wrapping funcs
	
.shiftTillFlag
	rra
	dec c
	jr nz, .shiftTillFlag
	
	ld a, b
	ld [rSVBK], a
	ret
	
	
SetFlag::
	call GetFlag
	scf
	
.shiftBack
	rla
	dec e
	jr nz, .shiftBack
	ld c, a
	
	ld a, BANK(wFlags)
	ld [rSVBK], a
	ld [hl], c
	ld a, b
	ld [rSVBK], a
	ret
	
ResetFlag::
	call GetFlag
	and a ; Reset carry
	
.shiftBack
	rla
	dec e
	jr nz, .shiftBack
	ld c, a
	
	ld a, BANK(wFlags)
	ld [rSVBK], a
	ld [hl], c
	ld a, b
	ld [rSVBK], a
	ret
	
ToggleFlag::
	call GetFlag
	ccf
	
.shiftBack
	rla
	dec e
	jr nz, .shiftBack
	ld c, a
	
	ld a, BANK(wFlags)
	ld [rSVBK], a
	ld [hl], c
	ld a, b
	ld [rSVBK], a
	ret
	