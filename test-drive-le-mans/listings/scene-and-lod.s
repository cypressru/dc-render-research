; Test Drive Le Mans (Dreamcast, 2000) LEMANS24.BIN, load base 0x8C010000.
; Disassembled with sh-elf-objdump -EL; short excerpts for analysis and
; commentary. See ../README.md for context.


; ==== lmTrackLODCullNode::Cull (0x8c0d2868): a layer is a far-plane multiplier ====
; far = max(far * node[+56], near + 0.001); cull the subtree (0x8c05d0a8); restore far.
; node[+56] presumably comes from TRACKDETAILS ~LODSetting: L_1/L_2 1.0, L_3 0.55, L_4 0.23
; (~MultiplayerLODSetting, i.e. split-screen: 0.5 / 0.275 / 0.115)
8c0d2868:  mov.l r14,@-r15
8c0d286a:  mov.l r13,@-r15
8c0d286c:  sts.l pr,@-r15
8c0d286e:  add #-8,r15
8c0d2870:  mov r4,r13
8c0d2872:  mov.l 0x8c0d28c8,r0 ! 8c23dea0
8c0d2874:  mov r15,r5
8c0d2876:  mov r15,r6
8c0d2878:  mov.l @r0,r14
8c0d287a:  add #4,r5
8c0d287c:  mov.l 0x8c0d28cc,r0 ! 8c060e40
8c0d287e:  add #16,r14
8c0d2880:  jsr @r0
8c0d2882:  mov r14,r4
8c0d2884:  mov #0,r2
8c0d2886:  mov r13,r1
8c0d2888:  add r15,r2
8c0d288a:  add #56,r1
8c0d288c:  fmov @r2,fr4
8c0d288e:  mova 0x8c0d28d0,r0
8c0d2890:  fmov @r1,fr0
8c0d2892:  mov #4,r2
8c0d2894:  add r15,r2
8c0d2896:  fmul fr0,fr4
8c0d2898:  fmov @r2,fr1
8c0d289a:  fmov @r0,fr0
8c0d289c:  fadd fr0,fr1
8c0d289e:  fcmp/gt fr4,fr1
8c0d28a0:  bt 0x8c0d28a6
8c0d28a2:  bra 0x8c0d28a8
8c0d28a4:  nop
8c0d28a6:  fmov fr1,fr4
8c0d28a8:  mov.l 0x8c0d28d4,r0 ! 8c060e4c
8c0d28aa:  jsr @r0
8c0d28ac:  mov r14,r4
8c0d28ae:  mov.l 0x8c0d28d8,r0 ! 8c05d0a8
8c0d28b0:  jsr @r0
8c0d28b2:  mov r13,r4
8c0d28b4:  mov #0,r0
8c0d28b6:  fmov @(r0,r15),fr4
8c0d28b8:  mov.l 0x8c0d28d4,r0 ! 8c060e4c
8c0d28ba:  jsr @r0
8c0d28bc:  mov r14,r4
8c0d28be:  add #8,r15
8c0d28c0:  lds.l @r15+,pr
8c0d28c2:  mov.l @r15+,r13
8c0d28c4:  rts
8c0d28c6:  mov.l @r15+,r14

