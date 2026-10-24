; Shenmue II (Dreamcast, Japan, Disc 1, 2001) 1ST_READ.BIN, load base 0x8C010000. sh-elf-objdump -D -EL, nop padding and literal words removed.
; Annotated T&L loops. Costs are static estimates from instruction counts (nothing measured).
; After fschg (FPSCR.SZ=1) objdump still prints "fmov @rX,frN": those are 64-bit pair moves of drN (or xdN for odd N).
; Sections:
;   A  renderer B bulk: MT7 mesh walker kernels, intensity lighting (world, characters, props, sky)   [0x8c1d79b2, 0x8c1d7e60, 0x8c1db1a0]
;   B  renderer B fast unlit path for mesh type -3 (packed colour)                                    [0x8c1d4620, 0x8c1d4840]
;   C  character joints: seam copy, weighted seam, hand envelope skinning                             [0x8c0502fa, 0x8c0503dc, 0x8c052860]
;   D  shadow modifier volumes, batch projector, light callback, matrix library                       [0x8c1dd420, 0x8c1de5d0, 0x8c1de1fc, 0x8c1decd0]
;   E  sea renderer A (TRSEA4.MT6)                                                                     [0x8c039b40, 0x8c0390b8, 0x8c03935c]
;   F  particles / billboards / sphere-map UV pre-pass                                                 [0x8c03a2de, 0x8c03ad00, 0x8c03aa30, 0x8c03bf40]

;; ################################################################ SECTION A
; NOTE: after fschg (FPSCR.SZ=1) objdump still prints "fmov @rX,frN": these are 64-bit pair moves of drN (frN,frN+1).
; Costs are static estimates (instruction counts), nothing measured.

