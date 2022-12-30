\ 6502 Emulator in FORTH
\ Copyright (C) 2021-2022 Alexandre Dumont <adumont@gmail.com>
\ SPDX-License-Identifier: GPL-3.0-only
\
\ At the moment, host Forth is AlexFORTH on 6502
\ Target CPU is 65C02 variant

HEX

2 CONSTANT CELL

\ Some compatibility words for gforth
\ still need to change .( ) into ." "

\ 8 CONSTANT CELL
\ : print_nibble $F AND DUP $A >= IF $67 + THEN $30 XOR EMIT ;
\ : C. $FF AND $10 /MOD print_nibble print_nibble ;
\ : GETC BEGIN KEY? UNTIL KEY ;
\ : 2+ 1+ 1+ ;
\ : EXEC EXECUTE ;
\ : NOT $FFFF XOR ;
\ : NEG 0 SWAP - ;

: C? C@ C. ;
: CELLS CELL * ;

CREATE _A  0 C,   CREATE _X  0 C,   CREATE _Y  0 C,
CREATE _SP 0 C,   CREATE _PC 0  ,   CREATE _P  0 C,

CREATE OPCODES #256 CELLS ALLOT
CREATE RAM $100 3 * ALLOT \ 3 pages of RAM
\ 0000-00FF ZP
\ 0100-01FF 6502 Stack
\ 0200-02FD user memory
02FE CONSTANT IN_CHAR
02FF CONSTANT OUT_CHAR

\ Target RAM operations
: TC@ ( addr -- byte ) DUP IN_CHAR  = IF DROP GETC EXIT THEN RAM + C@ ;
: TC! ( byte addr -- ) DUP OUT_CHAR = IF DROP EMIT EXIT THEN RAM + C! ;
: T@  ( addr -- word )
  DUP TC@       \ LO
  SWAP 1+ TC@   \ HI
  $100 * + \ LO HI --> HILO
;

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

1 VALUE TRACE  \ flag, show Status or not in NEXT

: STATUS
  .( A:) _A C? .( X:) _X C? .( Y:) _Y C?
  .( P:) _P C? .( SP:) _SP C? .( PC:) _PC ? .( > ) DUMPPC CR ;

: NEXT
  ( FETCH   ) BYTE@
  ( DECODE  ) CELLS OPCODES + @
  ( EXECUTE ) EXEC
  TRACE IF STATUS THEN ;

: RUN ( n -- )
  TRACE >R      \ save TRACE
  0 TO TRACE    \ no trace
  ( n ) 0 DO NEXT LOOP
  R> TO TRACE ; \ restore TRACE

: BIND ( xt opcode -- )   CELLS OPCODES + ! ; \ saves XT in OPCODES table

\ -- Processor Flags handling
%10000000 VALUE 'N
%01000000 VALUE 'V
%00010000 VALUE 'B
%00001000 VALUE 'D
%00000100 VALUE 'I
%00000010 VALUE 'Z
%00000001 VALUE 'C

: CLEAR ( mask -- ) NOT _P C@ AND _P C! ;
: SET   ( mask -- )     _P C@ OR  _P C! ;
: UPDATE-FLAG ( b/f reg -- ) SWAP IF SET ELSE CLEAR THEN ;

: >NZ  \ always updated together
( >N ) ( b -- b ) DUP 'N AND 'N UPDATE-FLAG
( >Z ) ( b -- b ) DUP     0= 'Z UPDATE-FLAG ;
: >Z   ( b -- b ) DUP     0= 'Z UPDATE-FLAG ;
: >D   ( f -- f ) DUP        'D UPDATE-FLAG ;
: >V   ( f -- f ) DUP        'V UPDATE-FLAG ;
: >C   ( f -- f ) DUP        'C UPDATE-FLAG ;


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

\ -- boilerplate opcodes definitions to be defined

:NONAME ( BRK STCK   ) .( BRK) CR ; $00 BIND \ BRK s

