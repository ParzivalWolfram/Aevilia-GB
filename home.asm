
INCLUDE "macros.asm"
INCLUDE "constants.asm"


SECTION "NULL", ROM0[$0000]
NULL::
Null::
null:
	ds 0 ; lol


INCLUDE "home/restarts.asm"
INCLUDE "home/interrupts.asm"

INCLUDE "home/utilities.asm"
	
	
SECTION "Home", ROM0[$0100]

Start::
	di ; Make sure nothing gets in the way
	ld e, a ; Save initial A for console check
	jr Init ; Skip over header
	
; Allocate header space for header.
; (Which will be generated by RGBFix)
; Must initialize to 0, otherwise slight conflicts arise
	dbfill ($0150 - $0104), 0
	
	
Init::
	; The init saves the original a in e, which isn't used for the duration of this init
	; We still need to save b's bit 0 to adjust palettes for GBA's.
	ld a, b ; a is safe now, so let's use it
	and $01 ; Only save bit 0, only one that matters (if it's set, it's GBA)
	ldh [hConsoleType], a
	ld sp, $D000 ; Put SP out of HRAM to fixed WRAM (push will write to $CFFF then $CFFE ;)
	
.waitVBlank
	ldh a, [rLY]
	cp LY_VBLANK
	jr nz, .waitVBlank
	xor a
	ld [rLCDC], a ; Shut screen down for init
	ld [rNR52], a ; Kill sound during init
	ld [rIF], a ; Clear all interrupts
	
	; First step of initializing the game : make sure *all* memory is in a known state
	; Maybe I'm clearing too much, but heh, at least I won't get any unexpected errors
	
	ld hl, $C000
	ld bc, $1000 - 4 ; The last four bytes are stack bytes, and this is the highest point `Fill` will reach. Clearing them would cause it to return to $0000, oopsies!
	xor a
	call Fill ; Clear WRAM bank 0
	
	; We now clear all WRAM banks ; on DMG, we will only clear bank 1
	ld d, 1
	ld a, e
	cp $11
	jr nz, .clearOnlyOneBank ; Skip setting VRAM bank, and run loop only once
	
	ld d, 7 ; WRAM bank ID
.clearWRAMBanks
	ld a, d
	ld [rSVBK], a
.clearOnlyOneBank
	ld hl, $D000
	ld b, $10 ; bc = $1000 'cause c = 0 from "call Fill"
.clearWRAMX
	xor a
	call Fill ; Clear WRAM bank d
	
	dec d ; Clear banks 7 to 1 (in this order)
	jr nz, .clearWRAMBanks

	; Don't clear the first few bytes, they are either already initialized or will be later before any read
	ld c, hHeldButtons & $FF
.clearHRAM
	xor a
	ld [$ff00+c], a
	inc c
	dec a ; a = $FF
	cp c
	jr nz, .clearHRAM ; Don't clear $FFFF, we'll set it a bit later
	
	; Now, we clear both VRAM banks (unless on DMG)
	inc c
	ld a, e
	cp $11
	push af ; Save that comparison's result for later
	jr nz, .clearOnlyOneVRAMBank ; Skip setting VRAM bank, and keep d to 0 so loop only runs once
	inc d ; d = 1 from clearing WRAM
.clearOneVRAMBank
	ld a, d
	ld [rVBK], a
.clearOnlyOneVRAMBank
	ld hl, $8000
	ld b, $20 ; bc = $2000
.clearVRAM
	xor a
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, .clearVRAM
	
	dec d ; Jump doesn't occur when underflowing from 0, which is what we want
	jr z, .clearOneVRAMBank
	
	; VRAM Bank is loaded, so we'll write stuff there.
	; a is zero, btw
	ld [rWX], a
	ld [rWY], a
	
	ld hl, $FE00
	ld c, $A0
	; a = 0
