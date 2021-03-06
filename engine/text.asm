
SECTION "Text engine", ROMX
	
EnableTextbox::
	ld a, 1
	ld [wTextboxStatus], a
	ret
	
WaitForTextbox::
.wait
	rst waitVBlank
	ld a, [wTextboxStatus]
	cp TILE_SIZE * 6 + 1
	jr nz, .wait
	ret
	
DisableTextbox::
	ld hl, wTextboxStatus
	set 7, [hl]
.waitUntilTextboxIsDown
	rst waitVBlank
	ld a, [wTextboxStatus]
	and a
	jr nz, .waitUntilTextboxIsDown
	rst waitVBlank ; Textbox actually needs one extra frame
	ret
	
ClearTextbox::
	ld hl, wTextFlags
	res TEXT_PIC_FLAG, [hl]
	
	ld hl, wTextboxTileMap
	ld a, $11
	ld [hli], a
	inc a
	ld c, SCREEN_WIDTH - 2
	rst fill
	dec a
	ld [hli], a
	dec a
	ld b, 4
.clearRow
	ld [hli], a
	xor a
	ld c, SCREEN_WIDTH - 2
	rst fill
	ld a, $10
	ld [hli], a
	dec b
	jr nz, .clearRow
	inc a
	ld [hli], a
	inc a
	ld c, SCREEN_WIDTH - 2
	call FillVRAMLite
	dec a
	ld [hl], a
	
	; a!= 0
	ld hl, wTransferRows
	ld c, 6
	rst fill
	
	ld a, 1
	ld [rVBK], a
	ld hl, vTextboxTileMap
	ld b, 5
.initRowAttr
	xor a
	ld c, SCREEN_WIDTH - 1
	call FillVRAMLite
.waitVRAM1
	rst isVRAMOpen
	jr nz, .waitVRAM1
	ld a, $20
	ld [hli], a
	ld a, l
	add a, VRAM_ROW_SIZE - SCREEN_WIDTH
	ld l, a
	dec b
	jr nz, .initRowAttr
	; Init last row, which is the same but with a VFlip
	ld a, $40
	ld c, SCREEN_WIDTH - 1
	call FillVRAMLite
.waitVRAM2
	rst isVRAMOpen
	jr nz, .waitVRAM2
	ld a, $60
	ld [hl], a
	xor a
	ld [rVBK], a
	ld [wNumOfPrintedLines], a
	
	ld hl, TextboxBorderTiles
	ld de, vTextboxBorderTiles
	ld bc, BANK(TextboxBorderTiles) << 8 | 7
	jp TransferTilesAcross
	
	
	
ProcessText_Hook::
	ld b, c
	ld h, d
	ld l, e
	
; Process the text pointed to by b:hl
; Text is actually a byte stream, you should use the macros defined in constants/text.asm to build a text stream
ProcessText::
	push bc ; Save ROM bank
	push hl ; Save read pointer
	ld a, 1
	call SwitchRAMBanks ; Switch to the text-related RAM bank
	call ClearTextbox
	ld hl, wTextFlags
	res TEXT_NO_FRAME_WAIT_FLAG, [hl]
.resetSameFrameFlag
	res TEXT_SAME_FRAME_FLAG, [hl]
.mainLoop
	; Step 1 : copy data about to be processed
	pop hl ; Retrieve read pointer
	pop bc ; Retrieve ROM bank
	push bc ; Place them back
	push hl ; Not using "inc sp"s, because if a handler fires right now the stack is modified :P
	ld de, wDigitBuffer
	ld c, 5
	call CopyAcrossLite ; Copy next 5 bytes for command to analyze
	
	; Step 2 : process copied data
	ld hl, wDigitBuffer
	ld a, [hli] ; Get command ID
	; Check if ID is invalid (out of bounds)
	; Also means we can't lose MSB on later "add a, a"
	cp INVALID_TXT_COMMAND
	; Print error message and end text
	jr nc, .printErrorAndEnd
	; Check if command is #0
	and a
	; End text normally if so
	jr z, .end
	
	; Step 3 : run text command
	; Get operation ID, we just ensured it is valid
	add a, a ; Double a (MSB can only be zero because of above check :)
	ld hl, TextCommandsPointers - 2 ; - 2 because first offset is for a = 1
	add a, l
	ld l, a
	jr nc, .noCarry1
	inc h
.noCarry1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	rst callHL ; Call appropriate command
	; Should return number of bytes consumed in a
	
	; Step 4 : prepare next call
	pop hl ; Get read pointer back
	; Put offset in bc
	ld c, a
	; Make b = 0 if c >= 0, and b = $FF if c < 0
	rla ; Move MSB (sign bit) into carry
	sbc a, a ; a <- a - a - carry : 0 if carry isn't set, $FF if set. Neat!
	ld b, a
	; bc now contains our movement offset
	add hl, bc ; Move read pointer
	push hl ; Save it
	
	; Step 5 : ensure at most one command is processed per frame, unless otherwise specified.
	ld hl, wTextFlags
	bit TEXT_SAME_FRAME_FLAG, [hl]
	jr nz, .resetSameFrameFlag ; "One-frame" flag must be reset if applied, even if "global" flag is set !!
	bit TEXT_NO_FRAME_WAIT_FLAG, [hl]
	jr nz, .mainLoop
	rst waitVBlank
	jr .mainLoop
	
.printErrorAndEnd
	debug_message "INVALID TEXT COMMAND $%A%"
	call ClearTextbox
	ld hl, TextErrorStr
	ld b, BANK(TextErrorStr)
	call PrintKnownPointer ; Print text error string
	ld hl, wTextboxStatus ; Make sure text box is up
	ld [hl], TILE_SIZE * 5
	ld bc, 40 ; Wait for user to read
	call DelayBCFrames