;; ==== 0x8c1d79b2  bulk strip kernel: 1 directional light + ambient, TEXTURED INTENSITY (TA type 7), no clip ====
;; entry from walker 0x8c1d7480 via 0x8c1d7880 when material tag r8 == 0 (r8 odd -> unlit twin 0x8c1d7890, r8 = table ptr -> +spec 0x8c1d7b06)
;; in : r4 = MT7-style strip stream: per vertex either an INLINE 32 B vertex {x,y,z,nx,ny,nz,u,v} (x has LSB=1 as the tag)
;;      or an 8 B BACK-REFERENCE {even tag word, byte offset} to an earlier inline copy (r14 = r4 + offset).
;;      r3 = strip length, XMTRX = proj*view*model with rows permuted so the result is (w, X, Y, -),
;;      fv12 = (Ly,Lz,Lx,0) light dir in MODEL space (normal never transformed), fr15 = ambient (fpul shuttle).
;; out: r6 = SQ address (0xE0000000|ptr) ; 32 B vertex {PCW, X/w, Y/w, 1/w, u, v, I_base, I_offset=0}, written backwards with
;;      four 64-bit stores; dr4 = (w, X) lands at +0 and the PCW store then overwrites w.  PCW = an SQ address (r2 = previous vertex's; top bits 111),
;;      end of strip = "shar r2" of that address (0xE.. -> 0xF..).  r5 = real list pointer (+32 per vertex).
;; cost: loop 0x8c1d79da-0x8c1d7a82 does TWO vertices (fv4 / fv8 alternate) = 79 instr on the back-ref path (+3 per inline vertex)
;;       = ~40 instr/vertex, 1 FTRV + 1 FIPR + 1 FDIV each, 1 data branch (N.L<=0) + tag branch; FDIV(n) consumed ~20 instr later
;;       while vertex n+1 is loaded/transformed -> no FDIV stall.  ~30-35 cycles/vertex est.
;;       Listing stops after vertex A; 0x8c1d7a3e-0x8c1d7a82 mirrors it for B (fv8), then bra 0x8c1d79da.
8c1d79b2:  mov.l @r4+,r3
8c1d79b4:  add #32,r6
8c1d79b6:  fschg                        ; SZ=1: all FP loads/stores below are 64-bit pairs
8c1d79b8:  mov.l @r4,r0
8c1d79ba:  mov r4,r14
8c1d79bc:  fldi0 fr2
8c1d79be:  tst #1,r0                    ; inline vertex? (x LSB = 1)
8c1d79c0:  add #32,r4
8c1d79c2:  bf 0x8c1d79ca
8c1d79c4:  mov.l @(4,r14),r14           ; back-ref: offset word
8c1d79c6:  add #-24,r4
8c1d79c8:  add r4,r14                   ; r14 -> earlier inline copy
8c1d79ca:  fmov @r14+,fr4               ; dr4 = (x,y)
8c1d79cc:  mov r6,r2
8c1d79ce:  fmov @r14+,fr6               ; dr6 = (z,nx)
8c1d79d0:  fadd fr7,fr2                 ; fr2 = nx (fr7 before it is overwritten)
8c1d79d2:  fldi1 fr7                    ; fv4 = (x,y,z,1)
8c1d79d4:  fldi0 fr3
8c1d79d6:  fmov @r14+,fr0               ; dr0 = (ny,nz) -> fv0 = (ny,nz,nx,0)
8c1d79d8:  ftrv xmtrx,fv4               ; A: -> (w, X, Y, -)
8c1d79da:  mov.l @r4+,r0
8c1d79dc:  dt r3
8c1d79de:  flds fr15,fpul               ; ambient into fpul
8c1d79e0:  fldi1 fr7
8c1d79e2:  fdiv fr4,fr7                 ; A: 1/w (FDIV, result needed ~20 instr later)
8c1d79e4:  mov.l @r4+,r1
8c1d79e6:  bt.s 0x8c1d7ab4
8c1d79e8:  fipr fv12,fv0                ; A: N.L (light dir pre-rotated into model space)
8c1d79ea:  tst #1,r0
8c1d79ec:  add r4,r1
8c1d79ee:  bt.s 0x8c1d79f8
8c1d79f0:  fsts fpul,fr2
8c1d79f2:  mov r4,r1
8c1d79f4:  add #24,r4
8c1d79f6:  add #-8,r1
8c1d79f8:  fldi0 fr0
8c1d79fa:  fcmp/gt fr0,fr3              ; N.L > 0 ?
8c1d79fc:  fmov @r14,fr0                ; dr0 = (u,v) of A
8c1d79fe:  add #32,r4
8c1d7a00:  fmov @r1+,fr8                ; B: dr8 = (x,y)
8c1d7a02:  bf 0x8c1d7a06
8c1d7a04:  fadd fr3,fr2                 ; I = ambient + max(0,N.L)
8c1d7a06:  fldi0 fr3
8c1d7a08:  dt r3
8c1d7a0a:  fmov fr2,@-r6                ; +24: (I_base, I_offset=0)
8c1d7a0c:  fsub fr2,fr2
8c1d7a0e:  pref @r4                     ; prefetch next source line
8c1d7a10:  add #-32,r4
8c1d7a12:  fmov @r1+,fr10
8c1d7a14:  fmul fr7,fr6                 ; Y*1/w (fr7 = 1/w ready now)
8c1d7a16:  fmov fr0,@-r6                ; +16: (u,v)
8c1d7a18:  fadd fr11,fr2
8c1d7a1a:  fldi1 fr11
8c1d7a1c:  fmul fr7,fr5                 ; X*1/w
8c1d7a1e:  fmov @r1+,fr0
8c1d7a20:  add #32,r5
8c1d7a22:  fmov fr6,@-r6                ; +8: (Y/w, 1/w)
8c1d7a24:  ftrv xmtrx,fv8               ; B: transform while A is stored
8c1d7a26:  fmov fr4,@-r6                ; +0: (w junk, X/w)
8c1d7a28:  mov.l r2,@r6                 ; PCW = SQ address held in r2 (overwrites w)
8c1d7a2a:  mov r6,r2
8c1d7a2c:  pref @r6                     ; burst A to the TA / RAM list
8c1d7a2e:  add #64,r6
8c1d7a30:  mov.l @r4+,r0
8c1d7a32:  mov.l @r4+,r14
8c1d7a34:  flds fr15,fpul
8c1d7a36:  fipr fv12,fv0                ; B: N.L
8c1d7a38:  fldi1 fr11
8c1d7a3a:  bt.s 0x8c1d7a84
8c1d7a3c:  fdiv fr8,fr11                ; B: 1/w

;; ==== 0x8c1d7e60  near-clip path: per-vertex classify (+light) for the clip state machines 0x8c1d7be0 (strips) / 0x8c1d8080 (tris) ====
;; Called once per vertex (bsr), result vertex parked in a 4-slot x 32 B ring at 0x8c2bdaa0 (0x8c1d7f40) or emitted (0x8c1d7f00);
;; the 3-bit in/out history in r9 selects one of 8 cases via braf; 0x8c1d7fe0 makes the intersection vertex
;; t = (w_near - wa)/(wb - wa) (1 FDIV), lerps (x,y,u,v,I) with fsub+fmac on 64-bit pairs and scales X,Y by the constant 1/w_near (r7).
;; Visibility = INTEGER compare of the float bit patterns: cmp/hi w_bits, r12 (r12 = near-plane w as float bits; w>0 so unsigned order works).
;; cost: ~33-40 instr per vertex in here + ~12 per emit (0x8c1d7f00) + bsr/rts overhead; only for meshes whose sphere crosses near.
8c1d7e60:  mov.l @r4,r0
8c1d7e62:  tst #1,r0                    ; inline vertex?
8c1d7e64:  bf.s 0x8c1d7e84
8c1d7e66:  fmov @r4+,fr4
8c1d7e68:  mov.l @r4+,r0
8c1d7e6a:  add r4,r0
8c1d7e6c:  fmov @r0+,fr4
8c1d7e6e:  fmov @r0+,fr5
8c1d7e70:  fmov @r0+,fr6
8c1d7e72:  fldi1 fr7
8c1d7e74:  fmov @r0+,fr2
8c1d7e76:  fmov @r0+,fr0
8c1d7e78:  ftrv xmtrx,fv4               ; clip-space transform (w,X,Y,-)
8c1d7e7a:  fmov @r0+,fr1
8c1d7e7c:  fldi0 fr3
8c1d7e7e:  add #32,r4
8c1d7e80:  bra 0x8c1d7e98
8c1d7e82:  mov r0,r2
8c1d7e84:  fmov @r4+,fr5
8c1d7e86:  fmov @r4+,fr6
8c1d7e88:  fldi1 fr7
8c1d7e8a:  fmov @r4+,fr2
8c1d7e8c:  fmov @r4+,fr0
8c1d7e8e:  ftrv xmtrx,fv4
8c1d7e90:  fmov @r4+,fr1
8c1d7e92:  fldi0 fr3
8c1d7e94:  mov r4,r2
8c1d7e96:  add #40,r4
8c1d7e98:  fldi0 fr11
8c1d7e9a:  fipr fv12,fv0                ; N.L
8c1d7e9c:  pref @r4
8c1d7e9e:  add #-32,r4
8c1d7ea0:  flds fr7,fpul
8c1d7ea2:  sts fpul,r0                  ; w as raw bits -> r0
8c1d7ea4:  fldi1 fr7
8c1d7ea6:  fdiv fr4,fr7                 ; 1/w (stored even if behind; only used if visible)
8c1d7ea8:  fsts fpul,fr4
8c1d7eaa:  fcmp/gt fr11,fr3
8c1d7eac:  fipr fv0,fv8                 ; second dot: N.H for the specular table
8c1d7eae:  fmov fr15,fr2
8c1d7eb0:  bf 0x8c1d7ee8
8c1d7eb2:  fadd fr3,fr2                 ; I = ambient + N.L
8c1d7eb4:  tst r8,r8
8c1d7eb6:  fldi0 fr3
8c1d7eb8:  bt.s 0x8c1d7eec
8c1d7eba:  mov #1,r1
8c1d7ebc:  tst r1,r8
8c1d7ebe:  bf.s 0x8c1d7ede
8c1d7ec0:  ftrc fr11,fpul               ; spec index = ftrc(N.H * k)
8c1d7ec2:  mov #127,r1
8c1d7ec4:  add #127,r1
8c1d7ec6:  sts fpul,r0
8c1d7ec8:  add #55,r1                   ; r1 = 309
8c1d7eca:  cmp/gt r1,r0
8c1d7ecc:  shll2 r0
8c1d7ece:  bf 0x8c1d7ee8
8c1d7ed0:  mov.l @(r0,r8),r0            ; offset intensity = table[idx] (per material)
8c1d7ed2:  lds r0,fpul
8c1d7ed4:  fsts fpul,fr3
8c1d7ed6:  flds fr4,fpul
8c1d7ed8:  sts fpul,r0
8c1d7eda:  rts
8c1d7edc:  cmp/hi r0,r12                ; T = vertex behind near plane (integer compare of floats)

;; ==== 0x8c1db1a0  RGB multi-light strip kernel (walker 0x8c1dad40), FLOATING-COLOUR TA vertex (64 B, type 5), no clip ====
;; per vertex: walk the per-mesh active-light bitmask r13 (*(0x8c03c3b0), built by 0x8c03c080 with sphere-vs-light-range culling);
;; light records 176 B at 0x8c30c75c, type at +2: 2 = directional (FIPR N.L), 3 = point, 4 = spot (L = Lpos - P, FIPR N.L, FIPR L.L,
;; range test, FSRRA(d^2) -> 1/d, spot cone test, falloff min(1, k*(1/d)^8)), RGB accumulated with 3 fmac into fr13..fr15 (start = ambient).
;; Lights are in model space: neither P nor N is transformed for lighting. The position FTRV is issued in the delay slot of the
;; "last light?" test, so it overlaps the last light's work. Output base ARGB = material (0x8c03c160) * light sum; offset ARGB = 0
;; written once into the SQ.  cost: ~80 instr/vertex with one directional light, +~25 per extra directional, +~45-60 per point/spot.
8c1db1a6:  mov r6,r1
8c1db1a8:  fmov @r0+,fr12               ; dr12/dr14 = ambient (A,R,G,B): fr13..15 accumulate RGB
8c1db1aa:  add #64,r5
8c1db1ac:  fmov @r0+,fr14
8c1db1ae:  add #64,r4
8c1db1b0:  fmov @r14+,fr4               ; dr4 = (x,y)
8c1db1b2:  add #80,r6
8c1db1b4:  fmov @r14+,fr6               ; dr6 = (z,nx)
8c1db1b6:  fschg
8c1db1b8:  pref @r1
8c1db1ba:  fmov fr7,fr8                 ; fr8 = nx  (fv8 = normal)
8c1db1bc:  tst r13,r13                  ; any lights for this mesh?
8c1db1be:  fmov @r14+,fr9
8c1db1c0:  bt.s 0x8c1db20c
8c1db1c2:  fmov @r14+,fr10
8c1db1c4:  shlr r13                     ; next light bit
8c1db1c6:  mov.l 0x8c1db368,r2 ! 8c30c75c
8c1db1c8:  bf 0x8c1db1fc
8c1db1ca:  mov.w @(2,r2),r0             ; light type
8c1db1cc:  fldi0 fr3
8c1db1ce:  cmp/eq #2,r0                 ; directional?
8c1db1d0:  mov #116,r1
8c1db1d2:  bf.s 0x8c1db214
8c1db1d4:  add r2,r1
8c1db1d6:  fldi1 fr7
8c1db1d8:  tst r13,r13
8c1db1da:  add #12,r1
8c1db1dc:  bf.s 0x8c1db1e2
8c1db1de:  fmov @r1+,fr0
8c1db1e0:  ftrv xmtrx,fv4               ; last light: transform position now
8c1db1e2:  fmov @r1+,fr1
8c1db1e4:  mov r2,r0
8c1db1e6:  fmov @r1+,fr2
8c1db1e8:  add #24,r0
8c1db1ea:  fipr fv0,fv8                 ; N.L (model-space light dir)
8c1db1ec:  fmov @r0+,fr1
8c1db1ee:  fmov @r0+,fr2
8c1db1f0:  fmov @r0+,fr3
8c1db1f2:  fldi0 fr0
8c1db1f4:  fcmp/gt fr11,fr0
8c1db1f6:  fmov fr11,fr0
8c1db1f8:  bf.s 0x8c1db292
8c1db1fa:  tst r13,r13
8c1db1fc:  mov #-80,r0
8c1db1fe:  bt 0x8c1db2b2
8c1db200:  shlr r13
8c1db202:  extu.b r0,r0
8c1db204:  bf.s 0x8c1db2a6
8c1db206:  add r0,r2
8c1db208:  bra 0x8c1db1cc
8c1db20a:  mov.w @(2,r2),r0
8c1db20c:  fldi1 fr7
8c1db20e:  bra 0x8c1db2b2
8c1db210:  ftrv xmtrx,fv4
8c1db214:  fmov @r1+,fr0
8c1db216:  tst r13,r13
8c1db218:  fmov @r1+,fr1
8c1db21a:  fsub fr4,fr0                 ; point/spot: L = Lpos - P
8c1db21c:  fmov @r1+,fr2
8c1db21e:  fsub fr5,fr1
8c1db220:  fldi1 fr7
8c1db222:  add #24,r1
8c1db224:  fldi0 fr11
8c1db226:  bf.s 0x8c1db22c
8c1db228:  fsub fr6,fr2
8c1db22a:  ftrv xmtrx,fv4
8c1db22c:  fipr fv0,fv8                 ; N.L (unnormalised)
8c1db22e:  fldi0 fr12
8c1db230:  fipr fv0,fv0                 ; d^2 = L.L
8c1db232:  fcmp/gt fr11,fr12
8c1db234:  fmov @r1,fr12
8c1db236:  bt 0x8c1db2a0
8c1db238:  fcmp/gt fr3,fr12             ; out of range?
8c1db23a:  bf 0x8c1db2a0
8c1db23c:  cmp/eq #3,r0
8c1db23e:  flds fr3,fpul
8c1db240:  bt.s 0x8c1db26a
8c1db242:  fsrra fr3                    ; 1/d by FSRRA
8c1db244:  add #-24,r1                  ; spot: cone = -(D.L)/d vs cutoff
8c1db246:  fmov @r1+,fr12
8c1db248:  fmul fr0,fr12
8c1db24a:  fmov @r1+,fr0
8c1db24c:  fmac fr0,fr1,fr12
8c1db24e:  fmov @r1,fr0
8c1db250:  add #-48,r1
8c1db252:  fmac fr0,fr2,fr12
8c1db254:  fmov @r1,fr2
8c1db256:  fneg fr12
8c1db258:  fmul fr3,fr12
8c1db25a:  add #68,r1
8c1db25c:  fcmp/gt fr12,fr2
8c1db25e:  fsub fr2,fr12
8c1db260:  fmov @r1,fr2
8c1db262:  bt 0x8c1db2a0
8c1db264:  fmul fr2,fr12
8c1db266:  add #-4,r1
8c1db268:  fmul fr12,fr11
8c1db26a:  add #-68,r1
8c1db26c:  fmul fr3,fr11                ; N.L / d
8c1db26e:  add #-8,r1
8c1db270:  fmul fr3,fr3                 ; (1/d)^2
8c1db272:  fmov @r1,fr12
8c1db274:  fmul fr3,fr3                 ; (1/d)^4
8c1db276:  fldi1 fr2
8c1db278:  mov r2,r0
8c1db27a:  fmul fr3,fr3                 ; (1/d)^8
8c1db27c:  add #24,r0
8c1db27e:  fmul fr3,fr12
8c1db280:  fmov fr11,fr0
8c1db282:  fcmp/gt fr2,fr12             ; attenuation k/d^8 clamped to 1
8c1db284:  fmov @r0+,fr1
8c1db286:  add #4,r1
8c1db288:  fmov @r0+,fr2
8c1db28a:  bt.s 0x8c1db290
8c1db28c:  fmov @r0+,fr3
8c1db28e:  fmul fr12,fr0
8c1db290:  tst r13,r13
8c1db292:  fmac fr0,fr1,fr13            ; R += c*Lr
8c1db294:  mov #-80,r0
8c1db296:  fmac fr0,fr2,fr14            ; G += c*Lg
8c1db298:  bt.s 0x8c1db2b2
8c1db29a:  fmac fr0,fr3,fr15            ; B += c*Lb
8c1db29c:  bra 0x8c1db2a8
8c1db29e:  shlr r13
8c1db2a0:  tst r13,r13
8c1db2a2:  mov #-80,r0
8c1db2a4:  bt.s 0x8c1db2b2
8c1db2a6:  shlr r13
8c1db2a8:  extu.b r0,r0                 ; skip light record (176 B)
8c1db2aa:  bf.s 0x8c1db2a6
8c1db2ac:  add r0,r2
8c1db2ae:  bra 0x8c1db1cc
8c1db2b0:  mov.w @(2,r2),r0
8c1db2b2:  mov.l 0x8c1db360,r2 ! 8c03c160
8c1db2b4:  fschg
8c1db2b6:  fldi1 fr7
8c1db2b8:  fdiv fr4,fr7                 ; 1/w (fdiv)
8c1db2ba:  pref @r4
8c1db2bc:  add #-32,r4
8c1db2be:  fmov @r2+,fr8
8c1db2c0:  mov r6,r1
8c1db2c2:  shar r1
8c1db2c4:  fmov @r2+,fr10
8c1db2c6:  fmul fr13,fr9                ; base RGB = material * light
8c1db2c8:  mov.l @r4,r0
8c1db2ca:  fmul fr14,fr10
8c1db2cc:  fmov @r14+,fr2
8c1db2ce:  fmul fr15,fr11
8c1db2d0:  mov.l 0x8c1db36c,r13 ! 8c03c3b0
8c1db2d2:  dt r3
8c1db2d4:  fmov fr10,@-r6               ; +40: base (B?) pair
8c1db2d6:  mov r4,r14
8c1db2d8:  fmov fr8,@-r6
8c1db2da:  add #-8,r6
8c1db2dc:  fmul fr7,fr6
8c1db2de:  fmov fr2,@-r6
8c1db2e0:  fmul fr7,fr5
8c1db2e2:  fmov fr6,@-r6
8c1db2e4:  bt.s 0x8c1db314
8c1db2e6:  fmov fr4,@-r6
8c1db2e8:  tst #1,r0
8c1db2ea:  mov.l r6,@r6                 ; PCW = SQ address
8c1db2ec:  bt 0x8c1db2f0
8c1db2ee:  bra 0x8c1db1a0
8c1db2f0:  pref @r6                     ; 64 B vertex = two SQ bursts


;; ################################################################ SECTION B
; Section B: renderer B, mesh-type -3 prelit (packed ARGB on disc) strip path (hook walkers 0x8c1d442a / 0x8c1d500a). Costs are static estimates.
; Reminder: between fschg pairs SZ=1 and "fmov @rN+,frK" is a 64-bit pair move (drK, or xdK for odd K).

;; ==== 0x8c1d4420/0x8c1d442a  strip-command walker (hook mode 1; mode 2 = 0x8c1d5000/0x8c1d500a, identical except offset colour) ====
;; Reached through the function pointer 0x8c2656f8 from 0x8c1da1e0 (mesh type -3 in the MT7 mesh walker 0x8c1d7480).
;; in : r4 = MT7 strip stream {u32 cmd, u32 count, entries...}, cmd<=0 ends; r6 = SQ address 0xE0000000|(listptr&0x03ffffe0);
;;      r5 = RAM-side list pointer (+32 per vertex, written back to *(0x8c317e44)[list] at exit); r12 = near (float bits)|clip flag
;; out: one 32-byte TA polygon header per command (PCW from material template, Gouraud from cmd bit6, culling from cmd bits0-1)

8c1d4460:  mov r0,r1                 ; r0 = strip command word (MT7: 0xf2/0xd2/...), r9 -> current material header template (0x8c2bda40)
8c1d4462:  mov #-5,r2
8c1d4464:  mov.l @r9+,r3
8c1d4466:  and #64,r0                ; bit6 of cmd -> PCW bit1 (Gouraud)
8c1d4468:  shld r2,r0
8c1d446a:  mov #-3,r2
8c1d446c:  and r2,r3
8c1d446e:  or r0,r3
8c1d4470:  add #32,r4
8c1d4472:  mov #-49,r2               ; -49 = ~0x30: col_type := 0 (packed ARGB); twin 0x8c1da248 instead sets 0x10 (float colour, mode 0)
8c1d4474:  and r2,r3
8c1d4476:  mov r1,r0
8c1d4478:  mov r15,r2
8c1d447a:  add #40,r2
8c1d447c:  lds r3,fpul
8c1d447e:  mov.l @(40,r2),r2
8c1d4480:  cmp/pz r2                 ; stack arg sign = mirrored model matrix?
8c1d4482:  mov #27,r2
8c1d4484:  bt.s 0x8c1d448a
8c1d4486:  and #3,r0                 ; cmd bits0-1 = ISP culling mode (PVR does back-face culling)
8c1d4488:  xor #1,r0                 ; mirrored: swap CW/CCW culling
8c1d448a:  shld r2,r0                ; -> ISP word bits 27-28
8c1d448c:  mov #3,r3
8c1d448e:  fschg                     ; SZ=1: pair moves for the 16-byte header
8c1d4490:  shld r2,r3
8c1d4492:  pref @r4                  ; prefetch the strip data
8c1d4494:  not r3,r3
8c1d4496:  mov.l @r9+,r2
8c1d4498:  and r3,r2
8c1d449a:  fsts fpul,fr0
8c1d449c:  or r0,r2
8c1d449e:  lds r2,fpul
8c1d44a0:  add #-32,r4
8c1d44a2:  fsts fpul,fr1
8c1d44a4:  add #16,r6
8c1d44a6:  fmov @r9+,fr2             ; dr2 = (TSP, texture) words of the template
8c1d44a8:  fmov fr2,@-r6             ; header written backwards into the SQ (only 16 of 32 bytes; words 4-7 are don't-care for this header)
8c1d44aa:  add #32,r5
8c1d44ac:  fmov fr0,@-r6
8c1d44ae:  fschg
8c1d44b0:  pref @r6                  ; burst the 32-byte global header
8c1d44b2:  add #32,r6
8c1d44b4:  rotcr r12                 ; r12 bit0 = "mesh sphere straddles near plane" (rotcr/shll test it non-destructively)
8c1d44b6:  mov r1,r0
8c1d44b8:  bt.s 0x8c1d44d0
8c1d44ba:  shll r12
8c1d44bc:  tst #8,r0                 ; cmd bit3 = triangle list (0x8c1d4740) else strip (0x8c1d4620)
8c1d44be:  bt 0x8c1d44c8
8c1d44c0:  bsr 0x8c1d4740
8c1d44c2:  nop
8c1d44c4:  bra 0x8c1d443a
8c1d44c6:  mov.l @r4+,r0
8c1d44c8:  bsr 0x8c1d4620
8c1d44ca:  nop
8c1d44cc:  bra 0x8c1d443a
8c1d44ce:  mov.l @r4+,r0
8c1d44d0:  mov #0,r1
8c1d44d2:  tst #64,r0
8c1d44d4:  addc r1,r12
8c1d44d6:  tst #16,r0                ; clip path: bit4 strip -> 0x8c1d4840, bit3 tris -> 0x8c1d4e00
8c1d44d8:  bt.s 0x8c1d44e4
8c1d44da:  tst #8,r0
8c1d44dc:  bsr 0x8c1d4840
8c1d44de:  nop
8c1d44e0:  bra 0x8c1d443a
8c1d44e2:  mov.l @r4+,r0
8c1d44e4:  bt 0x8c1d44f0
8c1d44e6:  bsr 0x8c1d4e00
8c1d44e8:  nop
8c1d44ea:  bra 0x8c1d443a
8c1d44ec:  mov.l @r4+,r0
8c1d44ee:  nop
8c1d44f0:  bra 0x8c1d44f0

;; ==== 0x8c1d4620  no-clip strip kernel (fast path for the ~22 prelit mesh-type -3 props; NOT the world bulk) ====
;; in : stream entries: inline 32 B vertex {x|1, y, z, w3, base ARGB, offset ARGB, u, v} or 8 B back-ref {tag (bit0=0), s32 rel offset}
;;      XMTRX = projection*view*model with rows permuted: (x,y,z,1) -> (w, X, Y, zclip)
;; out: TA vertex type 3 (textured, packed colour, float UV), 32 B, written backwards into the SQ, one pref per vertex
;; cost: 30 instr/vertex (back-ref) or 33 (inline), 1 FTRV + 1 FDIV + 2 FMUL, 2 branches + 1 per 2 vertices;
;;       2-vertex software pipeline (vertex n transformed while n-1 is scaled and stored), FDIV result used ~14 instr later.
;;       16 LS-group ops per vertex bound it at ~17 cycles; estimate 20-24 cycles/vertex with cache hits.
8c1d4620:  mov.l @r4+,r3             ; r3 = vertex count of this strip
8c1d4622:  add #32,r6
8c1d4624:  fschg                     ; SZ=1 for the whole kernel: every fmov below is a 64-bit pair move
8c1d4626:  mov.l @r4,r0              ; stream entry: inline vertex starts with x, whose LSB is 1 (set in the MT7 data)
8c1d4628:  mov r4,r14
8c1d462a:  tst #1,r0
8c1d462c:  add #32,r4
8c1d462e:  bf 0x8c1d4636             ; bit0 clear -> back-reference entry {tag, s32 offset}, 8 bytes
8c1d4630:  mov.l @(4,r14),r14
8c1d4632:  add #-24,r4
8c1d4634:  add r4,r14
8c1d4636:  fmov @r14+,fr4            ; dr4 = (x, y)
8c1d4638:  fmov @r14+,fr6            ; dr6 = (z, nx)
8c1d463a:  fldi1 fr7                 ; w = 1 overwrites word 3
8c1d463c:  fmov @r14+,fr2            ; dr2 = (word4, word5) = base ARGB, offset ARGB
8c1d463e:  fmov @r14,fr0             ; dr0 = (u, v)
8c1d4640:  ftrv xmtrx,fv4            ; (x,y,z,1) -> (w, X, Y, zclip): rows permuted so lane 0 is the divisor
8c1d4642:  fldi0 fr3                 ; offset colour := 0 (mode 1). The mode-2 twin 0x8c1d500a omits this and keeps word5
8c1d4644:  fldi1 fr7
8c1d4646:  fdiv fr4,fr7              ; 1/w by FDIV (no FSRRA anywhere in this family)
8c1d4648:  fmov fr2,@-r6             ; +24/+28 = base, offset colour (pair store)
8c1d464a:  dt r3                     ; count down; last vertex exits to 0x8c1d46f0
8c1d464c:  mov.l @r4+,r0             ; pre-read next tag and offset word
8c1d464e:  bt.s 0x8c1d46f0
8c1d4650:  mov.l @r4+,r14            ; (delay slot)
8c1d4652:  tst #1,r0
8c1d4654:  mov r6,r2                 ; r2 = SQ address of this vertex = its PCW: 0xE0xxxxxx is a valid vertex PCW
8c1d4656:  bt.s 0x8c1d4660
8c1d4658:  add r4,r14                ; backref target = r4 + offset
8c1d465a:  mov r4,r14                ; inline: r14 = start of the 32-byte vertex
8c1d465c:  add #24,r4
8c1d465e:  add #-8,r14
;; ==== steady state: 2 vertices per iteration (fv8 then fv4), each finishing the previous one ====
8c1d4660:  add #32,r4
8c1d4662:  fmov @r14+,fr8
8c1d4664:  pref @r4                  ; prefetch 32 bytes ahead in the stream (add/pref/add instead of an index register)
8c1d4666:  fmov @r14+,fr10
8c1d4668:  fldi1 fr11
8c1d466a:  fmul fr7,fr6              ; previous vertex: Y/w (fr7 = its 1/w)
8c1d466c:  fmov @r14+,fr2
8c1d466e:  fmul fr7,fr5              ; previous vertex: X/w
8c1d4670:  fmov fr0,@-r6             ; +16/+20 = u, v
8c1d4672:  ftrv xmtrx,fv8            ; transform this vertex while the previous one is stored
8c1d4674:  fmov fr6,@-r6             ; +8/+12 = (Y/w, 1/w)
8c1d4676:  add #-32,r4
8c1d4678:  fmov fr4,@-r6             ; +0/+4 = (w, X/w): word 0 is junk...
8c1d467a:  mov.l r2,@r6              ; ...overwritten by the PCW (the SQ address itself)
8c1d467c:  fmov @r14,fr0
8c1d467e:  dt r3
8c1d4680:  pref @r6                  ; SQ burst of the finished 32-byte vertex
8c1d4682:  add #64,r6                ; next 32-byte slot (alternates SQ0/SQ1)
8c1d4684:  fldi0 fr3
8c1d4686:  fmov fr2,@-r6
8c1d4688:  mov r6,r2
8c1d468a:  fldi1 fr11
8c1d468c:  fdiv fr8,fr11             ; FDIV for this vertex; first use 14 instructions later (0x8c1d46aa)
8c1d468e:  mov.l @r4+,r0
8c1d4690:  bt.s 0x8c1d46c8
8c1d4692:  mov.l @r4+,r14
8c1d4694:  tst #1,r0
8c1d4696:  bt.s 0x8c1d46a0
8c1d4698:  add r4,r14
8c1d469a:  mov r4,r14
8c1d469c:  add #24,r4
8c1d469e:  add #-8,r14
8c1d46a0:  add #32,r4
8c1d46a2:  fmov @r14+,fr4
8c1d46a4:  pref @r4
8c1d46a6:  fmov @r14+,fr6
8c1d46a8:  fldi1 fr7
8c1d46aa:  fmul fr11,fr10
8c1d46ac:  fmov @r14+,fr2
8c1d46ae:  fmul fr11,fr9
8c1d46b0:  fmov fr0,@-r6
8c1d46b2:  ftrv xmtrx,fv4
8c1d46b4:  fmov fr10,@-r6
8c1d46b6:  add #-32,r4
8c1d46b8:  fmov fr8,@-r6
8c1d46ba:  add #64,r5
8c1d46bc:  mov.l r2,@r6
8c1d46be:  fmov @r14,fr0
8c1d46c0:  pref @r6
8c1d46c2:  bra 0x8c1d4642            ; one loop branch per 2 vertices; per vertex: 30 instr (backref) / 33 (inline), 2-2.5 branches
8c1d46c4:  add #64,r6
8c1d46c6:  nop
8c1d46c8:  cmp/pl r0                 ; strip done: next word is the next command (bit7 set = chain another strip under the same header)
8c1d46ca:  mov r14,r3
8c1d46cc:  bf 0x8c1d46e8
8c1d46ce:  tst #128,r0
8c1d46d0:  bt 0x8c1d46e8
8c1d46d2:  mov.l @r4+,r0
8c1d46d4:  mov r6,r2
8c1d46d6:  shar r2                   ; shar r2: SQ address 0xE0.. >> 1 (arithmetic) = 0xF0.. = end-of-strip PCW for free
8c1d46d8:  mov.l @r4+,r14
8c1d46da:  tst #1,r0
8c1d46dc:  add r4,r14
8c1d46de:  bt 0x8c1d46a0
8c1d46e0:  mov r4,r14
8c1d46e2:  add #24,r4
8c1d46e4:  bra 0x8c1d46a0
8c1d46e6:  add #-8,r14
8c1d46e8:  add #32,r5
8c1d46ea:  fmov fr8,fr4
8c1d46ec:  bra 0x8c1d4710
8c1d46ee:  fmov fr10,fr6
8c1d46f0:  cmp/pl r0
8c1d46f2:  mov r14,r3
8c1d46f4:  bf 0x8c1d4710
8c1d46f6:  tst #128,r0
8c1d46f8:  bt 0x8c1d4710
8c1d46fa:  mov.l @r4+,r0
8c1d46fc:  mov r6,r2
8c1d46fe:  shar r2
8c1d4700:  mov.l @r4+,r14
8c1d4702:  tst #1,r0
8c1d4704:  add r4,r14
8c1d4706:  bt 0x8c1d4660
8c1d4708:  mov r4,r14
8c1d470a:  add #24,r4
8c1d470c:  bra 0x8c1d4660
8c1d470e:  add #-8,r14
8c1d4710:  fmul fr7,fr6
8c1d4712:  mov r6,r2
8c1d4714:  shar r2                   ; last vertex of strip: PCW = address >> 1 = end of strip
8c1d4716:  fmul fr7,fr5
8c1d4718:  fmov fr0,@-r6
8c1d471a:  add #-8,r4
8c1d471c:  fmov fr6,@-r6
8c1d471e:  add #32,r5
8c1d4720:  fmov fr4,@-r6
8c1d4722:  mov.l r2,@r6
8c1d4724:  fschg                     ; back to SZ=0 for the C caller
8c1d4726:  pref @r6
8c1d4728:  rts
8c1d472a:  add #32,r6

;; ==== 0x8c1d4840  near-clip strip kernel (only meshes whose sphere straddles the near plane), excerpts ====
;; ==== clip-capable strip kernel 0x8c1d4840, common (all visible) path ====
8c1d4896:  fldi0 fr3
8c1d4898:  fmov fr2,@-r6
8c1d489a:  flds fr7,fpul             ; lane 3 = view-space depth (negative in front)
8c1d489c:  fldi1 fr7
8c1d489e:  fdiv fr4,fr7
8c1d48a0:  sts fpul,r0               ; raw float bits
8c1d48a2:  cmp/hi r0,r12             ; unsigned compare against near (negative float, bit0 = flag): clipped iff near < z (including behind the eye); one integer compare, no FP compare
8c1d48a4:  bt 0x8c1d4958             ; clipped vertex -> state machine at 0x8c1d4958 (ring buffer 0x8c1d4500/4520, 4 x 32 B, per-case braf)
8c1d48a6:  dt r3
8c1d48a8:  mov.l @r4+,r0
8c1d48aa:  add #1,r11                ; r11 = vertex index in strip (ring slot)
8c1d48ac:  bt.s 0x8c1d4978
8c1d48ae:  mov.l @r4+,r14
8c1d48b0:  tst #1,r0
8c1d48b2:  mov r6,r2
8c1d48b4:  bt.s 0x8c1d48be
8c1d48b6:  add r4,r14
8c1d48b8:  mov r4,r14
8c1d48ba:  add #24,r4
8c1d48bc:  add #-8,r14
8c1d48be:  add #64,r4                ; prefetch 64 bytes ahead here
8c1d48c0:  fmov @r14+,fr8
8c1d48c2:  pref @r4
8c1d48c4:  fmov @r14+,fr10
8c1d48c6:  add #-64,r4
8c1d48c8:  fldi1 fr11
8c1d48ca:  fmul fr7,fr6
8c1d48cc:  fmov @r14+,fr2
8c1d48ce:  fmul fr7,fr5
8c1d48d0:  fmov fr0,@-r6
8c1d48d2:  ftrv xmtrx,fv8
8c1d48d4:  fmov fr6,@-r6
8c1d48d6:  fmov fr4,@-r6
8c1d48d8:  add #32,r5
8c1d48da:  mov.l r2,@r6
8c1d48dc:  fmov @r14,fr0
8c1d48de:  pref @r6
8c1d48e0:  add #64,r6
8c1d48e2:  fldi0 fr3
8c1d48e4:  fmov fr2,@-r6
8c1d48e6:  flds fr11,fpul
8c1d48e8:  fldi1 fr11
8c1d48ea:  fdiv fr8,fr11
8c1d48ec:  sts fpul,r0
8c1d48ee:  cmp/hi r0,r12
8c1d48f0:  bt 0x8c1d494c
8c1d48f2:  dt r3
8c1d48f4:  mov.l @r4+,r0
8c1d48f6:  add #1,r11
8c1d48f8:  bt.s 0x8c1d496c
8c1d48fa:  mov.l @r4+,r14
8c1d48fc:  tst #1,r0
8c1d48fe:  mov r6,r2
8c1d4900:  bt.s 0x8c1d490a
8c1d4902:  add r4,r14
8c1d4904:  mov r4,r14
8c1d4906:  add #24,r4
8c1d4908:  add #-8,r14
8c1d490a:  fmov @r14+,fr4
8c1d490c:  add #64,r4
8c1d490e:  fmov @r14+,fr6
8c1d4910:  pref @r4
8c1d4912:  fldi1 fr7
8c1d4914:  fmul fr11,fr10
8c1d4916:  fmov @r14+,fr2
8c1d4918:  fmul fr11,fr9
8c1d491a:  fmov fr0,@-r6
8c1d491c:  ftrv xmtrx,fv4
8c1d491e:  fmov fr10,@-r6
8c1d4920:  add #-64,r4
8c1d4922:  fmov fr8,@-r6
8c1d4924:  add #32,r5
8c1d4926:  mov.l r2,@r6
8c1d4928:  fmov @r14,fr0
8c1d492a:  pref @r6
8c1d492c:  bra 0x8c1d4896            ; per vertex: 35.5 instr (backref) / 38.5 (inline), 3 branches
8c1d492e:  add #64,r6
;; ==== culled run: SZ=0, only the depth lane is computed ====
8c1d49b8:  fmov @r14+,fr4
8c1d49ba:  fmov @r14+,fr5
8c1d49bc:  fmov @r14+,fr6
8c1d49be:  mov #32,r1
8c1d49c0:  mov.l @r4,r0
8c1d49c2:  add #32,r4
8c1d49c4:  pref @r4
8c1d49c6:  fipr fv12,fv4             ; FIPR with fv12 = row 3 of XMTRX (copied from XD regs at 0x8c1d4848): z only, no FTRV, no FDIV, no store
8c1d49c8:  tst #1,r0
8c1d49ca:  add #-32,r4
8c1d49cc:  bf.s 0x8c1d49d8
8c1d49ce:  mov r4,r14
8c1d49d0:  mov #8,r1
8c1d49d2:  mov.l @(4,r14),r14
8c1d49d4:  add #8,r14
8c1d49d6:  add r4,r14
8c1d49d8:  flds fr7,fpul
8c1d49da:  sts fpul,r0
8c1d49dc:  cmp/hi r0,r12             ; still behind the near plane?
8c1d49de:  add #1,r11
8c1d49e0:  bf.s 0x8c1d4a64           ; vertex re-enters -> emit intersection (0x8c1d4a64)
8c1d49e2:  rotcl r9                  ; r9 = visibility history of the last 3 vertices
8c1d49e4:  dt r3
8c1d49e6:  fldi1 fr7
8c1d49e8:  bt 0x8c1d4930
8c1d49ea:  add r1,r4
8c1d49ec:  fmov @r14+,fr4
8c1d49ee:  bra 0x8c1d49bc
8c1d49f0:  fmov @r14+,fr5

;; ################################################################ SECTION C
;; ######## CHARACTERS: skinning passes (CPU, RAM to RAM, patch the mesh's own vertex stream) ########
;; Characters are trees of rigid per-bone meshes (one MDC7 mesh per node). Each node is drawn with its own world
;; matrix by the ordinary rigid mesh kernels (0x8c1d6880/6980/71e0/72a0 -> 0x8c1d7480 family). Joints are made
;; seamless by rewriting some vertices of each child mesh before it is drawn, in the child's local space:
;;   A) 0x8c0501a0  seam copy: vertex taken from the PARENT mesh, re-expressed in child space (weight 1)
;;   B) 0x8c0503dc  weighted seam: vertex blended between child and parent by a weight (matrix lerp per weight group)
;;   C) 0x8c0daf00 + 0x8c0504fc  "WBTR" multi-bone envelopes, accumulate w*M*v over a bone matrix table (0x8c2e91b8)
;;   D) 0x8c052860  HMT_HandCalcSkin: same envelope scheme in hand-written asm for the hand meshes (finger poses)
;; All passes write {x,y,z,nx,ny,nz} into the mesh's inline vertex records and OR 1 into the low mantissa bit of x:
;; in the strip stream a word with bit0 = 1 is an inline vertex, bit0 = 0 a back-reference (the draw kernels test
;; this with "tst #1,r0"), so a skinned float must have that bit forced on.
;; Node draw/walk: 0x8c0d9140 (recursive, child @+44, sibling @+48, cached world matrix @+56, mesh @+40),
;; 0x8c0da580/0x8c0da100 (motion-driven walkers). Top level 0x8c0d9fc0 (character task 'MTWK' 0x8c0f6840).

;; ==== 0x8c0501a0  seam copy, setup (summary) ====
;; r4 = node, r5 = parent node, r6 = node world matrix, r7 = parent world matrix.
;; Requires an 'MDC7' chunk at node+64; count at node+132, list of {u32 srcOff, u32 dstOff} at node+136.
;; M0 = node matrix with its translation zeroed (copied with fschg 64-bit pair stores) -> 0x8c2e9258
;; M1 = parent matrix with translation (t_parent - t_node)                         -> 0x8c2e91d8
;; XMTRX = invert(M0) (0x8c1de7d0: transpose + fipr/fsrra, inverse translation by fipr) * M1 (0x8c1de9d0, 4 FTRV)
;;       = parent-local -> child-local. Subtracting the translations first keeps the floats small.
;; r1 = parent vertex base (@(40,parent)), r2 = child vertex base (@(40,node)).
;; cost: 54 real instructions + 12 pairing nops per 2 vertices (66 slots), 2 FTRV per vertex (position w=1,
;;       normal w=0). 2-way software pipelined (stores of vertex i overlap the loads of vertex i+1), no branch
;;       except the loop. Estimate about 17-20 cycles per seam vertex, if the explicit nops pair as intended.
;; ==== loop 0x8c0502fa-0x8c05037c: 2 vertices per iteration (A = fv0/fv4 lane, B = fv8/fv12 lane) ====
8c0502fa:  fmov fr2,@-r5                 ; store A.z (A's FTRV issued in the previous iteration)
8c0502fc:  nop                           ; explicit pairing filler (12 in the loop)
8c0502fe:  fldi1 fr11                    ; B.w = 1
8c050300:  nop
8c050302:  fmov fr1,@-r5                 ; A.y
8c050304:  nop
8c050306:  mov.l @r9+,r4                 ; B.srcOff
8c050308:  nop
8c05030a:  fmov fr0,@-r5                 ; A.x: r5 now points at x
8c05030c:  ftrv xmtrx,fv4                ; A normal (w=0)
8c05030e:  mov.l @r5,r0
8c050310:  add r1,r4                     ; B src = parent base + off
8c050312:  fmov @r4+,fr8                 ; B.x
8c050314:  nop
8c050316:  or #1,r0                      ; force LSB of A.x = 1: "inline vertex" tag
8c050318:  mov.l @r9+,r7                 ; B.dstOff
8c05031a:  mov.l r0,@r5
8c05031c:  nop
8c05031e:  add r2,r7                     ; B dst = child base + off
8c050320:  fmov fr6,@-r6                 ; A normal z,y,x -> dst+12..23
8c050322:  fldi0 fr15                    ; B normal w = 0
8c050324:  mov r7,r10
8c050326:  fmov @r4+,fr9
8c050328:  add #12,r7
8c05032a:  fmov fr5,@-r6
8c05032c:  fmov @r4+,fr10
8c05032e:  fmov fr4,@-r6
8c050330:  add #24,r10
8c050332:  fmov @r4+,fr12                ; B.nx
8c050334:  ftrv xmtrx,fv8                ; B position
8c050336:  fmov @r4+,fr13
8c050338:  fmov @r4,fr14
8c05033a:  mov.l @r9+,r4                 ; next A.srcOff
8c05033c:  nop
8c05033e:  fldi1 fr3
8c050340:  nop
8c050342:  mov.l @r9+,r5                 ; next A.dstOff
8c050344:  add r1,r4
8c050346:  fmov @r4+,fr0                 ; next A: x y z nx ny nz (24 B source record)
8c050348:  nop
8c05034a:  add r2,r5
8c05034c:  fmov @r4+,fr1
8c05034e:  mov r5,r6
8c050350:  fmov @r4+,fr2
8c050352:  fldi0 fr7
8c050354:  nop
8c050356:  fmov @r4+,fr4
8c050358:  nop
8c05035a:  fmov @r4+,fr5
8c05035c:  ftrv xmtrx,fv0                ; next A position
8c05035e:  fmov @r4,fr6
8c050360:  add #12,r5
8c050362:  fmov fr10,@-r7                ; B position z,y,x
8c050364:  add #24,r6
8c050366:  fmov fr9,@-r7
8c050368:  nop
8c05036a:  fmov fr8,@-r7
8c05036c:  ftrv xmtrx,fv12               ; B normal
8c05036e:  mov.l @r7,r0
8c050370:  dt r8
8c050372:  or #1,r0                      ; tag B.x
8c050374:  mov.l r0,@r7
8c050376:  fmov fr14,@-r10               ; B normal z,y,x
8c050378:  fmov fr13,@-r10
8c05037a:  bf.s 0x8c0502fa
8c05037c:  fmov fr12,@-r10

;; ==== 0x8c0503dc  weighted seam (only when 0x8c252e3c != 0: character near and in front, set at 0x8c0f6df0) ====
;; entry list at the end of the seam list: {count, then per vertex {u32 dstOff, f32 w, x,y,z, nx,ny,nz}}.
;; XMTRX (= parent->child from above) is saved to 0x8c2e9258 with fschg XD pair stores. Entries are sorted by
;; weight: only when w changes is M = (1-w)*M_rel + w*M_bind rebuilt (0x8c0504a6, 16 fmac), and for node
;; types 7 and 12 its three rows are renormalised (0x8c0504c2 -> 0x8c1df200). Then it is loaded into XMTRX.
;; cost per vertex (same weight): 33 instructions, 2 FTRV + FIPR + FSRRA, no pipelining: FIPR reads fv8 right
;; after its FTRV, so about 35-40 cycles. Each weight change adds about 120 instructions.
8c05041e:  mov.l @r10+,r12               ; dstOff
8c050420:  fmov @r10+,fr3                ; w
8c050422:  fcmp/eq fr3,fr2               ; same weight as the previous vertex?
8c050424:  bt 0x8c05045c                 ; yes: keep XMTRX
;  ... (rebuild the blended matrix, load into XMTRX with 8 fschg pair loads into XD0-XD14) ...
8c05045c:  fldi1 fr7
8c05045e:  fldi0 fr11
8c050460:  fmov @r10+,fr4                ; position
8c050462:  fmov @r10+,fr5
8c050464:  fmov @r10+,fr6
8c050466:  fmov @r10+,fr8                ; normal
8c050468:  fmov @r10+,fr9
8c05046a:  fmov @r10+,fr10
8c05046c:  ftrv xmtrx,fv8                ; blended normal
8c05046e:  ftrv xmtrx,fv4                ; blended position
8c050470:  add r11,r12
8c050472:  add #24,r12
8c050474:  fipr fv8,fv8                  ; |n|^2 -> fr11 (stalls on the FTRV)
8c050476:  fsrra fr11                    ; 1/|n|: a lerped matrix is not orthonormal
8c050478:  flds fr4,fpul
8c05047a:  sts fpul,r0
8c05047c:  or #1,r0                      ; inline-vertex tag in x
8c05047e:  fmul fr11,fr10
8c050480:  fmul fr11,fr9
8c050482:  fmul fr11,fr8
8c050484:  fmov fr10,@-r12
8c050486:  fmov fr9,@-r12
8c050488:  fmov fr8,@-r12
8c05048a:  fmov fr6,@-r12
8c05048c:  fmov fr5,@-r12
8c05048e:  mov.l r0,@-r12               ; x written from the integer side, with its tag
8c050490:  dt r9
8c050492:  bf.s 0x8c05041e
8c050494:  fmov fr3,fr2

;; ==== 0x8c052860  HMT_HandCalcSkin (hands): envelope skinning into a 48 B work vertex ====
;; r4 = hand object (*r4 = envelope data; error string 0x8c223840 if NULL), r5 = bone matrix palette (64 B per
;; bone; slot = current matrix * node+32 bind matrix, written by 0x8c052d20 during the finger walk 0x8c0b0320).
;; Work vertex 48 B: {x,y,z,nx,ny,nz (bind pose), ax,ay,az,anx,any,anz (accumulators, zeroed first)}.
;; Per bone: {u32 bone, u32 n, n x {u32 vtx, f32 w}}. The bone matrix goes straight into XMTRX with 8 fschg
;; 64-bit loads into XD0..XD14 (no FRCHG, no copy through the front bank).
;; cost: 50 slots per influence (48 instructions + 2 nops), 2 FTRV, 6 FMUL + 6 FADD, 2-stage pipelined (the
;;       accumulate of influence i overlaps the transform of i+1). About 26-30 cycles per influence.
8c0528d4:  fschg                         ; SZ=1
8c0528d6:  fmov @r6+,fr1                 ; = fmov @r6+,xd0: load the bone matrix into XMTRX directly
;  ... xd2..xd14 ...
8c0528f0:  fschg
8c052916:  fmul fr14,fr4                 ; w * (M n) of the previous influence
8c052918:  fldi1 fr3
8c05291a:  fmul fr14,fr5
8c05291c:  fmov @r0+,fr0                 ; next vertex bind position
8c05291e:  fmul fr14,fr6
8c052920:  fmov @r0+,fr1
8c052922:  fadd fr4,fr11                 ; accumulate the normal
8c052924:  fmov @r0+,fr2
8c052926:  fadd fr5,fr12
8c052928:  fmov @r14+,fr14               ; next weight
8c05292a:  fadd fr6,fr13
8c05292c:  fmov @r1+,fr8                 ; position accumulator (+24)
8c05292e:  ftrv xmtrx,fv0                ; M * (x,y,z,1)
8c052930:  mov.l @r14+,r4                ; next vertex index
8c052932:  nop
8c052934:  fmov @r1+,fr9
8c052936:  nop
8c052938:  fmov @r1+,fr10
8c05293a:  fmov fr13,@-r3                ; store the previous normal accumulator
8c05293c:  mov r0,r2
8c05293e:  fmov fr12,@-r3
8c052940:  shll2 r4
8c052942:  fmov fr11,@-r3
8c052944:  mov r1,r3
8c052946:  fmul fr14,fr0                 ; w * (M p)
8c052948:  fldi0 fr7
8c05294a:  fmul fr14,fr1
8c05294c:  fmov @r2+,fr4                 ; bind normal
8c05294e:  fmul fr14,fr2
8c052950:  fmov @r2+,fr5
8c052952:  fadd fr0,fr8
8c052954:  fmov @r2+,fr6
8c052956:  fadd fr1,fr9
8c052958:  shll2 r4
8c05295a:  fadd fr2,fr10
8c05295c:  fmov @r3+,fr11                ; normal accumulator (+36)
8c05295e:  ftrv xmtrx,fv4                ; M * (n,0)
8c052960:  fmov @r3+,fr12
8c052962:  mov r4,r0
8c052964:  fmov @r3+,fr13
8c052966:  shll r4                       ; index*16 + index*32 = index*48
8c052968:  fmov fr10,@-r1                ; position accumulator back
8c05296a:  add r4,r0
8c05296c:  fmov fr9,@-r1
8c05296e:  add r7,r0
8c052970:  fmov fr8,@-r1
8c052972:  dt r13
8c052974:  mov r0,r1
8c052976:  bf.s 0x8c052916
8c052978:  add #24,r1
;; then 0x8c052aa2-0x8c052b28: renormalise the normals, 4 vertices per iteration (68 instructions, about 17 per
;; vertex: FIPR fv,fv then FSRRA, no FDIV or FSQRT), tag x |= 1. 0x8c052be0 then scatters {x..nz} into the
;; hand mesh's strip-stream records at precomputed byte offsets (6 floats per vertex, 16 slots).

;; ################################################################ SECTION D
;; Shenmue II (DC, JP Disc 1) 1ST_READ.BIN, load base 0x8C010000. Section D: shadow modifier volumes, matrix library,
;; batch projector, light-pool callback. sh-elf-objdump -EL; nops/literals removed; with SZ=1 objdump still prints
;; frN for what are DRn/XDn pair moves. Costs are static estimates.


;; ==== 0x8c1dd420  shadow MODIFIER VOLUME from model strips, no-clip twin (also 0x8c1dd540; clip twins 0x8c1dd640 / 0x8c1dd9a0) ====
;; Driver 0x8c1dd220 (from 0x8c1d6600, header PCW 0x818c0000|cull = poly/MV param, list 1 = opaque modifier volume):
;;   per mesh: bounding-sphere FTRV + near/far + 4 screen-edge tests (0x8c1dd298), then per strip group the twin below.
;; in : the same strip stream as the opaque model renderer (inline 32 B vertices / 8 B back-references, only x,y,z read)
;; out: one 64 B TA modifier-volume triangle {PCW, A(X,Y,1/w), B, C} per strip vertex, written through the SQs into
;;      Kamui's list-1 buffer (*(0x8c317e44)+4); volume open/close headers (ISP | 0x40 "last") at 0x8c1dd378.
;; Clip twins: vertex with w < near (fr1) -> helpers 0x8c1ddc80-0x8c1dde58 compute t=(near-wa)/(wb-wa) with FDIV, fmac lerp
;;      of X,Y, and 1/w taken as the constant 1/near (r7) - the clipped polygon is fanned into extra MV triangles.
;; cost: ~43-46 instr per strip vertex (one MV triangle each), 1 FTRV + 1 FDIV, ~35-45 cycles; no CPU back-face cull.
8c1dd420:  mov #1,r9                  
8c1dd422:  mov.l @r4+,r3              ; r3 = strip vertex count (from strip header)
8c1dd424:  fschg                      ; SZ=1: fmov now moves 64-bit register PAIRS
8c1dd426:  lds r9,fpul                ; fpul = 1 (int) -> "float fpul,frN" makes w=1.0
8c1dd428:  add #-2,r3                 
8c1dd42a:  mov r0,r9                  
8c1dd42c:  add #1,r9                  
8c1dd42e:  mov r4,r14                 ; --- vertex 0 fetch: r14 = vertex address
8c1dd430:  mov.l @r4,r0               
8c1dd432:  add #32,r4                 
8c1dd434:  tst #1,r0                  ; bit0 of first word set = inline 32 B vertex (x float LSB doubles as the flag)
8c1dd436:  bf 0x8c1dd43e              
8c1dd438:  mov.l @(4,r14),r14         ; else 8 B back-reference {tag, rel. offset}: r14 = r4+offset (shared vertex, NOT re-read from a pool)
8c1dd43a:  add #-24,r4                
8c1dd43c:  add r4,r14                 
8c1dd43e:  fmov @r14+,fr4             ; dr4 = (x,y)  pair load
8c1dd440:  fmov @r14+,fr6             ; dr6 = (z,junk) pair load
8c1dd442:  float fpul,fr7             ; w = 1.0 (overwrites junk)
8c1dd444:  ftrv xmtrx,fv4             ; XMTRX = proj*view*shadow/light matrix, rows permuted: fr4=w, fr5=X, fr6=Y
8c1dd446:  mov r4,r14                 
8c1dd448:  mov.l @r4,r0               
8c1dd44a:  add #32,r4                 
8c1dd44c:  tst #1,r0                  
8c1dd44e:  bf 0x8c1dd456              
8c1dd450:  mov.l @(4,r14),r14         
8c1dd452:  add #-24,r4                
8c1dd454:  add r4,r14                 
8c1dd456:  fldi1 fr7                  
8c1dd458:  fdiv fr4,fr7               ; 1/w by FDIV (12-13 cyc latency)
8c1dd45a:  pref @r14                  
8c1dd45c:  mov r9,r0                  ; vertex parity selects slot: even -> C (+28), odd -> A (+4) keeps winding
8c1dd45e:  tst #1,r0                  
8c1dd460:  mov #40,r0                 
8c1dd462:  bf 0x8c1dd466              
8c1dd464:  mov #16,r0                 
8c1dd466:  add r6,r0                  
8c1dd468:  fmul fr7,fr6               
8c1dd46a:  fmul fr7,fr5               
8c1dd46c:  fmov fr6,@-r0              ; pair store dr6=(Y/w,1/w) -> slot+8
8c1dd46e:  fmov fr4,@-r0              ; pair store dr4=(w,X/w): w lands on a byte that the PCW/next slot overwrites
          ; ... vertex 1: same fetch/FTRV/FDIV, stored to the other end slot ...
8c1dd4a2:  mov r6,r0                  ; PCW = SQ address >> 1 (arith): 0xE..>>1 = 0xF.. = para type 7 + end-of-strip;
8c1dd4a4:  shar r0                    
8c1dd4a6:  mov.l r0,@r6               ;   the 0x8c1dd... emitter never loads a PCW constant
8c1dd4a8:  add #1,r9                  ; ===== steady state: one strip vertex -> one 64 B MV triangle =====
8c1dd4aa:  fmov @r14+,fr12            
8c1dd4ac:  dt r3                      
8c1dd4ae:  fmov @r14+,fr14            
8c1dd4b0:  float fpul,fr15            
8c1dd4b2:  mov r4,r14                 
8c1dd4b4:  bt.s 0x8c1dd4c6            
8c1dd4b6:  ftrv xmtrx,fv12            ; FTRV of the new vertex issued in the bt delay slot
8c1dd4b8:  mov.l @r4,r0               
8c1dd4ba:  add #32,r4                 
8c1dd4bc:  tst #1,r0                  ; peek next record: inline or back-reference (3 extra instr for a backref)
8c1dd4be:  bf 0x8c1dd4c6              
8c1dd4c0:  mov.l @(4,r14),r14         
8c1dd4c2:  add #-24,r4                
8c1dd4c4:  add r4,r14                 
8c1dd4c6:  fldi1 fr15                 
8c1dd4c8:  fdiv fr12,fr15             ; 1/w (FDIV); first use at 0x8c1dd4d6, ~6 instr later -> ~6 cycle stall
8c1dd4ca:  add #32,r6                 
8c1dd4cc:  pref @r6                   ; pref the SECOND 32 B half of this triangle record (flush)
8c1dd4ce:  add #-32,r6                
8c1dd4d0:  pref @r14                  ; prefetch next source vertex
8c1dd4d2:  fschg                      ; SZ=0 for single stores
8c1dd4d4:  mov #28,r0                 
8c1dd4d6:  fmul fr15,fr14             
8c1dd4d8:  add r6,r0                  
8c1dd4da:  fmul fr15,fr13             
8c1dd4dc:  fmov fr15,@-r0             ; B slot (+16..+24): X/w, Y/w, 1/w of the newest vertex
8c1dd4de:  fmov fr14,@-r0             
8c1dd4e0:  fmov fr13,@-r0             
8c1dd4e2:  pref @r0                   ; flush first half (PCW + A + B.x)
8c1dd4e4:  tst r3,r3                  
8c1dd4e6:  mov.l @r4,r0               
8c1dd4e8:  bt 0x8c1dd504              
8c1dd4ea:  mov r9,r0                  ; copy newest vertex into the NEXT record's A or C slot (r6 not yet advanced:
8c1dd4ec:  tst #1,r0                  
8c1dd4ee:  mov #40,r0                 
8c1dd4f0:  bt 0x8c1dd4f4              
8c1dd4f2:  mov #16,r0                 
8c1dd4f4:  add r6,r0                  
8c1dd4f6:  fmov fr15,@-r0             ;   +64 record = next triangle; parity flips which slot)
8c1dd4f8:  add #64,r6                 ; next 64 B MV record
8c1dd4fa:  fmov fr14,@-r0             
8c1dd4fc:  add #64,r5                 ; r5 = Kamui list-1 pointer shadow (+64 per triangle)
8c1dd4fe:  fmov fr13,@-r0             
8c1dd500:  bra 0x8c1dd4a8             ; loop; ~43-46 instr per strip vertex (= per MV triangle), 1 FTRV, 1 FDIV, 4 branches
8c1dd502:  fschg                      
8c1dd504:  cmp/pl r0                  ; strip-group end: next header word; <=0 -> end of mesh (emit closing volume headers)
8c1dd506:  add #64,r6                 
8c1dd508:  bt 0x8c1dd50c              
8c1dd50a:  bra 0x8c1dd374             
8c1dd50c:  add #64,r5                 
8c1dd50e:  tst #128,r0                ; bit7 / bit4 of the strip flag pick the parity-A or parity-B twin (0x8c1dd420 / 0x8c1dd540)
8c1dd510:  add #4,r4                  
8c1dd512:  bt.s 0x8c1dd51a            
8c1dd514:  mov.l @r4+,r3              
8c1dd516:  bra 0x8c1dd428             
8c1dd518:  fschg                      
8c1dd51a:  tst #16,r0                 

