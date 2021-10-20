#include <linux/config.h>
SYSSIZE = DEF_SYSSIZE
!
!	bootsect.S		(C) 2021 Tianyi Wang in honor of Linus
!
! bootsect.S is loaded at 0x7c00 by the BIOS-startup routines, and moves
! itsel out of the way to address 0x90000, and jumps there.
!
! It then loads 'setup' directly adter ifself at 0x90200, and the system 
! at 0x10000, using BIOS interrupts.
!
! NOTE! Current system is at most 8*65536 bytes long. This should be no
! problem for now. KISS, just for experiment.
! 
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand.

.global begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

SETUPLEN = 4
BOOTSEG  = 0X07C0
INITSEG  = DEF_INITSEG
SETUPSEG = DEF_SETUPSEG
SYSSEG   = DEF_SYSSEG
ENDSEG   = SYSSEG + SYSSIZE

! ROOT_DEV & SWAP_DEV will be written by "build".
ROOT_DEV = 0
SWAP_DEV = 0

entry start
start:
        mov     ax,#BOOTSEG
        mov     ds,ax
        mov     ax,#INITSEG
        mov     es,ax
        mov     cx,#256
        sub     si,si
        sub     di,di
        rep
        movw
        jmpi    go,INITSEG

go:     mov     ax,cs
        mov     dx,#0xfef4
        
        mov     ds,ax
        mov     es,ax
        
        mov     ss,ax
        mov     sp,dx
/*      
 *      Segments are as follows: ds = es = ss = cs = INITSEG,
 *              fs = 0, gs = parameter table segment
*/

        push    #0
        pop     fs
        mov     bx,#0x78
        seg fs
        lgs     si,(bx)
        
        mov     di,dx
        mov     cx,#6
        cld
        
        rep
        seg gs
        movw
        
        mov     di,dx
        movb    4(di),*18
        
        seg fs
        mov     (bx),di
        seg fs
        mov     2(bx),es
        
        mov     ax,cs           ! fix a bug in the original linux.
        mov     fs,ax
        mov     gs,ax
        
        xor     ah,ah
        xor     dl,dl
        int     0x13

! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.

load_setup:
        xor     dx,dx
        mov     cx,#0x0002
        mov     bx,#0x0200
        mov     ax,#0x0200+SETUPLEN
        int     0x13
        jnc     ok_load_setup
        
        push    ax
        call    print_nl
        mov     bp,sp
        call    print_hex
        pop     ax
        
        xor     dl,dl
        xor     ah,ah
        int     0x13
        j       load_setup
        
ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track

        xor     dl,dl
        mov     ah,#0x08
        int     0x13
        xor     ch,ch
        seg cs
        mov     sectors,cx
        mov     ax,#INITSEG
        mov     es,ax
        
! Print some inane message

        mov     ah,#0x03
        xor     bh,bh
        int     0x10
        
        mov     cx,#9
        mov     bx,#0x0007
        mov     bp,#msg1
        mov     ax,#0x1301
        int     0x10

! Load the system at 0x10000
        
        mov     ax,#SYSSEG
        mov     es,ax
        call    read_it
        call    kill_motor
        call    print_nl

! Check which root-device to use. If the device is defined (!=0), 
! nothing is done and the given device is used. Otherwise, either
! /dev/PS0 (2,28) or /dev/at0 (2,8), depending on the number of 
! sectors that the BIOS reports currently.

        seg cs
        mov     bx,sectors
        mov     ax,#0x0208
        cmp     bx,#15
        je      root_defined
        mov     ax,#0x021c
        je      root_defined
undef_root:
        jmpi    undef_root
root_defined:
        seg cs
        mov     root_dev,ax

! after that (everything loaded), we jump to
! the setup-routine loaded directly after 
! the bootblock:

        jmpi    0,SETUPSEG

! This routine loads the system at address 0x10000, making sure
! no 64KB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
! in:   es - starting address segment (normally 0x1000)