.end
	add sp, 4; Free top 2 stack entries, they contain read pointer and ROM bank
	jpacross DisableTextbox
	
	
	
TextCommandsPointers::
	dw ClearText
	dw PrintPic
	dw PrintNameAndWaitForTextbox
	dw WaitForButtonPress
	dw WaitForButtonPress
	dw PrintLine
	dw PrintEmptyLine
	dw DelayNFrames
	dw SetTextLoopCounter
	dw CopyTextLoopCounter
	dw TextDjnz
	dw DisplayNumber
	dw DisplayTextboxInstant
	dw CloseTextboxInstant
	dw DisplayTextboxWithoutWait
	dw CloseTextboxWithoutWait
	dw MakeNPCWalk
	dw MakeNPCWalkTo
	dw MakePlayerWalk
	dw MakePlayerWalkTo
	dw MakeChoice
	dw MakeChoice ; Difference between commands handled by function itself
	dw SetFadeSpeed
	dw Fadein_TextWrapper
	dw Fadeout_TextWrapper
	dw ReloadPalettes_TextWrapper
	dw TextLDA
	dw TextLDA_imm8
	dw TextSTA
	dw TextCMP
	dw TextDEC
	dw TextINC
	dw TextADD
	dw TextADC
	dw TextADD_mem
	dw TextSBC
	dw TextSUB_mem
	dw TextSetFlags
	dw TextToggleFlags
	dw TextCallFunc
	dw InstantPrintLines
	dw ReloadTextFlags
	dw TextJR
	dw TextJR_Conditional ; nc
	dw TextJR_Conditional ; c
	dw TextJR_Conditional ; p
	dw TextJR_Conditional ; n
	dw TextJR_Conditional ; pe
	dw TextJR_Conditional ; po
	dw TextJR_Conditional ; nz
	dw TextJR_Conditional ; z
	dw TextRAMBankswitch
	dw TextAND
	dw TextOR
	dw TextXOR
	dw TextBIT
	dw EndTextWithoutClosing
	dw TextFadeMusic
	dw TextPlayMusic
	dw TextStopMusic
	dw TextWaitSFX
	dw TextPlaySFX
	dw TextStopSFX
	dw TextPlayMapMusic
	dw OverrideTextboxPalette
	dw CloseTextbox
	dw TextGetFlag
	dw TextSetFlag
	dw TextResetFlag
	dw TextToggleFlag
	dw TextLoadMap
	dw TextStartAnim
	dw TextEndAnim
	dw TextPlayAnims
	
TextErrorStr::
	db "TEXT ERROR."
EmptyStr::
	db 0
	
YesNoCapsChoice::
	dstr "YES"
	dstr "NO"
	
YesNoChoice::
	dstr "Yes"
	dstr "No"
	
	
; Clears all three textbox lines
ClearText::
	ld hl, wTextFlags
	bit TEXT_PIC_FLAG, [hl]
	ld hl, wTextboxLine0
	ld c, SCREEN_WIDTH - 6
	jr nz, .picPresent
	ld c, SCREEN_WIDTH - 2
	ld l, LOW(wTextboxPicRow1)
.picPresent
	ld a, l
	add a, SCREEN_WIDTH
	ld e, a ; Save the next line's low byte
	ld d, c ; Save the length
	xor a
	; Clear all 3 text rows
	rst fill
	ld l, e
	ld a, e ; Move to the next line
	add a, SCREEN_WIDTH
	ld e, a
	ld c, d
	xor a
	rst fill
	ld l, e
	ld c, d
	rst fill
	
	xor a
	ld [wNumOfPrintedLines], a
	inc a
	ld hl, wTransferRows + 2
	ld c, 3
	; a is nonzero
	rst fill ; Mark rows as dirty
	
	; Consumed one byte
	ret
	
	
; Prints the picture pointed to to VRAM and displays it on the textbox
PrintPic::
	ld hl, wTextFlags
	set TEXT_PIC_FLAG, [hl] ; Set pic flag
	
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, b
	ld de, vPicTiles
	ld bc, VRAM_TILE_SIZE * 9
	call CopyAcrossToVRAM
	ld h, d
	ld l, e
	ld c, VRAM_TILE_SIZE * 3
	xor a
	call FillVRAMLite ; Blank out last 3 tiles (for text scrolling animation)
	
	ld a, 4
	ld hl, wTextboxPicRow0
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	inc a
	
	ld l, LOW(wTextboxPicRow1)
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	inc a
	
	ld l, LOW(wTextboxPicRow2)
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	inc a
	
	ld l, LOW(wTextboxPicRow3)
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	
	; a is nonzero
	ld hl, wTransferRows + 1
	ld c, 4
	rst fill
	
	ld a, 4 ; Consumed command byte + bank byte + pic ptr
	ret
	
	
; Prints the name and waits for the textbox to finish rising...
; Note : if the textbox is already rising, its animation will not restart
; And if the textbox is already fully up, it will not rise again
PrintNameAndWaitForTextbox::
	; Erase previous name
	ld hl, vTextboxTileMap + 1
	ld c, SCREEN_WIDTH - 2
	ld a, $12
	call FillVRAMLite
	
	ld hl, wTextFlags
	bit TEXT_PIC_FLAG, [hl]
	
	ld de, wTextboxName
	ld c, 12 ; 16 characters at most
	jr nz, .picPresent
	ld e, LOW(wTextboxName - 4)
	ld c, 16
.picPresent

	ld hl, wDigitBuffer + 1
	ld a, [hli] ; Get bank
	ld b, a
	ld a, [hli] ; Get pointer
	ld h, [hl]
	ld l, a
	or h
	jr z, .noName
	ld a, $15
	ld [de], a
	inc de
	call PrintAcross
	ld a, $16
	ld [de], a
	
	ld a, 1 ; Ask to transfer row
	ld [wTransferRows], a
	