.clearOAM
	ld [hl], a
	inc l ; Can't use 16-bit inc/dec on DMG, thus no `rst fill` (CGB would have no problem, but this code is shared by DMG)
	dec b
	jr nz, .clearOAM
	
	inc a ; a = 1 = BANK(TextTiles)
	ldh [hCurRAMBank], a
	rst bankswitch

	xor a
	ld [rSTAT], a
	ld a, LY_VBLANK
	ld [rLYC], a ; Default for our purposes
	
	ldh a, [hConsoleType]
	and a
	ld a, $80
	jr nz, .isGBA ; Enable graphics compensation by default if on a GBA
	xor a
.isGBA
	ldh [hGFXFlags], a
	
	ld c, $81
	callacross LoadFont
	ld c, 0
	callacross LoadFont
	
	; Init tilemap
	ld a, 1
	ld [rVBK], a
	ld hl, vTileMap0
	ld c, TITLE_NAME_DEST - vTileMap0
	rst fill
	; Put emphasis on the game's name (will be overwritten if we are on DMG)
	ld c, 10 ; Name's length, make sure to update if needed
	ld a, $09
	rst fill
	ld hl, TITLE_NAME_DEST + 10
	ld bc, vTileMap1 - (TITLE_NAME_DEST + 10)
	ld a, 1
	call Fill
	xor a
	ld [rVBK], a
	
	; Initialize sound engine with no music
	call DS_Stop
	
	; Display "AEVILIA GB" on-screen
	ld hl, AeviliaStr
	ld de, TITLE_NAME_DEST
	rst copyStr
	
	; a = 0
	ld [rIF], a ; Clear all requested interrupts before enabling them
	
	ld a, %00011 ; VBlank and STAT ints
	ld [rIE], a
	
	; Now we're going to check for the current console
	; If we're on a DMG, we will diverge to a different init that also displays a GBC-only message
	pop af ; Only thing that matters here are flags (but a will also be the same as initial one)
	jp nz, InitGBPalAndSryScreen
	
	xor a
	ld hl, GrayPalette
	call LoadBGPalette
	ld a, 1
	ld hl, DefaultPalette
	call LoadBGPalette
	
	; Enable LCD, set window to $9C00, enable it, (don't care about BG location, it's set by VBlank anyways), set sprites to 8x8 and enable them, AND enable background & window
	; That was one big comment.
	ld a, %11100011
	ld [rLCDC], a
	
	ei
	
	
THE_CONSTANT = 42
	
	; We're going to check for crappy emulators (which don't emulate Echo RAM)
	; #BGBIsLife
	ld a, THE_CONSTANT
	ld [wSaveA], a
	ld a, [wSaveA | $2000] ; Equivalent location in echo RAM
	cp THE_CONSTANT ; Check is change has been reflected
	jr z, .hasEchoRAM
	; Echo RAM is not emulated? Warn the user!
	
	; This will copy the full blob of text, which is only one string! ^^
	ld hl, VBAText
	ld de, wFixedTileMap + SCREEN_WIDTH
	rst copyStr
	
	inc a ; a = 1
	ldh [hTilemapMode], a ; Switch to fixed tile map
	ld hl, wTransferRows + 9 ; Transfer all of 'em rows!
	ld c, SCREEN_HEIGHT - 1
	rst fill
	
	; Make sure message is fully displayed
	ld bc, SCREEN_HEIGHT - 2
	call DelayBCFrames
	
.noEchoRAMLoop
	rst waitVBlank ; Wait for joypad input update & reduce power consumption
	ldh a, [hPressedButtons]
	and BUTTON_A ; Wait for A to be pressed
	jr z, .noEchoRAMLoop
	
	; Reset graphics
	ld hl, wFixedTileMap + SCREEN_WIDTH
	ld bc, SCREEN_WIDTH * (SCREEN_HEIGHT - 1)
	dec a
	call Fill
	inc a
	ld hl, wTransferRows + 9
	ld c, SCREEN_HEIGHT - 1
	rst fill
	
	; Leave enough time for GFX to be transferred to VRAM
	ld bc, SCREEN_HEIGHT + 10
	call DelayBCFrames
	
	ldh [hTilemapMode], a
	
	; a = CONSOLE_CRAPPY (0)
	jp .gotConsoleType
	