sread:  .word 1+SETUPLEN        ! sectors read of current track
head    .word 0                 ! current head
track   .word 0                 ! current track

read_it:
        mov     ax,es
        test    ax,#0x0fff
die:    jne     die             ! es must be at 64kB boundary
        xor     bx,bx           ! bx is starting address within segment
rp_read:
        mov     ax,es
        cmp     ax,#ENDSEG
        jb      ok1_read
        ret
ok1_read:
        seg cs
        mov     ax,sectors
        sub     ax,sread
        mov     cx,ax
        shl     cx,#9
        add     cx,bx
        jnc     ok2_read
        je      ok2_read
        xor     ax,ax
        sub     ax,bx
        shr     ax,#9
ok2_read:
        call    read_track
        mov     cx,ax
        add     ax,sread
        seg cs
        cmp     ax,sectors
        jne     ok3_read
        mov     ax,#1
        sub     ax,head
        jne     ok4_read
        inc     track
ok4_read:
        mov     head,ax
        xor     ax,ax
ok3_read:
        mov     sread,ax
        shl     cx,#9
        add     bx,cx
        jnc     rp_read
        mov     ax,es
        add     ah,#0x10
        mov     es,ax
        xor     bx,bx
        jmp     rp_read

read_track:
        pusha
        pusha
        mov     ax,#0xe2e
        mov     bx,#7
        int     0x10
        popa
        
        mov     dx,track
        mov     cx,sread
        inc     cx
        mov     ch,dl
        mov     dx,head
        mov     dh,dl
        and     dx,#0x0100
        mov     ah,#2
        
        push    dx              ! save for error dump
        push    cx
        push    bx
        push    ax
        
        int     0x13
        jc      bad_rt
        add     sp,#8
        popa
        ret

bad_rt: push    ax              ! save error code
        call    print_all       ! ah = error, al = read
        
        
        xor     ah,ah
        xor     dl,dl
        int     0x13
        
        
        add     sp, #10
        popa
        jmp     read_track

/*
 *      print_all is for debugging purposes.
 *      It will print out all of the registers with the stack frame like
 *      dx
 *      cx
 *      bx
 *      ax
 *      error
 *      ret <- sp
 *
*/

print_all:
        mov     cx,#5           ! error code + 4 registers
        mov     bp,sp

print_loop:
        push    cx              ! save count left
        call    print_nl        ! nl for readability
        jae     no_reg          ! see if register name is needed
        
        mov     ax,#0xe05 + 0x41 - 1
        sub     al,cl
        int     0x10
        
        mov     al,#0x58        ! X
        int     0x10
        
        mov     al,#0x3a        ! :
        
no_reg:
        add     bp,#2           ! next register
        call    print_hex       ! print it
        pop     cx
        loop    print_loop
        ret
        
print_nl:
        mov     ax,#0xe0d       ! CR
        int     0x10            ! LF
        ret
        
/*
 *      print_hex is for debugging purposes, and prints the word
 *      pointed to by ss:bp in hexadecimal.
*/

print_hex:
        mov     cx,#4           ! 4 hex digits
        mov     dx,(bp)         ! load word into dx
print_digit:
        rol     dx,#4           ! rotate so that lowest 4 bits are used
        mov     ah,#0xe
        mov     al,dl           ! mask off so we have only next niblle
        and     al,#0xf
        add     al,#0x30        ! convert to 0 based digit, '0'
        cmp     al,#0x39        ! check for overflow
        jbe     good_digit
        add     al,#0x41 - 0x30 - 0xa           ! 'A' - '0' - 0xa

good_digit:
        int     0x10
        loop    print_digit
        ret


/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
*/
kill_motor:
        push    dx
        mov     dx,#0x3f2
        xor     al,al
        outb
        pop dx
        ret
        
sectors:
        .word 0
        
msg1:
        .byte 13,10
        .ascii "Loading"

.org 506
swap_dev:
        .word SWAP_DEV
root_dev:
        .word ROOT_DEV
boot_flag:
        .word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:
