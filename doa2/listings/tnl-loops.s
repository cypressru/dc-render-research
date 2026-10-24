; Dead or Alive 2 (Dreamcast, USA, 2000) 1ST_READ.BIN, load base 0x8C010000. sh-elf-objdump -D -EL via tools/listing.py; nop padding and literal-pool words removed.
; Annotated T&L loops. Costs are static estimates from instruction counts (nothing measured).
; After fschg (FPSCR.SZ=1) objdump still prints "fmov @rX,frN": those are 64-bit pair moves of drN (xdN for odd N).
; The renderer core is AM2's NAOMI library (NL 0.9 / NLOBJPUT 0.99), the same code that Shenmue II ships. Kernels that are
; instruction-for-instruction identical to Shenmue II are NOT repeated here; see ../shenmue2/listings/tnl-loops.s:
;   DOA2 0x8c101540 walker = SM2 0x8c1d7480 (1081/1120 instr equal, rest literal pools + SM2-only 2nd-light hook)
;   DOA2 0x8c101a52 bulk kernel = SM2 0x8c1d79b2 (151/151)      DOA2 0x8c10a5ea..0x8c10b1c0 type -3 hooks/fast path = SM2 0x8c1d442a.. (1364/1376)
;   DOA2 0x8c10d980 shadow volumes = SM2 0x8c1dd220 (1559/1568)  DOA2 0x8c107d10 3-deep batch projector = SM2 0x8c1de5d0 (152/152)
;   DOA2 0x8c102660 RGB walker = SM2 0x8c1dad40 (398/400; unreachable from DOA2 game code)
; Sections:
;   A  NL bulk kernel twin with an intensity-driven offset term (DOA2-only)                 [0x8c108372]
;   B  twin / hook selection setters                                                         [0x8c103b60, 0x8c103be0]
;   C  model draw API used by all game draw sites (matrix setup, alpha walker entry)        [0x8c111680, 0x8c1116c0]
;   D  in-place RGB pre-light of a mesh (point/spot lights, writes packed ARGB into the vertices) + restore pass   [0x8c10d360, 0x8c1042da]
;   E  sphere-map UV pre-pass                                                                 [0x8c112560]
;   F  soft parts: particle -> vertex writer, point transform, chain constraint solver       [0x8c0c59a8, 0x8c111b80, 0x8c0c6278]
;   G  vertex-animation (APV) blend helpers                                                   [0x8c0cf8fa]
;   H  character shadows: limb volume matrix, modifier-volume header                         [0x8c0d43e8, 0x8c1014a0]
;   I  frame skip by patching draw entry points to rts                                       [0x8c012672, 0x8c012a74, 0x8c1177ee]

;; ################################################################ SECTION A
;; ==== 0x8c108372  bulk strip kernel, twin family (walker 0x8c107e60, tables 0x8c103fe8/0x8c104058 when 0x8c103b60 enabled it) ====
;; Same structure, register use and 2-vertex software pipeline as the plain kernel 0x8c101a52 (= SM2 0x8c1d79b2):
;;   in : r4 = MT7 strip stream (32 B inline {x,y,z,nx,ny,nz,u,v}, x LSB = tag, or 8 B back-reference), r3 = strip length,
;;        XMTRX = permuted screen*modelview (result (w,X,Y,-)), fv12 = model-space light dir (permuted), fpul/fr15 = ambient.
;;   out: 32 B TA vertex {PCW, X/w, Y/w, 1/w, u, v, I_base, I_offset} through the SQ (r6 = 0xE0..), PCW = SQ address, end = shar.
;; DOA2 addition: r13 -> 0x8c1ca940 = {k, -b} written by 0x8c103b60(b=fr4, k=fr5). Per vertex:
;;   I = ambient + max(0, N.L);  I_offset = (r8 >= 0) ? k*(I - b) : 0      (plain kernel: I_offset = 0)
;; i.e. a brightness ramp in the PVR offset colour driven by the diffuse term (no clamp; the PVR clamps the sum).
;; cost: loop 0x8c10839a-0x8c10845a = 97 instr per 2 vertices (91 on the back-reference path) vs 85/79 in the plain kernel:
;;   +6 instr/vertex (pair load of {k,-b}, fadd, cmp/pz, bf, fmac). ~45 instr, ~35-40 cycles per strip vertex.
;;   FDIV of vertex n is consumed ~20 instr later while n+1 is loaded/transformed (no stall). 2 data branches + tag branch per vertex.
8c108372:  mov.l @r4+,r3
8c108374:  add #32,r6
8c108376:  fschg                         ; SZ=1: 64-bit pair loads/stores
8c108378:  mov.l @r4,r0
8c10837a:  mov r4,r14
8c10837c:  fldi0 fr2
8c10837e:  tst #1,r0                     ; inline vertex? (x LSB)
8c108380:  add #32,r4
8c108382:  bf 0x8c10838a
8c108384:  mov.l @(4,r14),r14            ; back-reference: offset word
8c108386:  add #-24,r4
8c108388:  add r4,r14
8c10838a:  fmov @r14+,fr4                ; dr4 = (x,y)
8c10838c:  mov r6,r2
8c10838e:  fmov @r14+,fr6                ; dr6 = (z,nx)
8c108390:  fadd fr7,fr2
8c108392:  fldi1 fr7
8c108394:  fldi0 fr3
8c108396:  fmov @r14+,fr0                ; dr0 = (ny,nz): fv0 = (ny,nz,nx,0)
8c108398:  ftrv xmtrx,fv4                ; A: (w,X,Y,-)
8c10839a:  mov.l @r4+,r0
8c10839c:  flds fr15,fpul
8c10839e:  dt r3
8c1083a0:  mov.l @r4+,r1
8c1083a2:  fipr fv12,fv0                 ; A: N.L (light pre-rotated into model space)
8c1083a4:  fldi1 fr7
8c1083a6:  bt.s 0x8c10848c
8c1083a8:  fdiv fr4,fr7                  ; A: 1/w, consumed at 0x8c1083de
8c1083aa:  tst #1,r0
8c1083ac:  add r4,r1
8c1083ae:  bt.s 0x8c1083b8
8c1083b0:  fsts fpul,fr2
8c1083b2:  mov r4,r1
8c1083b4:  add #24,r4
8c1083b6:  add #-8,r1
8c1083b8:  fldi0 fr10                    ; fr10 = 0 (plain kernel uses fr0)
8c1083ba:  fcmp/gt fr10,fr3              ; N.L > 0 ?
8c1083bc:  fmov @r1+,fr8
8c1083be:  add #32,r4
8c1083c0:  fmov @r13,fr0                 ; dr0 = {k, -b} from r13 (DOA2-only)
8c1083c2:  bf 0x8c1083c6
8c1083c4:  fadd fr3,fr2                  ; I = ambient + N.L
8c1083c6:  pref @r4                      ; prefetch next source line
8c1083c8:  cmp/pz r8                     ; per-mesh flag: offset term enabled?
8c1083ca:  fadd fr2,fr1                  ; fr1 = I - b
8c1083cc:  fldi0 fr3
8c1083ce:  bf 0x8c1083d2
8c1083d0:  fmac fr0,fr1,fr3              ; I_offset = k*(I - b)
8c1083d2:  fmov @r14,fr0                 ; dr0 = (u,v) of A
8c1083d4:  fmov @r1+,fr10
8c1083d6:  add #-32,r4
8c1083d8:  fmov fr2,@-r6                 ; +24: (I_base, I_offset)
8c1083da:  fsub fr2,fr2
8c1083dc:  fmov fr0,@-r6                 ; +16: (u,v)
8c1083de:  fmul fr7,fr6                  ; Y*1/w
8c1083e0:  fmov @r1+,fr0
8c1083e2:  fadd fr11,fr2
8c1083e4:  fldi1 fr11
8c1083e6:  fmul fr7,fr5                  ; X*1/w
8c1083e8:  add #32,r5
8c1083ea:  fmov fr6,@-r6                 ; +8: (Y/w, 1/w)
8c1083ec:  dt r3
8c1083ee:  fmov fr4,@-r6                 ; +0: (w junk, X/w)
8c1083f0:  ftrv xmtrx,fv8                ; B: transform while A is being stored
8c1083f2:  mov.l r2,@r6                  ; PCW = SQ address (overwrites w)
8c1083f4:  fsub fr3,fr3
8c1083f6:  mov.l @r4+,r0
8c1083f8:  mov r6,r2
8c1083fa:  pref @r6                      ; burst A (32 B) to the list
8c1083fc:  add #64,r6
8c1083fe:  mov.l @r4+,r14
8c108400:  flds fr15,fpul
8c108402:  fipr fv12,fv0                 ; B: N.L
8c108404:  fldi1 fr11
8c108406:  bt.s 0x8c10845c
8c108408:  fdiv fr8,fr11                 ; B: 1/w
8c10840a:  tst #1,r0
8c10840c:  add r4,r14
8c10840e:  bt.s 0x8c108418
8c108410:  fsts fpul,fr2
8c108412:  mov r4,r14
8c108414:  add #24,r4
8c108416:  add #-8,r14
8c108418:  fldi0 fr0
8c10841a:  fcmp/gt fr0,fr3
8c10841c:  fmov @r14+,fr4
8c10841e:  add #32,r4
8c108420:  fmov @r13,fr0                 ; dr0 = {k, -b}
8c108422:  bf 0x8c108426
8c108424:  fadd fr3,fr2
8c108426:  pref @r4
8c108428:  cmp/pz r8
8c10842a:  fadd fr2,fr1
8c10842c:  fldi0 fr3
8c10842e:  bf 0x8c108432
8c108430:  fmac fr0,fr1,fr3              ; B: I_offset = k*(I - b)
8c108432:  fmov @r1,fr0
8c108434:  fmov @r14+,fr6
8c108436:  add #-32,r4
8c108438:  fmov fr2,@-r6
8c10843a:  fsub fr2,fr2
8c10843c:  fmov fr0,@-r6
8c10843e:  fmul fr11,fr10
8c108440:  fmov @r14+,fr0
8c108442:  fadd fr7,fr2
8c108444:  fldi1 fr7
8c108446:  fmul fr11,fr9
8c108448:  add #32,r5
8c10844a:  fmov fr10,@-r6
8c10844c:  fsub fr3,fr3
8c10844e:  fmov fr8,@-r6
8c108450:  ftrv xmtrx,fv4                ; A': transform (loop rotated by one vertex)
8c108452:  mov.l r2,@r6
8c108454:  mov r6,r2
8c108456:  pref @r6                      ; burst B
8c108458:  bra 0x8c10839a
8c10845a:  add #64,r6
8c10845c:  cmp/pl r0
8c10845e:  fsts fpul,fr2
8c108460:  bf 0x8c108480
8c108462:  tst #128,r0                   ; strip flag bit 7: another strip follows
8c108464:  mov r14,r3
8c108466:  bt 0x8c108480
8c108468:  mov.l @r4+,r0
8c10846a:  mov r6,r2
8c10846c:  shar r2                       ; end-of-strip PCW = SQ address >> 1 (0xF0..)
8c10846e:  tst #1,r0
8c108470:  mov.l @r4+,r14
8c108472:  bt.s 0x8c108418
8c108474:  add r4,r14
8c108476:  mov r4,r14
8c108478:  add #24,r4
8c10847a:  bra 0x8c108418
8c10847c:  add #-8,r14
8c10847e:  nop
8c108480:  add #48,r4
8c108482:  pref @r4
8c108484:  add #-48,r4
8c108486:  fmov fr8,fr4
8c108488:  bra 0x8c1084b8
8c10848a:  fmov fr10,fr6
8c10848c:  cmp/pl r0
8c10848e:  fsts fpul,fr2
8c108490:  bf 0x8c1084b0
8c108492:  tst #128,r0
8c108494:  mov r1,r3
8c108496:  bt 0x8c1084b0
8c108498:  mov.l @r4+,r0
8c10849a:  mov r6,r2
8c10849c:  shar r2
8c10849e:  tst #1,r0
8c1084a0:  mov.l @r4+,r1
8c1084a2:  bt.s 0x8c1083b8
8c1084a4:  add r4,r1
8c1084a6:  mov r4,r1
8c1084a8:  add #24,r4
8c1084aa:  bra 0x8c1083b8
8c1084ac:  add #-8,r1
8c1084ae:  nop
8c1084b0:  add #48,r4
8c1084b2:  mov r14,r1
8c1084b4:  pref @r4
8c1084b6:  add #-48,r4
8c1084b8:  fldi0 fr0
8c1084ba:  fcmp/gt fr0,fr3
8c1084bc:  fmov @r13,fr0
8c1084be:  bf 0x8c1084c2
8c1084c0:  fadd fr3,fr2
8c1084c2:  cmp/pz r8
8c1084c4:  fmov @r1,fr10
8c1084c6:  fadd fr2,fr1
8c1084c8:  fldi0 fr3
8c1084ca:  bf 0x8c1084ce
8c1084cc:  fmac fr0,fr1,fr3
8c1084ce:  fmul fr7,fr6
8c1084d0:  fmov fr2,@-r6
8c1084d2:  fmul fr7,fr5
8c1084d4:  fmov fr10,@-r6
8c1084d6:  mov r6,r2
8c1084d8:  shar r2
8c1084da:  fmov fr6,@-r6
8c1084dc:  add #32,r5
8c1084de:  fmov fr4,@-r6
8c1084e0:  add #-8,r4
8c1084e2:  mov.l r2,@r6                  ; last vertex: end-of-strip PCW
8c1084e4:  fschg
8c1084e6:  pref @r6
8c1084e8:  rts
8c1084ea:  add #32,r6