\ :NONAME ( ADC INDX   ) ; $61 BIND \ ADC (zp,x)
\ :NONAME ( ADC ZIND   ) ; $72 BIND \ ADC (zp)
\ :NONAME ( ADC INDY   ) ; $71 BIND \ ADC (zp),y
\ :NONAME ( ADC IMM    ) ; $69 BIND \ ADC #
\ :NONAME ( ADC ABS    ) ; $6D BIND \ ADC a
\ :NONAME ( ADC ABSX   ) ; $7D BIND \ ADC a,x
\ :NONAME ( ADC ABSY   ) ; $79 BIND \ ADC a,y
\ :NONAME ( ADC ZP     ) ; $65 BIND \ ADC zp
\ :NONAME ( ADC ZPX    ) ; $75 BIND \ ADC zp,x
\ :NONAME ( AND INDX   ) ; $21 BIND \ AND (zp,x)
\ :NONAME ( AND ZIND   ) ; $32 BIND \ AND (zp)
\ :NONAME ( AND INDY   ) ; $31 BIND \ AND (zp),y
\ :NONAME ( AND IMM    ) ; $29 BIND \ AND #
\ :NONAME ( AND ABS    ) ; $2D BIND \ AND a
\ :NONAME ( AND ABSX   ) ; $3D BIND \ AND a,x
\ :NONAME ( AND ABSY   ) ; $39 BIND \ AND a,y
\ :NONAME ( AND ZP     ) ; $25 BIND \ AND zp
\ :NONAME ( AND ZPX    ) ; $35 BIND \ AND zp,x
\ :NONAME ( ASL ACC    ) ; $0A BIND \ ASL A
\ :NONAME ( ASL ABS    ) ; $0E BIND \ ASL a
\ :NONAME ( ASL ABSX   ) ; $1E BIND \ ASL a,x
\ :NONAME ( ASL ZP     ) ; $06 BIND \ ASL zp
\ :NONAME ( ASL ZPX    ) ; $16 BIND \ ASL zp,x

: ?BRA ( f -- ) BYTE@ SWAP IF _PC @ SWAP DUP $80 AND IF FF00 OR NEG - ELSE + THEN _PC! ELSE DROP THEN ;
:NONAME ( BRA PCR    ) 1               ?BRA ; $80 BIND \ BRA r
:NONAME ( BEQ PCR    ) _P C@ 'Z AND    ?BRA ; $F0 BIND \ BEQ r
:NONAME ( BNE PCR    ) _P C@ 'Z AND 0= ?BRA ; $D0 BIND \ BNE r
:NONAME ( BCS PCR    ) _P C@ 'C AND    ?BRA ; $B0 BIND \ BCS r
:NONAME ( BCC PCR    ) _P C@ 'C AND 0= ?BRA ; $90 BIND \ BCC r
:NONAME ( BVS PCR    ) _P C@ 'V AND    ?BRA ; $70 BIND \ BVS r
:NONAME ( BVC PCR    ) _P C@ 'V AND 0= ?BRA ; $50 BIND \ BVC r
:NONAME ( BMI PCR    ) _P C@ 'N AND    ?BRA ; $30 BIND \ BMI r
:NONAME ( BPL PCR    ) _P C@ 'N AND 0= ?BRA ; $10 BIND \ BPL r

\ :NONAME ( BIT IMM    ) ; $89 BIND \ BIT #
\ :NONAME ( BIT ABS    ) ; $2C BIND \ BIT a
\ :NONAME ( BIT ABSX   ) ; $3C BIND \ BIT a,x
\ :NONAME ( BIT ZP     ) ; $24 BIND \ BIT zp
\ :NONAME ( BIT ZPX    ) ; $34 BIND \ BIT zp,x

\ :NONAME ( SEC IMPL   ) ; $38 BIND \ SEC i
\ :NONAME ( SED IMPL   ) ; $F8 BIND \ SED i
\ :NONAME ( SEI IMPL   ) ; $78 BIND \ SEI i

\ :NONAME ( CLC IMPL   ) ; $18 BIND \ CLC i
\ :NONAME ( CLD IMPL   ) ; $D8 BIND \ CLD i
\ :NONAME ( CLI IMPL   ) ; $58 BIND \ CLI i
\ :NONAME ( CLV IMPL   ) ; $B8 BIND \ CLV i

\ :NONAME ( CMP INDX   ) ; $C1 BIND \ CMP (zp,x)
\ :NONAME ( CMP ZIND   ) ; $D2 BIND \ CMP (zp)
\ :NONAME ( CMP INDY   ) ; $D1 BIND \ CMP (zp),y
\ :NONAME ( CMP IMM    ) ; $C9 BIND \ CMP #
\ :NONAME ( CMP ABS    ) ; $CD BIND \ CMP a
\ :NONAME ( CMP ABSX   ) ; $DD BIND \ CMP a,x
\ :NONAME ( CMP ABSY   ) ; $D9 BIND \ CMP a,y
\ :NONAME ( CMP ZP     ) ; $C5 BIND \ CMP zp
\ :NONAME ( CMP ZPX    ) ; $D5 BIND \ CMP zp,x