.hasEchoRAM
	ld hl, $FF6C ; Undocumented, GBC-only port
	ld [hl], 0 ; Only has bit 0 writable
	ld a, [hl]
	inc a
	inc a ; Will set 0 if and only if we read $FE
	jr z, .veryGoodAccuracy ; Correct behavior implies we are either on a GBC or on a GBA or on a really good emulator
	
	; Try to write to wram banks
	; This will fail on a DMG
	ld hl, $D000
	ld b, [hl]
	ld [hl], $C0
	ld a, 2
	call SwitchRAMBanks
	ld c, [hl]
	ld [hl], $DE
	dec a
	call SwitchRAMBanks
	ld a, [hl]
	cp $C0
	; So, we're not on a CGB (otherwise banking would have kicked in)
	; Wait, but... and the a register at startup??
	; Oooh. I get it.
	; We've been spoofed.
	jp nz, ScoldSpoofers
	; So we're neither on a CGB nor on a DMG, huh? :p
	ld [hl], b
	ld a, 2
	call SwitchRAMBanks
	ld [hl], c
	dec a
	call SwitchRAMBanks
	
	; 3DS VC doesn't flag rHDMA1 as readable, GG Nintendo
	; Pan Docs flagged those as R/W - they are write-only.
	ld c, LOW(rHDMA1)
	ld a, [c]
	inc a
	ld [c], a
	ld b, a
	ld a, [c]
	cp b
	ld a, CONSOLE_3DS ; Closer to being crap than decent
	jr nz, .gotConsoleType
	; This is a decent emulator, but not perfect
	jr .decentEmu
	
.veryGoodAccuracy
	di
	ld a, $20 ; Enable Mode 0
	ld [rSTAT], a
	ld a, 2
	ld [rIE], a ; Enable STAT int
	ld b, 0
	
.doHDMA
	ld c, LOW(rHDMA1)
	ld a, $E0
	ld [c], a
	inc c
	ld [c], a ; From $E0E0 (uh oh, Nintendo says not to do that)
	inc c
	ld a, $88
	ld [c], a
	inc c
	ld a, b
	ld [c], a ; To $88X0 (really anything is fine)
	inc c ; Leave C pointing to HDMA length
	
	xor a ; We need IF = 0 when HALT is hit
	ld [rIF], a
	; There's a 1-cycle flaw here, but I dunno how to do better...
	halt
	; Alright, we're perfectly synced with the PPU, and in Mode 2. What could go wrong, Mr. Emulator ?
	ld a, $80
	ld [c], a
	
	; Delay until HDMA occurs
	ld a, 13
.delay
	dec a
	jr nz, .delay
	ld a, b
	and a
	jr nz, .extraCycle
.extraCycle
	nop
	
	ld a, b
	xor $10 ; HDMA triggers here (2nd time)
	ld b, a ; or here (1st time)
	jr nz, .doHDMA
	
	; We're going to check if it behaved correctly
	xor a
	ld [rSTAT], a ; Disable Mode 2 int
	ld a, 3 ; Restore IE
	ld [rIE], a
	ei
	
	ld hl, $8800
	ld de, $47 << 8 | CONSOLE_AWESOME
.checkOneTile
	ld c, $10
.checkOneByte
	ld a, [rSTAT]
	and 2
	jr nz, .checkOneByte
	ld a, [hli]
	cp d
	jr nz, .awesomeEmu
	dec c
	jr nz, .checkOneByte
	ld a, $EE ; Opcode for "xor imm8"
	cp d
	ld d, a
	jr nz, .checkOneTile ; If we weren't checking for this tile, keep going
	
	
.thisIsGBC
	ldh a, [hConsoleType]
	and a
	ld a, CONSOLE_GBC
	jr z, .gotConsoleType
.decentEmu
	inc a
.gotConsoleType
	db $FE