;; ################################################################ SECTION B
;; ==== 0x8c103b60  select plain or twin intensity walkers (3 game callers: 0x8c0a8c26, 0x8c0a8e7c, 0x8c0bf7cc) ====
;; Stores {fr5, -fr4} at 0x8c1ca940 and patches both walker slots (opaque 0x8c103fe8, alpha 0x8c104058):
;; twin 0x8c107e60/62 when fr5 > 0 and fr4 >= 0, else plain 0x8c101540/42.
8c103b60:  mov.l 0x8c103bac,r1 ! 8c1ca940
8c103b62:  fneg fr4
8c103b64:  mov #0,r0
8c103b66:  fmov fr5,@(r0,r1)             ; k = fr5
8c103b68:  mov #4,r0
8c103b6a:  fmov fr4,@(r0,r1)             ; -b = -fr4
8c103b6c:  fldi0 fr0
8c103b6e:  fcmp/gt fr0,fr5               ; k > 0 ?
8c103b70:  fneg fr4
8c103b72:  bf 0x8c103b7c
8c103b74:  fcmp/gt fr4,fr0
8c103b76:  bt 0x8c103b7c
8c103b78:  bra 0x8c103b96
8c103b7a:  nop
8c103b7c:  mov.l 0x8c103bb0,r0 ! 8c103fe8
8c103b7e:  mov.l 0x8c103bb8,r1 ! 8c101540 ; plain walkers 0x8c101540 / 0x8c101542
8c103b80:  mov.l 0x8c103bbc,r2 ! 8c101540
8c103b82:  mov.l r1,@r0
8c103b84:  add #4,r0
8c103b86:  mov.l r2,@r0
8c103b88:  mov.l 0x8c103bb4,r0 ! 8c104058
8c103b8a:  mov.l 0x8c103bc4,r1 ! 8c101542
8c103b8c:  mov.l 0x8c103bc8,r2 ! 8c101542
8c103b8e:  mov.l r1,@r0
8c103b90:  add #4,r0
8c103b92:  rts
8c103b94:  mov.l r2,@r0
8c103b96:  mov.l 0x8c103bb0,r0 ! 8c103fe8
8c103b98:  mov.l 0x8c103bc0,r1 ! 8c107e60 ; twin walkers 0x8c107e60 / 0x8c107e62
8c103b9a:  mov.l r1,@r0
8c103b9c:  add #4,r0
8c103b9e:  mov.l r1,@r0
8c103ba0:  mov.l 0x8c103bb4,r0 ! 8c104058
8c103ba2:  mov.l 0x8c103bcc,r1 ! 8c107e62
8c103ba4:  mov.l r1,@r0
8c103ba6:  add #4,r0
8c103ba8:  rts
8c103baa:  mov.l r1,@r0

;; ==== 0x8c103be0  mesh type -3 hook (about 70 call sites, stage draw functions): 0 none, 1 = 0x8c10a5ea, 2 = 0x8c10b1ca ====
;; Hooks 1/2 route packed-colour meshes to the fast kernel 0x8c10a7e0 (= SM2 0x8c1d4620, ~30 instr, 20-24 cycles/vertex).
8c103be0:  mov.l 0x8c103e00,r5 ! 8c1ca948
8c103be2:  tst r4,r4
8c103be4:  bf 0x8c103bf0
8c103be6:  mov #0,r2
8c103be8:  bra 0x8c103c08
8c103bea:  mov.l r2,@r5
8c103bec:  nop
8c103bee:  nop
8c103bf0:  mov r4,r0
8c103bf2:  cmp/eq #1,r0
8c103bf4:  bf 0x8c103c00
8c103bf6:  mov.l 0x8c103e04,r3 ! 8c10a5ea ; hook 1 (packed base colour)
8c103bf8:  bra 0x8c103c08
8c103bfa:  mov.l r3,@r5
8c103bfc:  nop
8c103bfe:  nop
8c103c00:  cmp/eq #2,r0
8c103c02:  bf 0x8c103c08
8c103c04:  mov.l 0x8c103e08,r2 ! 8c10b1ca ; hook 2 (keeps offset colour)
8c103c06:  mov.l r2,@r5
8c103c08:  rts
8c103c0a:  nop

;; ################################################################ SECTION C
;; ==== 0x8c111680 / 0x8c1116a0 / 0x8c1116c0  draw one MT7 model with the current matrix (about 224 + 34 call sites) ====
;; 0x8c111680: alpha = 1.0; 0x8c1116a0: alpha = fr4 (alpha < 1 rewrites TSP blend and moves the mesh to the translucent list).
;; 0x8c111580/0x8c111560 (about 310 + 146 sites) first rotate the eye position into model space (FIPR+FSRRA normalise, stored at
;; 0x8c2e64b0) for the specular kernels, then share this tail. Every draw: push (0x8c0fdec0), build XMTRX, walker, pop.
;; The projection at 0x8c2f0670 is loaded with every 4-float group (m0,m1,m2,m3) rearranged to (m3,m0,m1,-m3): z dropped,
;; w first, so the kernels' FTRV yields (w, X, Y, -w) and the PCW store can overwrite w; 0x8c1111e0 (4 FTRV + FRCHG)
;; then forms XMTRX = permuted projection x current modelview (0x8c2f0630). The walker slot table is bypassed: these
;; draws always take the plain walker 0x8c101542, never the twin of section A.
8c111680:  fldi1 fr0                     ; alpha = 1.0
8c111682:  mov.l r14,@-r15
8c111684:  mov.l 0x8c111694,r3 ! 8c0fdec0
8c111686:  sts.l pr,@-r15
8c111688:  mov r4,r14
8c11168a:  fmov fr0,@-r15
8c11168c:  jsr @r3                       ; matrix push (NL 0x8c0fdec0 = SM2 0x8c1deb40)
8c11168e:  mov #0,r4
8c111690:  bra 0x8c1116c0
8c111692:  nop

8c1116a0:  mov.l r14,@-r15
8c1116a2:  mov.l 0x8c1116b4,r3 ! 8c0fdec0
8c1116a4:  sts.l pr,@-r15
8c1116a6:  mov r4,r14
8c1116a8:  fmov fr4,@-r15                ; alpha argument
8c1116aa:  jsr @r3
8c1116ac:  mov #0,r4
8c1116ae:  bra 0x8c1116c0
8c1116b0:  nop

8c1116c0:  mov.l 0x8c111710,r4 ! 8c2f0670
8c1116c2:  frchg                         ; build in the back bank (no FRCHG cost in the kernels)
8c1116c4:  fmov @r4+,fr1
8c1116c6:  fmov @r4,fr2
8c1116c8:  add #8,r4
8c1116ca:  fmov @r4,fr3
8c1116cc:  fmov @r4+,fr0
8c1116ce:  fneg fr3                      ; -w in slot 3
8c1116d0:  fmov @r4+,fr5
8c1116d2:  fmov @r4,fr6
8c1116d4:  add #8,r4
8c1116d6:  fmov @r4,fr7
8c1116d8:  fmov @r4+,fr4
8c1116da:  fneg fr7
8c1116dc:  fmov @r4+,fr9
8c1116de:  fmov @r4,fr10
8c1116e0:  add #8,r4
8c1116e2:  fmov @r4,fr11
8c1116e4:  fmov @r4+,fr8
8c1116e6:  fneg fr11
8c1116e8:  fmov @r4+,fr13
8c1116ea:  fmov @r4,fr14
8c1116ec:  add #8,r4
8c1116ee:  fmov @r4,fr15
8c1116f0:  fmov @r4+,fr12
8c1116f2:  fneg fr15
8c1116f4:  frchg                         ; back to front bank
8c1116f6:  mov.l 0x8c111714,r4 ! 8c2f0630
8c1116f8:  bsr 0x8c1111e0                ; XMTRX = permuted projection x modelview 0x8c2f0630
8c1116fa:  nop
8c1116fc:  mov.l 0x8c111718,r5 ! 8c2e6498
8c1116fe:  fmov @r15+,fr4
8c111700:  mov.l 0x8c11171c,r3 ! 8c101542 ; plain alpha walker entry 0x8c101542, called directly
8c111702:  jsr @r3
8c111704:  mov r14,r4
8c111706:  mov.l 0x8c111720,r3 ! 8c0fde70
8c111708:  mov #1,r4
8c11170a:  lds.l @r15+,pr
8c11170c:  jmp @r3                       ; matrix pop
8c11170e:  mov.l @r15+,r14