\ :NONAME ( CPX IMM    ) ; $E0 BIND \ CPX #
\ :NONAME ( CPX ABS    ) ; $EC BIND \ CPX a
\ :NONAME ( CPX ZP     ) ; $E4 BIND \ CPX zp

\ :NONAME ( CPY IMM    ) ; $C0 BIND \ CPY #
\ :NONAME ( CPY ABS    ) ; $CC BIND \ CPY a
\ :NONAME ( CPY ZP     ) ; $C4 BIND \ CPY zp

: INCR ( reg -- ) DUP C@ 1+   >NZ  SWAP C! ; \ no need to $FF MOD as we store with C!

:NONAME ( INC ACC    ) _A INCR ; $1A BIND \ INC A
:NONAME ( INX IMPL   ) _X INCR ; $E8 BIND \ INX i
:NONAME ( INY IMPL   ) _Y INCR ; $C8 BIND \ INY i

:NONAME ( INC ABS    ) WORD@         DUP TC@ 1+ SWAP TC! ; $EE BIND \ INC a
:NONAME ( INC ABSX   ) WORD@ _X C@ + DUP TC@ 1+ SWAP TC! ; $FE BIND \ INC a,x
:NONAME ( INC ZP     ) BYTE@         DUP TC@ 1+ SWAP TC! ; $E6 BIND \ INC zp
:NONAME ( INC ZPX    ) BYTE@ _X C@ + DUP TC@ 1+ SWAP TC! ; $F6 BIND \ INC zp,x

: DECR ( reg -- ) DUP C@ 1 -  >NZ  SWAP C! ; \ no need to $FF MOD as we store with C!

:NONAME ( DEC ACC    ) _A DECR ; $3A BIND \ DEC A
:NONAME ( DEX IMPL   ) _X DECR ; $CA BIND \ DEX i
:NONAME ( DEY IMPL   ) _Y DECR ; $88 BIND \ DEY i

:NONAME ( DEC ABS    ) WORD@         DUP TC@ 1 - SWAP TC! ; $CE BIND \ DEC a
:NONAME ( DEC ABSX   ) WORD@ _X C@ + DUP TC@ 1 - SWAP TC! ; $DE BIND \ DEC a,x
:NONAME ( DEC ZP     ) BYTE@         DUP TC@ 1 - SWAP TC! ; $C6 BIND \ DEC zp
:NONAME ( DEC ZPX    ) BYTE@ _X C@ + DUP TC@ 1 - SWAP TC! ; $D6 BIND \ DEC zp,x

:NONAME ( JMP ABS    ) WORD@            _PC! ; $4C BIND \ JMP a
:NONAME ( JMP IND    ) WORD@         T@ _PC! ; $6C BIND \ JMP (a)
:NONAME ( JMP AINDX  ) WORD@ _X C@ + T@ _PC! ; $7C BIND \ JMP (a,x)

\ :NONAME ( JSR ABS    ) ; $20 BIND \ JSR a

\ :NONAME ( RTI STCK   ) ; $40 BIND \ RTI s
\ :NONAME ( RTS STCK   ) ; $60 BIND \ RTS s

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

: LDA ( b -- ) >NZ _A C! ;
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
:NONAME ( LDX ZPY    ) 'ZPY   TC@ LDA ; $B6 BIND \ LDX zp,y

: STX ( addr -- ) _X C@ SWAP TC! ;
:NONAME ( STX ABS    ) 'ABS       STX ; $8E BIND \ STX a
:NONAME ( STX ZP     ) 'ZP        STX ; $86 BIND \ STX zp
:NONAME ( STX ZPY    ) 'ZPY       STX ; $96 BIND \ STX zp,y

: LDY ( b -- ) >NZ _Y C! ;
:NONAME ( LDY IMM    ) BYTE@                        LDY ; $A0 BIND \ LDY #
:NONAME ( LDY ZP     ) 'ZP    TC@ LDY ; $A4 BIND \ LDY zp
:NONAME ( LDY ABS    ) 'ABS   TC@ LDY ; $AC BIND \ LDY a
:NONAME ( LDY ABSX   ) 'ABSX  TC@ LDY ; $BC BIND \ LDY a,x
:NONAME ( LDY ZPX    ) 'ZPX   TC@ LDY ; $B4 BIND \ LDY zp,x