.awesomeEmu
	ld a, e
	ldh [hConsoleType], a
	
	; We will now check SRAM
	ld a, SRAM_UNLOCK
	ld [SRAMEnable], a
	
	xor a
	ld [SRAMBank], a
	; Check if the SRAM's size is incorrectly set ; some emulators don't recognize 128k as a valid size, and instead default to 32k
	ld hl, $A000
	ld b, [hl] ; Get bank 0's value
	ld a, 4
	ld [SRAMBank], a
	ld a, [hl] ; Also get bank 4's value
	cp b ; If they don't match, we can't be in 32k mode
	jr nz, .not32k
	inc [hl] ; Modify bank 4's value
	xor a
	ld [SRAMBank], a
	ld a, [hl] ; Check bank 0's value again
	cp b ; Did it change?
	jr z, .coincidentalMatch
	ld a, 1 ; It did!
	ldh [hSRAM32kCompat], a
.coincidentalMatch
	ld a, 4
	ld [SRAMBank], a
	ld [hl], b ; Restore bank 4's value
.not32k
	
	ld a, BANK(sFirstBootPattern)
	ld [SRAMBank], a
	
	ld a, BANK(SRAMFirstBootPattern)
	rst bankswitch
	
	; We first check for a specific value, indicating the game has never powered up before
	; I might put a full block of data to check that instead, thusly increasing the accuracy of the check
	ld hl, SRAMFirstBootPattern
	ld de, sFirstBootPattern
	ld bc, sFirstBootPatternEnd - sFirstBootPattern
.compareFirstBootPattern
	ld a, [de]
	cp [hl]
	jr nz, .firstBootCopy ; First time the game powers up
	inc hl
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .compareFirstBootPattern
	
	ld hl, SRAMCommonPattern
	ld de, sCommonPattern
	ld bc, sCommonPatternEnd - sCommonPattern
.compareCommonPattern
	ld a, [de]
	cp [hl]
	jr nz, .patternsDontMatch ; SRAM isn't correct! Maybe an overflow, or bad SRAM bank write?
	inc hl
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .compareCommonPattern
	jr .patternsMatched
	
.firstBootCopy
	rst copyStr
	
	ld hl, SRAMCommonPattern
	ld de, sCommonPattern
	ld b, 1
	jr .skipSettingB
.patternsDontMatch
	ld b, 0
.skipSettingB
	rst copyStr ; Copy the pattern
	ld h, d
	ld l, e
	ld c, sFirstBootPattern - sCommonPatternEnd
	rst fill ; Reset void states
	inc a
	ld a, b
	and a
	ld de, SaveDestroyedText
	jr z, .notFirstBoot
	ld de, FirstTimeLoadingText
.notFirstBoot
	xor a
	ld [SRAMEnable], a
	ld [SRAMBank], a
	
	ld c, BANK(FirstTimeLoadingText)
	callacross ProcessText_Hook
	
	ld bc, 10
	call DelayBCFrames
	
.patternsMatched
	
	xor a
	ld [SRAMEnable], a
	ld [SRAMBank], a
	
	ldh a, [hGFXFlags]
	rla
	jr nc, .useGBCGfx
	ld hl, .gfxPickStrings
	ld de, $9902
	call CopyStrToVRAM
	ld e, $44
	call CopyStrToVRAM
	ld hl, $9944
.pickGFXModeLoop
	rst waitVBlank
	ldh a, [hPressedButtons]
	rra
	jr c, .useGBCGfx
	and (DPAD_LEFT | DPAD_RIGHT) >> 1
	jr z, .pickGFXModeLoop
	ld [hl], 0
	ld a, l
	xor $04 ^ $0A
	ld l, a
	ld [hl], $7F
	ldh a, [hGFXFlags]
	xor $80
	ldh [hGFXFlags], a
	push hl
	call ReloadPalettes
	pop hl
	jr .pickGFXModeLoop
	
.gfxPickStrings
	dstr "PICK COLOR MODE:"
	dstr $7F, "GBA   GBC"
.useGBCGfx
	
	homecall PlayIntro
	
IF DEF(DebugMode)
	ldh a, [hHeldButtons]
	and BUTTON_START
	homejump nz, HomeDebugMenu