;; ################################################################ SECTION D
;; ==== 0x8c10d360  in-place RGB pre-light kernel (walker 0x8c10d120, entry 0x8c104240; 16 call sites in 6 stage draw functions) ====
;; Not a TA kernel: no FTRV, no store-queue output. For every INLINE vertex of a mesh (back-references are skipped, so each
;; unique vertex is lit once) it evaluates the active lights in model space and writes two packed ARGB words into the
;; vertex record itself; the walker then retypes the mesh to -3 (vertex colour) so the normal draw takes the fast
;; packed-colour kernel 0x8c10a7e0. On the first pass the float normal is packed to s8x3 in the nx slot (top byte 0x80),
;; freeing the ny/nz slots for the colours; the original type is saved in the mesh header (+48 >> 16). 0x8c104290 undoes it.
;;   in : r4 = strip stream, r8 = original mesh type (<0 = unlit), r6 = 1 if normals already packed, r13 = light mask
;;        (*0x8c1130f0, from the per-mesh sphere/cone cull 0x8c112d80), lights = 0xb0 B records at 0x8c2ef7e8 (types 2/3/4),
;;        fr13-15 = ambient x material, fr4-6 = vertex position.
;;   light: directional = 1 FIPR, clamp. point/spot = L=Lp-P, FIPR N.L, FIPR L.L, range test, FSRRA (1/d), spot cone,
;;          attenuation N.L/(d*(k0 + k1 d + k2 d^2)) with one FDIV (only when the divisor > 1). 3 FMAC accumulate RGB.
;;   out: base  = clamp(material ARGB x min(acc,..)) packed at vertex+16; offset = clamp((acc - 1) x k) packed at vertex+20:
;;        light above 1.0 spills into the PVR offset colour (over-bright highlight).
;; cost (s8 normals, 1 directional): ~8 load + ~29 unpack + ~22 light + ~75 clamp/pack = ~135 instr, ~110-130 cycles per
;;   unique vertex; +~50 instr per point light, +~10 for a spot. Then the fast type -3 kernel (~30 instr) per strip vertex.
;;   ~20 branches per vertex (clamps are branchy: 4 per channel). Runs every frame the stage asks for it.
8c10d360:  mov.l @r4+,r3
8c10d362:  mov.l @r4,r0
8c10d364:  mov r4,r14
8c10d366:  tst #1,r0                     ; inline vertex?
8c10d368:  mov.l 0x8c10d66c,r13 ! 8c1130f0
8c10d36a:  bf.s 0x8c10d378
8c10d36c:  add #32,r4
8c10d36e:  dt r3                         ; back-reference: skip (lit once per unique vertex)
8c10d370:  bf.s 0x8c10d362
8c10d372:  add #-24,r4
8c10d374:  bra 0x8c10d61c
8c10d376:  fschg
8c10d378:  mov.l 0x8c10d664,r0 ! 8c1130e0
8c10d37a:  fschg                         ; SZ=1
8c10d37c:  mov.l @r13,r13                ; r13 = active light mask for this mesh
8c10d37e:  fmov @r0+,fr12                ; dr12/dr14: fr13-15 = ambient x material
8c10d380:  fmov @r0+,fr14
8c10d382:  fmov @r14+,fr4                ; dr4 = (x,y)
8c10d384:  add #32,r4
8c10d386:  fmov @r14+,fr6                ; dr6 = (z, nx word)
8c10d388:  bra 0x8c10d39c
8c10d38a:  fschg
8c10d38c:  mov.l 0x8c10d664,r0 ! 8c1130e0
8c10d38e:  mov.l @r13,r13
8c10d390:  fmov @r0+,fr12
8c10d392:  fmov @r0+,fr14
8c10d394:  add #64,r4
8c10d396:  fmov @r14+,fr4
8c10d398:  fmov @r14+,fr6
8c10d39a:  fschg
8c10d39c:  cmp/pz r8                     ; mesh unlit (type < 0)?
8c10d39e:  fmov fr7,fr8
8c10d3a0:  bf.s 0x8c10d474
8c10d3a2:  tst r13,r13
8c10d3a4:  tst r6,r6                     ; normals already packed?
8c10d3a6:  bt 0x8c10d3ea
8c10d3a8:  mov #60,r0
8c10d3aa:  shll8 r0
8c10d3ac:  or #1,r0
8c10d3ae:  shll8 r0
8c10d3b0:  or #2,r0
8c10d3b2:  shll8 r0
8c10d3b4:  or #4,r0
8c10d3b6:  lds r0,fpul                   ; fpul = 1/127
8c10d3b8:  fsts fpul,fr0
8c10d3ba:  flds fr8,fpul
8c10d3bc:  sts fpul,r0
8c10d3be:  exts.b r0,r0
8c10d3c0:  lds r0,fpul
8c10d3c2:  float fpul,fr10               ; s8 normal -> float (3x exts.b, float, fmul)
8c10d3c4:  fmul fr0,fr10
8c10d3c6:  flds fr8,fpul
8c10d3c8:  sts fpul,r0
8c10d3ca:  shlr8 r0
8c10d3cc:  exts.b r0,r0
8c10d3ce:  lds r0,fpul
8c10d3d0:  float fpul,fr9
8c10d3d2:  fmul fr0,fr9
8c10d3d4:  flds fr8,fpul
8c10d3d6:  sts fpul,r0
8c10d3d8:  shlr16 r0
8c10d3da:  exts.b r0,r0
8c10d3dc:  lds r0,fpul
8c10d3de:  float fpul,fr8
8c10d3e0:  fmul fr0,fr8
8c10d3e2:  tst r13,r13
8c10d3e4:  bt 0x8c10d480
8c10d3e6:  bra 0x8c10d430
8c10d3e8:  nop
8c10d3ea:  fmov @r14+,fr9
8c10d3ec:  fmov @r14+,fr10
8c10d3ee:  mov #66,r0                    ; first pass: pack float normal
8c10d3f0:  shll8 r0
8c10d3f2:  or #254,r0
8c10d3f4:  shll16 r0
8c10d3f6:  lds r0,fpul                   ; 127.0
8c10d3f8:  fsts fpul,fr0
8c10d3fa:  mov #-128,r1
8c10d3fc:  fldi0 fr11
8c10d3fe:  fmac fr0,fr8,fr11             ; trunc(n*127)
8c10d400:  ftrc fr11,fpul
8c10d402:  sts fpul,r0
8c10d404:  and #255,r0
8c10d406:  shll8 r1
8c10d408:  or r0,r1
8c10d40a:  fldi0 fr11
8c10d40c:  fmac fr0,fr9,fr11
8c10d40e:  ftrc fr11,fpul
8c10d410:  sts fpul,r0
8c10d412:  and #255,r0
8c10d414:  shll8 r1
8c10d416:  or r0,r1
8c10d418:  fldi0 fr11
8c10d41a:  fmac fr0,fr10,fr11
8c10d41c:  ftrc fr11,fpul
8c10d41e:  sts fpul,r0
8c10d420:  and #255,r0
8c10d422:  shll8 r1
8c10d424:  or r0,r1
8c10d426:  add #-12,r14
8c10d428:  mov.l r1,@r14                 ; nx slot = 0x80|nx|ny|nz (s8 x3)
8c10d42a:  add #12,r14
8c10d42c:  tst r13,r13
8c10d42e:  bt 0x8c10d480
8c10d430:  shlr r13                      ; next light bit
8c10d432:  mov.l 0x8c10d668,r2 ! 8c2ef7e8
8c10d434:  bf 0x8c10d462
8c10d436:  mov.w @(2,r2),r0              ; light type
8c10d438:  fldi0 fr3
8c10d43a:  cmp/eq #2,r0                  ; 2 = directional
8c10d43c:  mov #116,r1
8c10d43e:  bf.s 0x8c10d484
8c10d440:  add r2,r1
8c10d442:  tst r13,r13
8c10d444:  add #12,r1
8c10d446:  fmov @r1+,fr0
8c10d448:  fmov @r1+,fr1
8c10d44a:  mov r2,r0
8c10d44c:  fmov @r1+,fr2
8c10d44e:  add #24,r0
8c10d450:  fipr fv0,fv8                  ; N.L (model-space direction)
8c10d452:  fmov @r0+,fr1
8c10d454:  fmov @r0+,fr2
8c10d456:  fmov @r0+,fr3
8c10d458:  fldi0 fr0
8c10d45a:  fcmp/gt fr11,fr0
8c10d45c:  fmov fr11,fr0
8c10d45e:  bf.s 0x8c10d506               ; N.L >= 0: accumulate
8c10d460:  tst r13,r13
8c10d462:  mov #-80,r0
8c10d464:  bt 0x8c10d52e
8c10d466:  shlr r13
8c10d468:  extu.b r0,r0
8c10d46a:  bf.s 0x8c10d51a
8c10d46c:  add r0,r2
8c10d46e:  bra 0x8c10d438
8c10d470:  mov.w @(2,r2),r0
8c10d472:  nop
8c10d474:  fldi1 fr7
8c10d476:  mov #0,r1
8c10d478:  sett
8c10d47a:  rotcr r1
8c10d47c:  bra 0x8c10d528
8c10d47e:  mov.l r1,@-r14
8c10d480:  bra 0x8c10d52e
8c10d482:  nop
8c10d484:  fmov @r1+,fr0
8c10d486:  tst r13,r13
8c10d488:  fmov @r1+,fr1
8c10d48a:  fsub fr4,fr0                  ; L = Lp - P
8c10d48c:  fmov @r1+,fr2
8c10d48e:  fsub fr5,fr1
8c10d490:  fldi1 fr7
8c10d492:  add #24,r1
8c10d494:  fldi0 fr11
8c10d496:  fsub fr6,fr2
8c10d498:  fipr fv0,fv8                  ; N.L (unnormalised)
8c10d49a:  fldi0 fr12
8c10d49c:  fipr fv0,fv0                  ; d^2
8c10d49e:  fcmp/gt fr11,fr12
8c10d4a0:  fmov @r1,fr12
8c10d4a2:  bt 0x8c10d514
8c10d4a4:  fcmp/gt fr3,fr12              ; range test
8c10d4a6:  bf 0x8c10d514
8c10d4a8:  cmp/eq #3,r0
8c10d4aa:  flds fr3,fpul
8c10d4ac:  bt.s 0x8c10d4d6
8c10d4ae:  fsrra fr3                     ; 1/d
8c10d4b0:  add #-24,r1
8c10d4b2:  fmov @r1+,fr12
8c10d4b4:  fmul fr0,fr12                 ; spot: cone term from L.D
8c10d4b6:  fmov @r1+,fr0
8c10d4b8:  fmac fr0,fr1,fr12
8c10d4ba:  fmov @r1,fr0
8c10d4bc:  add #-48,r1
8c10d4be:  fmac fr0,fr2,fr12
8c10d4c0:  fmov @r1,fr2
8c10d4c2:  fneg fr12
8c10d4c4:  fmul fr3,fr12
8c10d4c6:  add #68,r1
8c10d4c8:  fcmp/gt fr12,fr2
8c10d4ca:  fsub fr2,fr12
8c10d4cc:  fmov @r1,fr2
8c10d4ce:  bt 0x8c10d514
8c10d4d0:  fmul fr2,fr12
8c10d4d2:  add #-4,r1
8c10d4d4:  fmul fr12,fr11
8c10d4d6:  add #-68,r1
8c10d4d8:  fmov @r1,fr2
8c10d4da:  add #-8,r1
8c10d4dc:  fsts fpul,fr0
8c10d4de:  fmul fr3,fr11                 ; N.L / d
8c10d4e0:  fmov @r1,fr12
8c10d4e2:  fmul fr0,fr3
8c10d4e4:  add #4,r1
8c10d4e6:  fmac fr0,fr2,fr12             ; k0 + k2 d^2
8c10d4e8:  fmov @r1,fr2
8c10d4ea:  mov r2,r0
8c10d4ec:  fmov fr3,fr0
8c10d4ee:  fmac fr0,fr2,fr12             ; + k1 d
8c10d4f0:  fmov fr11,fr0
8c10d4f2:  add #24,r0
8c10d4f4:  fdiv fr12,fr11                ; attenuation divide
8c10d4f6:  fldi1 fr2
8c10d4f8:  fcmp/gt fr2,fr12
8c10d4fa:  fmov @r0+,fr1
8c10d4fc:  fmov @r0+,fr2
8c10d4fe:  bf.s 0x8c10d504
8c10d500:  fmov @r0+,fr3
8c10d502:  fmov fr11,fr0
8c10d504:  tst r13,r13
8c10d506:  fmac fr0,fr1,fr13             ; R += I*Lr
8c10d508:  mov #-80,r0
8c10d50a:  fmac fr0,fr2,fr14             ; G += I*Lg
8c10d50c:  bt.s 0x8c10d52e
8c10d50e:  fmac fr0,fr3,fr15             ; B += I*Lb
8c10d510:  bra 0x8c10d51c
8c10d512:  shlr r13
8c10d514:  tst r13,r13
8c10d516:  mov #-80,r0
8c10d518:  bt.s 0x8c10d52e
8c10d51a:  shlr r13
8c10d51c:  extu.b r0,r0
8c10d51e:  bf.s 0x8c10d51a
8c10d520:  add r0,r2
8c10d522:  bra 0x8c10d438
8c10d524:  mov.w @(2,r2),r0
8c10d526:  nop
8c10d528:  fldi1 fr13
8c10d52a:  fldi1 fr15
8c10d52c:  fldi1 fr14
8c10d52e:  mov.l 0x8c10d660,r2 ! 8c112e60
8c10d530:  fschg
8c10d532:  pref @r4
8c10d534:  add #-32,r4
8c10d536:  fmov @r2+,fr8                 ; material ARGB (pairs)
8c10d538:  fmov @r2+,fr10
8c10d53a:  fmul fr13,fr9
8c10d53c:  mov.l @r4,r0
8c10d53e:  fmul fr14,fr10
8c10d540:  fmul fr15,fr11
8c10d542:  cmp/pz r8
8c10d544:  fldi0 fr12
8c10d546:  bf 0x8c10d560
8c10d548:  fldi1 fr0
8c10d54a:  fsub fr0,fr13                 ; over-bright part (acc - 1) -> offset colour
8c10d54c:  mov.l 0x8c10d660,r2 ! 8c112e60
8c10d54e:  fsub fr0,fr14
8c10d550:  add #16,r2
8c10d552:  fsub fr0,fr15
8c10d554:  fmov @r2+,fr0
8c10d556:  fmul fr1,fr13
8c10d558:  fmov @r2+,fr0
8c10d55a:  fmul fr0,fr14
8c10d55c:  bra 0x8c10d576
8c10d55e:  fmul fr1,fr15
8c10d560:  mov #67,r1
8c10d562:  mov #127,r2
8c10d564:  shll8 r1
8c10d566:  or r2,r1
8c10d568:  shll16 r1
8c10d56a:  lds r1,fpul
8c10d56c:  fsts fpul,fr0                 ; 255.0
8c10d56e:  mov #-1,r13
8c10d570:  extu.b r13,r13
8c10d572:  bra 0x8c10d5c0
8c10d574:  mov #0,r1
8c10d576:  mov #67,r1
8c10d578:  mov #127,r2
8c10d57a:  shll8 r1
8c10d57c:  or r2,r1
8c10d57e:  shll16 r1
8c10d580:  lds r1,fpul
8c10d582:  fsts fpul,fr0
8c10d584:  mov #-1,r13
8c10d586:  extu.b r13,r13
8c10d588:  mov #0,r1
8c10d58a:  fcmp/gt fr12,fr13
8c10d58c:  bf.s 0x8c10d598
8c10d58e:  fcmp/gt fr0,fr13
8c10d590:  bt.s 0x8c10d598
8c10d592:  mov r13,r1
8c10d594:  ftrc fr13,fpul                ; clamp + ftrc per channel
8c10d596:  sts fpul,r1
8c10d598:  shll8 r1
8c10d59a:  fcmp/gt fr12,fr14
8c10d59c:  bf.s 0x8c10d5ac
8c10d59e:  fcmp/gt fr0,fr14
8c10d5a0:  bf 0x8c10d5a6
8c10d5a2:  bra 0x8c10d5ac
8c10d5a4:  or r13,r1
8c10d5a6:  ftrc fr14,fpul
8c10d5a8:  sts fpul,r2
8c10d5aa:  or r2,r1
8c10d5ac:  shll8 r1
8c10d5ae:  fcmp/gt fr12,fr15
8c10d5b0:  bf.s 0x8c10d5c0
8c10d5b2:  fcmp/gt fr0,fr15
8c10d5b4:  bf 0x8c10d5ba
8c10d5b6:  bra 0x8c10d5c0
8c10d5b8:  or r13,r1
8c10d5ba:  ftrc fr15,fpul
8c10d5bc:  sts fpul,r2
8c10d5be:  or r2,r1
8c10d5c0:  add #-12,r4
8c10d5c2:  mov.l r1,@r4                  ; offset ARGB -> vertex+20 (old nz slot)
8c10d5c4:  add #12,r4
8c10d5c6:  mov #0,r1
8c10d5c8:  fcmp/gt fr0,fr8
8c10d5ca:  bt.s 0x8c10d5d2
8c10d5cc:  mov r13,r1
8c10d5ce:  ftrc fr8,fpul
8c10d5d0:  sts fpul,r1
8c10d5d2:  shll8 r1
8c10d5d4:  fcmp/gt fr0,fr9
8c10d5d6:  bf 0x8c10d5dc
8c10d5d8:  bra 0x8c10d5e2
8c10d5da:  or r13,r1
8c10d5dc:  ftrc fr9,fpul
8c10d5de:  sts fpul,r2
8c10d5e0:  or r2,r1
8c10d5e2:  shll8 r1
8c10d5e4:  fcmp/gt fr0,fr10
8c10d5e6:  bf 0x8c10d5ec
8c10d5e8:  bra 0x8c10d5f2
8c10d5ea:  or r13,r1
8c10d5ec:  ftrc fr10,fpul
8c10d5ee:  sts fpul,r2
8c10d5f0:  or r2,r1
8c10d5f2:  shll8 r1
8c10d5f4:  fcmp/gt fr0,fr11
8c10d5f6:  bf 0x8c10d5fc
8c10d5f8:  bra 0x8c10d602
8c10d5fa:  or r13,r1
8c10d5fc:  ftrc fr11,fpul
8c10d5fe:  sts fpul,r2
8c10d600:  or r2,r1
8c10d602:  add #-16,r4
8c10d604:  mov.l r1,@r4                  ; base ARGB -> vertex+16 (old ny slot)
8c10d606:  add #16,r4
8c10d608:  mov.l 0x8c10d66c,r13 ! 8c1130f0
8c10d60a:  dt r3
8c10d60c:  mov r4,r14
8c10d60e:  bt 0x8c10d61c
8c10d610:  tst #1,r0
8c10d612:  bt 0x8c10d618
8c10d614:  bra 0x8c10d38c
8c10d616:  nop
8c10d618:  bra 0x8c10d36c
8c10d61a:  fschg
8c10d61c:  mov.l @r4+,r0                 ; next strip header
8c10d61e:  cmp/pl r0
8c10d620:  bf 0x8c10d63e
8c10d622:  tst #128,r0
8c10d624:  mov.l 0x8c10d66c,r13 ! 8c1130f0
8c10d626:  bt 0x8c10d63e
8c10d628:  mov.l @r4+,r3
8c10d62a:  mov.l @r4,r0
8c10d62c:  mov r4,r14
8c10d62e:  mov.l @r13,r13
8c10d630:  tst #1,r0
8c10d632:  mov.l 0x8c10d664,r0 ! 8c1130e0
8c10d634:  bt 0x8c10d638
8c10d636:  bra 0x8c10d392
8c10d638:  fmov @r0+,fr12
8c10d63a:  bra 0x8c10d36c
8c10d63c:  fschg
8c10d63e:  add #-4,r4
8c10d640:  fschg
8c10d642:  rts