: STY ( addr -- ) _X C@ SWAP TC! ;
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

\ :NONAME ( LSR ACC    ) ; $4A BIND \ LSR A
\ :NONAME ( LSR ABS    ) ; $4E BIND \ LSR a
\ :NONAME ( LSR ABSX   ) ; $5E BIND \ LSR a,x
\ :NONAME ( LSR ZP     ) ; $46 BIND \ LSR zp
\ :NONAME ( LSR ZPX    ) ; $56 BIND \ LSR zp,x

\ :NONAME ( NOP IMPL   ) ; $EA BIND \ NOP i

\ :NONAME ( PHA STCK   ) ; $48 BIND \ PHA s
\ :NONAME ( PHP STCK   ) ; $08 BIND \ PHP s
\ :NONAME ( PHX STCK   ) ; $DA BIND \ PHX s
\ :NONAME ( PHY STCK   ) ; $5A BIND \ PHY s
\ :NONAME ( PLA STCK   ) ; $68 BIND \ PLA s
\ :NONAME ( PLP STCK   ) ; $28 BIND \ PLP s
\ :NONAME ( PLX STCK   ) ; $FA BIND \ PLX s
\ :NONAME ( PLY STCK   ) ; $7A BIND \ PLY s

\ :NONAME ( ROL ACC    ) ; $2A BIND \ ROL A
\ :NONAME ( ROL ABS    ) ; $2E BIND \ ROL a
\ :NONAME ( ROL ABSX   ) ; $3E BIND \ ROL a,x
\ :NONAME ( ROL ZP     ) ; $26 BIND \ ROL zp
\ :NONAME ( ROL ZPX    ) ; $36 BIND \ ROL zp,x

\ :NONAME ( ROR ACC    ) ; $6A BIND \ ROR A
\ :NONAME ( ROR ABS    ) ; $6E BIND \ ROR a
\ :NONAME ( ROR ABSX   ) ; $7E BIND \ ROR a,x
\ :NONAME ( ROR ZP     ) ; $66 BIND \ ROR zp
\ :NONAME ( ROR ZPX    ) ; $76 BIND \ ROR zp,x

\ :NONAME ( SBC INDX   ) ; $E1 BIND \ SBC (zp,x)
\ :NONAME ( SBC ZIND   ) ; $F2 BIND \ SBC (zp)
\ :NONAME ( SBC INDY   ) ; $F1 BIND \ SBC (zp),y
\ :NONAME ( SBC IMM    ) ; $E9 BIND \ SBC #
\ :NONAME ( SBC ABS    ) ; $ED BIND \ SBC a
\ :NONAME ( SBC ABSX   ) ; $FD BIND \ SBC a,x
\ :NONAME ( SBC ABSY   ) ; $F9 BIND \ SBC a,y
\ :NONAME ( SBC ZP     ) ; $E5 BIND \ SBC zp
\ :NONAME ( SBC ZPX    ) ; $F5 BIND \ SBC zp,x

:NONAME ( TAX IMPL   ) _A  C@   >NZ   _X  C! ; $AA BIND \ TAX i
:NONAME ( TXA IMPL   ) _X  C@   >NZ   _A  C! ; $8A BIND \ TXA i

:NONAME ( TAY IMPL   ) _A  C@   >NZ   _Y  C! ; $A8 BIND \ TAY i
:NONAME ( TYA IMPL   ) _Y  C@   >NZ   _A  C! ; $98 BIND \ TYA i

:NONAME ( TSX IMPL   ) _SP C@   >NZ   _X  C! ; $BA BIND \ TSX i
:NONAME ( TXS IMPL   ) _X  C@         _SP C! ; $9A BIND \ TXS i

\ :NONAME ( TRB ABS    ) ; $1C BIND \ TRB a
\ :NONAME ( TRB ZP     ) ; $14 BIND \ TRB zp

\ :NONAME ( TSB ABS    ) ; $0C BIND \ TSB a
\ :NONAME ( TSB ZP     ) ; $04 BIND \ TSB zp

\ :NONAME ( STP IMPL   ) ; $DB BIND \ STP i
\ :NONAME ( WAI IMPL   ) ; $CB BIND \ WAI i