ENDC
	
	; Init music, awww yea
	ld a, 1
	call DS_Fade
	ld a, MUSIC_FILESELECT
	ld [wCurrentMusicID], a
	call DS_Init
	
	; Move down to adjust for the upcoming screen
	ld a, $10
	ldh [hSCY], a
	
	; Load appropriate console palette and tiles
	ldh a, [hConsoleType]
	ld b, a
	add a, a
	add a, a
	add a, a
	add a, b ; Multiplied by 9
	push af
	ld de, ConsolePalettes
	add a, e
	ld e, a
	; Assume that can't overflow
	ld c, 1
	callacross LoadOBJPalette_Hook
	
	ld a, BANK(ConsoleTiles)
	rst bankswitch
	pop af
	ld de, VRAM_TILE_SIZE
	call MultiplyDEByA
	ld de, ConsoleTiles
	add hl, de
	ld de, vFileSelectConsoleTiles
	ld bc, VRAM_TILE_SIZE * 9
	call CopyToVRAMLite
	
	ld a, 1
	ld [wLoadedMap], a ; Tell the file select this is the first time it boots
	
FileSelect::
	; Draws file select screen and waits until the user selects a file
	homecall DrawFileSelect ; To save space in home bank, this is another bank
	
	; This function leaves SRAM open, close it
	xor a
	ld [SRAMEnable], a
	ld [SRAMBank], a
	
	; Display the text (they should all be in the same bank)
	ld b, BANK(ConfirmLoadText)
	homecall ProcessText
	ld hl, wTextFlags
	bit TEXT_ZERO_FLAG, [hl] ; If "NO" has been chosen, return to file select
	jr nz, .loadFile ; Try loading the file
	
.resetFileSelect
	ld a, BANK(AeviliaStr)
	rst bankswitch
	
	ld hl, AeviliaStr
	ld de, TITLE_NAME_DEST
	call CopyStrToVRAM
	
	ldh [hTilemapMode], a
	jr FileSelect
	
.restoreBackup
	ldh a, [hSRAM32kCompat]
	and a
	jr z, .notCompatMode
	
	ld b, BANK(CompatFileCorruptedText)
	ld hl, CompatFileCorruptedText
	homecall ProcessText
	ld a, 2
	jr .newFile
	
.notCompatMode
	xor a
	ld [wSaveA], a
	; File is invalid!!
	; We now need to restore the backup
	ld a, [wSaveFileID]
	add a, a
	add a, a
	ld d, a
.restoreBackupBank
	ld hl, $BFFF
	ld bc, $2000
.restoreBackupLoop
	ld a, d
	inc a
	inc a
	ld [SRAMBank], a
	ld e, [hl]
	ld a, d
	ld [SRAMBank], a
	ld [hl], e
	dec hl
	dec bc
	ld a, b
	or c
	jr nz, .restoreBackupLoop
	inc d
	bit 0, d
	jr nz, .restoreBackupBank
	
	homecall VerifyChecksums
	jp nz, .dontBackup ; Backup is valid, move on (don't backup file, it'd be redundant)
	
	ld hl, BackupCorruptedText
	ld b, BANK(BackupCorruptedText)
	homecall ProcessText
	ld a, [wSaveFileID]
	ld e, a
	jr .corruptedBackupNewFile
	
.loadFile
	xor a
	ld [wFadeSpeed], a
	
;	ld a, BANK(PlayerTiles)
	inc a ; Does the job in one less byte
	rst bankswitch
	
	ld a, BANK(sNonVoidSaveFiles)
	ld [SRAMBank], a
	ld a, SRAM_UNLOCK
	ld [SRAMEnable], a
	
	; Check if file has been deemed corrupted
	ld a, [wSaveA]
	and a
	jr nz, .restoreBackup ; If so then it needs to be restored
	
	; Check if file is empty
	ld hl, sNonVoidSaveFiles - 1
	ld a, [wSaveFileID]
	ld e, a
	add a, l
	ld l, a
	ld a, [hl]
	and a
	jr nz, .backupFile ; If file is non-empty and valid, then back it up
	
	; File is empty, init it to default file
	ldh a, [hSRAM32kCompat]
	and a
	ld a, 2
	jr nz, .newFile