;; ==== 0x8c1de5d0  batch projector, SOFTWARE-PIPELINED 3 deep (FTRV n+1 / FDIV n / scale+store n-1) ====
;; in : r4 = 16 B {x,y,z,pad}, r5 = 16 B out, r6 = count, XMTRX = projection*modelview (w in fr3/fr7/fr11)
;; out: {X/w, Y/w, 1/w, -} ; no clip, no cull.  ~13 instr/vertex, FDIV latency mostly hidden (best-scheduled loop in this range)
8c1de5d0:  fmov fr12,@-r15            
8c1de5d2:  fmov fr13,@-r15            
8c1de5d4:  fmov fr14,@-r15            
8c1de5d6:  pref @r4                   
8c1de5d8:  fmov @r4+,fr0              ; v0 = (x,y,z,1)
8c1de5da:  fmov @r4+,fr1              
8c1de5dc:  fmov @r4,fr2               
8c1de5de:  add #16,r4                 
8c1de5e0:  fldi1 fr3                  
8c1de5e2:  pref @r4                   
8c1de5e4:  dt r6                      
8c1de5e6:  ftrv xmtrx,fv0             ; FTRV v0 (pipeline fill)
8c1de5e8:  bt 0x8c1de698              
8c1de5ea:  fldi1 fr12                 
8c1de5ec:  fmov @r4+,fr4              
8c1de5ee:  fmov @r4+,fr5              
8c1de5f0:  fmov @r4,fr6               
8c1de5f2:  add #16,r4                 
8c1de5f4:  fldi1 fr7                  
8c1de5f6:  pref @r4                   
8c1de5f8:  fdiv fr3,fr12              ; 1/w of v0 starts while v1 loads
8c1de5fa:  dt r6                      
8c1de5fc:  ftrv xmtrx,fv4             ; FTRV v1
8c1de5fe:  bt 0x8c1de672              
8c1de600:  pref @r5                   ; ===== 3x unrolled steady state, registers rotate fv0 -> fv4 -> fv8 =====
8c1de602:  fldi1 fr13                 
8c1de604:  fmov @r4+,fr8              
8c1de606:  fmov @r4+,fr9              
8c1de608:  fmov @r4,fr10              
8c1de60a:  add #16,r4                 
8c1de60c:  fldi1 fr11                 
8c1de60e:  pref @r4                   
8c1de610:  fdiv fr7,fr13              ; FDIV for v(n)   (w was produced by the previous FTRV)
8c1de612:  dt r6                      
8c1de614:  fmul fr12,fr1              ; scale v(n-1) by its 1/w (FDIV issued ~9 instr earlier: mostly hidden)
8c1de616:  add #12,r5                 
8c1de618:  fmul fr12,fr0              
8c1de61a:  ftrv xmtrx,fv8             ; FTRV v(n+1)
8c1de61c:  fmov fr12,@-r5             ; out {X/w, Y/w, 1/w} written backwards, 16 B stride (4th word untouched)
8c1de61e:  fmov fr1,@-r5              
8c1de620:  fmov fr0,@-r5              
8c1de622:  bt.s 0x8c1de6b0            
8c1de624:  add #16,r5                 
8c1de626:  pref @r5                   
8c1de628:  fldi1 fr14                 
8c1de62a:  fmov @r4+,fr0              
8c1de62c:  fmov @r4+,fr1              
8c1de62e:  fmov @r4,fr2               
8c1de630:  add #16,r4                 
8c1de632:  fldi1 fr3                  
8c1de634:  pref @r4                   
8c1de636:  fdiv fr11,fr14             
8c1de638:  dt r6                      
8c1de63a:  fmul fr13,fr5              
8c1de63c:  add #12,r5                 
8c1de63e:  fmul fr13,fr4              
8c1de640:  ftrv xmtrx,fv0             
8c1de642:  fmov fr13,@-r5             
8c1de644:  fmov fr5,@-r5              
8c1de646:  fmov fr4,@-r5              
8c1de648:  bt.s 0x8c1de6d6            
8c1de64a:  add #16,r5                 
8c1de64c:  pref @r5                   
8c1de64e:  fldi1 fr12                 
8c1de650:  fmov @r4+,fr4              
8c1de652:  fmov @r4+,fr5              
8c1de654:  fmov @r4,fr6               
8c1de656:  add #16,r4                 
8c1de658:  fldi1 fr7                  
8c1de65a:  pref @r4                   
8c1de65c:  fdiv fr3,fr12              
8c1de65e:  dt r6                      
8c1de660:  fmul fr14,fr9              
8c1de662:  add #12,r5                 
8c1de664:  fmul fr14,fr8              
8c1de666:  ftrv xmtrx,fv4             
8c1de668:  fmov fr14,@-r5             
8c1de66a:  fmov fr9,@-r5              
8c1de66c:  fmov fr8,@-r5              
8c1de66e:  bf.s 0x8c1de600            ; loop back every 3 vertices; ~13 instr/vertex
8c1de670:  add #16,r5                 
8c1de672:  pref @r5                   