\ :NONAME ( SMB0 ZP    ) ; $87 BIND \ SMB0 zp
\ :NONAME ( SMB1 ZP    ) ; $97 BIND \ SMB1 zp
\ :NONAME ( SMB2 ZP    ) ; $A7 BIND \ SMB2 zp
\ :NONAME ( SMB3 ZP    ) ; $B7 BIND \ SMB3 zp
\ :NONAME ( SMB4 ZP    ) ; $C7 BIND \ SMB4 zp
\ :NONAME ( SMB5 ZP    ) ; $D7 BIND \ SMB5 zp
\ :NONAME ( SMB6 ZP    ) ; $E7 BIND \ SMB6 zp
\ :NONAME ( SMB7 ZP    ) ; $F7 BIND \ SMB7 zp

\ :NONAME ( RMB0 ZP    ) ; $07 BIND \ RMB0 zp
\ :NONAME ( RMB1 ZP    ) ; $17 BIND \ RMB1 zp
\ :NONAME ( RMB2 ZP    ) ; $27 BIND \ RMB2 zp
\ :NONAME ( RMB3 ZP    ) ; $37 BIND \ RMB3 zp
\ :NONAME ( RMB4 ZP    ) ; $47 BIND \ RMB4 zp
\ :NONAME ( RMB5 ZP    ) ; $57 BIND \ RMB5 zp
\ :NONAME ( RMB6 ZP    ) ; $67 BIND \ RMB6 zp
\ :NONAME ( RMB7 ZP    ) ; $77 BIND \ RMB7 zp

\ :NONAME ( BBR0 PCR   ) ; $0F BIND \ BBR0 r
\ :NONAME ( BBR1 PCR   ) ; $1F BIND \ BBR1 r
\ :NONAME ( BBR2 PCR   ) ; $2F BIND \ BBR2 r
\ :NONAME ( BBR3 PCR   ) ; $3F BIND \ BBR3 r
\ :NONAME ( BBR4 PCR   ) ; $4F BIND \ BBR4 r
\ :NONAME ( BBR5 PCR   ) ; $5F BIND \ BBR5 r
\ :NONAME ( BBR6 PCR   ) ; $6F BIND \ BBR6 r
\ :NONAME ( BBR7 PCR   ) ; $7F BIND \ BBR7 r
\ :NONAME ( BBS0 PCR   ) ; $8F BIND \ BBS0 r
\ :NONAME ( BBS1 PCR   ) ; $9F BIND \ BBS1 r
\ :NONAME ( BBS2 PCR   ) ; $AF BIND \ BBS2 r
\ :NONAME ( BBS3 PCR   ) ; $BF BIND \ BBS3 r
\ :NONAME ( BBS4 PCR   ) ; $CF BIND \ BBS4 r
\ :NONAME ( BBS5 PCR   ) ; $DF BIND \ BBS5 r
\ :NONAME ( BBS6 PCR   ) ; $EF BIND \ BBS6 r
\ :NONAME ( BBS7 PCR   ) ; $FF BIND \ BBS7 r

\ TESTS
: T?= ( a b -- )    = 0= IF CR .( ** ERROR ** ) CR CR THEN ;
: T?A ( b -- )      _A C@ T?= ;
: T?X ( b -- )      _X C@ T?= ;
: T?Y ( b -- )      _Y C@ T?= ;
: T?P ( b -- )      _P C@ T?= ;
: T?MEM ( addr b -- )  SWAP TC@ T?= ;

\-- store a minimal program

: ORG   DUP TO THERE _PC! ;
: _     TC, ;

\ Test LDA IMM
$0200 ORG
0 _A C!
A9 _ FF _   \ 0000 LDA #$FF
NEXT $FF T?A $80 T?P

\ Test STA ABS
$0200 ORG
0 0222 TC!
8D _ 22 _ 02 _  \ 0002 STA $0222
NEXT 0222 FF T?MEM

\ Test LDX, BNE, DEX
\ $0200    a2 0a     LDX #$0a
\ $0202    ca        DEX
\ $0203    d0 fd     BNE $0202

\ $0200 ORG
\ A2 _ 0A _ CA _ D0 _ FD _

\ Test IO
\ AD FE 02  LDA $02fe
\ 1A        INC A
\ 8d ff 02  STA $02ff
\ d0 f8     BNE $0600

$0200 ORG
AD _ FE _ 02 _ 1A _ 8D _ FF _ 02 _ D0 _ F7 _