.noName
	ld hl, wTextboxStatus
	ld a, [hl]
	and $7F ; Check if textbox status is zero (don't care about bit 7)
	jr nz, .textboxAlreadyUp
	inc a
	ld [hl], a ; Make textbox begin to appear
.textboxAlreadyUp
	call WaitForTextbox
	
	ld a, 4 ; Consumed command byte + bank byte + name ptr
	ret
	
	
; Wait until the user has pressed a button
WaitForButtonPress::
	ld hl, vTextboxLine2 + VRAM_ROW_SIZE + 13
	ld a, $14
	ld [hld], a
	dec a
	ld [hl], a
	
.waitLoop
	rst waitVBlank
	ldh a, [hFrameCounter]
	and $1F
	jr nz, .noBlink
	ld a, $13 ^ $12 ; Change between border and arrow'd border
	xor [hl]
	ld [hli], a
	ld a, $14 ^ $12
	xor [hl]
	ld [hld], a
.noBlink
	; To continue, the player shall either hold B or is press A
	ldh a, [hHeldButtons]
	and 2
	jr nz, .end
	ldh a, [hPressedButtons]
	rrca
	jr nc, .waitLoop
.end
	ld a, $12
	ld [hli], a
	ld [hl], a
	
	ld a, [wDigitBuffer]
	cp WAIT_FOR_BUTTON_NO_SFX
	push	bc
	ld	c,SFX_TEXT_ADVANCE
	callacross nz, FXHammer_Trig
	pop	bc
	
	ld a, 1 ; Consumed command byte
	
	ret
	
	
; Prints a line of text
PrintLine::
	ld hl, wDigitBuffer + 1
	ld a, [hli] ; Get source bank
	ld b, a
	ld a, [hli] ; Get pointer
	ld h, [hl]
	ld l, a
	call PrintKnownPointer
	
	ld a, 4 ; Consumed command byte + bank byte + str ptr
	ret
	
; Use this hook when "callacross"-ing PrintKnownPointer ; put the print pointer in de instead of hl, and the bank in c instead of b
PrintKnownPointer_Hook::
	ld h, d
	ld l, e
	ld b, c
	
PrintKnownPointer::
	ld a, [wNumOfPrintedLines]
	and 3
	cp 3
	jp c, .printNewLine ; Too far to jr
	
	push hl ; Save read pointer
	push bc ; Save bank
	
	ld b, $40
.scrollLoop
	rst waitVBlank
	
.shiftPic
	ld hl, $9070
.shiftColumn
	ld de, 0
.shiftTile
	ld c, $08 ; Move the 8 lines
.shiftByte
	rst isVRAMOpen
	jr nz, .shiftByte
	ld a, e
	ld e, [hl]
	ld [hli], a
	ld a, d
	ld d, [hl]
	ld [hli], a
	dec c
	jr nz, .shiftByte
	ld a, l
	add a, $20
	ld l, a
	cp $30
	jr nc, .shiftTile
	ld a, l
	add a, $80
	ld l, a
	cp $A0
	jr nz, .shiftColumn
	inc b
	bit 0, b
	jr nz, .shiftPic
	
	ld a, [rLYC] ; Calc scanline on which scroll will happen
	add a, TILE_SIZE * 2
	cp $8F ; Check if it's displayed
	jr nc, .effectIsOffscreen
	ld c, a
	
	ld hl, rLYC ; Will be used for later writing
	ld a, b
	sub [hl]
	dec a
	ld d, a ; Precalc target SCY value
	ld l, LOW(rSCY) ; hl = rSCY
.waitUntilText
	ld a, [rLY]
	cp c
	jr c, .waitUntilText
	
.waitUntilLineEnds
	rst isVRAMOpen
	jr nz, .waitUntilLineEnds
	
	ld e, [hl] ; Save current value
	ld [hl], d ; Write precalc'd value to SCY
	ld hl, vTextboxPicRow0
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	
	ld a, c
	sub b
	add a, 3 * 8 + 1 + $40
	cp $90
	jr c, .noCap
	ld a, $8F
.noCap
	
	ld hl, rSCY
	ld c, a
.waitUntilTextBottom
	ld a, [rLY]
	cp c
	jr c, .waitUntilTextBottom
	
	ld a, 120 + TILE_SIZE
	add a, b
	ld [hl], a ; Force current textbox line to be 16th
	
.blankUnderText
	rst isVRAMOpen
	jr z, .blankUnderText
.waitLineEnd
	rst isVRAMOpen
	jr nz, .waitLineEnd
	
	dec [hl]
	ld a, [rLY]
	cp $8F - 7
	jr c, .blankUnderText
	
	ld [hl], e ; Restore display
	
	; Transfer textbox row #2 to restore picture (if needed)
	; a is non-zero
	ld [wTransferRows + 1], a
	
.effectIsOffscreen
	ld a, b
	cp $48
	jp nz, .scrollLoop ; Too far (though by REALLY not much)
	
	; Now we're going to race the beam. Goal : have the text box set up by the time it's rendered.
	ld hl, $90A0
	ld de, $9070
	ld c, $10 * 6
	call CopyToVRAMLite
	ld l, e
	dec h
	ld c, $30
	xor a
	call FillVRAMLite
	
	ld hl, wTextFlags
	bit TEXT_PIC_FLAG, [hl]
	ld bc, wTextboxPicRow1
	jr z, .picNotPresent
	ld c, LOW(wTextboxLine0)
.picNotPresent
	ld hl, SCREEN_WIDTH
	add hl, bc ; Move to second line
	ld d, h
	ld e, l ; Store pointer
	ld hl, SCREEN_WIDTH * 2
	add hl, bc ; Move to third line
.moveLines
	ld a, [de]
	ld [bc], a
	inc bc
	ld a, [hl]
	ld [de], a
	inc de
	xor a
	ld [hli], a
	ld a, c
	cp LOW(wTextboxLine0 + 14)
	jr nz, .moveLines
	
	ld hl, wTextboxTileMap + SCREEN_WIDTH * 2
	ld de, vTextboxTileMap + VRAM_ROW_SIZE * 2
.commitLines
	ld c, SCREEN_WIDTH
	call CopyToVRAMLite
	ld a, e
	add a, VRAM_ROW_SIZE - SCREEN_WIDTH
	ld e, a
	cp LOW(vTileMap1 + VRAM_ROW_SIZE * 6)
	jr nz, .commitLines
	
	pop bc ; Retrieve bank
	; Print at last line
	ld de, wTextboxLine2
	pop hl ; Get back read pointer
	jr .printLine
	
.printNewLine
	inc a
	ld [wNumOfPrintedLines], a
	ld c, a
	ld de, wTextboxLine0 - SCREEN_WIDTH
.calcDest
	ld a, SCREEN_WIDTH
	add a, e
	ld e, a ; Cannot overflow
	dec c
	jr nz, .calcDest
	
.printLine
	ld a, [wTextFlags]
	bit TEXT_PIC_FLAG, a ; Check if pic is present
	ld c, 14 ; When it is, only 15 chars can be printed
	jr nz, .picIsPresent
	ld a, e ; Place text on pic's space since it's free
	sub (wTextboxLine0 - wTextboxPicRow1)
	ld e, a
	ld c, 14 + (wTextboxLine0 - wTextboxPicRow1) ; This gives additional characters
.picIsPresent
	; Copy string across banks (b preserved thus far :D)
	push de
	
	; This is almost equivalent to CopyStrAcross, but doesn't copy the terminating $00 if it would overwrite the border
	call PrintAcross
	
	ld d, h ; Get after-copy hl
	ld e, l
	pop hl
	push de ; Save for later
	ld d, HIGH(vTextboxLine0)
	ld a, [wNumOfPrintedLines]
	and 3
	add a, a ; Mult by 2
	swap a ; Mult by 16 (since original 4 upper bits are zero)
	add a, LOW(vTextboxPicRow0)
	ld e, a
	ld c, 18
	ld a, [wTextFlags]
	bit TEXT_PIC_FLAG, a
	jr z, .noPicThere
	ld a, e
	add a, (wTextboxLine0 - wTextboxPicRow1) ; Add pic offset
	ld e, a
	ld c, 14
.noPicThere
	
.printLoop
	rst waitVBlank
	ld a, [hli]
	ld [de], a
	inc de
	and a
	jr z, .endPrint
	dec c
	jr nz, .printLoop
.endPrint
	ld d, h
	ld e, l
	pop hl
	ret
	
PrintEmptyLine::
	ld hl, EmptyStr
	ld b, BANK(EmptyStr)
	call PrintKnownPointer
	
	ld a, 1 ; Consumed command byte
	ret
	
	
DelayNFrames::
	ld hl, wDigitBuffer + 1 ; Get number of frames to delay
	ld c, [hl]
	inc hl
	ld b, [hl]
	call DelayBCFrames
	
	ld a, 3 ; Consumed command byte + delay word
	ret
	
	
SetTextLoopCounter::
	ld a, [wDigitBuffer + 1] ; Get counter
	ld [wTextLoopCounter], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 2 ; Consumed command byte + counter byte
	ret
	
CopyTextLoopCounter::
	ld hl, wDigitBuffer
	ld a, [hli] ; Get pointer
	ld h, [hl]
	ld l, a
	; Get counter from pointer
	ld a, [hl]
	ld [wTextLoopCounter], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3 ; Consumed command byte + counter pointer
	ret
	
TextDjnz::
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	
	ld a, 2 ; Consumed command byte + offset
	ld hl, wTextLoopCounter
	dec [hl]
	ret z ; Done decrementing, no jr. Already set consumed bytes!
	
TextJR::
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	
	ld a, [wDigitBuffer + 1] ; Get offset
	; Say it's the number of bytes we consumed
	ret
	
TextJR_Conditional::
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	
	ld hl, wDigitBuffer
	ld a, [hli]
	sub TEXT_JR_NC - 2 ; So b will be at least 1 (if conditional is correct, though)
	srl a
	ld b, a
	ld a, [wTextFlags]
	jr nc, .jumpIfFlagReset
	cpl ; Invert flags, so the jump will occur if the flag is reset (instead of set...)
.jumpIfFlagReset
.getFlagLoop
	add a, a
	dec b
	jr nz, .getFlagLoop
	
	ld a, 2
	ret c ; Flag is set -> jump shouldn't occur
	
	ld a, [hl]
	ret
	
	
DisplayNumber::
	ld hl, wDigitBuffer + 1
	ld a, [hli] ; Get display type
	and a ; Check whether we display a byte or a word
	
	ld a, [hli] ; Get pointer
	ld e, a
	ld d, [hl]
	
	ld h, 0
	ld a, [de]
	ld l, a
	jr z, .byte ; Z hasn't changed since "and a"
	inc de
	ld a, [de] ; Word? Get high byte!
	ld h, a ; Also overwrite b, which was 1
.byte
	
	xor a
	ld de, wDigitBuffer + 4 ; Write destination
	ld [de], a ; Make sure to terminate the string
.loop
	push de ; Save write offset
	ld de, 10
	call DivideHLByDE_KnownDE ; DE is known, skip the "divide by zero" check
	add hl, de ; Get remainder in hl
	pop de ; Get write offset back
	
	; hl contains remainder ; it cannot be invalid (except if I coded my divide function badly :P)
	ld a, l
	add a, "0" ; Add tile offset...
	dec de ; Write to digit buffer
	ld [de], a
	
	; Get hl / de back into hl, making sure it's not 0
	ld h, b
	ld l, c
	
	ld a, b
	or c
	jr nz, .loop ; If we printed all digits then it's done
	
	; de points to first digit
	call PrintKnownPointer_Hook ; Setting b is pointless, we're in WRAM :D
	
	ld a, 4 ; Consumed command byte + display type byte + display ptr
	ret
	
	
DisplayTextboxInstant::
	ld a, $31
	ld [wTextboxStatus], a
	
	ld a, 1 ; Consumed command byte
	ret
	
CloseTextboxInstant::
	xor a
	ld [wTextboxStatus], a
	
	inc a ; Consumed command byte
	ret
	
	
DisplayTextboxWithoutWait::
	ld hl, wTextboxStatus
	ld a, [hl]
	and $7F
	ld a, 1 ; Consumed bytes : OK
	ret nz
	ld [hl], a
	ret
	
CloseTextboxWithoutWait::
	ld hl, wTextboxStatus
	set 7, [hl]
	ld a, 1 ; Consumed command byte
	ret
	
	
MakePlayerWalkTo::
	ld hl, wDigitBuffer + 4
	ld a, [hld]
	and $02 ; Will modify Z...
	ld c, a
	ld b, [hl] ; Get speed
	dec hl
	ld d, [hl] ; Get target coord
	dec hl
	ld e, [hl]
	ld hl, wYPos
	; ... and Z is still the same !
	jr z, .verticalAxis
	inc hl
	inc hl
.verticalAxis
	ld a, [hli] ; Get current coord
	ld h, [hl]
	sub e ; Subtract
	ld l, a ; target
	ld a, h ; coord
	sbc d ; from
	ld h, a ; current
	rlca ; Is that negative ?
	jr nc, .moveNegatively ; If not, we need to move in the "negative" direction - thus we're fine.
	rrca ; Get back a
	cpl ; And
	ld h, a ; negate
	ld a, l ; hl
	cpl ; to
	ld l, a ; become
	inc hl ; positive
	set 0, c ; Flip direction
.moveNegatively
	inc h ; Make high byte 1 more than actual offset
.moveLoop
	ld e, b ; Shove speed into e
	dec h ; After this, hl will contain actual offset, and Z will be set if it's < 256
	ld a, c ; MakePlayerWalk_Hook expects a to be a copy of c to turn the player
	jr z, .finalWalk ; If there are <$100 steps remaining, that's handled in one go.
	inc hl ; Increment to subtract only $FF from hl, instead of the 256 from "dec h"
	push bc ; Save our registers
	push hl
	ld b, $FF ; And move 255 pixels ('cause that's the longest we can do in one go)
	call MakePlayerWalk_Hook
	pop hl ; Restore
	pop bc
	jr .moveLoop
.finalWalk
	ld b, l
	call MakePlayerWalk_Hook
	inc a
	ret
	
MakePlayerWalk::
	ld hl, wDigitBuffer + 3
	ld a, [hld] ; Get speed
	ld e, a ; Store that
	ld a, [hld] ; Get length
	ld b, a
	
	ld a, [hl] ; Get direction
	ld c, a
MakePlayerWalk_Hook:
	ld hl, wPlayerDir
	bit 2, c
	jr nz, .dontTurnPlayer
	and $03
	ld [hl], a
.dontTurnPlayer
	dec hl
	dec hl ; wXPos
	ld d, LOW(wNPC0_steps)
	call TextMoveEntity_Common
	dec a ; This command doesn't require the NPC ID byte
	ret
	
MakeNPCWalkTo::
	ld hl, wDigitBuffer + 1
	ld a, [hli] ; Get NPC id & direction
	and $27 ; Sanitize
	; No need to alter NPC id due to failsafe
	ld e, [hl]
	ld [hl], VERTICAL_AXIS ; Set defzult dir
	bit 5, a
	jr z, .wroteDirection
	ld [hl], HORIZONTAL_AXIS ; Re-write if horiz
.wroteDirection
	inc hl
	ld d, [hl]
	swap a ; Get pointer to coord ; a "| HORIZONTAL_AXIS << 4" will select the proper coord (offsetting by 2)
	add a, LOW(wNPC1_ypos)
	ld c, a
	adc a, HIGH(wNPC1_ypos)
	sub c
	ld b, a
	ld a, [bc] ; Read coord and subtract to get offset
	inc bc
	sub e
	ld e, a
	ld a, [bc]
	sbc d
	ld d, a
	rlca ; Is that negative ?
	jr nc, .moveNegatively
	rrca ; Negate offset
	cpl
	ld d, a
	ld a, e
	cpl
	ld e, a
	inc de
	dec hl ; Point to direction
	set 0, [hl] ; Switch directions
	inc hl
.moveNegatively
	; hl points to the "len" parameter in wDigitBuffer
	inc d ; Now, de = offset + 256
.moveLoop
	dec d ; Subtract 256, so de contains the offset minus the "256" compensation
	jr z, .finalWalk ; MakeNPCWalk cannot handle more than 255 steps, so if there are 256 or extra steps are required
	inc de ; Increment de to only subtract 255
	ld [hl], $FF
	push de
	call MakeNPCWalk ; Luckily this preserves all of wDigitBuffer
	pop de
	ld hl, wDigitBuffer + 3 ; Repoint to "len" argument
	jr .moveLoop
.finalWalk
	ld [hl], e
	; Slide for the last one
	
MakeNPCWalk::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	and 7 ; Max out! Hehehe, no buffer overflow :D
	swap a
	add a, LOW(wNPC1_sprite)
	ld e, a
	adc a, HIGH(wNPC1_sprite)
	sub e
	ld d, a ; Now we're pointing at the NPC's facing direction
	ld a, [hli] ; Get direction of movement
	ld c, a ; Store movement direction & flags in c
	bit 2, c
	jr nz, .dontTurnNPC
	and $03
	ld b, a ; Store direction only in b
	ld a, [de] ; Get NPC's sprite & direction
	and $FC ; Remove direction
	or b ; Set new direction
	ld [de], a ; Write back
.dontTurnNPC
	ld a, [hli]
	ld b, a ; Number of pixels to travel
	ld h, [hl] ; Number of pixels per frame
	ld a, e
	sub wNPC1_sprite - wNPC1_xpos
	ld l, a
	ld e, h ; Transfer speed to e
	ld h, d ; Transfer pointer to hl
	add wNPC1_steps - wNPC1_xpos
	ld d, a
	
; hl = pointer to horiz coord
; e = speed (pixels/frame)
; b = number of pixels, total
; c = direction of movement
; d = low byte of pointer to entity's step counter
TextMoveEntity_Common:
	push hl
	ld h, HIGH(wNPCArray)
	ld l, d
	ld [hl], b ; Reset entity's movement steps
	inc hl
	ld a, [hl]
	and $F4 ; Clear entity's movement (put it in a waiting state)
	ld [hl], a
	pop hl
	
	bit 1, c
	jr nz, .moveHorizontally
	dec hl
	dec hl ; Move to ypos instead of xpos
.moveHorizontally
	
	; If bit 4 is set, diagonal movement shall rotate CCW instead of CW
	bit 4, c
	jr z, .dontSwitchRotations
	ld a, c
	xor 2
	ld c, a
.dontSwitchRotations
	
	ld a, b
.movementLoop
	; a should contain number of pixels
	sub e ; Subtract one frame's worth of movement
	jr nc, .moveFully
	; We must move less than this, then.
	ld e, b ; Set the speed for this final frame.
	xor a ; Zero pixels will remain.
.moveFully
	ld b, a
	rst waitVBlank
	
	ld a, [hli] ; Get coordinate's low byte, and repoint to high byte
	bit 0, c
	jr nz, .movePositively
	sub e ; Move
	jr nc, .doneMoving
	dec [hl] ; If carry, change high byte
	jr .doneMoving
.movePositively
	add a, e
	jr nc, .doneMoving
	inc [hl] ; If carry, change high byte
.doneMoving
	dec hl ; Repoint to low byte
	ld [hl], a ; Write back low byte
	
	bit 3, c ; Check if should rotate by 45° CW
	jr z, .dontMoveDiagonally
	ld a, l
	xor 2
	ld l, a ; Switch directions
	ld a, c ; Make a copy of c
	rrca ; Roll bit 0 into carry
	bit 1, c ; If we were moving on the vertical axis, we need to toggle directions
	jr nz, .dontToggleDirection
	ccf ; Toggle direction
.dontToggleDirection
	ld a, [hli]
	jr c, .moveNegatively
	add a, e
	jr nc, .doneMovingDiagonally
	inc [hl]
	jr .doneMovingDiagonally
.moveNegatively
	sub e
	jr nc, .doneMovingDiagonally
	dec [hl]
.doneMovingDiagonally
	dec hl
	ld [hl], a
	ld a, l
	xor 2
	ld l, a
.dontMoveDiagonally
	
	push bc
	push de
	push hl
	ld h, HIGH(wNPCArray)
	ld l, d ; Get pointer to entity's steps in hl
	dec [hl]
	call MoveNPC0ToPlayer
	call MoveCamera
	call ProcessNPCs
	ld a, [wCameraYPos]
	ldh [hSCY], a
	ld a, [wCameraXPos]
	ldh [hSCX], a
	pop hl
	pop de
	pop bc
	ld a, b
	and a
	jr nz, .movementLoop
	
	; Reset entity's movement
	ld h, HIGH(wNPCArray)
	ld l, d
	ld [hl], 0
	call ProcessNPCs
	
	ld a, 5
	ret
	
	
CURSOR_TILE	equ $7F
	
MakeChoice::
	ld a, [wTextFlags]
	ld c, a
	bit TEXT_PIC_FLAG, c
	
	ld hl, wDigitBuffer + 1
	ld b, [hl]
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, wTextboxLine2 + 1
	jr nz, .picPresent
	ld e, LOW(wTextboxLine2 - 3)
.picPresent
	call CopyStrAcross ; Preserves c
	xor a
	ld [de], a
	inc de
	call CopyStrAcross ; Preserves c
	
	ld hl, wTextboxLine2 - 4
	ld de, vTextboxLine2 - 4
	bit TEXT_PIC_FLAG, c
	jr z, .picNotPresent
	ld l, LOW(wTextboxLine2)
	ld e, LOW(vTextboxLine2)
.picNotPresent
	ld b, h
	ld c, l
	ld [hl], CURSOR_TILE
.drawChoiceText1
	rst waitVBlank
	ld a, [hli]
	ld [de], a
	inc de
	and a
	jr nz, .drawChoiceText1
	
	push hl
	ld [de], a
	inc hl
	inc de
	
.drawChoiceText2
	rst waitVBlank
	ld a, [hli]
	ld [de], a
	inc de
	and a
	jr nz, .drawChoiceText2
	
	pop hl
	
.loop
	rst waitVBlank
	ldh a, [hPressedButtons]
	rrca
	jr c, .done
	rrca
	jr nc, .checkDirections
	ld d, a
	ld a, [wDigitBuffer]
	cp MAKE_B_CHOICE
	ld a, d
	jr nz, .checkDirections
	
	ld a, CURSOR_TILE
	ld [hl], a
	ld [wTransferRows + 4], a
	xor a
	ld [bc], a
REPT 4
	rst waitVBlank
ENDR
	jr .done
	
.checkDirections
	and $30 >> 2
	jr z, .loop
	ld [wTransferRows + 4], a ; Next VBlank won't trigger soon, so this is ok
	and $20 >> 2
	jr nz, .goingLeft
	ld [hl], CURSOR_TILE
	xor a
	jr .writeOtherCursor
.goingLeft
	ld [hl], 0
	ld a, CURSOR_TILE
.writeOtherCursor
	ld [bc], a
	jr .loop
	
.done

	ld a, [hl]
	and a
	ld hl, wTextFlags
	set TEXT_ZERO_FLAG, [hl] ; Set status
	ld a, 5
	ret z ; Didn't select the second option
	res TEXT_ZERO_FLAG, [hl]
	ld a, [wDigitBuffer + 4]
	ret
	
	
SetFadeSpeed::
	ld a, [wDigitBuffer + 1]
	ld [wFadeSpeed], a
	
	ld a, 2
	ret
	
Fadein_TextWrapper::
	callacross Fadein ; Returns with a = 0
	
	ld a, 1
	ret
	
Fadeout_TextWrapper::
	callacross Fadeout
	
	ld a, 1
	ret
	
ReloadPalettes_TextWrapper::
	callacross ReloadPalettes
	
	ld a, 1
	ret
	
	
TextLDA::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [hl]
	ld [wTextAcc], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3
	ret
	
TextLDA_imm8::
	ld a, [wDigitBuffer + 1]
	ld [wTextAcc], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 2
	ret
	
TextSTA::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [wTextAcc]
	ld [hl], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3
	ret
	
TextDEC::
	ld hl, wTextAcc
	ld a, [hl]
	inc [hl]
	
	inc hl
	res TEXT_CARRY_FLAG, [hl]
	and a
	jr nz, .noCarry
	set TEXT_CARRY_FLAG, [hl]
.noCarry
	
	jr INCDECCommon
	
TextINC::
	ld hl, wTextAcc
	inc [hl]
INCDECCommon:
	call UpdateTextFlags
	ld a, 1
	ret
	
TextAND::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	and [hl]
	jr Text2ByteArithCommon
	
TextOR::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	or [hl]
	jr Text2ByteArithCommon
	
TextXOR::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	xor [hl]
	jr Text2ByteArithCommon
	
TextADD::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	add a, [hl]
	jr Text2ByteArithCommon
	
TextADC::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	adc a, [hl]
	jr Text2ByteArithCommon
	
TextCMP::
	ld a, [wDigitBuffer + 1]
	ld b, a
	ld hl, wTextAcc
	ld a, [hli]
	sub b
	jr Text2ByteArithCommon_NoWriteback
	
TextBIT::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextAcc
	and [hl]
	jr Text2ByteArithCommon_NoWriteback
	
TextSBC::
	ld a, [wDigitBuffer + 1]
	ld b, a
	ld hl, wTextAcc
	ld a, [hl]
	sbc a, b
Text2ByteArithCommon:
	ld [hli], a
Text2ByteArithCommon_NoWriteback:
	res TEXT_CARRY_FLAG, [hl]
	jr nc, .noCarry
	set TEXT_CARRY_FLAG, [hl]
.noCarry
	call UpdateTextFlags
	; a = 1
	inc a ; a = 2
	ret
	
TextADD_mem::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [hl]
	ld hl, wTextAcc
	add a, [hl]
	jr Text3ByteArithCommon
	
TextSUB_mem::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [hl]
	ld b, a
	ld hl, wTextAcc
	ld a, [hl]
	sbc a, b
Text3ByteArithCommon:
	ld [hli], a
Text3ByteArithCommon_NoWriteback:
	res TEXT_CARRY_FLAG, [hl]
	jr nc, .noCarry
	set TEXT_CARRY_FLAG, [hl]
.noCarry
	call UpdateTextFlags
	ld a, 3
	ret
	
TextSetFlags::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextFlags
	or [hl]
	jr TextFlagOpsCommon
	
TextToggleFlags::
	ld a, [wDigitBuffer + 1]
	ld hl, wTextFlags
	xor [hl]
TextFlagOpsCommon:
	ld [hl], a
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 1
	ret
	
	
TextCallFunc::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	and a
	ld b, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jr z, .bank0
	
	call CallAcrossBanks
	
.done
	ld a, 4
	ret
.bank0
	rst callHL
	jr .done
	
	
InstantPrintLines::
	ld hl, wDigitBuffer + 1
	ld b, [hl]
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [wTextFlags]
	bit TEXT_PIC_FLAG, a ; Check if pic is there
	ld de, wTextboxPicRow1
	ld c, 18
	jr z, .picNotPresent
	ld e, LOW(wTextboxLine0)
	ld c, 15
.picNotPresent
	ld a, 3
.loop
	push af
	push de
	push bc
	call PrintAcross
	pop bc
.clearLoop
	ld a, [de]
	cp $10
	jr z, .endClearing
	xor a
	ld [de], a
	inc de
	jr .clearLoop
.endClearing
	pop de
	ld a, SCREEN_WIDTH
	add a, e
	ld e, a
	pop af
	dec a
	jr nz, .loop
	
	ld hl, wTransferRows + 2
	ld a, 3
	ld c, a ; ld c, 3
	rst fill
	
	rst waitVBlank
	rst waitVBlank
	
	ld a, 4
	ret
	
	
ReloadTextFlags::
	ld a, [wTextAcc]
UpdateTextFlags::
	ld b, a
	ld hl, wTextFlags
	ld a, [hl]
	and $FF ^ (1 << TEXT_ZERO_FLAG | 1 << TEXT_PARITY_FLAG | 1 << TEXT_SIGN_FLAG) ; Reset all flags we're going to affect
	ld [hl], a
	
	ld a, b ; Get accumulator value
	and a ; For Z flag check
	jr nz, .noZero
	set TEXT_ZERO_FLAG, [hl]
.noZero
	rrca
	jr nc, .parityEven
	set TEXT_PARITY_FLAG, [hl]
.parityEven
	rlca
	rlca
	jr nc, .positive
	set TEXT_SIGN_FLAG, [hl]
.positive
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 1
	ret
	
	
TextRAMBankswitch::
	ld a, [wDigitBuffer + 1]
	call SwitchRAMBanks
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 2
	ret
	
	
EndTextWithoutClosing:: ; To do so, bypasses the end of ProcessText and directly returns to the parent. This requires removing a few things from the stack :
	; Remove return address
	; Remove read pointer
	; Remove bank
	add sp, 6
	ret ; End operations
	
	

TextFadeMusic::
	ld a, [wDigitBuffer + 1]
	call DS_Fade
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 2
	ret
	
TextPlayMusic::
	ld a, [wDigitBuffer + 1]
	call DS_Init
	ld a, 2
	ret
	
TextStopMusic::
	call DS_Stop
	ld a, 1
	ret
	
	
TextWaitSFX::
	ld hl, FXHammer_SFXCH2
	ld de, FXHammer_SFXCH4
.wait
	rst waitVBlank
	bit 1, [hl]
	jr nz, .wait
	ld a, [de]
	and 2
	jr nz, .wait
	
	inc a
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ret
	
TextPlaySFX::
	ld a, [wDigitBuffer + 1]
	ld c, a
	callacross FXHammer_Trig
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 2
	ret
	
TextStopSFX::
	callacross FXHammer_Stop
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 1
	ret
	
	
TextPlayMapMusic::
	ld a, [wMapMusicID]
	call DS_Init
	ld a, 1
	ret
	
	
OverrideTextboxPalette::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld e, a
	ld d, [hl]
	or d
	jr nz, .normalLoad
	ld de, EvieDefaultPalette
	ld a, [wPlayerGender]
	and a
	jr z, .normalLoad
	ld de, TomDefaultPalette
.normalLoad
	ld c, 1
	callacross LoadBGPalette
	ld a, 3
	ret
	
CloseTextbox::
	callacross DisableTextbox
	ld a, 1
	ret
	
	
TextGetFlag::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld d, [hl]
	ld e, a
	call GetFlag
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3
	
	res TEXT_ZERO_FLAG, [hl]
	ret c ; If the flag is set, then it's NZ
	set TEXT_ZERO_FLAG, [hl]
	ret
	
TextSetFlag::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld d, [hl]
	ld e, a
	call SetFlag
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3
	ret
	
TextResetFlag::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld d, [hl]
	ld e, a
	call ResetFlag
	
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	ld a, 3
	ret
	
TextToggleFlag::
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld d, [hl]
	ld e, a
	call ToggleFlag
	ld a, 3
	ret
	
	
TextLoadMap::
	ld hl, wDigitBuffer + 2
	ld a, [hld]
	ld [wTargetWarpID], a
	ld c, [hl]
	
	; Ususally a macro is used instead, but it would cause a bank 0 load, which isn't good practice.
	ld b, 1
	ld hl, LoadMap_Hook
	call CallAcrossBanks
	
	ld a, 3
	ret
	
	
TextStartAnim::
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	
	ld hl, wDigitBuffer + 1
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	push hl
	call StartAnimation
	pop hl
	jr z, .allocationFailed
	ld e, [hl] ; Get ID of the slot to be used
	ld d, 0
	
	ld hl, wActiveAnimations + 8
.getAllocatedID
	ld a, [hld]
	inc a
	jr nz, .getAllocatedID
	ld a, [hl] ; Get the ID of the last animation
	; Since it's the one that was just allocated
	
	ld hl, wTextAnimationSlots
	add hl, de
	ld [hl], a
	ld a, 5
	ret
	
.allocationFailed
	xor a ; Try again
	ret
	
TextEndAnim::
	ld hl, wTextFlags
	set TEXT_SAME_FRAME_FLAG, [hl]
	
	ld a, [wDigitBuffer + 1]
	and $07
	ld l, a
	ld h, 0
	ld de, wTextAnimationSlots
	add hl, de
	ld b, [hl]
	
	ld a, $FF
	ld [hl], a
	cp b ; Don't end slot if it was empty
	call nz, EndAnimation
	
	ld a, 2
	ret
	
	
TextPlayAnims::
	ld hl, wAnimation0_linkID
	ld de, 8
	ld b, e ; ld b, 8
.freezeAnims
	set 4, [hl]
	add hl, de
	dec b
	jr nz, .freezeAnims
	
	ld bc, wTextAnimationSlots
.unfreezeTextAnims
	ld a, [bc]
	inc a
	jr z, .slotEmpty
	
	dec a
	and $07
	add a, a
	add a, a
	add a, a
	add a, LOW(wAnimation0_linkID)
	ld l, a
	adc a, HIGH(wAnimation0_linkID)
	sub l
	ld h, a
	res 4, [hl]
	
.slotEmpty
	inc bc
	dec e
	jr nz, .unfreezeTextAnims
	
	
.play
	rst waitVBlank
	call PlayAnimations
	call ProcessNPCs
	call ExtendOAM
	ld a, 1
	ld [wTransferSprites], a
	
	ld hl, wDigitBuffer + 1
	ld a, [hl]
	and $F8
	add a, 8
	jr nz, .decrementFrame
	
	; Check if target animation is playing
	ld a, [hl]
	and $07
	ld l, a
	ld h, 0
	ld bc, wTextAnimationSlots
	add hl, bc
	ld b, [hl]
	ld hl, wActiveAnimations
.lookUpSlot
	ld a, [hli]
	cp b
	jr z, .play ; If animation is still playing, keep on truckin'
	inc a
	jr nz, .lookUpSlot
	jr .stopPlaying ; If animation isn't running anymore, stop
	
.decrementFrame
	dec [hl]
	jr nz, .play
.stopPlaying
	
	
	ld hl, wAnimation0_linkID
	ld de, 8
	ld b, e ; ld b, 8
.unfreezeAnims
	res 4, [hl]
	add hl, de
	dec b
	jr nz, .unfreezeAnims
	
	ld a, 2
	ret