;; ==== 0x8c1de1fc  vertex-light pool callback (ctx gbr+16, installed by 0x8c1de14c when no extra lights are active) ====
;; in : r4 = {x,y,z, nx,ny,nz} 24 B, r6 = count, XMTRX = proj*modelview; ambient 0x8c30d25c
;; out: 16 B pool {X/w, Y/w, 1/w, I=max(N.L,0)+ambient}; pool end saved at 0x8c2bdbb0. The multi-light version
;;      0x8c1de320 (directional/point/spot, per-object light mask from 0x8c1de500, fsrra attenuation, ftrc+clamp
;;      to packed ARGB) costs ~80-150 instr/vertex.
8c1de1fc:  pref @r4                   
8c1de1fe:  mova 0x8c1de308,r0         
8c1de200:  mov.l @r0+,r5              
8c1de202:  mov.l @r5,r5               
8c1de204:  add #-16,r5                
8c1de206:  mov.l 0x8c1de318,r1 ! 8c2bdba8
8c1de208:  fmov @r1,fr0               
8c1de20a:  fldi1 fr1                  
8c1de20c:  fdiv fr0,fr1               ; 1/scale: light vector rescaled for scaled objects
8c1de20e:  mov.l 0x8c1de304,r2 ! 8c30c75c
8c1de210:  mov #-128,r1               
8c1de212:  extu.b r1,r1               
8c1de214:  add r1,r2                  
8c1de216:  fmov @r2+,fr8              ; fv8 = light direction in object space (from light 0, ctx 0x8c30c75c+0x80)
8c1de218:  fmov @r2+,fr9              
8c1de21a:  fmov @r2+,fr10             
8c1de21c:  fmul fr1,fr8               
8c1de21e:  fmul fr1,fr9               
8c1de220:  fmul fr1,fr10              
8c1de222:  mov.l @(0,r7),r0           
8c1de224:  mov.l 0x8c1de278,r2 ! 8c03c74c
8c1de226:  mov #4,r1                  
8c1de228:  tst r0,r1                  ; flag bit 2 -> multi-light/spot variant at 0x8c1de27c
8c1de22a:  bf 0x8c1de27c              
8c1de22c:  mov #0,r0                  
8c1de22e:  mov.l r0,@r2               
8c1de230:  mov.l 0x8c1de300,r0 ! 8c30d25c
8c1de232:  fmov @r0,fr15              ; fr15 = ambient intensity
8c1de234:  fmov @r4+,fr4              ; ===== loop: {pos 12 B, normal 12 B} -> pool {X/w,Y/w,1/w,I} =====
8c1de236:  add #28,r5                 
8c1de238:  fmov @r4+,fr5              
8c1de23a:  fmov @r4+,fr6              
8c1de23c:  fldi1 fr7                  
8c1de23e:  pref @r5                   
8c1de240:  ftrv xmtrx,fv4             ; FTRV position
8c1de242:  fmov @r4+,fr0              
8c1de244:  fmov @r4+,fr1              
8c1de246:  fmov @r4+,fr2              
8c1de248:  fldi0 fr3                  
8c1de24a:  fipr fv0,fv8               ; N.L in one FIPR (fr11)
8c1de24c:  fldi1 fr6                  
8c1de24e:  fdiv fr7,fr6               ; 1/w FDIV
8c1de250:  pref @r4                   
8c1de252:  fcmp/gt fr11,fr3           ; clamp N.L at 0 (branch) ...
8c1de254:  bf.s 0x8c1de25a            
8c1de258:  fldi0 fr11                 
8c1de25a:  fadd fr15,fr11             ; ... + ambient -> float INTENSITY (no ARGB packing)
8c1de25c:  fmov fr11,@r5              
8c1de25e:  dt r6                      
8c1de260:  fmov fr6,@-r5              
8c1de262:  fmul fr6,fr5               ; fmul by 1/w ~8 instr after FDIV (some stall)
8c1de266:  fmul fr6,fr4               
8c1de268:  fmov fr5,@-r5              
8c1de26a:  bf.s 0x8c1de234            ; ~22 instr/vertex
8c1de26c:  fmov fr4,@-r5              
8c1de26e:  mov.l 0x8c1de310,r0 ! 8c2bdbb0
8c1de270:  add #16,r5                 
8c1de272:  mov.l r5,@r0               
8c1de274:  rts                        

;; ==== 0x8c1decd0  matrix library: XMTRX *= RotY(angle)  (0x8c1de000-0x8c1df000 = the engine's matrix stack/lib) ====
;; Explains much of the fschg count: SZ=1 pair moves between banks (DRn<->XDm) and 64-bit pair loads/stores of matrices.
;; push 0x8c1deb40: frchg+fschg then 8 pair stores; pop 0x8c1deaf0: 8 pair loads into XD regs (stack ptr 0x8c30d470).
8c1decd0:  lds r4,fpul                
8c1decd2:  fsca fpul,dr4              ; (sin,cos) of a 16-bit BAM angle
8c1decd4:  fldi0 fr0                  
8c1decd6:  fldi0 fr3                  
8c1decd8:  fldi0 fr7                  
8c1decda:  fmov fr5,fr1               
8c1decdc:  fmov fr4,fr2               
8c1decde:  fmov fr2,fr5               
8c1dece0:  fneg fr5                   
8c1dece2:  fmov fr1,fr6               
8c1dece4:  ftrv xmtrx,fv0             ; 2 FTRV = XMTRX * the two non-trivial rotation columns
8c1dece6:  fldi0 fr4                  
8c1dece8:  ftrv xmtrx,fv4             
8c1decea:  fschg                      ; SZ=1: "fmov frN,frM" with odd M encodes FMOV DRn,XDm:
8c1decec:  fmov fr0,fr5               ; pair moves straight into the BACK bank = XMTRX columns,
8c1decee:  fmov fr2,fr7               
8c1decf0:  fmov fr4,fr9               ; so XMTRX *= RotY(a) costs 2 FTRV + 4 pair moves, no FRCHG, no memory
8c1decf2:  fmov fr6,fr11              
8c1decf4:  rts                        
8c1decf6:  fschg                      

;; ################################################################ SECTION E
;; ######## RENDERER A (0x8c039000-0x8c039d10): MT6 strip-stream renderer, used only for the SEA (MISC/TRSEA4.MT6) ########
;; Entry 0x8c039b40(r4 = model node). GBR = 0x8c2bdb80 render context: +72/+80/+88 = SQ-space write pointers for
;; Kamui lists 0/2/4 (opaque/translucent/punch-through, from table *(0x8c317e44) +0/+8/+16, converted with
;; &0x03ffffff | 0xE0000000 on entry and back on exit), +40 = radius scale.
;; Stream (MT6 "HRCM" body, read straight from the file): u32 op | len<<8 ; op 0-5: 4 TA header words (PCW,ISP,TSP,TEX),
;; u32 nstrips, then per strip i32 nverts (negative = start with reversed winding) + vertices. op 6 colour cmd, op 7 UV scale.
;; Vertex in stream: either INLINE 36 B {x,y,z, nx,ny,nz, s16 v, s16 u, base ARGB, offset ARGB} with LSB(x)=1,
;; or a 4-byte BACK-REFERENCE word (LSB=0) = byte distance back to an earlier inline copy. Normals are never read.

;; ==== 0x8c039b40  model entry: sphere cull, near-straddle select, op dispatch ====
8c039ba8:  fmov @r4+,fr0               ; node+16: sphere centre
8c039baa:  fmov @r4+,fr1
8c039bac:  fmov @r4+,fr2
8c039bae:  fldi1 fr3
8c039bb0:  fmov @r4,fr4                ; radius
8c039bb4:  ftrv xmtrx,fv0              ; centre -> view space
8c039bc0:  fmul fr6,fr4                ; radius *= gbr+40 scale
8c039bca:  fadd fr4,fr7                ; fr7 = -z + r
8c039bcc:  fsub fr4,fr8                ; fr8 = -z - r
8c039bce:  fcmp/gt fr9,fr8             ; whole sphere beyond near (fr9 = *0x8c2bdb9c)?
8c039bd0:  bf 0x8c039bd8
8c039bd2:  sett
8c039bd4:  rotcl r14                   ; r14 = 4 -> table 0x8c039d30 (no-clip kernels)
8c039bd6:  shll2 r14                   ; else r14 = 0 -> table 0x8c039d10 (near-clip kernels)
8c039bd8:  fcmp/gt fr7,fr9             ; entirely in front of near -> reject
;  ... far reject (fr8 > *0x8c2bdba0) ...
8c039bf2:  fschg                       ; SZ=1
8c039bf4:  fmov @r0+,fr4               ; = fmov @r0+,dr4  (plane a,b)  64-bit pair load
8c039bf6:  fmov @r0+,fr6               ; = fmov @r0+,dr6  (plane c,d)
8c039bf8:  fipr fv0,fv4                ; signed distance (planes at *0x8c30d6c0)
8c039bfa:  fcmp/gt fr7,fr15            ; r > d ? else reject (4 side planes, reject-only)
8c039bfc:  fschg
8c039c06:  mov.l 0x8c039c78,r3         ; 0x8c1deb40 = push XMTRX (frchg+fschg pair stores)
8c039c0e:  mov.l 0x8c039c7c,r3         ; 0x8c1e74a0 = XMTRX = projection*viewport*modelview
8c039c3e:  ldc r2,r3_bank              ; bank-1 regs used as spare globals (privileged mode)
8c039c40:  ldc r1,r4_bank              ; 0xF0000000
8c039c42:  mov.l @r4,r0                ; op word
8c039c48:  exts.b r0,r0                ; op = low byte, negative = end
8c039c50:  mov.l @(r0,r14),r3          ; kernel from 8-entry table
8c039c52:  jsr @r3
8c039c56:  bra 0x8c039c44              ; next op (kernel returns advanced r4)

;; ==== 0x8c0390b8  NO-CLIP strip kernel (ops 0-5 when the sphere is in front of near) ====
;; in : r4 = vertex stream, XMTRX = full 4x4 (screen offset folded in), fr3 = UV scale (1/256 or op-7 value)
;; out: TA vertex type 3 (packed colour, float UV) 32 B to SQ: {PCW, X, Y, 1/w, U, V, base, offset}; colours prebaked
;; cost: 39 instr/vertex (41 for a back-reference), 1 FTRV, 1 FDIV (10 instr before use, ~4-6 cycle stall),
;;       ~16 load/store, 2 int->float for UV; est. 30-35 cycles/vertex. No culling, no source prefetch.
8c0390b8:  mov r4,r13
8c0390ba:  mov.l @r4,r0                ; first word of the vertex = x (inline) or back-ref offset
8c0390bc:  tst #1,r0                   ; LSB of x float = "inline vertex" tag
8c0390be:  bf.s 0x8c0390c6
8c0390c0:  add #36,r4                  ; inline: consume 36 B
8c0390c2:  add #-32,r4                 ; back-ref: consume 4 B ...
8c0390c4:  sub r0,r13                  ; ... and read the vertex r0 bytes back in the stream
8c0390c6:  fmov @r13+,fr8
8c0390c8:  fmov @r13+,fr9
8c0390ca:  fmov @r13+,fr10
8c0390cc:  fldi1 fr11                  ; (x,y,z,1)  (x keeps its tag bit: 1 ulp error)
8c0390ce:  ftrv xmtrx,fv8              ; -> (X*w', Y*w', -, w)
8c0390d0:  add #12,r13                 ; skip the normal (unused: lighting is prebaked)
8c0390d2:  fldi1 fr10
8c0390d4:  mov.w @r13+,r2              ; s16 (V)
8c0390d6:  mov.w @r13+,r3              ; s16 (U)
8c0390d8:  mov.l @r13+,r6              ; base ARGB
8c0390da:  mov.l @r13,r7               ; offset ARGB
8c0390dc:  fdiv fr11,fr10              ; 1/w
8c0390de:  add #32,r12
8c0390e0:  lds r2,fpul
8c0390e2:  float fpul,fr12
8c0390e4:  lds r3,fpul
8c0390e6:  float fpul,fr13
8c0390e8:  mov.l r7,@-r12              ; vertex written backwards from +28
8c0390ea:  mov.l r6,@-r12
8c0390ec:  fmul fr3,fr12               ; u * scale
8c0390ee:  fmul fr3,fr13
8c0390f0:  dt r8
8c0390f2:  fmul fr10,fr8               ; FDIV result needed here
8c0390f4:  fmul fr10,fr9
8c0390f6:  fmov fr12,@-r12
8c0390f8:  fmov fr13,@-r12             ; first s16 lands at +20 (V), second at +16 (U): stream order is (v,u)
8c0390fa:  fmov fr10,@-r12             ; Z = 1/w
8c0390fc:  fmov fr9,@-r12
8c0390fe:  fmov fr8,@-r12
8c039100:  bt 0x8c03910a
8c039102:  mov.l r12,@-r12             ; PCW = the SQ address itself: 0xE0xxxxxx = vertex, bit28 clear
8c039104:  pref @r12                   ; burst 32 B
8c039106:  bra 0x8c0390b8
8c039108:  add #32,r12
8c03910a:  mov.l r5,@-r12              ; last vertex: PCW = r5 = 0xFFFFFFFF (end of strip)
8c03910c:  dt r11                      ; strips left
8c03910e:  pref @r12
8c039110:  bf.s 0x8c0390b0
8c039112:  add #32,r12
8c039114:  stc r3_bank,r3              ; r3_bank = &gbr slot of this list
8c039116:  rts
8c039118:  mov.l r12,@r3               ; write back the list pointer

;; ==== 0x8c03935c  NEAR-CLIP strip kernel, steady state (ops 0-5 when the sphere straddles near) ====
;; Keeps a 3-vertex window in fv4/fv8/fv12 = (X/w, Y/w, 1/w, base colour bits); source pointers in a scratch block
;; at 0x8c039408 (inside the code segment). Outcode = integer compare of the 1/w bit pattern.
;; cost: 54 instr + 29 in the 0x8c039500 emitter = ~83 instr/vertex, est. 60-70 cycles; triangles touching the near
;; plane go to 0x8c039560 -> 6 case handlers (0x8c039620..0x8c039760) that emit a short clipped strip, each
;; intersection costing 5 FDIV (0x8c039880) plus a packed-colour lerp on the integer side.
8c03935c:  mov.l @r14,r1
8c03935e:  fschg                       ; SZ=1: the next 4 fmov are 64-bit pair moves
8c039360:  tst r2,r9
8c039362:  fmov fr8,fr4                ; dr8 -> dr4  : window B -> A (X,Y)
8c039364:  mov.l @(20,r8),r13
8c039366:  mov.l @(24,r8),r3
8c039368:  mov.l r13,@(16,r8)          ; shift source pointers too
8c03936a:  mov.l r3,@(20,r8)
8c03936c:  mov r14,r13
8c03936e:  fmov fr10,fr6               ; dr10 -> dr6 : (1/w, colour)
8c039370:  subc r2,r2
8c039372:  fmov fr12,fr8               ; dr12 -> dr8 : C -> B
8c039374:  xor r2,r5                   ; winding parity bookkeeping (r5 never emitted: likely dead)
8c039376:  fmov fr14,fr10              ; dr14 -> dr10
8c039378:  rotcr r1                    ; LSB(x) -> T : inline tag
8c03937a:  fschg
8c03937c:  bt.s 0x8c039386
8c03937e:  add #36,r14
8c039380:  shll r1
8c039382:  add #-32,r14
8c039384:  sub r1,r13                  ; back-reference
8c039386:  mov.l r13,@(24,r8)
8c039388:  fmov @r13+,fr12
8c03938a:  fmov @r13+,fr13
8c03938c:  fmov @r13+,fr14
8c03938e:  pref @r14                   ; prefetch next source vertex (2 lines)
8c039390:  fldi1 fr15
8c039392:  mov r14,r1
8c039394:  ftrv xmtrx,fv12
8c039396:  add #32,r1
8c039398:  fldi1 fr14
8c03939a:  fdiv fr15,fr14              ; 1/w
8c03939c:  pref @r1
8c03939e:  add #16,r13
8c0393a0:  fmov @r13,fr15              ; base colour as raw bits in lane 3
8c0393a2:  stc r7_bank,r13             ; UV scale kept in a bank-1 register
8c0393a4:  flds fr14,fpul
8c0393a6:  fmul fr14,fr12
8c0393a8:  sts fpul,r3                 ; r3 = bits(1/w)
8c0393aa:  lds r13,fpul
8c0393ac:  fmul fr14,fr13
8c0393ae:  cmp/hi r10,r3               ; unsigned: 1/w > 1/near  OR  w < 0 (sign bit) -> clipped
8c0393b0:  rotcl r4                    ; outcode history
8c0393b2:  fsts fpul,fr3
8c0393b4:  tst r4,r4
8c0393b6:  bf 0x8c0393cc               ; any clipped -> end strip (PCW -1 on stale SQ half), clip triangle
8c0393b8:  bsr 0x8c039500              ; emit one vertex: 29 instr, UV unpacked from the source again
8c0393ba:  nop
8c0393bc:  mov #4,r2
8c0393be:  bra 0x8c039356

;; ################################################################ SECTION F
;; ######## EFFECTS: particle / billboard emitters (0x8c03a260 driver, table 0x8c03a4c0/0x8c03a4e0/0x8c03a500) ########
;; 16 effect slots of 104 B at 0x8c3015b8 (filled by C code around 0x8c08d340, tag 'EFCT'), each = flags word,
;; element count (+4), element array (+8), TA header words (+12..+24), sprite base colour (+92).
;; Element: 32 B {state, x,y,z, ..., +28 callback} (screen sprites) or 64 B {state, x,y,z, .., +36 angle1, +40 angle2,
;; +56 ARGB, +60 size} (rotated quads). state bit31 = alive. Each element has its OWN C callback (+28) called per frame
;; from inside the draw loop (update and draw are fused); 0x8c03a040 (gaussian jitter, 48 refs) and 0x8c03a000
;; (pos += vel, colour += dcolour) are typical callbacks.

;; ==== 0x8c03a2de  per-slot dispatch (inside driver 0x8c03a260) ====
;; list write pointers are kept in the BANKED registers r1_bank (list table +0) / r2_bank (list table +8) for the whole
;; pass (ldc/stc, no memory); r3_bank remembers which one the kernel advanced. QACR is hard-coded per list.
8c03a2de:  mov.l @r14,r1                ; slot flags
8c03a2e0:  shll r1                      ; bit31: slot active?
8c03a2e2:  mov.l @(4,r14),r13           ; element count
8c03a2e4:  bf.s 0x8c03a38c
8c03a2e6:  mov.l @(8,r14),r9            ; element array
8c03a2fc:  shll r1                      ; bit30: which list
8c03a2fe:  mov r1,r8
8c03a300:  stc r2_bank,r12              ; SQ pointer of list +8 ...
8c03a302:  mov #1,r7
8c03a304:  mov #12,r3                   ; ... QACR = 0x0C -> RAM vertex buffer
8c03a306:  bt 0x8c03a30e
8c03a308:  stc r1_bank,r12              ; SQ pointer of list +0 ...
8c03a30a:  mov #0,r7
8c03a30c:  mov #16,r3                   ; ... QACR = 0x10 -> TA FIFO directly (list +0 is the direct-transfer list)
8c03a30e:  ldc r7,r3_bank
8c03a310:  mov.l 0x8c03a358,r7          ; ff000038 QACR0
8c03a312:  mov.l r3,@(0,r7)
8c03a314:  mov.l r3,@(4,r7)             ; QACR1
;; ... 5-word global header written backwards to the SQ: PCW/ISP/TSP/TEX from slot+12..+24, base colour slot+92 (sprites)
8c03a33c:  pref @r12                    ; header burst
8c03a340:  mov.l 0x8c03a35c,r0          ; 10000000 (flag bit 26 after the two shifts)
8c03a342:  and r1,r0
8c03a344:  cmp/pl r0
8c03a346:  bf 0x8c03a360                ; set -> update-only kernels (table 0x8c03a500: a580/a620, nothing drawn)
8c03a360:  mov #-27,r4
8c03a362:  shld r4,r8                   ; r8 = flag bits 29..25
8c03a364:  shlr r8                      ; T = bit25: 1 = "no per-element callback" kernel set
8c03a366:  bf 0x8c03a374
8c03a368:  shlr r8
8c03a36a:  shll2 r8
8c03a36c:  mova 0x8c03a4e0,r0           ; b620 ba60 b320 bcc0 b9c0 b9c0 b920 b920
8c03a36e:  mov.l @(r0,r8),r8
8c03a374:  shlr r8
8c03a376:  shll2 r8
8c03a378:  mova 0x8c03a4c0,r0           ; aa00 ae40 a700 b0a0 ada0 ada0 ad00 ad00  (index = flag bits 29..27)
8c03a37a:  mov.l @(r0,r8),r8
8c03a37c:  jsr @r8                      ; r9 = elements, r13 = count, r12 = SQ ptr, fr8/fr9 = half size
8c03a37e:  mov.l @(28,r9),r1            ; first element's callback

;; ==== 0x8c03ad00  screen-aligned TEXTURED point sprite (TA sprite, 64 B) ====
;; in : 32 B elements {state, x,y,z, .., +28 callback}; XMTRX = projection*view; fr12/fr13 = half width/height (world)
;; out: TA sprite record {PCW=-1, A.xyz, B.xyz, C.xyz, D.xy, UV A/B/C as 16-bit pairs}; colour is the header base colour
;; cost: 63 instr per sprite (+ C callback), 1 FTRV, 1 FDIV (stall ~8 cycles), 64-bit pair stores, 2 SQ bursts.
;;       Near test only: w <= 0 -> sprite dropped. Size is scaled by 1/w (perspective size), no screen clip.
8c03ad00:  sts.l pr,@-r15
8c03ad02:  mov r14,r5
8c03ad04:  jsr @r1                      ; per-element update callback (C) - inside the draw loop
8c03ad06:  mov r9,r4
8c03ad08:  mov.l @r9+,r1                ; state
8c03ad0a:  fldi1 fr7                    ; w = 1
8c03ad0c:  fmov @r9+,fr4
8c03ad0e:  fmov @r9+,fr5
8c03ad10:  fmov @r9+,fr6
8c03ad12:  shll r1                      ; T = alive
8c03ad14:  ftrv xmtrx,fv4               ; centre -> clip space
8c03ad16:  fldi1 fr14
8c03ad18:  bf.s 0x8c03ad88              ; dead -> skip
8c03ad1a:  shlr r1
8c03ad1c:  fldi0 fr6
8c03ad1e:  fcmp/gt fr6,fr7              ; w > 0 ?
8c03ad20:  add #-12,r9
8c03ad22:  bf.s 0x8c03ad78              ; behind the eye -> drop
8c03ad24:  fdiv fr7,fr14                ; 1/w
8c03ad26:  mova 0x8c03ae2c,r0           ; constant UV words (0x00003f80, 0x3f800000)
8c03ad28:  fmov fr12,fr8
8c03ad2a:  fmov fr13,fr9
8c03ad2c:  mov #-1,r8                   ; PCW 0xFFFFFFFF (vertex, end of strip)
8c03ad2e:  add #32,r12
8c03ad30:  fmov fr14,fr7                ; FDIV stall here
8c03ad32:  fmul fr7,fr4                 ; X = x/w
8c03ad34:  fmul fr7,fr5                 ; Y = y/w
8c03ad36:  fmov fr7,fr0
8c03ad38:  fmul fr7,fr8                 ; half width on screen
8c03ad3a:  fmov fr7,fr3
8c03ad3c:  fmul fr7,fr9
8c03ad3e:  fmov fr4,fr15
8c03ad40:  fmov fr4,fr1
8c03ad42:  fadd fr8,fr1
8c03ad44:  fmov fr5,fr6
8c03ad46:  fsub fr9,fr5
8c03ad48:  fschg                        ; SZ=1: the next 3 stores are 64-bit register pairs
8c03ad4a:  fmov fr0,@-r12               ; (dr0 = {1/w, Bx})  objdump prints fr0, it is dr0
8c03ad4c:  fmov fr4,@-r12               ; dr4 = {Ax, Ay}
8c03ad4e:  fmov fr6,@-r12               ; dr6 = {..}
8c03ad50:  fschg
8c03ad52:  fmov fr15,@-r12
8c03ad54:  mov.l r8,@-r12               ; PCW last
8c03ad56:  pref @r12                    ; first 32 B of the sprite
8c03ad58:  add #64,r12
8c03ad5a:  fmov fr5,fr2
8c03ad5c:  fmov fr1,fr10
8c03ad5e:  fmov fr2,fr11
8c03ad60:  fadd fr9,fr11
8c03ad62:  fmov @r0+,fr5                ; UV16 pair words loaded as floats (raw bits)
8c03ad64:  fldi0 fr6
8c03ad66:  fmov @r0,fr7
8c03ad68:  fschg
8c03ad6a:  fmov fr6,@-r12               ; 4 pair stores = second 32 B half
8c03ad6c:  fmov fr4,@-r12
8c03ad6e:  fmov fr10,@-r12
8c03ad70:  fmov fr2,@-r12
8c03ad72:  fschg
8c03ad74:  pref @r12                    ; second burst
8c03ad76:  add #32,r12
8c03ad78:  dt r13
8c03ad7a:  add #28,r9
8c03ad7c:  pref @r9                     ; prefetch next element
8c03ad7e:  bf.s 0x8c03ad02
8c03ad80:  mov.l @(28,r9),r1            ; next callback
;; Twin 0x8c03b920 (no callback) does the same with 18 scalar "fmov @r12 / add #4" stores instead of pair stores.

;; ==== 0x8c03aa30  world-space ROTATED quad (2 FSCA angles), packed colour, 4-vertex strip ====
;; Per element the XMTRX is rebuilt: identity rotation in the back bank (frchg block), view-space centre written straight
;; into the matrix translation column with 64-bit XD moves, basis rotated by FSCA+FTRV, then a full 4x4 multiply through
;; the matrix-stack helpers (push 0x8c1deb40, multiply 0x8c1dea10 = 8 pair loads + 4 FTRV + FRCHG, pop 0x8c1deac0).
;; cost: 225 inline instr + ~60 in helpers per quad = ~70 instr per output vertex; 11 FTRV, 4 FDIV, 2 FSCA per quad.
8c03aa5e:  fmov @r6+,fr4
8c03aa60:  fmov @r6+,fr5
8c03aa62:  fmov @r6+,fr6
8c03aa64:  fldi1 fr7
8c03aa66:  ftrv xmtrx,fv4               ; centre -> view space
8c03aa68:  add #20,r6
8c03aa6a:  lds.l @r6+,fpul              ; angle 1 (16-bit FSCA angle)
8c03aa72:  fschg
8c03aa74:  fmov fr4,fr13                ; = fmov dr4,xd12 : (x,y) into XMTRX column 3, no FRCHG needed
8c03aa76:  fmov fr6,fr15                ; = fmov dr6,xd14 : (z,w)
8c03aa78:  fschg
8c03aa7a:  frchg                        ; back bank: write rotation part of XMTRX = identity
8c03aa7c:  fldi1 fr0
8c03aa7e:  fldi0 fr1
8c03aa80:  fldi0 fr2
8c03aa82:  fldi0 fr4
8c03aa84:  fldi1 fr5
8c03aa86:  fldi0 fr6
8c03aa88:  fldi0 fr8
8c03aa8a:  fldi0 fr9
8c03aa8c:  fldi1 fr10
8c03aa8e:  frchg
8c03aa90:  fsca fpul,dr4                ; sin/cos angle 1
;; ... rotated basis vectors by FTRV, written back into XMTRX columns with fschg pair moves (fmov drN,xdM) ...
8c03aab4:  fsca fpul,dr4                ; sin/cos angle 2
;; ... push / multiply / pop (3 calls), then 4 corners, each:
8c03ab0e:  fmov fr0,fr4
8c03ab10:  fmov fr1,fr5
8c03ab12:  fmov fr2,fr6
8c03ab14:  fldi1 fr7
8c03ab16:  ftrv xmtrx,fv4               ; corner (-sx,+sy,0,1) -> clip
8c03ab18:  add #24,r12
8c03ab1a:  mov.l r7,@r12                ; packed ARGB from the element (+56)
8c03ab1c:  fldi1 fr15
8c03ab1e:  fldi0 fr6
8c03ab20:  add #-8,r12
8c03ab22:  fcmp/gt fr6,fr7              ; w > 0 ? else the whole quad is abandoned (r12 rewound)
8c03ab24:  bt 0x8c03ab30
8c03ab30:  fdiv fr7,fr15                ; 1/w, used 5 instr later (stall ~8 cycles)
8c03ab32:  add #60,r9
8c03ab34:  pref @r9
8c03ab36:  fsub fr13,fr1                ; next corner computed while the FDIV runs
8c03ab38:  fsub fr13,fr1
8c03ab3a:  fmov fr15,@-r12              ; 1/w
8c03ab3c:  fmul fr15,fr5
8c03ab3e:  fmov fr5,@-r12               ; Y
8c03ab40:  fmul fr15,fr4
8c03ab42:  fmov fr4,@-r12               ; X
8c03ab44:  mov.l r12,@-r12              ; PCW = the SQ address itself (0xE.... -> type 7 vertex), saves a register
8c03ab46:  pref @r12
;; last corner stores mov #-1 as PCW (end of strip). Afterwards XMTRX is restored from a save area with
;; fschg + 8 x "fmov @r10+,xdN" + fschg (0x8c03abde) - the same 10-instruction XMTRX restore runs once per element
;; in every kernel of this family (callbacks are C and may clobber XMTRX).

;; ==== 0x8c03bf40  in-place sphere-map UV generator (pre-pass before the MT7 model draw) ====
;; called by model draws (0x8c0836d0, 0x8c0d907c, 0x8c0d9248, 0x8c0d963c, 0x8c0d979c, 0x8c11ba60) when model flag
;; (+4) & 4 is set, right before 0x8c1d6880 / 0x8c1d6980 / 0x8c1d71e0. XMTRX = view rotation.
;; in : strip vertex stream: inline vertex has x with LSB = 1, back-references (LSB 0) are skipped; float normals
;;      (scale 0.5) or s8 normals (path 0x8c03bfe2, scale 1/256); out: u,v overwritten in the vertex data.
;; cost: 31 instr per vertex (float normals), 38 (s8 normals), 1 FTRV, no divide.
8c03bf74:  mov.l @r4,r2                 ; vertex x word
8c03bf76:  mov #1,r0
8c03bf78:  fldi0 fr7                    ; w = 0: direction
8c03bf7a:  add #12,r4
8c03bf7c:  tst r0,r2
8c03bf7e:  bt 0x8c03bfca                ; LSB 0 = back-reference entry, nothing to do
8c03bf80:  fmov @r4+,fr4                ; nx
8c03bf82:  fmov @r4+,fr5                ; ny
8c03bf84:  fmov @r4,fr6                 ; nz
8c03bf86:  add #8,r4
8c03bf88:  mov.l @r4,r1                 ; old v word (keeps its LSB flag)
8c03bf8a:  add #36,r4
8c03bf8c:  pref @r4
8c03bf8e:  add #-32,r4
8c03bf90:  ftrv xmtrx,fv4               ; view-space normal
8c03bf92:  and r0,r1
8c03bf94:  fmov fr1,fr2                 ; 0.5
8c03bf96:  fmov fr1,fr3
8c03bf98:  fmac fr0,fr4,fr2             ; u = 0.5 + 0.5*n'x
8c03bf9a:  fmac fr0,fr5,fr3             ; v = 0.5 + 0.5*n'y
8c03bf9c:  flds fr3,fpul
8c03bf9e:  sts fpul,r2
8c03bfa0:  mov #-8,r0
8c03bfa2:  fmov fr2,@(r0,r4)            ; store u
8c03bfa4:  dt r5
8c03bfa6:  mov #-4,r0
8c03bfa8:  and r6,r2                    ; r6 = 0xFFFFFFFE
8c03bfaa:  or r2,r1                     ; v with the original LSB flag re-inserted
8c03bfac:  mov.l @r4,r2
8c03bfae:  mov.l r1,@(r0,r4)            ; store v
8c03bfb0:  bf 0x8c03bf76