;; ==== 0x8c1042da  restore pass (0x8c104290): type back from header+80>>16, s8 normals re-expanded to floats and renormalised ====
8c1042da:  mov r4,r13
8c1042dc:  mov.l @(36,r13),r6
8c1042de:  mov r13,r5
8c1042e0:  add #80,r4
8c1042e2:  mov r6,r0
8c1042e4:  cmp/eq #-3,r0
8c1042e6:  mov.l r4,@r15
8c1042e8:  add #100,r5
8c1042ea:  bf.s 0x8c104390
8c1042ec:  mov.l @r5,r5
8c1042ee:  cmp/pz r5
8c1042f0:  bt 0x8c104390
8c1042f2:  mov #80,r0
8c1042f4:  mov.l @(r0,r13),r3
8c1042f6:  shlr16 r3
8c1042f8:  exts.w r3,r3
8c1042fa:  exts.b r3,r3
8c1042fc:  mov.l r3,@(36,r13)            ; restore original mesh type
8c1042fe:  mov.l @(r0,r13),r2
8c104300:  mov.l 0x8c1043e0,r3 ! ff00ffff
8c104302:  and r3,r2
8c104304:  mov.l r2,@(r0,r13)
8c104306:  mov.l @r4,r5
8c104308:  cmp/pl r5
8c10430a:  bf.s 0x8c104390
8c10430c:  mov.l @(36,r13),r10
8c10430e:  mov r4,r0
8c104310:  mov.b @r0,r0
8c104312:  mov.l @(4,r4),r12
8c104314:  mov r4,r5
8c104316:  tst #8,r0
8c104318:  mov r4,r14
8c10431a:  bt.s 0x8c104324
8c10431c:  add #8,r14
8c10431e:  mov r12,r3
8c104320:  shll r12
8c104322:  add r3,r12
8c104324:  cmp/pl r12
8c104326:  bf.s 0x8c104388
8c104328:  mov r8,r11
8c10432a:  mov r14,r3
8c10432c:  add #32,r3
8c10432e:  pref @r3
8c104330:  mov.l @r14,r2
8c104332:  tst r9,r2
8c104334:  bt 0x8c104380
8c104336:  cmp/pz r10
8c104338:  bf 0x8c104370
8c10433a:  mov r14,r4
8c10433c:  mov.l @(12,r4),r4             ; packed s8 normal word
8c10433e:  mov #12,r0
8c104340:  mov r4,r3
8c104342:  shlr16 r3
8c104344:  exts.b r3,r3
8c104346:  lds r3,fpul
8c104348:  mov r4,r3
8c10434a:  shlr8 r3
8c10434c:  exts.b r3,r3
8c10434e:  float fpul,fr3
8c104350:  lds r3,fpul
8c104352:  exts.b r4,r4
8c104354:  mov.l 0x8c1043e4,r3 ! 8c0fea00
8c104356:  fmov fr3,@(r0,r14)
8c104358:  float fpul,fr3
8c10435a:  lds r4,fpul
8c10435c:  mov #16,r0
8c10435e:  mov r14,r4
8c104360:  fmov fr3,@(r0,r14)
8c104362:  float fpul,fr3
8c104364:  mov #20,r0
8c104366:  fmov fr3,@(r0,r14)
8c104368:  jsr @r3                       ; renormalise (0x8c0fea00)
8c10436a:  add #12,r4
8c10436c:  bra 0x8c10437c
8c10436e:  nop
8c104370:  mov #12,r0                    ; unlit meshes get (1,0,0)
8c104372:  fmov fr14,@(r0,r14)
8c104374:  mov #16,r0
8c104376:  fmov fr15,@(r0,r14)
8c104378:  mov #20,r0
8c10437a:  fmov fr15,@(r0,r14)
8c10437c:  bra 0x8c104382
8c10437e:  add #32,r14
8c104380:  add #8,r14
8c104382:  add #1,r11
8c104384:  cmp/ge r12,r11
8c104386:  bf 0x8c10432a
8c104388:  bra 0x8c104306
8c10438a:  mov r14,r4

