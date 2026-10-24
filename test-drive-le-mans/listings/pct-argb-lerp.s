; Test Drive Le Mans (DC) LEMANS24.BIN, base 0x8C010000.
; PCT routine (packed-colour textured strips, entry 0x8c15a320), near-plane
; clip path: build the intersection vertex between vertex A (current, base
; colour held in r13) and vertex B (ring entry at r6), t = (1 - wA)/(wB - wA).
;
; The packed ARGB lerp splits the colour into two masks so that each channel
; has 8 free bits above it, then does ONE 32x32 mul.l per mask:
;     rb = c & 0x00FF00FF   -> R at bits 16-23, B at bits 0-7  (gap of 8 bits each)
;     g  = c & 0x0000FF00   -> G at bits 8-15
;     out = (((A_rb*(256-t8) + B_rb*t8) >> 8) & 0x00FF00FF)
;         | (((A_g *(256-t8) + B_g *t8) >> 8) & 0x0000FF00)
; t8 = (int)(t*256); the weights sum to 256, so each channel's product is at most
; 255*256 and never carries into the next one. That's 4 mul.l for R, G and B
; together, not 3-4 per channel.
; NOTE: the alpha byte is masked out (neither mask covers 0xFF000000), so
; clipped vertices come out with A = 0. Either this geometry never uses vertex
; alpha (opaque headers), or it's a bug.

; --- float attribute lerp (position, UV) with the same t ---
8c15a426:  fldi1 fr0
8c15a428:  fmov @r6+,fr14             ; wB
8c15a42a:  fsub fr4,fr0               ; 1 - wA
8c15a42c:  fsub fr4,fr14              ; wB - wA
8c15a42e:  fdiv fr14,fr0              ; fr0 = t
8c15a430:  fldi1 fr4                  ; clipped point lies on w = 1: w = 1/w = 1, no divide
8c15a432:  fldi1 fr5
8c15a434:  fmov @r6+,fr14            ; B.X, B.Y from the clip ring
8c15a436:  fmov @r6+,fr15            
8c15a438:  fsub fr7,fr14             ; d = B - A
8c15a43a:  fsub fr6,fr15             
8c15a43c:  fmac fr0,fr14,fr7         ; X += t*dX (fmac)
8c15a43e:  fmac fr0,fr15,fr6         ; Y += t*dY
8c15a440:  add #4,r6                 ; skip one word
8c15a442:  fmov @r6+,fr14            
8c15a444:  fmov @r6+,fr15            
8c15a446:  fsub fr12,fr14            ; du, dv
8c15a448:  fsub fr13,fr15            
8c15a44a:  fmac fr0,fr14,fr12        ; u += t*du
8c15a44c:  fmac fr0,fr15,fr13        ; v += t*dv

; --- packed ARGB lerp, two channels per register ---
8c15a44e:  mov.l r0,@-r15             ; (spills: they ran out of registers)
8c15a450:  mov.l r14,@-r15
8c15a452:  mov   r13,r14              ; r13 = r14 = colour A
8c15a454:  mov.l r2,@-r15
8c15a456:  mov   #1,r1
8c15a458:  mov.l r3,@-r15
8c15a45a:  shll8 r1                   ; r1 = 256
8c15a45c:  mov.l r4,@-r15
8c15a45e:  lds   r1,fpul
8c15a460:  mov   r1,r0                ; r0 = 256
8c15a462:  float fpul,fr14            ; fr14 = 256.0
8c15a464:  add   #-1,r1               ; r1 = 255
8c15a466:  mov   r1,r2                ; r2 = 255
8c15a468:  shll16 r1
8c15a46a:  or    r2,r1                ; r1 = 0x00FF00FF  (mask R|B)
8c15a46c:  mov.l @r6+,r3              ; r3 = colour B (from the clip ring)
8c15a46e:  fmul  fr0,fr14             ; fr14 = t*256
8c15a470:  shll8 r2                   ; r2 = 0x0000FF00  (mask G)
8c15a472:  and   r1,r13               ; A_rb
8c15a474:  and   r2,r14               ; A_g
8c15a476:  mov   r3,r4
8c15a478:  and   r1,r3                ; B_rb
8c15a47a:  ftrc  fr14,fpul
8c15a47c:  and   r2,r4                ; B_g
8c15a47e:  mov.l r5,@-r15
8c15a480:  sts   fpul,r5              ; r5 = t8 = (int)(t*256), 0..256
8c15a482:  mul.l r5,r3                ; B_rb * t8
8c15a484:  sub   r5,r0                ; r0 = 256 - t8
8c15a486:  sts   macl,r3
8c15a488:  mul.l r0,r13               ; A_rb * (256-t8)
8c15a48a:  sts   macl,r13
8c15a48c:  mul.l r5,r4                ; B_g * t8
8c15a48e:  add   r3,r13
8c15a490:  shlr8 r13                  ; R and B back in place
8c15a492:  sts   macl,r4
8c15a494:  mul.l r0,r14               ; A_g * (256-t8)
8c15a496:  and   r1,r13               ; drop the fraction bits that spilled into the gaps
8c15a498:  sts   macl,r14
8c15a49a:  mov.l @r15+,r5
8c15a49c:  add   r4,r14
8c15a49e:  mov.l @r15+,r4
8c15a4a0:  shlr8 r14
8c15a4a2:  mov.l @r15+,r3
8c15a4a4:  and   r2,r14               ; G back in place
8c15a4a6:  mov.l @r15+,r2
8c15a4a8:  or    r14,r13              ; r13 = lerped 0x00RRGGBB (alpha = 0)
8c15a4aa:  mov.l @r15+,r14            ; r14 = offset colour (constant, from a self-modified literal)
8c15a4ac:  mov.l @r15+,r0
8c15a4ae:  add   #-28,r6

; --- emit the clipped vertex to the store queue (backwards) ---
8c15a4b0:  mov.l r14,@-r2             ; offset ARGB (not lerped)
8c15a4b2:  mov.l r13,@-r2             ; base ARGB (lerped)
8c15a4b4:  fmov  fr13,@-r2            ; v
8c15a4b6:  fmov  fr12,@-r2            ; u
8c15a4b8:  fmov  fr5,@-r2             ; 1/w = 1
8c15a4ba:  fmov  fr7,fr14
8c15a4bc:  fmov  fr6,fr15
8c15a4be:  fmul  fr5,fr14             ; X * 1 (kept for code sharing with the visible path)
8c15a4c0:  fmul  fr5,fr15
8c15a4c2:  fmov  fr15,@-r2
8c15a4c4:  fmov  fr14,@-r2
8c15a4c6:  mov.l r10,@-r2             ; PCW
8c15a4c8:  pref  @r9                  ; flush the previous SQ
8c15a4ca:  mov   r2,r9
8c15a4cc:  add   #64,r2
