\ 6502 Emulator in FORTH
\ Copyright (C) 2021-2023 Alexandre Dumont <adumont@gmail.com>
\ SPDX-License-Identifier: GPL-3.0-only
\
\ Host Forth is gForth
\ Target CPU is 65C02 variant

HEX

\ Some compatibility words for gforth
: print_nibble $F AND DUP $A >= IF $67 + THEN $30 XOR EMIT ;
: C. $FF AND $10 /MOD print_nibble print_nibble SPACE ;
\ : GETC BEGIN KEY? UNTIL KEY ;   \ blocking
: GETC KEY? IF KEY EXIT THEN 0 ;  \ non-blocking
: 2+ 1+ 1+ ;
: EXEC EXECUTE ;
: NEG 0 SWAP - ;
: NOT NEG 1 - ;
: CLS CLEARSTACK ;

: C? C@ C. ;
\ : CELLS CELL * ;

CREATE _A  0 C,   CREATE _X  0 C,   CREATE _Y    0 C,
CREATE _SP 0 C,   CREATE _PC 0  ,   CREATE _P  $30 C,

: LDP  ( byte -- ) $30 OR _P C! ;

CREATE OPCODES $100 CELLS ALLOT
CREATE RAM $10000 ALLOT \ Full 6502 memory space
\ 0000-00FF ZP
\ 0100-01FF 6502 Stack
\ 0200-02FD user memory
$F004 CONSTANT IN_CHAR
$F001 CONSTANT OU_CHAR

\ Target RAM operations
DEFER READ_HOOK
DEFER WRIT_HOOK

: TC@ ( addr -- byte ) READ_HOOK ( ELSE ) RAM + C@ ;
: TC! ( byte addr -- ) WRIT_HOOK ( ELSE ) RAM + C! ;
: T@  ( addr -- word )
  DUP TC@       \ LO
  SWAP 1+ TC@   \ HI
  $100 * + \ LO HI --> HILO
;

: CHAR_IN? ( addr -- byte ) DUP IN_CHAR  = IF DROP GETC RDROP THEN ;
: CHAR_OU? ( byte addr -- ) DUP OU_CHAR  = IF DROP EMIT RDROP THEN ;

' CHAR_IN? IS READ_HOOK
' CHAR_OU? IS WRIT_HOOK

0000 VALUE THERE \ Target HERE
: TC, ( b -- ) THERE TC!   THERE 1+ TO THERE ;

\ -- PC --

: _PC! $FFFF AND _PC ! ;

\ Fetch a BYTE and advance PC by 1
: BYTE@ ( -- byte )
  _PC @ DUP 1+ _PC! TC@
;

\ Fetch a WORD and advance PC by 2
: WORD@ ( -- byte )
  _PC @ DUP 2+ _PC! T@
;

: DUMPPC _PC @ DUP 3 + SWAP DO I TC@ C. LOOP ;
: TDUMP ( t-addr n -- ) SWAP RAM + SWAP DUMP ;

1 VALUE TRACE  \ flag, show Status or not in NEXT

: BIN. 8 0 DO DUP $80 AND IF ." 1" ELSE ." 0" THEN 2* LOOP DROP ;

: STATUS
  CR #17 spaces ." NV-BDIZC"
  CR ." A:" _A C? ." X:" _X C? ." Y:" _Y C?
     ." P:" _P C@ DUP BIN. ." :" C. ." SP:" _SP C? ." PC:" _PC ? ." > " DUMPPC ;

-1 VALUE LASTINSTR

CREATE FREQ $100 CELLS ALLOT
CREATE XEQTIME $100 CELLS ALLOT
0 VALUE startTime

: STAT( utime DROP TO startTime ;
: )STAT
  1 FREQ LASTINSTR CELLS + +!
  utime DROP startTime - \ time spent to run the instruction in us
  XEQTIME LASTINSTR CELLS + +!
;

: STATS DECIMAL $100 0 DO CR I . FREQ I CELLS + @ . XEQTIME I CELLS + @ . LOOP HEX ;
: RESETSTATS
  FREQ $100 CELLS 0 FILL
  XEQTIME $100 CELLS 0 FILL
;
RESETSTATS

: NEXT
  STAT(
  ( FETCH   ) BYTE@ DUP TO LASTINSTR
  ( DECODE  ) CELLS OPCODES + @
  ( EXECUTE ) EXEC
  )STAT
  TRACE IF STATUS THEN ;

DEFER BREAKPOINT

\ examples breakpoints words:
\ :NONAME _A C@ 1 = ; IS BREAKPOINT \ break when A=1
\ :NONAME C>    1 = ; IS BREAKPOINT \ break when C is set

\ Default breakpoint is when last instr. was BRK ($00)
: BPONBRK LASTINSTR $00 = ;
' BPONBRK IS BREAKPOINT

\ Breakpoint on infinite loop (PC won't change)
0 VALUE LASTPC
: BPONLOOP ( -- f ) _PC @ DUP LASTPC = SWAP TO LASTPC ;
: BPONLOOP ['] BPONLOOP IS BREAKPOINT ;

\ breakpoint on PC=PCBP
0 VALUE PCBP
: BPONPC ( -- f ) _PC @ PCBP = ;

\ set breakpoint at addr
: BREAKAT ( addr -- ) TO PCBP ['] BPONPC IS BREAKPOINT ;

\ run until breakpoint is reached
: RUN ( n -- )
  TRACE >R         \ save TRACE
   0 TO TRACE      \ no trace
  -1 TO LASTINSTR  \ reset last instr to -1
  BEGIN
    BREAKPOINT 0=
  WHILE
    NEXT
  REPEAT
  R> TO TRACE      \ restore TRACE
  STATUS ;

: BIND ( xt opcode -- )   CELLS OPCODES + ! ; \ saves XT in OPCODES table

\ -- Processor Flags handling
$80 VALUE 'N    \ Negative flag
$40 VALUE 'V    \ Overflow flag
$10 VALUE 'B    \ Break flag, set whenever a BRK instruction is executed, clear at all other times
$08 VALUE 'D    \ Decimal flag.
$04 VALUE 'I    \ Interrupt disabled. When this bit is set, the computer will not honor interrupts
$02 VALUE 'Z    \ Zero flag
$01 VALUE 'C    \ Carry flag

: CLEAR ( mask -- ) NOT _P C@ AND _P C! ;
: SET   ( mask -- )     _P C@ OR  _P C! ;
: UPDATE-FLAG ( b/f reg -- ) SWAP IF SET ELSE CLEAR THEN ;

: >N   ( b -- b ) DUP         'N AND 'N UPDATE-FLAG ; \ non-droppy
: >Z   ( b -- b ) DUP $FF AND     0= 'Z UPDATE-FLAG ; \ non-droppy
: >V   ( f --   )                    'V UPDATE-FLAG ; \ this one is droppy
: >C   ( f --   )                    'C UPDATE-FLAG ; \ this one is droppy
: >NZ >N >Z ;

: C>   (   -- f ) _P C@ 'C AND ;
: D>   (   -- f ) _P C@ 'D AND ;

\ 65C02 Addressing Modes

\ Mode   Id    Mode   Len 65c02  Mode Descr
\ ABS     0    a       3         Absolute a
\ AINDX   1    (a,x)   3    *    Absolute Indexed Indirect (a,x)
\ ABSX    2    a,x     3         Absolute Indexed with X a,x
\ ABSY    3    a,y     3         Absolute Indexed with Y a,y
\ IND     4    (a)     3         Absolute Indirect (a)
\ ACC     5    A       1         Accumulator A
\ IMM     6    #       2         Immediate Addressing #
\ IMPL    7    i       1         Implied i
\ PCR     8    r       2         Program Counter Relative r
\ STCK    9    s       1         Stack s
\ ZP     10    zp      2         Zero Page zp
\ INDX   11    (zp,x)  2         Zero Page Indexed Indirect (zp,x)
\ ZPX    12    zp,x    2         Zero Page Indexed with X zp,x
\ ZPY    13    zp,y    2         Zero Page Indexed with Y zp,y
\ ZIND   14    (zp)    2    *    Zero Page Indirect (zp)
\ INDY   15    (zp),y  2         Zero Page Indirect Indexed with Y (zp), y

\ Addressing modes words
: 'ZP   ( -- addr ) BYTE@ ;                     \ Zero Page zp
: 'ABS  ( -- addr ) WORD@ ;                     \ Absolute a
: 'ABSX ( -- addr ) WORD@ _X C@ + ;             \ Absolute Indexed with X a,x
: 'ABSY ( -- addr ) WORD@ _Y C@ + ;             \ Absolute Indexed with Y a,y
: 'ZPX  ( -- addr ) BYTE@ _X C@ + $FF AND ;     \ Zero Page Indexed with X zp,x
: 'ZPY  ( -- addr ) BYTE@ _Y C@ + $FF AND ;     \ Zero Page Indexed with Y zp,y
: 'INDX ( -- addr ) BYTE@ _X C@ + $FF AND T@ ;  \ Zero Page Indexed Indirect (zp,x)
: 'ZIND ( -- addr ) BYTE@ T@ ;                  \ Zero Page Indirect (zp)
: 'INDY ( -- addr ) BYTE@ T@ _Y C@ + ;          \ Zero Page Indirect Indexed with Y (zp), y

\ -- boilerplate opcodes definitions to be defined

:NONAME ( BRK STCK   ) 'B SET ." BRK" CR ; $00 BIND \ BRK s

: ?BRA ( f -- ) BYTE@ SWAP IF _PC @ SWAP DUP $80 AND IF FF00 OR NEG - ELSE + THEN _PC! ELSE DROP THEN ;
:NONAME ( BRA PCR    ) 1               ?BRA ; $80 BIND \ BRA r
:NONAME ( BEQ PCR    ) _P C@ 'Z AND    ?BRA ; $F0 BIND \ BEQ r
:NONAME ( BNE PCR    ) _P C@ 'Z AND 0= ?BRA ; $D0 BIND \ BNE r
:NONAME ( BCS PCR    )           C>    ?BRA ; $B0 BIND \ BCS r
:NONAME ( BCC PCR    )           C> 0= ?BRA ; $90 BIND \ BCC r
:NONAME ( BVS PCR    ) _P C@ 'V AND    ?BRA ; $70 BIND \ BVS r
:NONAME ( BVC PCR    ) _P C@ 'V AND 0= ?BRA ; $50 BIND \ BVC r
:NONAME ( BMI PCR    ) _P C@ 'N AND    ?BRA ; $30 BIND \ BMI r
:NONAME ( BPL PCR    ) _P C@ 'N AND 0= ?BRA ; $10 BIND \ BPL r

:NONAME ( SEC IMPL   ) 'C SET   ; $38 BIND \ SEC i
:NONAME ( SED IMPL   ) 'D SET   ; $F8 BIND \ SED i
:NONAME ( SEI IMPL   ) 'I SET   ; $78 BIND \ SEI i

:NONAME ( CLC IMPL   ) 'C CLEAR ; $18 BIND \ CLC i
:NONAME ( CLD IMPL   ) 'D CLEAR ; $D8 BIND \ CLD i
:NONAME ( CLI IMPL   ) 'I CLEAR ; $58 BIND \ CLI i
:NONAME ( CLV IMPL   ) 'V CLEAR ; $B8 BIND \ CLV i

: REG++ ( reg -- ) DUP C@ 1+   >NZ  SWAP C! ; \ no need to $FF MOD as we store with C!

:NONAME ( INC ACC    ) _A REG++ ; $1A BIND \ INC A
:NONAME ( INX IMPL   ) _X REG++ ; $E8 BIND \ INX i
:NONAME ( INY IMPL   ) _Y REG++ ; $C8 BIND \ INY i

: REG-- ( reg -- ) DUP C@ 1 -  >NZ  SWAP C! ; \ no need to $FF MOD as we store with C!

:NONAME ( DEC ACC    ) _A REG-- ; $3A BIND \ DEC A
:NONAME ( DEX IMPL   ) _X REG-- ; $CA BIND \ DEX i
:NONAME ( DEY IMPL   ) _Y REG-- ; $88 BIND \ DEY i

: MEM++ ( reg -- ) DUP TC@ 1+ >NZ SWAP TC! ;

:NONAME ( INC ABS    ) 'ABS   MEM++ ; $EE BIND \ INC a
:NONAME ( INC ABSX   ) 'ABSX  MEM++ ; $FE BIND \ INC a,x
:NONAME ( INC ZP     ) 'ZP    MEM++ ; $E6 BIND \ INC zp
:NONAME ( INC ZPX    ) 'ZPX   MEM++ ; $F6 BIND \ INC zp,x

: MEM-- ( reg -- ) DUP TC@ 1 - >NZ SWAP TC! ;

:NONAME ( DEC ABS    ) 'ABS   MEM-- ; $CE BIND \ DEC a
:NONAME ( DEC ABSX   ) 'ABSX  MEM-- ; $DE BIND \ DEC a,x
:NONAME ( DEC ZP     ) 'ZP    MEM-- ; $C6 BIND \ DEC zp
:NONAME ( DEC ZPX    ) 'ZPX   MEM-- ; $D6 BIND \ DEC zp,x

:NONAME ( JMP ABS    ) WORD@            _PC! ; $4C BIND \ JMP a
:NONAME ( JMP IND    ) WORD@         T@ _PC! ; $6C BIND \ JMP (a)
:NONAME ( JMP AINDX  ) WORD@ _X C@ + T@ _PC! ; $7C BIND \ JMP (a,x)

: LDA ( b -- ) >NZ _A C! ;
0 LDA \ will set the flags
:NONAME ( LDA IMM    ) BYTE@      LDA ; $A9 BIND \ LDA #
:NONAME ( LDA ZP     ) 'ZP    TC@ LDA ; $A5 BIND \ LDA zp
:NONAME ( LDA ABS    ) 'ABS   TC@ LDA ; $AD BIND \ LDA a
:NONAME ( LDA ABSX   ) 'ABSX  TC@ LDA ; $BD BIND \ LDA a,x
:NONAME ( LDA ABSY   ) 'ABSY  TC@ LDA ; $B9 BIND \ LDA a,y
:NONAME ( LDA ZPX    ) 'ZPX   TC@ LDA ; $B5 BIND \ LDA zp,x
:NONAME ( LDA INDX   ) 'INDX  TC@ LDA ; $A1 BIND \ LDA (zp,x)
:NONAME ( LDA ZIND   ) 'ZIND  TC@ LDA ; $B2 BIND \ LDA (zp)
:NONAME ( LDA INDY   ) 'INDY  TC@ LDA ; $B1 BIND \ LDA (zp),y

: STA ( addr -- ) _A C@ SWAP TC! ;
:NONAME ( STA ABS    ) 'ABS       STA ; $8D BIND \ STA a
:NONAME ( STA ZP     ) 'ZP        STA ; $85 BIND \ STA zp
:NONAME ( STA ZPX    ) 'ZPX       STA ; $95 BIND \ STA zp,x
:NONAME ( STA ABSX   ) 'ABSX      STA ; $9D BIND \ STA a,x
:NONAME ( STA ABSY   ) 'ABSY      STA ; $99 BIND \ STA a,y
:NONAME ( STA INDX   ) 'INDX      STA ; $81 BIND \ STA (zp,x)
:NONAME ( STA ZIND   ) 'ZIND      STA ; $92 BIND \ STA (zp)
:NONAME ( STA INDY   ) 'INDY      STA ; $91 BIND \ STA (zp),y

: STZ ( addr -- ) 0 SWAP TC! ;
:NONAME ( STZ ABS    ) 'ABS       STZ ; $9C BIND \ STZ a
:NONAME ( STZ ABSX   ) 'ABSX      STZ ; $9E BIND \ STZ a,x
:NONAME ( STZ ZP     ) 'ZP        STZ ; $64 BIND \ STZ zp
:NONAME ( STZ ZPX    ) 'ZPX       STZ ; $74 BIND \ STZ zp,x

: LDX ( b -- ) >NZ _X C! ;
:NONAME ( LDX IMM    ) BYTE@      LDX ; $A2 BIND \ LDX #
:NONAME ( LDX ZP     ) 'ZP    TC@ LDX ; $A6 BIND \ LDX zp
:NONAME ( LDX ABS    ) 'ABS   TC@ LDX ; $AE BIND \ LDX a
:NONAME ( LDX ABSY   ) 'ABSY  TC@ LDX ; $BE BIND \ LDX a,y
:NONAME ( LDX ZPY    ) 'ZPY   TC@ LDX ; $B6 BIND \ LDX zp,y

: STX ( addr -- ) _X C@ SWAP TC! ;
:NONAME ( STX ABS    ) 'ABS       STX ; $8E BIND \ STX a
:NONAME ( STX ZP     ) 'ZP        STX ; $86 BIND \ STX zp
:NONAME ( STX ZPY    ) 'ZPY       STX ; $96 BIND \ STX zp,y

: LDY ( b -- ) >NZ _Y C! ;
:NONAME ( LDY IMM    ) BYTE@      LDY ; $A0 BIND \ LDY #
:NONAME ( LDY ZP     ) 'ZP    TC@ LDY ; $A4 BIND \ LDY zp
:NONAME ( LDY ABS    ) 'ABS   TC@ LDY ; $AC BIND \ LDY a
:NONAME ( LDY ABSX   ) 'ABSX  TC@ LDY ; $BC BIND \ LDY a,x
:NONAME ( LDY ZPX    ) 'ZPX   TC@ LDY ; $B4 BIND \ LDY zp,x

: STY ( addr -- ) _Y C@ SWAP TC! ;
:NONAME ( STY ABS    ) 'ABS       STY ; $8C BIND \ STY a
:NONAME ( STY ZP     ) 'ZP        STY ; $84 BIND \ STY zp
:NONAME ( STY ZPX    ) 'ZPX       STY ; $94 BIND \ STY zp,x

: EOR ( b -- ) _A C@ XOR LDA ;
:NONAME ( EOR IMM    ) BYTE@      EOR ; $49 BIND \ EOR #
:NONAME ( EOR ABS    ) 'ABS   TC@ EOR ; $4D BIND \ EOR a
:NONAME ( EOR ABSX   ) 'ABSX  TC@ EOR ; $5D BIND \ EOR a,x
:NONAME ( EOR ABSY   ) 'ABSY  TC@ EOR ; $59 BIND \ EOR a,y
:NONAME ( EOR ZP     ) 'ZP    TC@ EOR ; $45 BIND \ EOR zp
:NONAME ( EOR ZPX    ) 'ZPX   TC@ EOR ; $55 BIND \ EOR zp,x
:NONAME ( EOR ZIND   ) 'ZIND  TC@ EOR ; $52 BIND \ EOR (zp)
:NONAME ( EOR INDX   ) 'INDX  TC@ EOR ; $41 BIND \ EOR (zp,x)
:NONAME ( EOR INDY   ) 'INDY  TC@ EOR ; $51 BIND \ EOR (zp),y

: ORA ( b -- ) _A C@ OR LDA ;
:NONAME ( ORA IMM    ) BYTE@      ORA ; $09 BIND \ ORA #
:NONAME ( ORA ABS    ) 'ABS   TC@ ORA ; $0D BIND \ ORA a
:NONAME ( ORA ABSX   ) 'ABSX  TC@ ORA ; $1D BIND \ ORA a,x
:NONAME ( ORA ABSY   ) 'ABSY  TC@ ORA ; $19 BIND \ ORA a,y
:NONAME ( ORA ZP     ) 'ZP    TC@ ORA ; $05 BIND \ ORA zp
:NONAME ( ORA ZPX    ) 'ZPX   TC@ ORA ; $15 BIND \ ORA zp,x
:NONAME ( ORA ZIND   ) 'ZIND  TC@ ORA ; $12 BIND \ ORA (zp)
:NONAME ( ORA INDX   ) 'INDX  TC@ ORA ; $01 BIND \ ORA (zp,x)
:NONAME ( ORA INDY   ) 'INDY  TC@ ORA ; $11 BIND \ ORA (zp),y

: _AND ( b -- ) _A C@ AND LDA ;
:NONAME ( AND IMM    ) BYTE@      _AND ; $29 BIND \ AND #
:NONAME ( AND ABS    ) 'ABS   TC@ _AND ; $2D BIND \ AND a
:NONAME ( AND ABSX   ) 'ABSX  TC@ _AND ; $3D BIND \ AND a,x
:NONAME ( AND ABSY   ) 'ABSY  TC@ _AND ; $39 BIND \ AND a,y
:NONAME ( AND ZP     ) 'ZP    TC@ _AND ; $25 BIND \ AND zp
:NONAME ( AND ZPX    ) 'ZPX   TC@ _AND ; $35 BIND \ AND zp,x
:NONAME ( AND ZIND   ) 'ZIND  TC@ _AND ; $32 BIND \ AND (zp)
:NONAME ( AND INDX   ) 'INDX  TC@ _AND ; $21 BIND \ AND (zp,x)
:NONAME ( AND INDY   ) 'INDY  TC@ _AND ; $31 BIND \ AND (zp),y

:NONAME ( NOP IMPL   ) ; $EA BIND \ NOP i

: PUSH ( byte -- ) _SP C@ SWAP OVER $0100 OR TC! 1 - _SP C! ;
:NONAME ( PHA STCK   ) _A C@ PUSH ; $48 BIND \ PHA s
:NONAME ( PHX STCK   ) _X C@ PUSH ; $DA BIND \ PHX s
:NONAME ( PHY STCK   ) _Y C@ PUSH ; $5A BIND \ PHY s
:NONAME ( PHP STCK   ) _P C@ PUSH ; $08 BIND \ PHP s

: PULL ( reg -- ) _SP C@ 1+ DUP _SP C! $0100 OR TC@ ;
:NONAME ( PLA STCK   ) PULL LDA ; $68 BIND \ PLA s
:NONAME ( PLX STCK   ) PULL LDX ; $FA BIND \ PLX s
:NONAME ( PLY STCK   ) PULL LDY ; $7A BIND \ PLY s
:NONAME ( PLP STCK   ) PULL LDP ; $28 BIND \ PLP s

\ ASL C <- [76543210] <- 0      N	Z	C

: ASL# ( byte -- ) 2* $100 /MOD >C >NZ ;
:NONAME ( ASL ACC    )       _A C@   ASL#    _A C! ; $0A BIND \ ASL A

: ASL ( addr -- ) DUP TC@ ASL# SWAP TC! ;
:NONAME ( ASL ABS    ) 'ABS  ASL ; $0E BIND \ ASL a
:NONAME ( ASL ABSX   ) 'ABSX ASL ; $1E BIND \ ASL a,x
:NONAME ( ASL ZP     ) 'ZP   ASL ; $06 BIND \ ASL zp
:NONAME ( ASL ZPX    ) 'ZPX  ASL ; $16 BIND \ ASL zp,x

\ LSR 0 -> [76543210] -> C

: LSR# ( byte -- ) DUP 1 AND >C 2/ >NZ ; \ LSR the byte and set NZC flags
:NONAME ( LSR ACC    ) _A C@ LSR# _A C! ; $4A BIND \ LSR A

: LSR ( addr -- ) DUP TC@ LSR# SWAP TC! ; \ we redefine LSR again here
:NONAME ( LSR ABS    ) 'ABS  LSR ; $4E BIND \ LSR a
:NONAME ( LSR ABSX   ) 'ABSX LSR ; $5E BIND \ LSR a,x
:NONAME ( LSR ZP     ) 'ZP   LSR ; $46 BIND \ LSR zp
:NONAME ( LSR ZPX    ) 'ZPX  LSR ; $56 BIND \ LSR zp,x

\ ROR C -> [76543210] -> C      N	Z	C

: ROR# ( byte -- ) DUP 1 AND C> $100 * SWAP >C OR 2/ >NZ ;
:NONAME ( ROR ACC    ) _A C@ ROR# _A C! ; $6A BIND \ ROR A

: ROR ( addr -- ) DUP TC@ ROR# SWAP TC! ;
:NONAME ( ROR ABS    ) 'ABS  ROR ; $6E BIND \ ROR a
:NONAME ( ROR ABSX   ) 'ABSX ROR ; $7E BIND \ ROR a,x
:NONAME ( ROR ZP     ) 'ZP   ROR ; $66 BIND \ ROR zp
:NONAME ( ROR ZPX    ) 'ZPX  ROR ; $76 BIND \ ROR zp,x

\ ROL C <- [76543210] <- C      N	Z	C

: ROL# ( byte -- ) 2* $100 /MOD SWAP C> OR >NZ SWAP >C ;
:NONAME ( ROL ACC    ) _A C@ ROL# _A C! ; $2A BIND \ ROL A

: ROL ( addr -- ) DUP TC@ ROL# SWAP TC! ;
:NONAME ( ROL ABS    ) 'ABS  ROL ; $2E BIND \ ROL a
:NONAME ( ROL ABSX   ) 'ABSX ROL ; $3E BIND \ ROL a,x
:NONAME ( ROL ZP     ) 'ZP   ROL ; $26 BIND \ ROL zp
:NONAME ( ROL ZPX    ) 'ZPX  ROL ; $36 BIND \ ROL zp,x

\ Info on overflow (V) flag here https://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
\ Info on decimal mode (BCD) http://www.6502.org/tutorials/decimal_mode.html#B

: >BIN ( bcd -- bin ) D> IF $FF AND $10 /MOD #10 * + THEN ; \ only when Decimal flag is set
: >BCD ( bin -- bcd ) D> IF #100 /MOD $100 * SWAP #10 /MOD  $10 * + + THEN ;

\ this version has something wrong with the overflow flag logic
\ : ADC ( byte -- )
\   >BIN DUP _A C@ >BIN DUP -ROT + C> + >BCD ( >BCD here ? )
\   $100 /MOD >C >NZ ( set NZ and C flags )
\   DUP ( or >BCD here ? )_A C!
\   SWAP OVER XOR -ROT XOR AND $80 AND >V ( set overflow flag ) ;

\ : OVERFLOW? ( data -- data ) DUP DUP -$80 <= SWAP $7F >= OR >V ; \non-droppy

: V? ( bcdM bcdA bcdResult -- v ) SWAP OVER XOR -ROT XOR AND $80 AND ;

: ADC ( byte -- )
  DUP >BIN _A C@ DUP >BIN ROT + C> + >BCD
  $100 /MOD >C DUP LDA
  V? >V ( set overflow flag ) ;

:NONAME ( ADC IMM    ) BYTE@      ADC ; $69 BIND \ ADC #
:NONAME ( ADC ZP     ) 'ZP    TC@ ADC ; $65 BIND \ ADC zp
:NONAME ( ADC ABS    ) 'ABS   TC@ ADC ; $6D BIND \ ADC a
:NONAME ( ADC ABSX   ) 'ABSX  TC@ ADC ; $7D BIND \ ADC a,x
:NONAME ( ADC ABSY   ) 'ABSY  TC@ ADC ; $79 BIND \ ADC a,y
:NONAME ( ADC ZPX    ) 'ZPX   TC@ ADC ; $75 BIND \ ADC zp,x
:NONAME ( ADC INDX   ) 'INDX  TC@ ADC ; $61 BIND \ ADC (zp,x)
:NONAME ( ADC ZIND   ) 'ZIND  TC@ ADC ; $72 BIND \ ADC (zp)
:NONAME ( ADC INDY   ) 'INDY  TC@ ADC ; $71 BIND \ ADC (zp),y

\ : BIN-SBC ( byte -- )
\   NOT $FF AND DUP _A C@ DUP ROT + C> +
\   $100 /MOD >C DUP
\   LDA
\   V? >V ;

\ : BCD-SBC ( byte -- )
\   DUP >BIN
\   _A C@ DUP >BIN #100 +
\   ROT - C> - 1+
\   DUP >BCD $100 /MOD >C ( carry )
\   LDA
\   ROT NOT $FF AND -ROT \ 1complement the operand before calculing V
\   V? >V ;

\ : SBC1 D> IF BCD-SBC ELSE BIN-SBC THEN ;

: SBC ( byte -- )
  DUP >BIN
  _A C@ DUP >BIN
  D> IF #100 ELSE $100 THEN + \ because my >BIN works only on 1 byte, $100 >BIN is $00
  ROT - C> + 1-
  DUP >BCD $100 /MOD 1 = >C ( carry )
  LDA
  ROT NOT FF AND -ROT \ 1complement the operand before calculing V
  V? >V ;

:NONAME ( SBC IMM    ) BYTE@      SBC ; $E9 BIND \ SBC #
:NONAME ( SBC ZP     ) 'ZP    TC@ SBC ; $E5 BIND \ SBC zp
:NONAME ( SBC ABS    ) 'ABS   TC@ SBC ; $ED BIND \ SBC a
:NONAME ( SBC ABSX   ) 'ABSX  TC@ SBC ; $FD BIND \ SBC a,x
:NONAME ( SBC ABSY   ) 'ABSY  TC@ SBC ; $F9 BIND \ SBC a,y
:NONAME ( SBC ZPX    ) 'ZPX   TC@ SBC ; $F5 BIND \ SBC zp,x
:NONAME ( SBC INDX   ) 'INDX  TC@ SBC ; $E1 BIND \ SBC (zp,x)
:NONAME ( SBC ZIND   ) 'ZIND  TC@ SBC ; $F2 BIND \ SBC (zp)
:NONAME ( SBC INDY   ) 'INDY  TC@ SBC ; $F1 BIND \ SBC (zp),y

\ CMP/CPX/CPY: performs A + 1complement(operand) + 1 and updates flags according to the result
: CMP ( byte A -- ) SWAP NOT $FF AND + 1+ $100 /MOD >C >NZ DROP ;
: CPA ( byte -- ) _A C@ CMP ;

:NONAME ( CMP IMM    ) BYTE@      CPA ; $C9 BIND \ CMP #
:NONAME ( CMP ZP     ) 'ZP    TC@ CPA ; $C5 BIND \ CMP zp
:NONAME ( CMP ABS    ) 'ABS   TC@ CPA ; $CD BIND \ CMP a
:NONAME ( CMP ABSX   ) 'ABSX  TC@ CPA ; $DD BIND \ CMP a,x
:NONAME ( CMP ABSY   ) 'ABSY  TC@ CPA ; $D9 BIND \ CMP a,y
:NONAME ( CMP ZPX    ) 'ZPX   TC@ CPA ; $D5 BIND \ CMP zp,x
:NONAME ( CMP INDX   ) 'INDX  TC@ CPA ; $C1 BIND \ CMP (zp,x)
:NONAME ( CMP ZIND   ) 'ZIND  TC@ CPA ; $D2 BIND \ CMP (zp)
:NONAME ( CMP INDY   ) 'INDY  TC@ CPA ; $D1 BIND \ CMP (zp),y

: CPX ( byte -- ) _X C@ CMP ;
:NONAME ( CPX IMM    ) BYTE@      CPX ; $E0 BIND \ CPX #
:NONAME ( CPX ZP     ) 'ZP    TC@ CPX ; $E4 BIND \ CPX zp
:NONAME ( CPX ABS    ) 'ABS   TC@ CPX ; $EC BIND \ CPX a

: CPY ( byte -- ) _Y C@ CMP ;
:NONAME ( CPY IMM    ) BYTE@      CPY ; $C0 BIND \ CPY #
:NONAME ( CPY ZP     ) 'ZP    TC@ CPY ; $C4 BIND \ CPY zp
:NONAME ( CPY ABS    ) 'ABS   TC@ CPY ; $CC BIND \ CPY a

:NONAME ( TAX IMPL   ) _A  C@   >NZ   _X  C! ; $AA BIND \ TAX i
:NONAME ( TXA IMPL   ) _X  C@   >NZ   _A  C! ; $8A BIND \ TXA i

:NONAME ( TAY IMPL   ) _A  C@   >NZ   _Y  C! ; $A8 BIND \ TAY i
:NONAME ( TYA IMPL   ) _Y  C@   >NZ   _A  C! ; $98 BIND \ TYA i

:NONAME ( TSX IMPL   ) _SP C@   >NZ   _X  C! ; $BA BIND \ TSX i
:NONAME ( TXS IMPL   ) _X  C@         _SP C! ; $9A BIND \ TXS i

:NONAME ( JSR ABS    ) _PC @ 1+ $FFFF AND $100 /MOD ( PCH ) PUSH ( PCL ) PUSH WORD@ _PC! ; $20 BIND \ JSR a

:NONAME ( RTS STCK   )                PULL ( PCL ) PULL ( PCH ) $100 * OR 1+ _PC! ; $60 BIND \ RTS s
:NONAME ( RTI STCK   ) PULL ( P ) LDP PULL ( PCL ) PULL ( PCH ) $100 * OR    _PC! ; $40 BIND \ RTI s

\ TRB A & M -> Z, !A & M -> M
: TRB ( addr -- ) DUP TC@ _A C@ 2DUP AND >Z DROP NOT AND SWAP TC! ;
:NONAME ( TRB ABS    ) 'ABS TRB ; $1C BIND \ TRB a
:NONAME ( TRB ZP     ) 'ZP  TRB ; $14 BIND \ TRB zp

\ TSB A & M -> Z, A | M -> M
: TSB ( addr -- ) DUP TC@ _A C@ 2DUP AND >Z DROP      OR SWAP TC! ;
:NONAME ( TSB ABS    ) 'ABS TSB ; $0C BIND \ TSB a
:NONAME ( TSB ZP     ) 'ZP  TSB ; $04 BIND \ TSB zp

\ :NONAME ( STP IMPL   ) ; $DB BIND \ STP i
\ :NONAME ( WAI IMPL   ) ; $CB BIND \ WAI i

: BIT# ( byte -- ) _A C@ AND >Z ; \ BIT IMM doesn't set NV http://forum.6502.org/viewtopic.php?f=2&t=2241&p=27243#p27239
: BIT  ( byte -- ) >N DUP 'V AND >V BIT# ;
:NONAME ( BIT IMM    ) BYTE@     BIT# ; $89 BIND \ BIT #
:NONAME ( BIT ABS    ) 'ABS  TC@ BIT  ; $2C BIND \ BIT a
:NONAME ( BIT ZP     ) 'ZP   TC@ BIT  ; $24 BIND \ BIT zp
:NONAME ( BIT ABSX   ) 'ABSX TC@ BIT  ; $3C BIND \ BIT a,x
:NONAME ( BIT ZPX    ) 'ZPX  TC@ BIT  ; $34 BIND \ BIT zp,x

: SMB ( addr mask -- ) OVER TC@ OR SWAP TC! ;
:NONAME ( SMB0 ZP    ) 'ZP %00000001 SMB ; $87 BIND \ SMB0 zp
:NONAME ( SMB1 ZP    ) 'ZP %00000010 SMB ; $97 BIND \ SMB1 zp
:NONAME ( SMB2 ZP    ) 'ZP %00000100 SMB ; $A7 BIND \ SMB2 zp
:NONAME ( SMB3 ZP    ) 'ZP %00001000 SMB ; $B7 BIND \ SMB3 zp
:NONAME ( SMB4 ZP    ) 'ZP %00010000 SMB ; $C7 BIND \ SMB4 zp
:NONAME ( SMB5 ZP    ) 'ZP %00100000 SMB ; $D7 BIND \ SMB5 zp
:NONAME ( SMB6 ZP    ) 'ZP %01000000 SMB ; $E7 BIND \ SMB6 zp
:NONAME ( SMB7 ZP    ) 'ZP %10000000 SMB ; $F7 BIND \ SMB7 zp

: RMB ( addr mask -- ) OVER TC@ AND SWAP TC! ;
:NONAME ( RMB0 ZP    ) 'ZP %11111110 RMB ; $07 BIND \ RMB0 zp
:NONAME ( RMB1 ZP    ) 'ZP %11111101 RMB ; $17 BIND \ RMB1 zp
:NONAME ( RMB2 ZP    ) 'ZP %11111011 RMB ; $27 BIND \ RMB2 zp
:NONAME ( RMB3 ZP    ) 'ZP %11110111 RMB ; $37 BIND \ RMB3 zp
:NONAME ( RMB4 ZP    ) 'ZP %11101111 RMB ; $47 BIND \ RMB4 zp
:NONAME ( RMB5 ZP    ) 'ZP %11011111 RMB ; $57 BIND \ RMB5 zp
:NONAME ( RMB6 ZP    ) 'ZP %10111111 RMB ; $67 BIND \ RMB6 zp
:NONAME ( RMB7 ZP    ) 'ZP %01111111 RMB ; $77 BIND \ RMB7 zp

: BBR ( mask -- ) 'ZP TC@ AND 0= ?BRA ;
:NONAME ( BBR0 PCR   ) %00000001 BBR ; $0F BIND \ BBR0 r
:NONAME ( BBR1 PCR   ) %00000010 BBR ; $1F BIND \ BBR1 r
:NONAME ( BBR2 PCR   ) %00000100 BBR ; $2F BIND \ BBR2 r
:NONAME ( BBR3 PCR   ) %00001000 BBR ; $3F BIND \ BBR3 r
:NONAME ( BBR4 PCR   ) %00010000 BBR ; $4F BIND \ BBR4 r
:NONAME ( BBR5 PCR   ) %00100000 BBR ; $5F BIND \ BBR5 r
:NONAME ( BBR6 PCR   ) %01000000 BBR ; $6F BIND \ BBR6 r
:NONAME ( BBR7 PCR   ) %10000000 BBR ; $7F BIND \ BBR7 r

: BBS ( mask -- ) 'ZP TC@ AND ?BRA ;
:NONAME ( BBS0 PCR   ) %00000001 BBS ; $8F BIND \ BBS0 r
:NONAME ( BBS1 PCR   ) %00000010 BBS ; $9F BIND \ BBS1 r
:NONAME ( BBS2 PCR   ) %00000100 BBS ; $AF BIND \ BBS2 r
:NONAME ( BBS3 PCR   ) %00001000 BBS ; $BF BIND \ BBS3 r
:NONAME ( BBS4 PCR   ) %00010000 BBS ; $CF BIND \ BBS4 r
:NONAME ( BBS5 PCR   ) %00100000 BBS ; $DF BIND \ BBS5 r
:NONAME ( BBS6 PCR   ) %01000000 BBS ; $EF BIND \ BBS6 r
:NONAME ( BBS7 PCR   ) %10000000 BBS ; $FF BIND \ BBS7 r

\ TESTS
: T?= ( a b -- )    OVER OVER = 0= IF SWAP CR ." ** Expected " C. ." got " C. ." ** " ABORT THEN 2DROP ;
: T?A ( b -- )      _A C@ T?= ;
: T?X ( b -- )      _X C@ T?= ;
: T?Y ( b -- )      _Y C@ T?= ;
: T?P ( b -- )      _P C@ T?= ;
: T?MEM ( addr b -- )  SWAP TC@ T?= ;

\ -- store a minimal program

: ORG   DUP TO THERE _PC! ;
: _     TC, ;

\ Test LDA IMM
\ $0200 ORG 0 _A C!
\ A9 _ FF _   \ 0000 LDA #$FF
\ NEXT $FF T?A $B0 T?P

\ Test STA ABS
\ $0200 ORG
\ 0 0222 TC!
\ 8D _ 22 _ 02 _  \ 0002 STA $0222
\ NEXT 0222 FF T?MEM

\ Test LDX, BNE, DEX
\ $0200    a2 0a     LDX #$0a
\ $0202    ca        DEX
\ $0203    d0 fd     BNE $0202

\ $0200 ORG A2 _ 0A _ CA _ D0 _ FD _

\ Test IO
\ AD FE 02  LDA $02fe
\ 1A        INC A
\ 8d ff 02  STA $02ff
\ d0 f8     BNE $0600

\ $0200 ORG AD _ FE _ 02 _ 1A _ 8D _ FF _ 02 _ D0 _ F7 _

\ $0200 ORG 18 _ A9 _ 30 _ 69 _ 70 _


\ Test SBC

\ : TEST-SBC
\   $100 0 DO
\     CLS 'C SET 'D CLEAR 10 LDA
\     CR _P C@ BIN. _A C? I C.
\     I SBC
\     ." SBC -> " _A C? _P C@ BIN.
\   LOOP
\ ;

\ : TEST-ADC
\   $100 0 DO
\     CLS 'C CLEAR 'D CLEAR 10 LDA
\     CR _P C@ BIN. _A C? I C.
\     I ADC
\     ." ADC -> " _A C? _P C@ BIN.
\   LOOP
\ ;

\ Address  Hexdump   Dissassembly
\ -------------------------------
\ $0600    a2 ff     LDX #$ff
\ $0602    9a        TXS
\ $0603    a0 0a     LDY #$0a
\ $0605    20 11 06  JSR $0611
\ $0608    18        CLC
\ $0609    69 01     ADC #$01
\ $060b    20 15 06  JSR $0615
\ $060e    88        DEY
\ $060f    d0 f4     BNE $0605
\ $0611    ad fe 02  LDA $02fe
\ $0614    60        RTS
\ $0615    8d ff 02  STA $02ff
\ $0618    60        RTS

\ 0600 ORG
\ A2 _ FF _ 9A _ A0 _ 0A _ 20 _ 11 _ 06 _ 18 _
\ 69 _ 01 _ 20 _ 15 _ 06 _ 88 _ D0 _ F4 _ AD _
\ FE _ 02 _ 60 _ 8D _ FF _ 02 _ 60 _

0 VALUE FD
0 VALUE LEN
\ S" test.bin" R/O OPEN-FILE THROW TO FD

\ load binary rom file to target addr
: load-rom ( t-addr filename )
  0 to fd
  R/O OPEN-FILE THROW TO FD
  DUP RAM +     ( addr in host )
  $10000 ROT -  ( max chars to read )
  FD            ( fd )
  read-file throw TO LEN
;

\ 0600 s" rom.bin" load-rom

\ create file-buffer $10000 allot

\ file-buffer $10000 FD read-file throw TO LEN

\ : read-byte ( addr len )
\   >R >R 0 0 R> R>
\   >NUMBER
\   >R >R DROP R> R> SWAP 1+ SWAP 1- ROT
\ ;

: n next ;
: RESET $FFFC T@ _PC! ;
: AlexForth $8000 s" forth-emu.bin" load-rom reset CR run ;
: AlexMon   $8000 s" monitor/monitor.bin" load-rom reset CR run ;
: Chatbot   $8000 s" chatbot/chatbot.bin" load-rom reset run ;

\ : mybrk _PC @ 8562 = ; ' mybrk IS BREAKPOINT

: s 0 TC! RUN 0 4 TDUMP 200 30 TDUMP ;

: demo1

  CR ." Address  Hexdump   Dissassembly"
  CR ." -------------------------------"
  CR ." $0600    a9 12     LDA #$12"
  CR ." $0602    85 30     STA $30"
  CR
  0600 ORG a9 _ 12 _ 85 _ 30 _
  00 _A C! 00 30 TC!
  status
  CR ." Use n to run step by step " CR
;

: demo2
  CR ." Address  Hexdump   Dissassembly"
  CR ." -------------------------------"
  CR ." $0600    a2 61     LDX #$61"
  CR ." $0602    8e 01 f0  STX $f001"
  CR ." $0605    e8        INX"
  CR ." $0606    e0 7b     CPX #$7b"
  CR ." $0608    d0 f8     BNE $0602"
  CR ." $060a    00        BRK"
  CR
  0600 ORG
  a2 _ 61 _ 8e _ 01 _ f0 _ e8 _ e0 _ 7b _ d0 _ f8 _ 00 _
  status
;

: demo3
  CR ." Execute alexmon, goto $3000 and type:" CR
  CR ." Address  Hexdump   Dissassembly"
  CR ." -------------------------------"
  CR ." $3000    a9 ff     LDA #$ff"
  CR ." $3002    85 30     STA $30"
  CR ." $3004    00        BRK"
  CR
  CR ." Then go back to 3000 and type j (JUMP)"
  00 _A C! 00 30 TC!
;

: demo4
  CR ." Execute alexforth" CR
;

: test1   $0000 s" tests/6502_functional_test.bin" load-rom reset $0400 org ;
: test2   $0000 s" tests/65C02_extended_opcodes_test.bin" load-rom reset $0400 org ;