;; ################################################################ SECTION E
;; ==== 0x8c112560  sphere-map UV pre-pass (9 game call sites from 7 literal loads: 0x8c093e76, 0x8c0a8c00, 0x8c0c5486, 0x8c0c5642, 0x8c0c596a, 0x8c0ca086, 0x8c0cc78a) ====
;; Same idea as SM2 0x8c03bf40 but lives in the library region: rewrites (u,v) of each inline vertex of strips whose flag
;; has bit 8, from the normal rotated by XMTRX (view rotation): u = 0.5 + s*n'x, v = 0.5 + s*n'y (s = 0.5, or 1/256 for
;; type -3 meshes with s8 normals), keeping the old LSB of the v word. Then the normal draw runs.
;; cost: 31 instr per float-normal vertex (1 FTRV, result used 2 instr later: ~3 cycles stall), ~40 with s8 normals.
8c112560:  mov.l @r4,r5
8c112562:  add #60,r4
8c112564:  mova 0x8c112688,r0            ; constants {0.5, 0.5, 0x100}
8c112566:  mov.b @r4,r2
8c112568:  cmp/pz r5
8c11256a:  fmov @r0+,fr1
8c11256c:  bf 0x8c1125e6
8c11256e:  fmov @r0+,fr8
8c112570:  add #44,r4
8c112572:  mov.l @r0+,r7
8c112574:  mov #-2,r6
8c112576:  mov.l @r4+,r1
8c112578:  cmp/eq r6,r2                  ; mesh type -2 (bump): skip
8c11257a:  bt 0x8c1125fa
8c11257c:  tst r1,r7                     ; strip flag & 0x100: env-mapped?
8c11257e:  bt 0x8c1125fa
8c112580:  cmp/gt r6,r2                  ; type -3 (s8 normals) path at 0x8c112602
8c112582:  bf 0x8c112602
8c112584:  mov r1,r0
8c112586:  tst #8,r0
8c112588:  mov.l @r4+,r5
8c11258a:  bt.s 0x8c112594
8c11258c:  fmov fr1,fr0
8c11258e:  mov r5,r0                     ; triangle list: n*3 entries
8c112590:  shll r5
8c112592:  add r0,r5
8c112594:  mov.l @r4,r2
8c112596:  mov #1,r0
8c112598:  fldi0 fr7
8c11259a:  add #12,r4
8c11259c:  tst r0,r2                     ; inline vertex?
8c11259e:  bt 0x8c1125ea
8c1125a0:  fmov @r4+,fr4                 ; normal (w = 0)
8c1125a2:  fmov @r4+,fr5
8c1125a4:  fmov @r4,fr6
8c1125a6:  add #8,r4
8c1125a8:  mov.l @r4,r1
8c1125aa:  add #36,r4
8c1125ac:  pref @r4                      ; prefetch next record
8c1125ae:  add #-32,r4
8c1125b0:  ftrv xmtrx,fv4                ; rotate normal into view space
8c1125b2:  and r0,r1
8c1125b4:  fmov fr1,fr2
8c1125b6:  fmov fr1,fr3
8c1125b8:  fmac fr0,fr4,fr2              ; u = 0.5 + s*nx'
8c1125ba:  fmac fr0,fr5,fr3              ; v = 0.5 + s*ny'
8c1125bc:  flds fr3,fpul
8c1125be:  sts fpul,r2
8c1125c0:  mov #-8,r0
8c1125c2:  fmov fr2,@(r0,r4)             ; store u
8c1125c4:  dt r5
8c1125c6:  mov #-4,r0
8c1125c8:  and r6,r2
8c1125ca:  or r2,r1
8c1125cc:  mov.l @r4,r2
8c1125ce:  mov.l r1,@(r0,r4)             ; store v (old LSB kept)
8c1125d0:  bf 0x8c112596
8c1125d2:  mov.l @r4+,r1
8c1125d4:  cmp/pl r1
8c1125d6:  bt 0x8c112584
8c1125d8:  tst r1,r1
8c1125da:  bt 0x8c1125e6
8c1125dc:  add #32,r4
8c1125de:  mov.b @r4,r2
8c1125e0:  add #44,r4
8c1125e2:  bra 0x8c112578
8c1125e4:  mov.l @r4+,r1
8c1125e6:  rts
8c1125e8:  nop
8c1125ea:  mov r4,r0
8c1125ec:  add #32,r0
8c1125ee:  dt r5
8c1125f0:  pref @r0
8c1125f2:  add #-4,r4
8c1125f4:  bf 0x8c112594
8c1125f6:  bra 0x8c1125d4
8c1125f8:  mov.l @r4+,r1
8c1125fa:  add #-8,r4
8c1125fc:  mov.l @r4+,r0
8c1125fe:  bra 0x8c1125d2
8c112600:  add r0,r4
8c112602:  mov r1,r0
8c112604:  tst #8,r0
8c112606:  mov.l @r4+,r5
8c112608:  bt.s 0x8c112612
8c11260a:  fmov fr8,fr0
8c11260c:  mov r5,r0
8c11260e:  shll r5
8c112610:  add r0,r5
8c112612:  mov.l @r4,r2
8c112614:  mov #1,r0
8c112616:  mov.l @(12,r4),r3
8c112618:  tst r0,r2
8c11261a:  add #13,r4
8c11261c:  bt 0x8c112676
8c11261e:  mov.b @r4+,r2
8c112620:  exts.b r3,r3                  ; s8 normals: 3x float
8c112622:  mov.b @r4,r1
8c112624:  lds r3,fpul
8c112626:  add #14,r4
8c112628:  float fpul,fr6
8c11262a:  lds r2,fpul
8c11262c:  float fpul,fr5
8c11262e:  lds r1,fpul
8c112630:  float fpul,fr4
8c112632:  fldi0 fr7
8c112634:  mov.l @r4,r1
8c112636:  add #36,r4
8c112638:  pref @r4
8c11263a:  add #-32,r4
8c11263c:  ftrv xmtrx,fv4
8c11263e:  and r0,r1
8c112640:  fmov fr1,fr2
8c112642:  fmov fr1,fr3
8c112644:  fmac fr0,fr4,fr2
8c112646:  fmac fr0,fr5,fr3
8c112648:  flds fr3,fpul
8c11264a:  sts fpul,r2
8c11264c:  mov #-8,r0
8c11264e:  fmov fr2,@(r0,r4)
8c112650:  dt r5
8c112652:  mov #-4,r0
8c112654:  and r6,r2
8c112656:  or r2,r1
8c112658:  mov.l @r4,r2
8c11265a:  mov.l r1,@(r0,r4)
8c11265c:  bf 0x8c112614
8c11265e:  mov.l @r4+,r1
8c112660:  cmp/pl r1
8c112662:  bt 0x8c112602
8c112664:  tst r1,r1
8c112666:  bt 0x8c112672
8c112668:  add #32,r4
8c11266a:  mov.b @r4,r2
8c11266c:  add #44,r4
8c11266e:  bra 0x8c112578
8c112670:  mov.l @r4+,r1
8c112672:  rts
8c112674:  nop
8c112676:  mov r4,r0
8c112678:  add #32,r0
8c11267a:  dt r5
8c11267c:  pref @r0
8c11267e:  add #-5,r4
8c112680:  bf 0x8c112612
8c112682:  bra 0x8c112660
8c112684:  mov.l @r4+,r1

;; ################################################################ SECTION F
;; ==== 0x8c0c5996  soft parts: write simulated particle positions into MT7 vertex records (callers 0x8c0c65da, 0x8c0c6f8a) ====
;; Part of the per-character accessory system (0x8c0c4000-0x8c0c7c00, data in *_A0n.ACS): each object has particles (48 B
;; records, position first) simulated in world space; here XMTRX = inverse of the owning bone (64 B matrices at *0x8c29daf8,
;; inverted by 0x8c0fd2b0) and each particle is transformed into the bone's model space by 0x8c111b80 and stored into
;; the x,y,z of every vertex record listed for it (list at obj+0x1f0: first entry LSB=1, duplicates/seams LSB=0, -1 ends).
;; The x word gets |1 so the walker treats the record as inline. The model is then drawn with the normal NL path.
;; cost: ~36 instr + 0x8c111b80 (~9 instr, 1 FTRV with the result stored immediately: ~4-cycle stall) per particle, ~10 per duplicate.
8c0c59a8:  mov.w 0x8c0c5a82,r0 ! 1f0
8c0c59aa:  mov r4,r8
8c0c59ac:  mov.l @(r0,r8),r9             ; vertex-offset list
8c0c59ae:  tst r9,r9
8c0c59b0:  bt.s 0x8c0c5a6c
8c0c59b2:  mov r6,r11
8c0c59b4:  mov.b @(1,r8),r0
8c0c59b6:  mov.l 0x8c0c5a98,r2 ! 8c29daf8
8c0c59b8:  extu.b r0,r5
8c0c59ba:  mov r5,r4
8c0c59bc:  shll2 r4
8c0c59be:  mov.l @r2,r3
8c0c59c0:  shll2 r4
8c0c59c2:  shll2 r4
8c0c59c4:  add r3,r4
8c0c59c6:  mov.l 0x8c0c5a9c,r3 ! 8c110f80
8c0c59c8:  jsr @r3                       ; XMTRX = bone matrix of this part
8c0c59ca:  nop
8c0c59cc:  mov #76,r0
8c0c59ce:  mov.l @(r0,r8),r12
8c0c59d0:  mov.b @(4,r8),r0
8c0c59d2:  extu.b r0,r0
8c0c59d4:  cmp/pl r0
8c0c59d6:  mov.l r0,@r15
8c0c59d8:  bf.s 0x8c0c5a6c
8c0c59da:  mov #1,r13
8c0c59dc:  mov.b @(5,r8),r0
8c0c59de:  extu.b r0,r10
8c0c59e0:  cmp/pl r10
8c0c59e2:  bf.s 0x8c0c5a62
8c0c59e4:  add #48,r12
8c0c59e6:  mov.l @r9+,r14                ; next list entry
8c0c59e8:  mov r14,r0
8c0c59ea:  nop
8c0c59ec:  cmp/eq #-1,r0
8c0c59ee:  bt 0x8c0c5a5a
8c0c59f0:  mov r14,r2
8c0c59f2:  tst r13,r2                    ; LSB=1: particle shared by several records (copy loop)
8c0c59f4:  bt 0x8c0c5a4a
8c0c59f6:  mov.l 0x8c0c5aa0,r2 ! 8c111b80
8c0c59f8:  mov r15,r5
8c0c59fa:  add #4,r5
8c0c59fc:  jsr @r2                       ; transform particle (0x8c111b80) into a temp
8c0c59fe:  mov r12,r4
8c0c5a00:  mov r15,r3
8c0c5a02:  add #4,r3
8c0c5a04:  mov.l @r3,r2
8c0c5a06:  or r13,r2                     ; set inline tag bit
8c0c5a08:  mov.l r2,@r3
8c0c5a0a:  mov #4,r0
8c0c5a0c:  mov #-2,r4
8c0c5a0e:  fmov @(r0,r15),fr3
8c0c5a10:  and r14,r4
8c0c5a12:  add r11,r4
8c0c5a14:  mov #8,r0
8c0c5a16:  fmov fr3,@r4                  ; copy x,y,z into a duplicate vertex record
8c0c5a18:  fmov @(r0,r15),fr3
8c0c5a1a:  mov #4,r0
8c0c5a1c:  fmov fr3,@(r0,r4)
8c0c5a1e:  mov #12,r0
8c0c5a20:  fmov @(r0,r15),fr3
8c0c5a22:  mov #8,r0
8c0c5a24:  fmov fr3,@(r0,r4)
8c0c5a26:  mov.l @r9+,r14
8c0c5a28:  mov r14,r3
8c0c5a2a:  tst r13,r3
8c0c5a2c:  bf 0x8c0c5a0a
8c0c5a2e:  mov #4,r0
8c0c5a30:  mov r11,r4
8c0c5a32:  fmov @(r0,r15),fr3
8c0c5a34:  add r14,r4
8c0c5a36:  mov #8,r0
8c0c5a38:  fmov fr3,@r4
8c0c5a3a:  fmov @(r0,r15),fr3
8c0c5a3c:  mov #4,r0
8c0c5a3e:  fmov fr3,@(r0,r4)
8c0c5a40:  mov #12,r0
8c0c5a42:  fmov @(r0,r15),fr3
8c0c5a44:  mov #8,r0
8c0c5a46:  bra 0x8c0c5a5a
8c0c5a48:  fmov fr3,@(r0,r4)
8c0c5a4a:  mov.l 0x8c0c5aa0,r2 ! 8c111b80
8c0c5a4c:  add r11,r14
8c0c5a4e:  mov r14,r5
8c0c5a50:  jsr @r2                       ; single record: transform straight into it
8c0c5a52:  mov r12,r4
8c0c5a54:  mov.l @r14,r3
8c0c5a56:  or r13,r3
8c0c5a58:  mov.l r3,@r14                 ; set inline tag bit
8c0c5a5a:  add #-1,r10
8c0c5a5c:  cmp/pl r10
8c0c5a5e:  bt.s 0x8c0c59e6
8c0c5a60:  add #48,r12                   ; next particle (48 B)
8c0c5a62:  mov.l @r15,r3
8c0c5a64:  add #-1,r3
8c0c5a66:  cmp/pl r3
8c0c5a68:  bt.s 0x8c0c59dc
8c0c5a6a:  mov.l r3,@r15
8c0c5a6c:  add #16,r15
8c0c5a6e:  lds.l @r15+,pr
8c0c5a70:  mov.l @r15+,r8
8c0c5a72:  mov.l @r15+,r9
8c0c5a74:  mov.l @r15+,r10
8c0c5a76:  mov.l @r15+,r11
8c0c5a78:  mov.l @r15+,r12
8c0c5a7a:  mov.l @r15+,r13
8c0c5a7c:  rts
8c0c5a7e:  mov.l @r15+,r14

;; ==== 0x8c111b80  transform point (r4 -> r5, or in place when r5 = 0) ====
8c111b80:  tst r5,r5
8c111b82:  fldi1 fr7
8c111b84:  bt.s 0x8c111b98
8c111b86:  fmov @r4+,fr4
8c111b88:  add #8,r5
8c111b8a:  fmov @r4+,fr5
8c111b8c:  fmov @r4,fr6
8c111b8e:  ftrv xmtrx,fv4                ; FTRV result stored next instruction (stall)
8c111b90:  fmov fr6,@r5
8c111b92:  fmov fr5,@-r5
8c111b94:  rts
8c111b96:  fmov fr4,@-r5
8c111b98:  fmov @r4+,fr5
8c111b9a:  fmov @r4,fr6
8c111b9c:  ftrv xmtrx,fv4
8c111b9e:  fmov fr6,@r4
8c111ba0:  fmov fr5,@-r4
8c111ba2:  rts
8c111ba4:  fmov fr4,@-r4