; ==== Sphere vs frustum test (0x8c060e54): one FTRV for the centre, radius scaled by the matrix column length ====
; 6 compares give an outside code (0x3f0000 + bits 0-5) or a straddle mask (bits 0-5);
; this does not pick the kernel: that is a later box-vs-w=1 test in the device draw (0x8c0e4794, flag
; 0x8c27ab80); a fully-inside parent sets 0x8c23de78 and its subtree skips tests
8c060e54:  fmov fr15,@-r15
8c060e56:  fmov fr14,@-r15
8c060e58:  fmov fr13,@-r15
8c060e5a:  mov.l r14,@-r15
8c060e5c:  mov.l r13,@-r15
8c060e5e:  mov r4,r14
8c060e60:  mov.l r12,@-r15
8c060e62:  mov r6,r13
8c060e64:  sts.l pr,@-r15
8c060e66:  add #-12,r15
8c060e68:  mov r5,r12
8c060e6a:  mov r15,r0
8c060e6c:  mov.l r0,@-r15
8c060e6e:  mov.l 0x8c060f54,r0 ! 8c0b2900
8c060e70:  jsr @r0
8c060e72:  mov r13,r4
8c060e74:  add #4,r15
8c060e76:  mov #0,r2
8c060e78:  add r15,r2
8c060e7a:  fmov @r2,fr15
8c060e7c:  mov r13,r4
8c060e7e:  mov.l 0x8c060f58,r0 ! 8c0b2ba0
8c060e80:  mov #4,r2
8c060e82:  add r15,r2
8c060e84:  fmov @r2,fr14
8c060e86:  mov #8,r2
8c060e88:  add r15,r2
8c060e8a:  jsr @r0
8c060e8c:  fmov @r2,fr13
8c060e8e:  add #12,r12
8c060e90:  fmov @r12,fr4
8c060e92:  fmov fr13,fr9
8c060e94:  fmov @r14,fr3
8c060e96:  fmul fr0,fr4
8c060e98:  fadd fr4,fr9
8c060e9a:  fcmp/gt fr3,fr9
8c060e9c:  bt 0x8c060ea4
8c060e9e:  mov.l 0x8c060f5c,r0 ! 200020
8c060ea0:  bra 0x8c060f40
8c060ea2:  nop
8c060ea4:  mov r14,r0
8c060ea6:  add #4,r0
8c060ea8:  fmov @r0,fr10
8c060eaa:  fmov fr13,fr2
8c060eac:  fsub fr4,fr2
8c060eae:  fcmp/gt fr2,fr10
8c060eb0:  bt 0x8c060eb8
8c060eb2:  mov.l 0x8c060f60,r0 ! 40004
8c060eb4:  bra 0x8c060f40
8c060eb6:  nop
8c060eb8:  mov r14,r1
8c060eba:  mov r14,r0
8c060ebc:  add #8,r1
8c060ebe:  add #12,r0
8c060ec0:  fmov @r1,fr5
8c060ec2:  fmov @r0,fr7
8c060ec4:  fmul fr15,fr5
8c060ec6:  fmov fr5,fr0
8c060ec8:  fmul fr13,fr7
8c060eca:  fmov fr7,fr1
8c060ecc:  fadd fr4,fr1
8c060ece:  fneg fr0
8c060ed0:  fcmp/gt fr0,fr1
8c060ed2:  bt 0x8c060eda
8c060ed4:  mov.l 0x8c060f64,r0 ! 10001
8c060ed6:  bra 0x8c060f40
8c060ed8:  nop
8c060eda:  fcmp/gt fr5,fr1
8c060edc:  bt 0x8c060ee4
8c060ede:  mov.l 0x8c060f68,r0 ! 20002
8c060ee0:  bra 0x8c060f40
8c060ee2:  nop
8c060ee4:  mov r14,r0
8c060ee6:  add #16,r0
8c060ee8:  add #20,r14
8c060eea:  fmov @r0,fr6
8c060eec:  fmov @r14,fr8
8c060eee:  fmul fr14,fr6
8c060ef0:  fmov fr6,fr0
8c060ef2:  fmul fr13,fr8
8c060ef4:  fmov fr8,fr1
8c060ef6:  fadd fr4,fr1
8c060ef8:  fneg fr0
8c060efa:  fcmp/gt fr0,fr1
8c060efc:  bt 0x8c060f04
8c060efe:  mov.l 0x8c060f6c,r0 ! 100010
8c060f00:  bra 0x8c060f40
8c060f02:  nop
8c060f04:  fcmp/gt fr6,fr1
8c060f06:  bt 0x8c060f0e
8c060f08:  mov.l 0x8c060f70,r0 ! 80008
8c060f0a:  bra 0x8c060f40
8c060f0c:  nop
8c060f0e:  fcmp/gt fr2,fr3
8c060f10:  bf.s 0x8c060f16
8c060f12:  mov #0,r0
8c060f14:  or #32,r0
8c060f16:  fcmp/gt fr10,fr9
8c060f18:  bf 0x8c060f1c
8c060f1a:  or #4,r0
8c060f1c:  fmov fr5,fr0
8c060f1e:  fsub fr4,fr7
8c060f20:  fneg fr0
8c060f22:  fcmp/gt fr7,fr0
8c060f24:  bf 0x8c060f28
8c060f26:  or #1,r0
8c060f28:  fcmp/gt fr7,fr5
8c060f2a:  bf 0x8c060f2e
8c060f2c:  or #2,r0
8c060f2e:  fmov fr6,fr0
8c060f30:  fsub fr4,fr8
8c060f32:  fneg fr0
8c060f34:  fcmp/gt fr8,fr0
8c060f36:  bf 0x8c060f3a
8c060f38:  or #16,r0
8c060f3a:  fcmp/gt fr8,fr6
8c060f3c:  bf 0x8c060f40
8c060f3e:  or #8,r0
8c060f40:  add #12,r15
8c060f42:  lds.l @r15+,pr
8c060f44:  mov.l @r15+,r12
8c060f46:  mov.l @r15+,r13
8c060f48:  mov.l @r15+,r14
8c060f4a:  fmov @r15+,fr13
8c060f4c:  fmov @r15+,fr14
8c060f4e:  rts
8c060f50:  fmov @r15+,fr15

; ==== Track strip-vertex count (0x8c1be54c): sums precomputed per-mesh counts of the meshes drawn ====
8c1be54c:  mov.l r14,@-r15
8c1be54e:  mov.l r13,@-r15
8c1be550:  mov r4,r14
8c1be552:  mov.l r12,@-r15
8c1be554:  mov.l r11,@-r15
8c1be556:  mov.l r10,@-r15
8c1be558:  sts.l pr,@-r15
8c1be55a:  mov.l 0x8c1be5c4,r0 ! 8c23dab0
8c1be55c:  mov.l 0x8c1be5c8,r1 ! 8c0b557c
8c1be55e:  mov.l @r0,r3
8c1be560:  add #72,r3
8c1be562:  mov.l 0x8c1be5cc,r0 ! d0
8c1be564:  mov.l @r3,r3
8c1be566:  jsr @r1
8c1be568:  mov.l @(r0,r3),r13
8c1be56a:  mov r14,r0
8c1be56c:  add #124,r0
8c1be56e:  mov.l @r0,r12
8c1be570:  cmp/pl r12
8c1be572:  bf 0x8c1be5b6
8c1be574:  mov r14,r0
8c1be576:  add #120,r0
8c1be578:  mov.l @r0,r1
8c1be57a:  mov #0,r5
8c1be57c:  mov.l @(60,r14),r7
8c1be57e:  mov r5,r6
8c1be580:  mov r5,r3
8c1be582:  mov r5,r4
8c1be584:  bra 0x8c1be5ac
8c1be586:  mov r5,r0
8c1be588:  mov.l @(56,r14),r10
8c1be58a:  bra 0x8c1be592
8c1be58c:  mov.l @(r0,r10),r11
8c1be58e:  add #12,r1
8c1be590:  add #1,r3
8c1be592:  mov.l @r1,r10
8c1be594:  cmp/eq r10,r11
8c1be596:  bt 0x8c1be59c
8c1be598:  cmp/gt r3,r12
8c1be59a:  bt 0x8c1be58e
8c1be59c:  cmp/ge r12,r3
8c1be59e:  bt 0x8c1be5b0
8c1be5a0:  mov.l @(4,r1),r10
8c1be5a2:  add #8,r0
8c1be5a4:  mov.l @(8,r1),r11
8c1be5a6:  add r10,r5
8c1be5a8:  add #1,r4
8c1be5aa:  add r11,r6
8c1be5ac:  cmp/gt r4,r7
8c1be5ae:  bt 0x8c1be588
8c1be5b0:  mov.l 0x8c1be5d0,r0 ! 8c0f0828
8c1be5b2:  jsr @r0
8c1be5b4:  mov r13,r4
8c1be5b6:  lds.l @r15+,pr
8c1be5b8:  mov.l @r15+,r10
8c1be5ba:  mov.l @r15+,r11
8c1be5bc:  mov.l @r15+,r12
8c1be5be:  mov.l @r15+,r13
8c1be5c0:  rts
8c1be5c2:  mov.l @r15+,r14

; ==== lmCarLODController cull (0x8c0f0850): car budget = m_totalStripVertBudget (37000) - track strip verts ====
; sum the cars' current-LOD strip verts, bubble-sort cars by a per-car float (presumably distance);
; over budget: step cars down one level, farthest first, until it fits, for m_maxAdaptiveLODStepDown
; = 2 passes; under budget: step back up, <= m_maxAdaptiveLODStepUp = 1 level per frame;
; still over budget: drop the farthest cars from the draw list (0x8c0f0c2c)
8c0f0850:  mov.l r14,@-r15
8c0f0852:  mov.l r13,@-r15
8c0f0854:  mov.l r12,@-r15
8c0f0856:  mov.l r11,@-r15
8c0f0858:  mov.l r10,@-r15
8c0f085a:  mov r4,r11
8c0f085c:  mov.l r9,@-r15
8c0f085e:  mov.l r8,@-r15
8c0f0860:  sts.l pr,@-r15
8c0f0862:  add #-4,r15
8c0f0864:  mov.l 0x8c0f0904,r0 ! 8c05d0a8
8c0f0866:  jsr @r0
8c0f0868:  nop
8c0f086a:  mov.l 0x8c0f0908,r0 ! 8c010f88
8c0f086c:  mov r11,r4
8c0f086e:  add #108,r4
8c0f0870:  mov #8,r6
8c0f0872:  jsr @r0
8c0f0874:  mov #0,r5
8c0f0876:  mov.l @(60,r11),r8
8c0f0878:  mov r11,r4
8c0f087a:  mov #72,r0
8c0f087c:  mov #0,r1
8c0f087e:  mov.l r1,@(r0,r11)
8c0f0880:  mov r8,r5
8c0f0882:  mov.l 0x8c0f090c,r0 ! 8c0594b8
8c0f0884:  jsr @r0
8c0f0886:  add #68,r4
8c0f0888:  mov #96,r0
8c0f088a:  mov #0,r9
8c0f088c:  mov r11,r1
8c0f088e:  mov.l r9,@(r0,r11)
8c0f0890:  add #104,r1
8c0f0892:  mov.l @r1,r1
8c0f0894:  mov #-1,r3
8c0f0896:  mov #100,r0
8c0f0898:  add r3,r1
8c0f089a:  mov.l r1,@(r0,r11)
8c0f089c:  mov r11,r3
8c0f089e:  mov.l 0x8c0f0910,r0 ! 8c23dbf8
8c0f08a0:  mov #116,r4
8c0f08a2:  add #116,r3
8c0f08a4:  mov.l @r0,r1
8c0f08a6:  cmp/pl r8
8c0f08a8:  mov.l 0x8c0f0914,r0 ! 14c
8c0f08aa:  mov.l @(r0,r1),r1
8c0f08ac:  mov r4,r0
8c0f08ae:  mov.l r1,@(r0,r11)
8c0f08b0:  mov.l 0x8c0f0918,r0 ! 90
8c0f08b2:  mov.l @r3,r3
8c0f08b4:  mov.l @(r0,r11),r1
8c0f08b6:  mov r4,r0
8c0f08b8:  sub r1,r3
8c0f08ba:  bf.s 0x8c0f0980
8c0f08bc:  mov.l r3,@(r0,r11)
8c0f08be:  mov r11,r0
8c0f08c0:  add #64,r0
8c0f08c2:  mov.l @r0,r5
8c0f08c4:  mov r9,r10
8c0f08c6:  shll2 r10
8c0f08c8:  add r10,r5
8c0f08ca:  mov.l @r5,r0
8c0f08cc:  add #80,r0
8c0f08ce:  mov.b @r0,r0
8c0f08d0:  extu.b r0,r0
8c0f08d2:  extu.b r0,r0
8c0f08d4:  tst r0,r0
8c0f08d6:  bt 0x8c0f097a
8c0f08d8:  mov.l 0x8c0f091c,r0 ! 8c01e358
8c0f08da:  mov r11,r4
8c0f08dc:  jsr @r0
8c0f08de:  add #68,r4
8c0f08e0:  mov r11,r0
8c0f08e2:  add #64,r0
8c0f08e4:  mov.l @r0,r3
8c0f08e6:  mov r11,r1
8c0f08e8:  add #96,r1
8c0f08ea:  mov r10,r0
8c0f08ec:  mov.l @(r0,r3),r3
8c0f08ee:  mov.l @r1,r0
8c0f08f0:  add #72,r3
8c0f08f2:  mov.l @r3,r1
8c0f08f4:  lds r0,fpul
8c0f08f6:  float fpul,fr1
8c0f08f8:  lds r1,fpul
8c0f08fa:  float fpul,fr0
8c0f08fc:  fcmp/gt fr1,fr0
8c0f08fe:  bt 0x8c0f0920
8c0f0900:  bra 0x8c0f0922
8c0f0902:  nop
8c0f0904:  mov.l 0x8c0f0ba8,r0 ! 67b3d04a
8c0f0906:  .word 0x8c05
8c0f0908:  .word 0x0f88
8c0f090a:  .word 0x8c01
8c0f090c:  mov.w 0x8c0f0a80,r4 ! 6432
8c0f090e:  .word 0x8c05
8c0f0910:  mov.l 0x8c0f0cf4,r11 ! 340c4408
8c0f0912:  .word 0x8c23
8c0f0914:  mov.b @(r0,r4),r1
8c0f0916:  .word 0x0000
8c0f0918:  .word 0x0090
8c0f091a:  .word 0x0000
8c0f091c:  mov #88,r3
8c0f091e:  .word 0x8c01
8c0f0920:  fmov fr0,fr1
8c0f0922:  ftrc fr1,fpul
8c0f0924:  mov r11,r3
8c0f0926:  mov #96,r0
8c0f0928:  add #100,r3
8c0f092a:  sts fpul,r4
8c0f092c:  mov.l r4,@(r0,r11)
8c0f092e:  mov.l @r3,r0
8c0f0930:  lds r1,fpul
8c0f0932:  float fpul,fr0
8c0f0934:  lds r0,fpul
8c0f0936:  float fpul,fr1
8c0f0938:  fcmp/gt fr0,fr1
8c0f093a:  bt 0x8c0f0940
8c0f093c:  bra 0x8c0f0942
8c0f093e:  nop
8c0f0940:  fmov fr0,fr1
8c0f0942:  ftrc fr1,fpul
8c0f0944:  mov r11,r3
8c0f0946:  mov #100,r0
8c0f0948:  add #64,r3
8c0f094a:  sts fpul,r4
8c0f094c:  mov.l r4,@(r0,r11)
8c0f094e:  shll2 r1
8c0f0950:  mov.l @r3,r3
8c0f0952:  mov r10,r0
8c0f0954:  mov r11,r4
8c0f0956:  mov.l @(r0,r3),r5
8c0f0958:  add #108,r4
8c0f095a:  mov.l @r4,r4
8c0f095c:  mov r11,r3
8c0f095e:  mov.l 0x8c0f09b0,r0 ! c4
8c0f0960:  add #112,r3
8c0f0962:  mov.l @(r0,r5),r5
8c0f0964:  mov r1,r0
8c0f0966:  mov.l @(r0,r5),r5
8c0f0968:  mov.l @r5,r1
8c0f096a:  mov #108,r0
8c0f096c:  add r1,r4
8c0f096e:  mov.l r4,@(r0,r11)
8c0f0970:  mov.l @r3,r3
8c0f0972:  mov #112,r0
8c0f0974:  mov.l @(4,r5),r1
8c0f0976:  add r1,r3
8c0f0978:  mov.l r3,@(r0,r11)
8c0f097a:  add #1,r9
8c0f097c:  cmp/gt r9,r8
8c0f097e:  bt 0x8c0f08be
8c0f0980:  mov r11,r0
8c0f0982:  add #72,r0
8c0f0984:  mov.l @r0,r1
8c0f0986:  mov r11,r10
8c0f0988:  add #124,r10
8c0f098a:  mov #124,r0
8c0f098c:  mov.l r1,@(r0,r11)
8c0f098e:  mov.l @r10,r3
8c0f0990:  mov r8,r1
8c0f0992:  mov.l 0x8c0f09b4,r0 ! 80
8c0f0994:  sub r3,r1
8c0f0996:  mov.l r1,@(r0,r11)
8c0f0998:  mov.l 0x8c0f09b8,r0 ! 8c202230
8c0f099a:  mov.b @r0,r0
8c0f099c:  extu.b r0,r0
8c0f099e:  extu.b r0,r0
8c0f09a0:  tst r0,r0
8c0f09a2:  bt 0x8c0f09fc
8c0f09a4:  mov.l 0x8c0f09bc,r6 ! 84
8c0f09a6:  mov r11,r9
8c0f09a8:  add #76,r9
8c0f09aa:  mov #0,r12
8c0f09ac:  bra 0x8c0f09f6
8c0f09ae:  mov #-1,r13
8c0f09b0:  mov.b r12,@(r0,r0)
8c0f09b2:  .word 0x0000
8c0f09b4:  .word 0x0080
8c0f09b6:  .word 0x0000
8c0f09b8:  mov.b r3,@r2
8c0f09ba:  .word 0x8c20
8c0f09bc:  mov.b r8,@(r0,r0)
8c0f09be:  .word 0x0000
8c0f09c0:  add r13,r14
8c0f09c2:  cmp/gt r12,r14
8c0f09c4:  bf 0x8c0f09f4
8c0f09c6:  mov r14,r4
8c0f09c8:  add r13,r4
8c0f09ca:  mov r14,r0
8c0f09cc:  mov.l @r9,r1
8c0f09ce:  shll2 r4
8c0f09d0:  shll2 r0
8c0f09d2:  add r1,r4
8c0f09d4:  mov.l @(r0,r1),r7
8c0f09d6:  mov.l @r4,r3
8c0f09d8:  mov r7,r5
8c0f09da:  add r6,r5
8c0f09dc:  mov r3,r1
8c0f09de:  add r6,r1
8c0f09e0:  fmov @r5,fr1
8c0f09e2:  fmov @r1,fr0
8c0f09e4:  fcmp/gt fr1,fr0
8c0f09e6:  bf 0x8c0f09ee
8c0f09e8:  mov.l r7,@r4
8c0f09ea:  mov.l @r9,r1
8c0f09ec:  mov.l r3,@(r0,r1)
8c0f09ee:  add #-1,r14
8c0f09f0:  cmp/gt r12,r14
8c0f09f2:  bt 0x8c0f09c6
8c0f09f4:  add #1,r12
8c0f09f6:  mov.l @r10,r14
8c0f09f8:  cmp/gt r12,r14
8c0f09fa:  bt 0x8c0f09c0
8c0f09fc:  mov.l 0x8c0f0a30,r0 ! 8c2aaf10
8c0f09fe:  mov.b @r0,r0
8c0f0a00:  extu.b r0,r0
8c0f0a02:  extu.b r0,r0
8c0f0a04:  tst r0,r0
8c0f0a06:  bt 0x8c0f0a0c
8c0f0a08:  bra 0x8c0f0c2c
8c0f0a0a:  nop
8c0f0a0c:  mov r11,r1
8c0f0a0e:  add #108,r1
8c0f0a10:  mov.l @r1,r3
8c0f0a12:  mov r11,r0
8c0f0a14:  add #116,r0
8c0f0a16:  mov.l @r0,r1
8c0f0a18:  cmp/gt r1,r3
8c0f0a1a:  bf 0x8c0f0af0
8c0f0a1c:  mov.l 0x8c0f0a34,r0 ! 85
8c0f0a1e:  mov.b @(r0,r11),r0
8c0f0a20:  extu.b r0,r0
8c0f0a22:  extu.b r0,r0
8c0f0a24:  cmp/eq #1,r0
8c0f0a26:  bf 0x8c0f0af0
8c0f0a28:  mov #0,r12
8c0f0a2a:  bra 0x8c0f0ad6
8c0f0a2c:  mov #-1,r14
8c0f0a2e:  .word 0x0000
8c0f0a30:  bra 0x8c0f0854
8c0f0a32:  .word 0x8c2a
8c0f0a34:  mov.w r8,@(r0,r0)
8c0f0a36:  .word 0x0000
8c0f0a38:  mov r11,r0
8c0f0a3a:  add #124,r0
8c0f0a3c:  mov.l @r0,r13
8c0f0a3e:  add r14,r13
8c0f0a40:  cmp/pz r13
8c0f0a42:  bf 0x8c0f0ad4
8c0f0a44:  mov r11,r0
8c0f0a46:  add #76,r0
8c0f0a48:  mov.l @r0,r3
8c0f0a4a:  mov r11,r1
8c0f0a4c:  add #92,r1
8c0f0a4e:  mov r13,r0
8c0f0a50:  shll2 r0
8c0f0a52:  mov.l @(r0,r3),r10
8c0f0a54:  mov.l @r1,r0
8c0f0a56:  cmp/eq r0,r10
8c0f0a58:  bt 0x8c0f0ace
8c0f0a5a:  mov r10,r0
8c0f0a5c:  mov r10,r1
8c0f0a5e:  add #76,r0
8c0f0a60:  add #72,r1
8c0f0a62:  mov.l @r0,r0
8c0f0a64:  mov.l @r1,r9
8c0f0a66:  add r14,r0
8c0f0a68:  cmp/gt r9,r0
8c0f0a6a:  bf 0x8c0f0ace
8c0f0a6c:  mov.l 0x8c0f0ae4,r0 ! c4
8c0f0a6e:  mov r11,r4
8c0f0a70:  add #108,r4
8c0f0a72:  mov.l @(r0,r10),r1
8c0f0a74:  mov.l @r4,r6
8c0f0a76:  mov r9,r0
8c0f0a78:  shll2 r0
8c0f0a7a:  mov.l @(r0,r1),r3
8c0f0a7c:  add #1,r9
8c0f0a7e:  mov r9,r5
8c0f0a80:  mov.l @r3,r4
8c0f0a82:  mov r11,r1
8c0f0a84:  mov #108,r0
8c0f0a86:  sub r4,r6
8c0f0a88:  mov.l r6,@(r0,r11)
8c0f0a8a:  add #112,r1
8c0f0a8c:  mov.l @(4,r3),r6
8c0f0a8e:  mov #112,r0
8c0f0a90:  mov.l @r1,r1
8c0f0a92:  mov r10,r4
8c0f0a94:  mov.l 0x8c0f0ae8,r3 ! 8c0d91e8
8c0f0a96:  sub r6,r1
8c0f0a98:  jsr @r3
8c0f0a9a:  mov.l r1,@(r0,r11)
8c0f0a9c:  mov.l 0x8c0f0ae4,r0 ! c4
8c0f0a9e:  mov r11,r1
8c0f0aa0:  add #108,r1
8c0f0aa2:  mov.l @(r0,r10),r3
8c0f0aa4:  shll2 r9
8c0f0aa6:  mov r11,r4
8c0f0aa8:  mov r9,r0
8c0f0aaa:  mov.l @(r0,r3),r6
8c0f0aac:  add #112,r4
8c0f0aae:  mov.l @r1,r5
8c0f0ab0:  mov #108,r0
8c0f0ab2:  mov.l @r6,r3
8c0f0ab4:  add r3,r5
8c0f0ab6:  mov.l r5,@(r0,r11)
8c0f0ab8:  mov r11,r3
8c0f0aba:  mov.l @r4,r5
8c0f0abc:  mov #112,r0
8c0f0abe:  add #116,r3
8c0f0ac0:  mov.l @(4,r6),r4
8c0f0ac2:  add r4,r5
8c0f0ac4:  mov.l r5,@(r0,r11)
8c0f0ac6:  mov.l @r1,r1
8c0f0ac8:  mov.l @r3,r0
8c0f0aca:  cmp/gt r1,r0
8c0f0acc:  bt 0x8c0f0ad4
8c0f0ace:  add #-1,r13
8c0f0ad0:  cmp/pz r13
8c0f0ad2:  bt 0x8c0f0a44
8c0f0ad4:  add #1,r12
8c0f0ad6:  mov.l 0x8c0f0aec,r0 ! 8c
8c0f0ad8:  mov.l @(r0,r11),r0
8c0f0ada:  cmp/gt r12,r0
8c0f0adc:  bt 0x8c0f0a38
8c0f0ade:  bra 0x8c0f0c2c
8c0f0ae0:  nop
8c0f0ae2:  .word 0x0000
8c0f0ae4:  mov.b r12,@(r0,r0)
8c0f0ae6:  .word 0x0000
8c0f0ae8:  mov.w 0x8c0f0cbc,r1 ! 400b
8c0f0aea:  .word 0x8c0d
8c0f0aec:  mov.b @(r0,r8),r0
8c0f0aee:  .word 0x0000
8c0f0af0:  cmp/gt r3,r1
8c0f0af2:  bt 0x8c0f0af8
8c0f0af4:  bra 0x8c0f0c2c
8c0f0af6:  nop
8c0f0af8:  mov.l 0x8c0f0b20,r0 ! 84
8c0f0afa:  mov.b @(r0,r11),r0
8c0f0afc:  extu.b r0,r0
8c0f0afe:  extu.b r0,r0
8c0f0b00:  cmp/eq #1,r0
8c0f0b02:  bt 0x8c0f0b08
8c0f0b04:  bra 0x8c0f0c2c
8c0f0b06:  nop
8c0f0b08:  mov.l 0x8c0f0b24,r0 ! 8c0f1138
8c0f0b0a:  mov r11,r4
8c0f0b0c:  add #80,r4
8c0f0b0e:  jsr @r0
8c0f0b10:  mov #0,r9
8c0f0b12:  mov.l @(60,r11),r5
8c0f0b14:  mov r11,r4
8c0f0b16:  mov.l 0x8c0f0b28,r0 ! 8c0f1270
8c0f0b18:  jsr @r0
8c0f0b1a:  add #80,r4
8c0f0b1c:  bra 0x8c0f0b4a
8c0f0b1e:  mov r9,r10
8c0f0b20:  mov.b r8,@(r0,r0)
8c0f0b22:  .word 0x0000
8c0f0b24:  mov.l r3,@(32,r1)
8c0f0b26:  .word 0x8c0f
8c0f0b28:  mov.l r7,@(0,r2)
8c0f0b2a:  .word 0x8c0f
8c0f0b2c:  mov r11,r0
8c0f0b2e:  add #76,r0
8c0f0b30:  mov.l @r0,r1
8c0f0b32:  mov r11,r4
8c0f0b34:  mov r15,r5
8c0f0b36:  mov r10,r0
8c0f0b38:  shll2 r0
8c0f0b3a:  mov.l @(r0,r1),r0
8c0f0b3c:  add #80,r4
8c0f0b3e:  add #72,r0
8c0f0b40:  mov.l @r0,r1
8c0f0b42:  mov.l 0x8c0f0b58,r0 ! 8c0f1154
8c0f0b44:  jsr @r0
8c0f0b46:  mov.l r1,@r15
8c0f0b48:  add #1,r10
8c0f0b4a:  mov r11,r0
8c0f0b4c:  add #124,r0
8c0f0b4e:  mov.l @r0,r0
8c0f0b50:  cmp/gt r10,r0
8c0f0b52:  bt 0x8c0f0b2c
8c0f0b54:  bra 0x8c0f0c1c
8c0f0b56:  mov #-1,r12
8c0f0b58:  mov.l r5,@(16,r1)
8c0f0b5a:  .word 0x8c0f
8c0f0b5c:  mov #0,r3
8c0f0b5e:  bra 0x8c0f0c0a
8c0f0b60:  mov r3,r13
8c0f0b62:  mov r11,r0
8c0f0b64:  add #76,r0
8c0f0b66:  mov.l @r0,r4
8c0f0b68:  mov r13,r1
8c0f0b6a:  shll2 r1
8c0f0b6c:  mov r1,r0
8c0f0b6e:  mov.l @(r0,r4),r4
8c0f0b70:  mov r4,r0
8c0f0b72:  add #84,r0
8c0f0b74:  mov.l @r0,r0
8c0f0b76:  cmp/eq #1,r0
8c0f0b78:  bt 0x8c0f0c08
8c0f0b7a:  mov r4,r0
8c0f0b7c:  add #72,r0
8c0f0b7e:  mov.l @r0,r5
8c0f0b80:  cmp/pl r5
8c0f0b82:  bf 0x8c0f0c08
8c0f0b84:  mov r11,r0
8c0f0b86:  add #88,r0
8c0f0b88:  mov.l @r0,r6
8c0f0b8a:  mov r1,r0
8c0f0b8c:  mov.l @(r0,r6),r6
8c0f0b8e:  mov r4,r1
8c0f0b90:  add #76,r1
8c0f0b92:  mov.l 0x8c0f0cd0,r0 ! 88
8c0f0b94:  mov.l @r1,r1
8c0f0b96:  mov.l @(r0,r11),r0
8c0f0b98:  sub r6,r1
8c0f0b9a:  add r12,r1
8c0f0b9c:  cmp/gt r0,r1
8c0f0b9e:  bf 0x8c0f0ba2
8c0f0ba0:  mov r0,r1
8c0f0ba2:  sub r5,r6
8c0f0ba4:  cmp/gt r6,r1
8c0f0ba6:  bf 0x8c0f0c08
8c0f0ba8:  mov.l 0x8c0f0cd4,r0 ! c4
8c0f0baa:  mov r11,r7
8c0f0bac:  mov r11,r6
8c0f0bae:  mov.l @(r0,r4),r10
8c0f0bb0:  add #108,r7
8c0f0bb2:  add #116,r6
8c0f0bb4:  mov r5,r0
8c0f0bb6:  shll2 r0
8c0f0bb8:  mov.l @(r0,r10),r1
8c0f0bba:  add r12,r5
8c0f0bbc:  mov.l @r7,r7
8c0f0bbe:  mov r5,r0
8c0f0bc0:  shll2 r0
8c0f0bc2:  mov.l @(r0,r10),r14
8c0f0bc4:  mov.l @r6,r6
8c0f0bc6:  mov.l @r1,r10
8c0f0bc8:  mov.l @r14,r0
8c0f0bca:  sub r10,r0
8c0f0bcc:  add r7,r0
8c0f0bce:  cmp/gt r6,r0
8c0f0bd0:  bt 0x8c0f0c14
8c0f0bd2:  sub r10,r7
8c0f0bd4:  mov #108,r0
8c0f0bd6:  mov.l r7,@(r0,r11)
8c0f0bd8:  mov r11,r0
8c0f0bda:  mov.l @(4,r1),r3
8c0f0bdc:  add #112,r0
8c0f0bde:  mov.l @r0,r6
8c0f0be0:  mov.l 0x8c0f0cd8,r1 ! 8c0d91e8
8c0f0be2:  mov #112,r0
8c0f0be4:  sub r3,r6
8c0f0be6:  jsr @r1
8c0f0be8:  mov.l r6,@(r0,r11)
8c0f0bea:  mov r11,r0
8c0f0bec:  add #108,r0
8c0f0bee:  mov.l @r0,r5
8c0f0bf0:  mov r11,r1
8c0f0bf2:  mov.l @r14,r4
8c0f0bf4:  mov #108,r0
8c0f0bf6:  add #112,r1
8c0f0bf8:  add r4,r5
8c0f0bfa:  mov.l r5,@(r0,r11)
8c0f0bfc:  mov #1,r3
8c0f0bfe:  mov.l @r1,r4
8c0f0c00:  mov #112,r0
8c0f0c02:  mov.l @(4,r14),r1
8c0f0c04:  add r1,r4
8c0f0c06:  mov.l r4,@(r0,r11)
8c0f0c08:  add #1,r13
8c0f0c0a:  mov r11,r0
8c0f0c0c:  add #124,r0
8c0f0c0e:  mov.l @r0,r0
8c0f0c10:  cmp/gt r13,r0
8c0f0c12:  bt 0x8c0f0b62
8c0f0c14:  extu.b r3,r0
8c0f0c16:  tst r0,r0
8c0f0c18:  bt.s 0x8c0f0c2c
8c0f0c1a:  add #1,r9
8c0f0c1c:  mov r11,r1
8c0f0c1e:  mov r11,r0
8c0f0c20:  add #108,r1
8c0f0c22:  add #116,r0
8c0f0c24:  mov.l @r1,r1
8c0f0c26:  mov.l @r0,r0
8c0f0c28:  cmp/gt r1,r0
8c0f0c2a:  bt 0x8c0f0b5c
8c0f0c2c:  mov r11,r5
8c0f0c2e:  mov r11,r4
8c0f0c30:  add #108,r5
8c0f0c32:  add #116,r4
8c0f0c34:  mov.l @r5,r1
8c0f0c36:  mov.l @r4,r0
8c0f0c38:  cmp/gt r0,r1
8c0f0c3a:  bf 0x8c0f0cac
8c0f0c3c:  mov r11,r0
8c0f0c3e:  add #124,r0
8c0f0c40:  mov.l @r0,r6
8c0f0c42:  add #-1,r6
8c0f0c44:  cmp/pz r6
8c0f0c46:  bf 0x8c0f0c96
8c0f0c48:  mov.l 0x8c0f0cd4,r1 ! c4
8c0f0c4a:  mov r11,r3
8c0f0c4c:  mov r11,r9
8c0f0c4e:  mov r11,r7
8c0f0c50:  add #76,r3
8c0f0c52:  add #112,r9
8c0f0c54:  add #72,r7
8c0f0c56:  mov #108,r14
8c0f0c58:  mov.l @r3,r10
8c0f0c5a:  mov r6,r0
8c0f0c5c:  shll2 r0
8c0f0c5e:  mov.l @(r0,r10),r13
8c0f0c60:  mov.l @r5,r12
8c0f0c62:  mov r1,r0
8c0f0c64:  mov.l @(r0,r13),r10
8c0f0c66:  add #72,r13
8c0f0c68:  mov.l @r13,r0
8c0f0c6a:  shll2 r0
8c0f0c6c:  mov.l @(r0,r10),r13
8c0f0c6e:  mov.l @r13,r10
8c0f0c70:  mov r14,r0
8c0f0c72:  sub r10,r12
8c0f0c74:  mov.l r12,@(r0,r11)
8c0f0c76:  mov.l @r9,r10
8c0f0c78:  mov #112,r0
8c0f0c7a:  mov.l @(4,r13),r12
8c0f0c7c:  sub r12,r10
8c0f0c7e:  mov.l r10,@(r0,r11)
8c0f0c80:  mov.l @r7,r10
8c0f0c82:  mov #72,r0
8c0f0c84:  add #-1,r10
8c0f0c86:  mov.l r10,@(r0,r11)
8c0f0c88:  mov.l @r5,r10
8c0f0c8a:  mov.l @r4,r0
8c0f0c8c:  cmp/gt r10,r0
8c0f0c8e:  bt 0x8c0f0c96
8c0f0c90:  add #-1,r6
8c0f0c92:  cmp/pz r6
8c0f0c94:  bt 0x8c0f0c58
8c0f0c96:  mov r11,r0
8c0f0c98:  add #72,r0
8c0f0c9a:  mov.l @r0,r3
8c0f0c9c:  mov r11,r1
8c0f0c9e:  add #124,r1
8c0f0ca0:  mov #124,r0
8c0f0ca2:  mov.l r3,@(r0,r11)
8c0f0ca4:  mov.l @r1,r1
8c0f0ca6:  mov.l 0x8c0f0cdc,r0 ! 80
8c0f0ca8:  sub r1,r8
8c0f0caa:  mov.l r8,@(r0,r11)
8c0f0cac:  mov r11,r0
8c0f0cae:  add #120,r0
8c0f0cb0:  mov r11,r1
8c0f0cb2:  mov.l @r0,r4
8c0f0cb4:  add #104,r1
8c0f0cb6:  mov.l @r1,r6
8c0f0cb8:  mov #0,r5
8c0f0cba:  mov.l 0x8c0f0ce0,r0 ! 8c010f88
8c0f0cbc:  jsr @r0
8c0f0cbe:  shll2 r6
8c0f0cc0:  mov r11,r5
8c0f0cc2:  mov r11,r3
8c0f0cc4:  mov r11,r1
8c0f0cc6:  add #76,r5
8c0f0cc8:  add #120,r3
8c0f0cca:  add #124,r1
8c0f0ccc:  bra 0x8c0f0cfe
8c0f0cce:  mov #0,r6
8c0f0cd0:  .word 0x0088
8c0f0cd2:  .word 0x0000
8c0f0cd4:  mov.b r12,@(r0,r0)
8c0f0cd6:  .word 0x0000
8c0f0cd8:  mov.w 0x8c0f0eac,r1 ! 6ef6
8c0f0cda:  .word 0x8c0d
8c0f0cdc:  .word 0x0080
8c0f0cde:  .word 0x0000
8c0f0ce0:  .word 0x0f88
8c0f0ce2:  .word 0x8c01
8c0f0ce4:  mov.l @r5,r4
8c0f0ce6:  mov r6,r0
8c0f0ce8:  shll2 r0
8c0f0cea:  mov.l @(r0,r4),r4
8c0f0cec:  add #1,r6
8c0f0cee:  add #72,r4
8c0f0cf0:  mov.l @r4,r4
8c0f0cf2:  mov.l @r3,r0
8c0f0cf4:  shll2 r4
8c0f0cf6:  add r0,r4
8c0f0cf8:  mov.l @r4,r0
8c0f0cfa:  add #1,r0
8c0f0cfc:  mov.l r0,@r4
8c0f0cfe:  mov.l @r1,r0
8c0f0d00:  cmp/gt r6,r0
8c0f0d02:  bt 0x8c0f0ce4
8c0f0d04:  mov.l 0x8c0f0d1c,r0 ! 8c202238
8c0f0d06:  mov.b @r0,r0
8c0f0d08:  extu.b r0,r0
8c0f0d0a:  extu.b r0,r0
8c0f0d0c:  tst r0,r0
8c0f0d0e:  bt 0x8c0f0dec
8c0f0d10:  mov.l 0x8c0f0d20,r14 ! 11c
8c0f0d12:  mov.l 0x8c0f0d24,r12 ! 120
8c0f0d14:  mov.l 0x8c0f0d28,r13 ! 110
8c0f0d16:  bra 0x8c0f0de2
8c0f0d18:  mov #0,r9
8c0f0d1a:  .word 0x0000
8c0f0d1c:  tst r3,r2
8c0f0d1e:  .word 0x8c20
8c0f0d20:  mov.b @(r0,r1),r1
8c0f0d22:  .word 0x0000
8c0f0d24:  .word 0x0120
8c0f0d26:  .word 0x0000
8c0f0d28:  .word 0x0110
8c0f0d2a:  .word 0x0000
8c0f0d2c:  mov r11,r0
8c0f0d2e:  add #76,r0
8c0f0d30:  mov.l @r0,r1
8c0f0d32:  mov r9,r0
8c0f0d34:  shll2 r0
8c0f0d36:  mov.l @(r0,r1),r8
8c0f0d38:  mov r8,r1
8c0f0d3a:  add #72,r1
8c0f0d3c:  mov.l 0x8c0f0e00,r0 ! 8c0d8ef0
8c0f0d3e:  mov r8,r4
8c0f0d40:  jsr @r0
8c0f0d42:  mov.l @r1,r5
8c0f0d44:  mov.l 0x8c0f0e04,r1 ! 8c23dea0
8c0f0d46:  mov r0,r4
8c0f0d48:  mov.l 0x8c0f0e08,r3 ! 8c
8c0f0d4a:  mov.l @r1,r10
8c0f0d4c:  mov r8,r1
8c0f0d4e:  add r3,r1
8c0f0d50:  mov.l @(48,r10),r3
8c0f0d52:  mov.l @r1,r5
8c0f0d54:  mov.l @(4,r1),r0
8c0f0d56:  mov.l r5,@r3
8c0f0d58:  mov.l r0,@(4,r3)
8c0f0d5a:  mov.l @(8,r1),r5
8c0f0d5c:  mov.l @(12,r1),r0
8c0f0d5e:  mov.l r5,@(8,r3)
8c0f0d60:  mov.l r0,@(12,r3)
8c0f0d62:  mov.l @(16,r1),r5
8c0f0d64:  mov.l @(20,r1),r0
8c0f0d66:  mov.l r5,@(16,r3)
8c0f0d68:  mov.l r0,@(20,r3)
8c0f0d6a:  mov.l @(24,r1),r5
8c0f0d6c:  mov.l @(28,r1),r0
8c0f0d6e:  mov.l r5,@(24,r3)
8c0f0d70:  mov.l r0,@(28,r3)
8c0f0d72:  mov.l @(32,r1),r5
8c0f0d74:  mov.l @(36,r1),r0
8c0f0d76:  mov.l r5,@(32,r3)
8c0f0d78:  mov.l r0,@(36,r3)
8c0f0d7a:  mov.l @(40,r1),r5
8c0f0d7c:  mov.l @(44,r1),r0
8c0f0d7e:  mov.l r5,@(40,r3)
8c0f0d80:  mov.l r0,@(44,r3)
8c0f0d82:  mov.l @(48,r10),r0
8c0f0d84:  add #48,r0
8c0f0d86:  mov.l r0,@(48,r10)
8c0f0d88:  mov.l @r4,r0
8c0f0d8a:  mov.l @(16,r0),r0
8c0f0d8c:  jsr @r0
8c0f0d8e:  nop
8c0f0d90:  mov.l 0x8c0f0e0c,r0 ! 8c202240
8c0f0d92:  mov r8,r1
8c0f0d94:  add #72,r1
8c0f0d96:  mov.l @r1,r1
8c0f0d98:  mov.l @r0,r0
8c0f0d9a:  cmp/gt r1,r0
8c0f0d9c:  bf 0x8c0f0dda
8c0f0d9e:  mov.l 0x8c0f0e10,r0 ! 114
8c0f0da0:  mov.l @(r0,r8),r4
8c0f0da2:  mov.l @r4,r0
8c0f0da4:  mov.l @(16,r0),r0
8c0f0da6:  jsr @r0
8c0f0da8:  nop
8c0f0daa:  mov.l 0x8c0f0e14,r0 ! 118
8c0f0dac:  mov.l @(r0,r8),r4
8c0f0dae:  mov.l @r4,r0
8c0f0db0:  mov.l @(16,r0),r0
8c0f0db2:  jsr @r0
8c0f0db4:  nop
8c0f0db6:  mov r14,r0
8c0f0db8:  mov.l @(r0,r8),r4
8c0f0dba:  mov.l @r4,r0
8c0f0dbc:  mov.l @(16,r0),r0
8c0f0dbe:  jsr @r0
8c0f0dc0:  nop
8c0f0dc2:  mov r12,r0
8c0f0dc4:  mov.l @(r0,r8),r4
8c0f0dc6:  mov.l @r4,r0
8c0f0dc8:  mov.l @(16,r0),r0
8c0f0dca:  jsr @r0
8c0f0dcc:  nop
8c0f0dce:  mov r13,r0
8c0f0dd0:  mov.l @(r0,r8),r4
8c0f0dd2:  mov.l @r4,r0
8c0f0dd4:  mov.l @(16,r0),r0
8c0f0dd6:  jsr @r0
8c0f0dd8:  nop
8c0f0dda:  mov.l @(48,r10),r0
8c0f0ddc:  add #1,r9
8c0f0dde:  add #-48,r0
8c0f0de0:  mov.l r0,@(48,r10)
8c0f0de2:  mov r11,r0
8c0f0de4:  add #124,r0
8c0f0de6:  mov.l @r0,r0
8c0f0de8:  cmp/gt r9,r0
8c0f0dea:  bt 0x8c0f0d2c
8c0f0dec:  add #4,r15
8c0f0dee:  lds.l @r15+,pr
8c0f0df0:  mov.l @r15+,r8
8c0f0df2:  mov.l @r15+,r9
8c0f0df4:  mov.l @r15+,r10
8c0f0df6:  mov.l @r15+,r11
8c0f0df8:  mov.l @r15+,r12
8c0f0dfa:  mov.l @r15+,r13
8c0f0dfc:  rts
8c0f0dfe:  mov.l @r15+,r14