.corruptedBackupNewFile
	ld a, e
	add a, a
	add a, a
.newFile
	push af
	ld [SRAMBank], a
	; Copy both "default" banks from ROM
	ld hl, DefaultSaveBank0
	ld de, sFile1Header0
	ld bc, $2000
	ld a, BANK(DefaultSaveBank0)
	call CopyAcross
	pop af
	inc a
	ld [SRAMBank], a
	; hl = DefaultSaveBank1
	ld de, sFile1Header1
	ld bc, $2000
	ld a, BANK(DefaultSaveBank1)
	call CopyAcross
	
	; Calculate checksums so all goes fine
	callacross CalculateFileChecksums_Hook
	
	; Now, slide into backup-ing code to initialize backup with default save file. Otherwise, it is possible to load an uninitialized backup, like so :
	; 1. Start a new file
	; 2. Save properly at least once
	; 3. Without loading the file, corrupt it (easiest method : reset while saving, since the file is voluntarily corrupted while saving to prevent such abuse)
	; 4. Accept to restore from backup
	; 5. Done! (Game will probably crash or load test map, as of writing these lines)
	; If the backup is invalid it will be trapped, but otherwise...
	
.backupFile
	ldh a, [hSRAM32kCompat]
	and a
	jr nz, .dontBackup ; SRAM32k has no backups (there's just no room for them)
	
	ld a, [wSaveFileID]
	add a, a
	add a, a
	ld d, a
.backupBank
	ld hl, sFile1Header0
	ld bc, $2000
.backupLoop
	ld a, d
	ld [SRAMBank], a
	ld e, [hl]
	ld a, d
	xor 2
	ld [SRAMBank], a
	ld [hl], e
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .backupLoop
	inc d
	bit 0, d
	jr nz, .backupBank
	
.dontBackup
	; Clear what the Option screen leaves
	ld hl, $99C1
	xor a
	ld c, 3
	call FillVRAMLite
	ld l, $D0
	ld c, $B0
	call FillVRAMLite

	callacross LoadFile
FileLoaded::
	xor a
	ld [SRAMEnable], a
	ld [SRAMBank], a
	
	; Scramble RNG a bit to avoid save files being too savestate-like
	ld a, [rDIV]
	ld hl, hRandIntLow
	add a, [hl]
	ld [hli], a
	jr nc, .noCarry
	inc [hl]
.noCarry
	
	ld a, 1
	call SwitchRAMBanks
	
	homecall LoadPlayerGraphics
	
	xor a
	ldh [hPressedButtons], a ; Clear all buttons
	ldh [hHeldButtons], a
	ldh [hTilemapMode], a
	
	dec a
	ld [wLoadedTileset], a ; Force loading tileset
	ld [wCurrentMusicID], a ; Force changing musics
	
	ld a, BANK(AnimationCopyTiles)
	rst bankswitch
	ld hl, wAnimationGfxHooks
.loadAnimGfx
	ld de, 8
	ld a, [hl]
	inc a
	jr z, .skipHook
	
	ld a, $FF
	ld [hli], a ; Make room (the point is that all hooks will be shuffled, but preserved)
	ld de, wLargerBuf
	ld c, 6
	rst copy
	push hl
	call AnimationCopyTiles
	pop hl
	ld de, 1
	
.skipHook
	add hl, de
	ld a, l
	sub LOW(wAnimationGfxHook7_animID + 8)
	jr nz, .loadAnimGfx
	
	
	ld a, [wLoadedMap] ; Get map ID, set by save file
	call LoadMap + 3 ; + 3 to skip putting a into wLoadedMap... :p
	
INCLUDE "home/overworld.asm"
	
	
SECTION "Konami keys", ROM0,ALIGN[8]
KonamiCheatKeys::
	db $40, $40, $80, $80, $20, $10, $20, $10, $02, $01, $00
	
	
INCLUDE "home/handlers.asm"
INCLUDE "home/utilities2.asm"

INCLUDE "home/map.asm"
INCLUDE "home/flags.asm"
INCLUDE "home/strings.asm"