;; ==== 0x8c0c6278  chain distance constraint (one of 6 copies: 0x8c0c6278, 633a, 63fc, 6afe, 6bd2, 6ca4) ====
;; Position-based: for consecutive particles d = |p1 - p0| (FSQRT), if d > rest (fr15) both ends move by
;; (d - rest)*fr13/d along the segment (one FDIV). 81 instr per link, all scalar (fsub/fmul/fmac; no FIPR).
8c0c6278:  mov r13,r7
8c0c627a:  mov r8,r5
8c0c627c:  fmov @r7,fr2
8c0c627e:  mov #4,r0
8c0c6280:  fmov @r5,fr3
8c0c6282:  fadd fr3,fr2
8c0c6284:  fmov @r6,fr3
8c0c6286:  fsub fr3,fr2
8c0c6288:  fmov @r4,fr3
8c0c628a:  fmov fr2,fr5
8c0c628c:  fsub fr3,fr5
8c0c628e:  fmov @(r0,r7),fr2
8c0c6290:  fmov @(r0,r5),fr3
8c0c6292:  fadd fr3,fr2
8c0c6294:  fmov @(r0,r6),fr3
8c0c6296:  fmov fr5,fr0
8c0c6298:  fsub fr3,fr2
8c0c629a:  fmov @(r0,r4),fr3
8c0c629c:  mov #8,r0
8c0c629e:  fmov fr2,fr4
8c0c62a0:  fsub fr3,fr4
8c0c62a2:  fmov @(r0,r7),fr2
8c0c62a4:  fmov @(r0,r5),fr3
8c0c62a6:  fadd fr3,fr2
8c0c62a8:  fmov @(r0,r6),fr3
8c0c62aa:  fsub fr3,fr2
8c0c62ac:  fmov @(r0,r4),fr3
8c0c62ae:  fmov fr2,fr6
8c0c62b0:  fsub fr3,fr6
8c0c62b2:  fmov fr4,fr3
8c0c62b4:  fmul fr4,fr3                  ; d^2 = dx^2 + dy^2 + dz^2 (scalar, no FIPR)
8c0c62b6:  fmac fr0,fr5,fr3
8c0c62b8:  fmov fr6,fr0
8c0c62ba:  fmac fr0,fr6,fr3
8c0c62bc:  mov.l 0x8c0c6328,r2 ! 8c2a3e48
8c0c62be:  mov.l @r2,r3
8c0c62c0:  fsqrt fr3                     ; d
8c0c62c2:  fmov fr3,fr7
8c0c62c4:  fcmp/gt fr15,fr7              ; stretched beyond rest length?
8c0c62c6:  movt r0
8c0c62c8:  or r3,r0
8c0c62ca:  tst r0,r0
8c0c62cc:  bt.s 0x8c0c630a
8c0c62ce:  mov r13,r6
8c0c62d0:  fmov fr7,fr3
8c0c62d2:  fsub fr15,fr3
8c0c62d4:  fmov fr7,fr2
8c0c62d6:  mov #4,r0
8c0c62d8:  fmul fr13,fr3
8c0c62da:  fmov fr3,fr7
8c0c62dc:  fdiv fr2,fr7                  ; (d - rest)*k / d
8c0c62de:  fmov @r5,fr3
8c0c62e0:  fmul fr7,fr5
8c0c62e2:  fmul fr7,fr4
8c0c62e4:  fmul fr7,fr6
8c0c62e6:  fsub fr5,fr3                  ; move p1 back
8c0c62e8:  fmov fr3,@r5
8c0c62ea:  fmov @r4,fr2
8c0c62ec:  fadd fr5,fr2                  ; move p0 forward
8c0c62ee:  fmov fr2,@r4
8c0c62f0:  fmov @(r0,r5),fr3
8c0c62f2:  fsub fr4,fr3
8c0c62f4:  fmov fr3,@(r0,r5)
8c0c62f6:  fmov @(r0,r4),fr2
8c0c62f8:  fadd fr4,fr2
8c0c62fa:  fmov fr2,@(r0,r4)
8c0c62fc:  mov #8,r0
8c0c62fe:  fmov @(r0,r5),fr3
8c0c6300:  fsub fr6,fr3
8c0c6302:  fmov fr3,@(r0,r5)
8c0c6304:  fmov @(r0,r4),fr2
8c0c6306:  fadd fr6,fr2
8c0c6308:  fmov fr2,@(r0,r4)
8c0c630a:  mov.l @r15,r3
8c0c630c:  mov r8,r4
8c0c630e:  add #12,r13
8c0c6310:  add #-1,r3
8c0c6312:  cmp/pl r3
8c0c6314:  add #12,r8
8c0c6316:  bt.s 0x8c0c6278
8c0c6318:  mov.l r3,@r15

;; ################################################################ SECTION G
;; ==== 0x8c0cf8fa..0x8c0cfa16  per-vertex animation blends into MT7 vertex records (APV data); no static caller found ====
;; r4 = list of vertex byte offsets (-1 ends), r7/r6 = model base, keyframes are packed xyz (12 B). Each writes x,y,z of the
;; record and ORs 1 into x (inline tag). AYA00.APV: 9 group slots, e.g. 236 vertices x 8 position blocks (base + 7 targets) of 12 B (facial animation, probably).
;;   0x8c0cf8fa: v = A + t*B          24 instr/vertex (3 FMAC, 1 pref)
;;   0x8c0cf940: v = (t*A + (1-t)*B) + C   37 instr/vertex
;;   0x8c0cf9a6: v = A (copy key)      18 instr/vertex
;;   0x8c0cf9da: v += t*A              24 instr/vertex
8c0cf8fa:  mov.l r14,@-r15
8c0cf8fc:  mov r5,r14
8c0cf8fe:  mov.l r13,@-r15
8c0cf900:  mov r6,r13
8c0cf902:  mov.l @r4,r0
8c0cf904:  cmp/eq #-1,r0
8c0cf906:  bt.s 0x8c0cf93a
8c0cf908:  mov #1,r1
8c0cf90a:  pref @r14                     ; prefetch key A
8c0cf90c:  fmov @r14+,fr7
8c0cf90e:  fmov @r13+,fr3
8c0cf910:  fmov fr4,fr0
8c0cf912:  fmac fr0,fr3,fr7              ; x = A.x + t*B.x
8c0cf914:  fmov @r14+,fr6
8c0cf916:  fmov @r13+,fr3
8c0cf918:  fmov @r14+,fr5
8c0cf91a:  fmac fr0,fr3,fr6
8c0cf91c:  fmov @r13+,fr3
8c0cf91e:  mov.l @r4+,r5                 ; vertex byte offset
8c0cf920:  fmac fr0,fr3,fr5
8c0cf922:  add r7,r5
8c0cf924:  mov r5,r6
8c0cf926:  add #8,r5
8c0cf928:  fmov fr7,@r6
8c0cf92a:  fmov fr5,@r5
8c0cf92c:  mov.l @r6,r3
8c0cf92e:  or r1,r3
8c0cf930:  mov.l r3,@r6                  ; x |= 1: keep the inline tag
8c0cf932:  fmov fr6,@-r5
8c0cf934:  mov.l @r4,r0
8c0cf936:  cmp/eq #-1,r0
8c0cf938:  bf 0x8c0cf90a
8c0cf93a:  mov.l @r15+,r13
8c0cf93c:  rts
8c0cf93e:  mov.l @r15+,r14
8c0cf940:  fldi1 fr5
8c0cf942:  fsub fr4,fr5
8c0cf944:  mov.l r14,@-r15
8c0cf946:  mov r7,r1
8c0cf948:  mov.l r12,@-r15
8c0cf94a:  mov r5,r14
8c0cf94c:  mov.l @r4,r0
8c0cf94e:  mov r6,r12
8c0cf950:  cmp/eq #-1,r0
8c0cf952:  bt.s 0x8c0cf9a0
8c0cf954:  mov #1,r7
8c0cf956:  pref @r14
8c0cf958:  fmov @r1+,fr3
8c0cf95a:  fmov @r12+,fr2
8c0cf95c:  fmul fr4,fr3
8c0cf95e:  fmov fr5,fr0
8c0cf960:  mov.l @r4+,r5
8c0cf962:  mov.l @(8,r15),r3
8c0cf964:  fmac fr0,fr2,fr3              ; t*A + (1-t)*B
8c0cf966:  fmov @r14+,fr2
8c0cf968:  add r3,r5
8c0cf96a:  mov r5,r6
8c0cf96c:  add #8,r5
8c0cf96e:  fmov fr3,fr6
8c0cf970:  fadd fr2,fr6                  ; + C
8c0cf972:  fmov @r1+,fr3
8c0cf974:  fmov @r12+,fr2
8c0cf976:  fmul fr4,fr3
8c0cf978:  fmac fr0,fr2,fr3
8c0cf97a:  fmov @r14+,fr2
8c0cf97c:  fmov fr3,fr7
8c0cf97e:  fadd fr2,fr7
8c0cf980:  fmov @r1+,fr3
8c0cf982:  fmov @r12+,fr2
8c0cf984:  fmul fr4,fr3
8c0cf986:  fmac fr0,fr2,fr3
8c0cf988:  fmov @r14+,fr2
8c0cf98a:  fmov fr6,@r6
8c0cf98c:  fmov fr3,fr8
8c0cf98e:  fadd fr2,fr8
8c0cf990:  fmov fr8,@r5
8c0cf992:  mov.l @r6,r3
8c0cf994:  or r7,r3
8c0cf996:  mov.l r3,@r6
8c0cf998:  fmov fr7,@-r5
8c0cf99a:  mov.l @r4,r0
8c0cf99c:  cmp/eq #-1,r0
8c0cf99e:  bf 0x8c0cf956
8c0cf9a0:  mov.l @r15+,r12
8c0cf9a2:  rts
8c0cf9a4:  mov.l @r15+,r14
8c0cf9a6:  mov r5,r7
8c0cf9a8:  pref @r7
8c0cf9aa:  mov.l @r4,r0
8c0cf9ac:  cmp/eq #-1,r0
8c0cf9ae:  bt.s 0x8c0cf9d6
8c0cf9b0:  mov #1,r1
8c0cf9b2:  fmov @r7+,fr5
8c0cf9b4:  mov.l @r4+,r5
8c0cf9b6:  fmov @r7+,fr4
8c0cf9b8:  add r6,r5
8c0cf9ba:  mov r5,r0
8c0cf9bc:  nop
8c0cf9be:  fmov @r7+,fr6
8c0cf9c0:  add #8,r5
8c0cf9c2:  fmov fr5,@r0
8c0cf9c4:  fmov fr6,@r5
8c0cf9c6:  mov.l @r0,r3
8c0cf9c8:  or r1,r3
8c0cf9ca:  mov.l r3,@r0
8c0cf9cc:  fmov fr4,@-r5
8c0cf9ce:  pref @r7
8c0cf9d0:  mov.l @r4,r0
8c0cf9d2:  cmp/eq #-1,r0
8c0cf9d4:  bf 0x8c0cf9b2
8c0cf9d6:  rts
8c0cf9d8:  nop
8c0cf9da:  mov r5,r7
8c0cf9dc:  pref @r7
8c0cf9de:  mov.l @r4,r0
8c0cf9e0:  cmp/eq #-1,r0
8c0cf9e2:  bt.s 0x8c0cfa16
8c0cf9e4:  mov #1,r1
8c0cf9e6:  mov.l @r4+,r5
8c0cf9e8:  add r6,r5
8c0cf9ea:  mov r5,r0
8c0cf9ec:  nop
8c0cf9ee:  fmov @r5+,fr6
8c0cf9f0:  fmov @r7+,fr3
8c0cf9f2:  fmov fr4,fr0
8c0cf9f4:  fmac fr0,fr3,fr6              ; v += t*A (in place)
8c0cf9f6:  fmov @r5+,fr5
8c0cf9f8:  fmov @r7+,fr3
8c0cf9fa:  fmov @r5+,fr7
8c0cf9fc:  fmac fr0,fr3,fr5
8c0cf9fe:  fmov @r7+,fr3
8c0cfa00:  fmov fr6,@r0
8c0cfa02:  fmac fr0,fr3,fr7
8c0cfa04:  fmov fr7,@-r5
8c0cfa06:  mov.l @r0,r3
8c0cfa08:  or r1,r3
8c0cfa0a:  mov.l r3,@r0
8c0cfa0c:  fmov fr5,@-r5
8c0cfa0e:  pref @r7
8c0cfa10:  mov.l @r4,r0
8c0cfa12:  cmp/eq #-1,r0
8c0cfa14:  bf 0x8c0cf9e6
8c0cfa16:  rts
8c0cfa18:  nop

