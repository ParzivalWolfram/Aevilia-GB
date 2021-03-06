

INCLUDE "macros.asm"
INCLUDE "constants.asm"


SECTION "Map pointers", ROMX[$4000]
	
MapROMBanks:: ; MAKE SURE THIS IS 256-BYTE ALIGNED!!
	db BANK(StarthamMap)
	db BANK(TestHouse)
	db BANK(IntroMap)
	db BANK(StarthamForestMap)
	db BANK(PlayerHouse)
	db BANK(PlayerHouse2F)
	db BANK(StarthamHouse2)
	db BANK(StarthamLargeHouse)
	
MapPointers::
	dw StarthamMap
	dw TestHouse
	dw IntroMap
	dw StarthamForestMap
	dw PlayerHouse
	dw PlayerHouse2F
	dw StarthamHouse2
	dw StarthamLargeHouse


; ** Map header structure : **
; Byte       - Tileset ID
; Word       - Map script pointer
;              (must be in same bank as map)
; Byte       - Map width
; Byte       - Map height
; Word       - Map loading script pointer
; Byte       - Number of interactions
; Int_stream - Interactions, stored sequentially
;   Byte     - A constant identifying the following structure
;   Struct   - The corresponding structure
; Bytestream - Blocks


INCLUDE "maps/startham.asm"
INCLUDE "maps/testhouse.asm"
INCLUDE "maps/intro.asm"
INCLUDE "maps/startham_forest.asm"
INCLUDE "maps/playerhouse.asm"
INCLUDE "maps/playerhouse2f.asm"
INCLUDE "maps/starthamhouse2.asm"
INCLUDE "maps/starthamlargehouse1f.asm"