;; ################################################################ SECTION H
;; ==== 0x8c0d43e8  character shadow: shear matrix for one limb volume (driver 0x8c0d3df0, 15 calls per character) ====
;; Builds at 0x8c2a60f0 a matrix that maps a unit volume model onto the segment joint A (r4) -> joint B (r5) sheared along the
;; light direction 0x8c2a60e0 (B - L*B.y), renormalises (0x8c0fea00), multiplies by the view (0x8c21a148), then tail-calls
;; 0x8c101430 = NL modifier-volume draw of the volume model taken from the character's CHR table (the run of 15 untextured
;; type -1 hulls, models 33-47 in AYA00, probably). Floor meshes have PCW bit 7 set (0x..ac/0x..bc), characters do not.
8c0d43e8:  mov.l r14,@-r15
8c0d43ea:  mov #4,r0
8c0d43ec:  sts.l pr,@-r15
8c0d43ee:  mov.l 0x8c0d44f0,r14 ! 8c2a60f0
8c0d43f0:  mov.l r6,@-r15
8c0d43f2:  mov.l 0x8c0d44dc,r6 ! 8c2a60e0
8c0d43f4:  fmov @(r0,r5),fr4
8c0d43f6:  mov #8,r0
8c0d43f8:  fmov @r6,fr3
8c0d43fa:  fmov @(r0,r6),fr2
8c0d43fc:  fmul fr4,fr3                  ; light dir scaled by joint height
8c0d43fe:  fmov @r5,fr5
8c0d4400:  fmul fr4,fr2
8c0d4402:  fmov @(r0,r5),fr4
8c0d4404:  mov #48,r0
8c0d4406:  fsub fr3,fr5                  ; sheared axis
8c0d4408:  fmov @r4,fr3
8c0d440a:  fsub fr2,fr4
8c0d440c:  fmov fr3,@(r0,r14)            ; translation = joint A
8c0d440e:  mov #16,r0
8c0d4410:  fmov fr5,@(r0,r14)
8c0d4412:  mov #8,r0
8c0d4414:  fmov fr5,@(r0,r14)
8c0d4416:  fmov @(r0,r4),fr3
8c0d4418:  mov #56,r0
8c0d441a:  fmov fr3,@(r0,r14)
8c0d441c:  mov #24,r0
8c0d441e:  fmov fr4,@(r0,r14)
8c0d4420:  mov #4,r0
8c0d4422:  fneg fr4
8c0d4424:  fmov fr4,@r14
8c0d4426:  fmov @(r0,r4),fr3
8c0d4428:  mov #52,r0
8c0d442a:  mov.l 0x8c0d44f4,r3 ! 8c0fea00
8c0d442c:  fmov fr3,@(r0,r14)
8c0d442e:  mov #20,r0
8c0d4430:  fldi0 fr3
8c0d4432:  fmov fr3,@(r0,r14)
8c0d4434:  jsr @r3                       ; normalise / length
8c0d4436:  mov r14,r4
8c0d4438:  fldi1 fr3
8c0d443a:  fmov fr0,fr4
8c0d443c:  fcmp/gt fr3,fr4
8c0d443e:  bf 0x8c0d4446
8c0d4440:  mov.l 0x8c0d44f8,r2 ! 8c0ffbf0
8c0d4442:  jsr @r2
8c0d4444:  nop
8c0d4446:  mov.l 0x8c0d4500,r3 ! 8c110f80
8c0d4448:  mov.l 0x8c0d44fc,r4 ! 8c21a148
8c0d444a:  jsr @r3                       ; load view matrix
8c0d444c:  nop
8c0d444e:  mov.l 0x8c0d4504,r2 ! 8c1111e0
8c0d4450:  mov.l 0x8c0d44f0,r4 ! 8c2a60f0
8c0d4452:  jsr @r2                       ; XMTRX = view x limb matrix
8c0d4454:  nop
8c0d4456:  mov.l @r15,r4
8c0d4458:  add #4,r15
8c0d445a:  lds.l @r15+,pr
8c0d445c:  mov.l 0x8c0d4508,r3 ! 8c101430
8c0d445e:  jmp @r3                       ; NL modifier volume (0x8c101430 -> 0x8c1014a0)
8c0d4460:  mov.l @r15+,r14

;; ==== 0x8c1014a0  modifier-volume header, then the NL volume kernels (= SM2 0x8c1dd420 family, ~35-45 cycles per triangle) ====
8c1014a0:  sts.l pr,@-r15
8c1014a2:  mov.l r5,@-r15
8c1014a4:  mov.l @r4,r3
8c1014a6:  cmp/pz r3
8c1014a8:  bf.s 0x8c1014ee
8c1014aa:  mov.l @(24,r4),r5
8c1014ac:  tst r5,r5
8c1014ae:  bt 0x8c1014ee
8c1014b0:  mov.l 0x8c10150c,r1 ! 8c2b6f34
8c1014b2:  mov.l 0x8c101510,r0 ! ff000038
8c1014b4:  mov.l @r1,r2
8c1014b6:  mov.l 0x8c101514,r3 ! ff00003c
8c1014b8:  mov.l @(4,r2),r6              ; list pointer (Kamui table *0x8c2b6f34 +4: opaque modifier list)
8c1014ba:  mov.l 0x8c101518,r2 ! 8c2e6498
8c1014bc:  shlr16 r6
8c1014be:  shlr8 r6
8c1014c0:  mov.l r6,@r0                  ; QACR0/1 = pointer >> 24
8c1014c2:  mov.l 0x8c10151c,r0 ! 8c2ef7e0
8c1014c4:  mov.l r6,@r3
8c1014c6:  mov.l @r0,r1
8c1014c8:  mov.l 0x8c101520,r3 ! 30000
8c1014ca:  or r1,r5
8c1014cc:  mov.l 0x8c101524,r1 ! 818c0000 ; PCW 0x818c0000 | (flags & 0x30000)
8c1014ce:  and r3,r5
8c1014d0:  mov.l 0x8c101528,r3 ! 8c2e649c
8c1014d2:  or r1,r5
8c1014d4:  mov.l 0x8c1014fc,r0 ! 8c2f07f4
8c1014d6:  mov.l r5,@r2
8c1014d8:  mov #0,r2
8c1014da:  mov.l r2,@r3
8c1014dc:  mov.l @r0,r2
8c1014de:  mov.l 0x8c10152c,r1 ! 8c2e64a0
8c1014e0:  mov.l 0x8c101500,r3 ! 8c2f07f8
8c1014e2:  mov.l r2,@r1
8c1014e4:  mov.l 0x8c101530,r2 ! 8c10d980
8c1014e6:  mov.l 0x8c101518,r5 ! 8c2e6498
8c1014e8:  mov.l @r3,r7
8c1014ea:  jsr @r2                       ; 0x8c10d980 = SM2 0x8c1dd220
8c1014ec:  mov.l @r15,r6
8c1014ee:  mov #1,r4
8c1014f0:  add #4,r15
8c1014f2:  mov.l 0x8c101534,r3 ! 8c0fde70
8c1014f4:  jmp @r3
8c1014f6:  lds.l @r15+,pr

;; ################################################################ SECTION I
;; ==== 0x8c012672  frame skip: when the frame is late, stub the draw API for one logic pass ====
8c012672:  mov.l 0x8c0126e0,r3 ! 8c1cb900
8c012674:  mov.l r14,@r3
8c012676:  mov.l 0x8c0126d8,r2 ! 8c2b6f44
8c012678:  mov.l @r15,r1
8c01267a:  mov.l @r2,r0
8c01267c:  mov.l 0x8c01270c,r2 ! 8c0f9b80
8c01267e:  add r1,r0
8c012680:  mul.l r13,r0
8c012682:  sts macl,r0
8c012684:  jsr @r2                       ; time/vblank query
8c012686:  mov.l r0,@-r15
8c012688:  mov.l @r15+,r3
8c01268a:  cmp/ge r0,r3
8c01268c:  bt 0x8c012692
8c01268e:  bsr 0x8c012a74                ; late: patch entries to rts;nop
8c012690:  mov.l r10,@r11
8c012692:  mov.l 0x8c012710,r2 ! 8c1cb8fc
8c012694:  bra 0x8c01272a
8c012696:  mov.l r14,@r2

;; ==== 0x8c012a74  swap the first 4 bytes of each draw entry with {rts; nop} (0x0b000900 at 0x8c150398..0x8c1503c0), then ocbwb ====
;; Entries: 0x8c111580, 0x8c111680, 0x8c111560, 0x8c1116a0, 0x8c103920, 0x8c103980, 0x8c1040b0, 0x8c100430 (sprites),
;; 0x8c101430, 0x8c101450 (volumes), 0x8c0fbb30 (debug print). Calling it again restores them (0x8c012714).
8c012a74:  mov.l r14,@-r15
8c012a76:  mov #2,r14
8c012a78:  mov.l r13,@-r15
8c012a7a:  mov r14,r5
8c012a7c:  sts.l pr,@-r15
8c012a7e:  mov.l 0x8c012c44,r6 ! 8c15039c
8c012a80:  mov.l 0x8c012c40,r4 ! 8c111580 ; entry 0x8c111580
8c012a82:  mov.w @r6,r2
8c012a84:  dt r5
8c012a86:  mov.w @r4,r7                  ; swap halfwords with the saved {rts; nop}
8c012a88:  mov.w r2,@r4
8c012a8a:  add #2,r4
8c012a8c:  mov.w r7,@r6
8c012a8e:  bf.s 0x8c012a82
8c012a90:  add #2,r6
8c012a92:  mov.l 0x8c012c40,r4 ! 8c111580
8c012a94:  mov.l 0x8c012c48,r13 ! 8c111f00 ; 0x8c111f00 = ocbwb @r4 (write the patched line back)
8c012a96:  jsr @r13
8c012a98:  nop

8c012bb2:  lds.l @r15+,pr
8c012bb4:  mov.l 0x8c012ca0,r2 ! 8c1177ee
8c012bb6:  mov.l 0x8c012c9c,r3 ! a0000000
8c012bb8:  mov.l @r15+,r13
8c012bba:  or r3,r2
8c012bbc:  jmp @r2                       ; tail-call 0x8c1177ee through P2 (uncached)
8c012bbe:  mov.l @r15+,r14

;; ==== 0x8c1177ee  syCache: CCR |= ICI (0x800), invalidates the instruction cache so the patched entries are fetched ====
8c1177ee:  mov.l 0x8c117840,r3 ! ff00001c
8c1177f0:  mov.w 0x8c11783a,r2 ! 800
8c1177f2:  mov.l @r3,r0
8c1177f4:  or r2,r0
8c1177f6:  rts
8c1177f8:  mov.l r0,@r3                  ; CCR = CCR | 0x800

