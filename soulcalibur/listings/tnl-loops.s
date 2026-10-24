; Soulcalibur (Dreamcast USA, 1999) 1ST_READ.BIN, load base 0x8C010000. sh-elf-objdump -D -EL, nop padding and literal-pool words removed.
; Annotated T&L loops. Sections: CORE (stage+character pools, skinning, lighting, emitters, shadow MV, metal),
; A (skeleton concat), B (effect/2D projector + emitters), C (effect projector, weapon trails, sprites). Costs are static estimates.

;; ######## CORE PIPELINE: shared-vertex pools + FTRV 4-light lighting + strip emitter (stage AND characters) ########
;; All pools live at ctx 0x8c266c10: +76 = position/screen pool (16 B entries), +80 = colour pool (16 B entries),
;; +84 = view matrix (16 floats), +0x3e4 = 4-light direction matrix, +0x424 = light colour matrix + ambient,
;; +0x6f4 = per-list vertex-buffer pointer table (Kamui RAM buffers, written through the SQs).
;; Pool writers allocate each 32-byte output line with movca.l (no read-for-ownership on the write miss).

;; ==== 0x8c03a9cc  stage pool transform + perspective  (called before every rigid mesh) ====
;; in : r5 = 16 B src {x,y,z, attr(u32)}, r6 = count, r4 = pool, XMTRX = view*object (focal scale folded in), fr4 = depth scale
;; out: pool {X=x/z+320, Y=y/z+240, Z=fr4/z, attr raw}; returns r0 = #vertices with |x/z|<320 (0 -> caller skips mesh)
;; cost: 30 instr/vertex, 1 FTRV, 1 FDIV used 2 instr later (~9-cycle stall), no pipelining; z<=0 -> x,y,Z *= +Inf sentinel
8c03a9cc:  cmp/pl r6                   
8c03a9ce:  bf 0x8c03aa1c               
8c03a9d0:  mov.l 0x8c03aa20,r0 ! 8c03aa30
8c03a9d2:  fldi0 fr7                   
8c03a9d4:  fmov @r0+,fr8               ; fr8=320, fr9=240, fr10=+Inf (table 0x8c03aa30)
8c03a9d6:  fmov @r0+,fr9               
8c03a9d8:  fmov @r0+,fr10              
8c03a9da:  mov #0,r2                   
8c03a9dc:  mov #0,r7                   
8c03a9de:  mov #31,r0                  
8c03a9e0:  fmov @r5+,fr0               
8c03a9e2:  fmov @r5+,fr1               
8c03a9e4:  fmov @r5+,fr2               
8c03a9e6:  fldi1 fr3                   ; w=1
8c03a9e8:  mov.l @r5+,r3               ; attr word moved raw on the integer side
8c03a9ea:  ftrv xmtrx,fv0              ; (x,y,z,1) -> view space (screen-scaled)
8c03a9ec:  tst r4,r0                   ; r0=31: start of a 32 B cache line?
8c03a9ee:  bf.s 0x8c03a9f4             
8c03a9f0:  fldi1 fr6                   
8c03a9f2:  movca.l r0,@r4              ; allocate line without fetching it
8c03a9f4:  mov.l r3,@(12,r4)           
8c03a9f6:  fcmp/gt fr7,fr2             ; T = z>0
8c03a9f8:  fdiv fr2,fr6                ; 1/z (~12 cycles latency)
8c03a9fa:  bf.s 0x8c03aa24             
8c03a9fc:  add #12,r4                  
8c03a9fe:  fmul fr6,fr0                ; stalls here on the FDIV
8c03aa00:  fmul fr6,fr1                
8c03aa02:  fmul fr4,fr6                ; Z = depth scale / z
8c03aa04:  fmov fr0,fr3                
8c03aa06:  fabs fr3                    
8c03aa08:  fadd fr8,fr0                
8c03aa0a:  fcmp/gt fr3,fr8             ; T = |x/z| < 320
8c03aa0c:  fadd fr9,fr1                
8c03aa0e:  addc r2,r7                  ; on-screen counter += T (branch-free)
8c03aa10:  fmov fr6,@-r4               
8c03aa12:  fmov fr1,@-r4               
8c03aa14:  fmov fr0,@-r4               ; written backwards: X lands at +0
8c03aa16:  dt r6                       
8c03aa18:  bf.s 0x8c03a9e0             
8c03aa1a:  add #16,r4                  
8c03aa1c:  rts                         
8c03aa1e:  mov r7,r0                   
8c03aa20:  bra 0x8c039e84              
8c03aa24:  fmul fr10,fr0               ; behind the eye: multiply by +Inf
8c03aa26:  fmul fr10,fr1               
8c03aa28:  fmov fr10,@-r4              
8c03aa2a:  fmov fr1,@-r4               
8c03aa2c:  bra 0x8c03aa16              
8c03aa2e:  fmov fr0,@-r4               

;; ==== 0x8c03aa3c  N.L for 4 directional lights in ONE FTRV ====
;; in : r5 = 16 B normals {nx,ny,nz,pad}, XMTRX rows = 4 light directions (already rotated into object space)
;; out: colour pool entry = (max(0,N.L0), max(0,N.L1), max(0,N.L2), max(0,N.L3)); 29 instr/vertex, 4 clamp branches
8c03aa3c:  cmp/pl r6                   
8c03aa3e:  fldi0 fr8                   
8c03aa40:  bf.s 0x8c03aa80             
8c03aa42:  fldi1 fr9                   
8c03aa44:  mov #31,r0                  
8c03aa46:  fmov @r5+,fr0               
8c03aa48:  fmov @r5+,fr1               
8c03aa4a:  fmov @r5+,fr2               
8c03aa4c:  fldi0 fr3                   ; w=0: direction
8c03aa4e:  add #4,r5                   
8c03aa50:  ftrv xmtrx,fv0              ; 4 dot products at once
8c03aa52:  tst r0,r4                   
8c03aa54:  bf.s 0x8c03aa5a             
8c03aa56:  add #16,r4                  
8c03aa58:  movca.l r0,@r4              
8c03aa5a:  fcmp/gt fr0,fr8             ; clamp each lane at 0 (fr8=0)
8c03aa5c:  bf 0x8c03aa60               
8c03aa5e:  fldi0 fr0                   
8c03aa60:  fcmp/gt fr1,fr8             
8c03aa62:  bf.s 0x8c03aa68             
8c03aa64:  fcmp/gt fr2,fr8             
8c03aa66:  fldi0 fr1                   
8c03aa68:  bf.s 0x8c03aa6e             
8c03aa6a:  fcmp/gt fr3,fr8             
8c03aa6c:  fldi0 fr2                   
8c03aa6e:  bf.s 0x8c03aa74             
8c03aa70:  dt r6                       
8c03aa72:  fldi0 fr3                   
8c03aa74:  fmov fr3,@-r4               
8c03aa76:  fmov fr2,@-r4               
8c03aa78:  fmov fr1,@-r4               
8c03aa7a:  fmov fr0,@-r4               
8c03aa7c:  bf.s 0x8c03aa46             
8c03aa7e:  add #16,r4                  
8c03aa80:  rts                         
8c03aa82:  mov r5,r0                   

;; ==== 0x8c03aa84  light-colour mix + pack to ARGB ====
;; XMTRX columns = light colours (RGB) of the 4 lights: one FTRV gives sum_i I_i*C_i; ambient (integer) added after ftrc
;; out: word0 of the colour entry = 0x00RRGGBB (saturated at 255); 29 instr/vertex on the common path (32 if all saturate)
8c03aa84:  cmp/pl r5                   
8c03aa86:  bf 0x8c03aa80               
8c03aa88:  mov.l r8,@-r15              
8c03aa8a:  mov.l r9,@-r15              
8c03aa8c:  mov.l r10,@-r15             
8c03aa8e:  mov.l r11,@-r15             
8c03aa90:  mov.l r12,@-r15             
8c03aa92:  mov.l r13,@-r15             
8c03aa94:  mov.l r14,@-r15             
8c03aa96:  frchg                       ; back bank: load colour matrix (3x4, w column zeroed)
8c03aa98:  fmov @r6+,fr0               
8c03aa9a:  fmov @r6+,fr1               
8c03aa9c:  fmov @r6+,fr2               
8c03aa9e:  add #4,r6                   
8c03aaa0:  fmov @r6+,fr4               
8c03aaa2:  fmov @r6+,fr5               
8c03aaa4:  fmov @r6+,fr6               
8c03aaa6:  add #4,r6                   
8c03aaa8:  fmov @r6+,fr8               
8c03aaaa:  fmov @r6+,fr9               
8c03aaac:  fmov @r6+,fr10              
8c03aaae:  add #4,r6                   
8c03aab0:  fmov @r6+,fr12              
8c03aab2:  fmov @r6+,fr13              
8c03aab4:  fmov @r6+,fr14              
8c03aab6:  add #4,r6                   
8c03aab8:  fldi0 fr3                   
8c03aaba:  fldi0 fr7                   
8c03aabc:  fldi0 fr11                  
8c03aabe:  fldi0 fr15                  
8c03aac0:  frchg                       ; swap: it becomes XMTRX
8c03aac2:  mov.l @(4,r6),r12           ; ambient R,G,B as integers
8c03aac4:  mov.l @(8,r6),r13           
8c03aac6:  mov.l @(12,r6),r14          
8c03aac8:  mov.w 0x8c03ab1a,r6 ! ff    
8c03aaca:  fmov @r4+,fr0               
8c03aacc:  fmov @r4+,fr1               
8c03aace:  fmov @r4+,fr2               
8c03aad0:  fmov @r4+,fr3               
8c03aad2:  add #-16,r4                 
8c03aad4:  ftrv xmtrx,fv0              ; (I0..I3) -> (R,G,B,-)
8c03aad6:  ftrc fr0,fpul               ; float -> int on FPUL
8c03aad8:  sts fpul,r0                 
8c03aada:  ftrc fr1,fpul               
8c03aadc:  sts fpul,r1                 
8c03aade:  add r12,r0                  
8c03aae0:  add r13,r1                  
8c03aae2:  cmp/gt r0,r6                ; saturate at 255 (3 compare+branch)
8c03aae4:  ftrc fr2,fpul               
8c03aae6:  bt.s 0x8c03aaec             
8c03aae8:  sts fpul,r2                 
8c03aaea:  mov r6,r0                   
8c03aaec:  cmp/gt r1,r6                
8c03aaee:  add r14,r2                  
8c03aaf0:  bt.s 0x8c03aaf6             
8c03aaf2:  shll16 r0                   
8c03aaf4:  mov r6,r1                   
8c03aaf6:  cmp/gt r2,r6                
8c03aaf8:  shll8 r1                    
8c03aafa:  bt.s 0x8c03ab00             
8c03aafc:  or r0,r1                    
8c03aafe:  mov r6,r2                   
8c03ab00:  or r1,r2                    
8c03ab02:  dt r5                       
8c03ab04:  mov.l r2,@r4                ; packed RGB over the first float
8c03ab06:  bf.s 0x8c03aaca             
8c03ab08:  add #16,r4                  
8c03ab0a:  mov.l @r15+,r14             
8c03ab0c:  mov.l @r15+,r13             
8c03ab0e:  mov.l @r15+,r12             
8c03ab10:  mov.l @r15+,r11             
8c03ab12:  mov.l @r15+,r10             
8c03ab14:  mov.l @r15+,r9              
8c03ab16:  rts                         
8c03ab18:  mov.l @r15+,r8              

;; ==== 0x8c03ab1c  strip emitter (stage, characters' UV16 variant): pool -> TA vertex type 4 (packed colour, UV16), 32 B ====
;; in : strip list: 4 B header, then 8 B per vertex {u16 pos idx, u16 colour idx | bit15 = end of strip, u32 UV16 (u16 v, u16 u: U in the high half)}
;; out: {PCW, X, Y, Z, UV16, -, base ARGB, offset ARGB} into the SQ (r4 = 0xE0000000 | buffer ptr); 30 instr per strip vertex, 0 FPU ops
;; trick: PCW 0xE0000000 is written ONCE into both store-queue halves (+0 and +32) and survives the bursts;
;;        only the last vertex overwrites it with 0xF0000000 (end of strip), and the next strip rewrites both.
8c03ab1c:  mov.l r8,@-r15              
8c03ab1e:  mov.l r9,@-r15              
8c03ab20:  mov.l r10,@-r15             
8c03ab22:  mov.l r11,@-r15             
8c03ab24:  mov.l r12,@-r15             
8c03ab26:  mov.l r13,@-r15             
8c03ab28:  mov.l @r5,r10               
8c03ab2a:  mov.l @(4,r6),r7            
8c03ab2c:  mov.l @(0,r6),r6            
8c03ab2e:  mov.w 0x8c03ab7e,r9 ! 3fff  
8c03ab30:  mov #4,r8                   
8c03ab32:  mov.l 0x8c03ab80,r3 ! ff000000
8c03ab34:  mov.l 0x8c03ab84,r0 ! 8c03aba8
8c03ab36:  fmov @r0+,fr8               
8c03ab38:  fmov @r0+,fr9               
8c03ab3a:  mov #32,r0                  
8c03ab3c:  fmov fr8,@r4                ; PCW into SQ0
8c03ab3e:  fmov fr8,@(r0,r4)           ; PCW into SQ1 (stays there)
8c03ab40:  add #4,r10                  
8c03ab42:  mov.w @r10+,r0              ; position index
8c03ab44:  mov.w @r10+,r1              ; colour index (bit15 = last)
8c03ab46:  mov.l @r10+,r2              ; UV16 straight from the strip stream
8c03ab48:  cmp/pz r1                   ; T = not last
8c03ab4a:  and r9,r0                   
8c03ab4c:  and r9,r1                   
8c03ab4e:  shld r8,r0                  ; *16: pool stride
8c03ab50:  shld r8,r1                  
8c03ab52:  add r6,r0                   
8c03ab54:  add r7,r1                   
8c03ab56:  mov.l @(0,r0),r11           ; X,Y,Z copied as raw words
8c03ab58:  mov.l @(4,r0),r12           
8c03ab5a:  mov.l @(8,r0),r13           
8c03ab5c:  mov.l r11,@(4,r4)           
8c03ab5e:  mov.l r12,@(8,r4)           
8c03ab60:  mov.l r13,@(12,r4)          
8c03ab62:  mov.l @(12,r0),r0           ; attr word
8c03ab64:  mov.l @(0,r1),r11           
8c03ab66:  mov r0,r1                   
8c03ab68:  shll8 r0                    ; byte2 -> base alpha
8c03ab6a:  and r3,r0                   
8c03ab6c:  or r11,r0                   ; base = alpha | RGB
8c03ab6e:  and r3,r1                   ; byte3 -> offset alpha (fog?)
8c03ab70:  mov.l r0,@(24,r4)           
8c03ab72:  mov.l r1,@(28,r4)           
8c03ab74:  bf.s 0x8c03ab88             
8c03ab76:  mov.l r2,@(16,r4)           
8c03ab78:  pref @r4                    ; burst this vertex
8c03ab7a:  bra 0x8c03ab42              
8c03ab7c:  add #32,r4                  
8c03ab7e:  addv r15,r15                
8c03ab82:  fadd fr0,fr15               
8c03ab84:  bra 0x8c03a2d8              
8c03ab88:  mov.b @(3,r10),r0           
8c03ab8a:  fmov fr9,@r4                ; last vertex: PCW = 0xF0000000 (end of strip)
8c03ab8c:  cmp/pl r0                   
8c03ab8e:  pref @r4                    
8c03ab90:  bt.s 0x8c03ab3a             
8c03ab92:  add #32,r4                  
8c03ab94:  add #4,r10                  
8c03ab96:  mov.l r10,@r5               
8c03ab98:  mov.l @r15+,r13             
8c03ab9a:  mov.l @r15+,r12             
8c03ab9c:  mov.l @r15+,r11             
8c03ab9e:  mov.l @r15+,r10             
8c03aba0:  mov.l @r15+,r9              
8c03aba2:  mov.l @r15+,r8              
8c03aba4:  rts                         
8c03aba6:  mov r4,r0                   

;; ==== 0x8c03c81c  matrix concat into XMTRX (view x bone): used once per bone ====
;; back bank <- view (3x4, w row 0001); then the bone matrix's 4 columns are FTRV'd and frchg makes the product XMTRX.
;; 4 FTRV + 30 loads; the product never touches memory.
8c03c81c:  fmov fr12,@-r15             
8c03c81e:  fmov fr13,@-r15             
8c03c820:  fmov fr14,@-r15             
8c03c822:  fmov fr15,@-r15             
8c03c824:  fmov @r4+,fr0               
8c03c826:  fmov @r4+,fr1               
8c03c828:  fmov @r4+,fr2               
8c03c82a:  fmov @r4+,fr3               
8c03c82c:  fmov @r4+,fr4               
8c03c82e:  fmov @r4+,fr5               
8c03c830:  fmov @r4+,fr6               
8c03c832:  fmov @r4+,fr7               
8c03c834:  fmov @r4+,fr8               
8c03c836:  fmov @r4+,fr9               
8c03c838:  fmov @r4+,fr10              
8c03c83a:  fmov @r4+,fr11              
8c03c83c:  fmov @r4+,fr12              
8c03c83e:  fmov @r4+,fr13              
8c03c840:  fmov @r4+,fr14              
8c03c842:  fldi0 fr3                   
8c03c844:  fldi0 fr7                   
8c03c846:  fldi0 fr11                  
8c03c848:  fldi1 fr15                  
8c03c84a:  frchg                       ; view is now XMTRX
8c03c84c:  fmov @r5+,fr0               
8c03c84e:  fmov @r5+,fr1               
8c03c850:  fmov @r5+,fr2               
8c03c852:  add #4,r5                   
8c03c854:  fldi0 fr3                   
8c03c856:  fmov @r5+,fr4               
8c03c858:  fmov @r5+,fr5               
8c03c85a:  ftrv xmtrx,fv0              ; column 0
8c03c85c:  fmov @r5+,fr6               
8c03c85e:  fldi0 fr7                   
8c03c860:  add #4,r5                   
8c03c862:  fmov @r5+,fr8               
8c03c864:  fmov @r5+,fr9               
8c03c866:  ftrv xmtrx,fv4              
8c03c868:  fmov @r5+,fr10              
8c03c86a:  fldi0 fr11                  
8c03c86c:  add #4,r5                   
8c03c86e:  fmov @r5+,fr12              
8c03c870:  fmov @r5+,fr13              
8c03c872:  ftrv xmtrx,fv8              
8c03c874:  fmov @r5+,fr14              
8c03c876:  fldi1 fr15                  
8c03c878:  ftrv xmtrx,fv12             
8c03c87a:  frchg                       ; product -> XMTRX, ready for the vertex loop
8c03c87c:  fmov @r15+,fr15             
8c03c87e:  fmov @r15+,fr14             
8c03c880:  fmov @r15+,fr13             
8c03c882:  rts                         
8c03c884:  fmov @r15+,fr12             

;; ==== 0x8c03c920  SKINNING: per-bone partial vertices, weight pre-multiplied, accumulated in the pool ====
;; header {u16 nFirst, u16 nAdd, ptr}. vertex 16 B {x*w, y*w, z*w, w} with the pool index in the low 12 bits of w (u16 read, <<4, &0xfff0).
;; pass 1 (first influence, sequential dest): 15 instr (14 run); pass 2 (extra influences, indexed, read-modify-write): 20 instr.
;; NB pass 1 tests r0 = entry+12 for a line start, never 32 B aligned for a 16 B-aligned pool, so its movca.l never runs.
;; FTRV of (wx,wy,wz,w) = w*(M*p), so summing over bones = linear blend skinning with one matrix per bone, no per-vertex matrix.
8c03c920:  mov.l r8,@-r15              
8c03c922:  mov.w @r5+,r6               
8c03c924:  mov.w @r5+,r7               
8c03c926:  mov.l @r5,r5                
8c03c928:  mov.l 0x8c03c98c,r1 ! fff0  
8c03c92a:  mov.l 0x8c03c990,r2 ! 4     
8c03c92c:  mov.l 0x8c03c994,r8 ! 1f    
8c03c92e:  cmp/pl r6                   
8c03c930:  bf 0x8c03c958               
8c03c932:  mov.w @(12,r5),r0           ; dest index from the low half of w
8c03c934:  shld r2,r0                  
8c03c936:  and r1,r0                   
8c03c938:  add r4,r0                   
8c03c93a:  fmov @r5+,fr0               
8c03c93c:  fmov @r5+,fr1               
8c03c93e:  fmov @r5+,fr2               
8c03c940:  fmov @r5+,fr3               
8c03c942:  add #12,r0                  
8c03c944:  ftrv xmtrx,fv0              ; (w*p, w) by view*bone
8c03c946:  tst r0,r8                   
8c03c948:  bf 0x8c03c94c               
8c03c94a:  movca.l r0,@r0              ; allocate pool line (never reached, see above)
8c03c94c:  dt r6                       
8c03c94e:  fmov fr2,@-r0               
8c03c950:  fmov fr1,@-r0               
8c03c952:  fmov fr0,@-r0               
8c03c954:  bf.s 0x8c03c93a             
8c03c956:  add #16,r0                  
8c03c958:  cmp/pl r7                   
8c03c95a:  bf 0x8c03c984               
8c03c95c:  fmov @r5+,fr0               
8c03c95e:  fmov @r5+,fr1               
8c03c960:  fmov @r5+,fr2               
8c03c962:  mov.l @r5,r0                ; index (low half of w)
8c03c964:  fmov @r5+,fr3               
8c03c966:  shld r2,r0                  
8c03c968:  and r1,r0                   
8c03c96a:  ftrv xmtrx,fv0              ; partial = w_k * M_k * p
8c03c96c:  add r4,r0                   
8c03c96e:  fmov @r0+,fr4               
8c03c970:  fmov @r0+,fr5               
8c03c972:  fmov @r0+,fr6               
8c03c974:  fadd fr4,fr0                ; accumulate into the vertex
8c03c976:  fadd fr5,fr1                
8c03c978:  fadd fr6,fr2                
8c03c97a:  dt r7                       
8c03c97c:  fmov fr2,@-r0               ; write back
8c03c97e:  fmov fr1,@-r0               
8c03c980:  bf.s 0x8c03c95c             
8c03c982:  fmov fr0,@-r0               
8c03c984:  mov.l @r15+,r8              
8c03c986:  rts                         
8c03c988:  mov r5,r0                   
8c03c98c:  fadd fr15,fr15              
8c03c990:  mov.b r0,@(r0,r0)           
8c03c994:  mac.l @r1+,@r0+             

;; ==== 0x8c03c9ec  skinned N.L for 4 lights (XMTRX = light dirs x bone rotation, built by 0x8c03c7c0) ====
;; same split as positions: w-sign of the low half selects first/accumulate. Low byte of nz carries a per-vertex
;; highlight factor, stored into byte 0 of the colour entry for the packer. 34 instr/vertex first pass, 34 accumulate (fadd skipped per unlit lane).
8c03c9ec:  mov.l 0x8c03ca4c,r1 ! fff0  
8c03c9ee:  mov.l 0x8c03ca50,r2 ! 4     
8c03c9f0:  mov #31,r7                  
8c03c9f2:  cmp/pl r6                   
8c03c9f4:  bf 0x8c03ca98               
8c03c9f6:  mov.l @(12,r5),r3           
8c03c9f8:  shld r2,r3                  
8c03c9fa:  and r1,r3                   
8c03c9fc:  add r4,r3                   
8c03c9fe:  fldi0 fr8                   
8c03ca00:  fldi1 fr9                   
8c03ca02:  fmov @r5+,fr0               
8c03ca04:  fmov @r5+,fr1               
8c03ca06:  fmov @r5+,fr2               
8c03ca08:  mov.w @r5,r0                
8c03ca0a:  fmov @r5+,fr3               
8c03ca0c:  flds fr2,fpul               ; keep raw nz bits (low byte = highlight factor)
8c03ca0e:  cmp/pz r0                   
8c03ca10:  bf 0x8c03ca60               ; negative -> accumulate path
8c03ca12:  ftrv xmtrx,fv0              ; 4 N.L at once
8c03ca14:  tst r3,r7                   
8c03ca16:  bf 0x8c03ca1a               
8c03ca18:  movca.l r0,@r3              ; allocate line
8c03ca1a:  add #16,r3                  
8c03ca1c:  fcmp/gt fr0,fr8             ; clamp at 0
8c03ca1e:  bf.s 0x8c03ca24             
8c03ca20:  fcmp/gt fr1,fr8             
8c03ca22:  fldi0 fr0                   
8c03ca24:  bf.s 0x8c03ca2a             
8c03ca26:  fcmp/gt fr2,fr8             
8c03ca28:  fldi0 fr1                   
8c03ca2a:  bf.s 0x8c03ca30             
8c03ca2c:  fcmp/gt fr3,fr8             
8c03ca2e:  fldi0 fr2                   
8c03ca30:  bf.s 0x8c03ca36             
8c03ca32:  sts fpul,r0                 
8c03ca34:  fldi0 fr3                   
8c03ca36:  fmov fr3,@-r3               
8c03ca38:  fmov fr2,@-r3               
8c03ca3a:  fmov fr1,@-r3               
8c03ca3c:  fmov fr0,@-r3               
8c03ca3e:  dt r6                       
8c03ca40:  mov.b r0,@r3                ; factor byte
8c03ca42:  bf.s 0x8c03ca02             
8c03ca44:  add #16,r3                  
8c03ca46:  rts                         
8c03ca48:  mov r5,r0                   
8c03ca4c:  fadd fr15,fr15              
8c03ca50:  mov.b r0,@(r0,r0)           
8c03ca54:  fmov @r5+,fr0               
8c03ca56:  fmov @r5+,fr1               
8c03ca58:  fmov @r5+,fr2               
8c03ca5a:  mov.w @r5,r0                
8c03ca5c:  fmov @r5+,fr3               
8c03ca5e:  flds fr2,fpul               
8c03ca60:  shld r2,r0                  
8c03ca62:  and r1,r0                   
8c03ca64:  add r4,r0                   
8c03ca66:  ftrv xmtrx,fv0              ; accumulate path: N.L of this bone
8c03ca68:  fmov @r0+,fr4               
8c03ca6a:  fmov @r0+,fr5               
8c03ca6c:  fmov @r0+,fr6               
8c03ca6e:  fmov @r0+,fr7               
8c03ca70:  fcmp/gt fr0,fr8             
8c03ca72:  bt.s 0x8c03ca78             
8c03ca74:  fcmp/gt fr1,fr8             
8c03ca76:  fadd fr0,fr4                ; adds only lanes that are > 0
8c03ca78:  bt.s 0x8c03ca7e             
8c03ca7a:  fcmp/gt fr2,fr8             
8c03ca7c:  fadd fr1,fr5                
8c03ca7e:  bt.s 0x8c03ca84             
8c03ca80:  fcmp/gt fr3,fr8             
8c03ca82:  fadd fr2,fr6                
8c03ca84:  bt.s 0x8c03ca8a             
8c03ca86:  sts fpul,r3                 
8c03ca88:  fadd fr3,fr7                
8c03ca8a:  dt r6                       
8c03ca8c:  fmov fr7,@-r0               
8c03ca8e:  fmov fr6,@-r0               
8c03ca90:  fmov fr5,@-r0               
8c03ca92:  fmov fr4,@-r0               
8c03ca94:  bf.s 0x8c03ca54             
8c03ca96:  mov.b r3,@r0                
8c03ca98:  rts                         

;; ==== 0x8c03ca9c  colour pack with over-bright -> offset-colour highlight (characters) ====
;; base = sat(ambient + sum I_i C_i) | alpha; offset = ((c-255)^2 >> 8) * factor >> 8 per channel, i.e. the part of the
;; light above 255 turns into an additive white-ish highlight. 41 instr/vertex when nothing saturates, ~+11 per channel that does.
8c03ca9c:  mov.l r8,@-r15              
8c03ca9e:  mov.l r9,@-r15              
8c03caa0:  mov.l r10,@-r15             
8c03caa2:  mov.l r11,@-r15             
8c03caa4:  mov.l r12,@-r15             
8c03caa6:  mov.l r13,@-r15             
8c03caa8:  mov.l r14,@-r15             
8c03caaa:  frchg                       
8c03caac:  fmov @r6+,fr0               
8c03caae:  fmov @r6+,fr1               
8c03cab0:  fmov @r6+,fr2               
8c03cab2:  add #4,r6                   
8c03cab4:  fmov @r6+,fr4               
8c03cab6:  fmov @r6+,fr5               
8c03cab8:  fmov @r6+,fr6               
8c03caba:  add #4,r6                   
8c03cabc:  fmov @r6+,fr8               
8c03cabe:  fmov @r6+,fr9               
8c03cac0:  fmov @r6+,fr10              
8c03cac2:  add #4,r6                   
8c03cac4:  fmov @r6+,fr12              
8c03cac6:  fmov @r6+,fr13              
8c03cac8:  fmov @r6+,fr14              
8c03caca:  add #4,r6                   
8c03cacc:  fldi0 fr3                   
8c03cace:  fldi0 fr7                   
8c03cad0:  fldi0 fr11                  
8c03cad2:  fldi0 fr15                  
8c03cad4:  frchg                       
8c03cad6:  mov.l 0x8c03cb94,r3 ! ff000000
8c03cad8:  mov.l @(0,r6),r0            
8c03cada:  mov.l @(4,r6),r12           
8c03cadc:  mov.l @(8,r6),r13           
8c03cade:  mov.l @(12,r6),r14          
8c03cae0:  mov r3,r11                  
8c03cae2:  and r0,r3                   
8c03cae4:  shll8 r0                    
8c03cae6:  and r0,r11                  
8c03cae8:  mov.l 0x8c03cb98,r6 ! ff    
8c03caea:  fmov @r4+,fr0               
8c03caec:  fmov @r4+,fr1               
8c03caee:  fmov @r4+,fr2               
8c03caf0:  fmov @r4+,fr3               
8c03caf2:  add #-16,r4                 
8c03caf4:  mov.l 0x8c03cb9c,r8 ! 0     ; zeroes loaded from the literal pool (3 loads per vertex)
8c03caf6:  ftrv xmtrx,fv0              ; 4 intensities -> RGB
8c03caf8:  mov.b @r4,r7                
8c03cafa:  mov.l 0x8c03cb9c,r9 ! 0     
8c03cafc:  extu.b r7,r7                
8c03cafe:  mov.l 0x8c03cb9c,r10 ! 0    
8c03cb00:  ftrc fr0,fpul               
8c03cb02:  sts fpul,r0                 
8c03cb04:  ftrc fr1,fpul               
8c03cb06:  sts fpul,r1                 
8c03cb08:  ftrc fr2,fpul               
8c03cb0a:  sts fpul,r2                 
8c03cb0c:  add r12,r0                  
8c03cb0e:  cmp/gt r0,r6                ; R <= 255?
8c03cb10:  bt 0x8c03cb2a               
8c03cb12:  mov r0,r8                   
8c03cb14:  sub r6,r8                   
8c03cb16:  mulu.w r8,r8                ; (R-255)^2
8c03cb18:  sts macl,r8                 
8c03cb1a:  shlr8 r8                    
8c03cb1c:  mulu.w r7,r8                ; * highlight factor
8c03cb1e:  sts macl,r8                 
8c03cb20:  shlr8 r8                    
8c03cb22:  cmp/gt r8,r6                
8c03cb24:  bt.s 0x8c03cb2a             
8c03cb26:  mov r6,r0                   
8c03cb28:  mov r6,r8                   
8c03cb2a:  add r13,r1                  
8c03cb2c:  cmp/gt r1,r6                
8c03cb2e:  bt 0x8c03cb48               
8c03cb30:  mov r1,r9                   
8c03cb32:  sub r6,r9                   
8c03cb34:  mulu.w r9,r9                
8c03cb36:  sts macl,r9                 
8c03cb38:  shlr8 r9                    
8c03cb3a:  mulu.w r7,r9                
8c03cb3c:  sts macl,r9                 
8c03cb3e:  shlr8 r9                    
8c03cb40:  cmp/gt r9,r6                
8c03cb42:  bt.s 0x8c03cb48             
8c03cb44:  mov r6,r1                   
8c03cb46:  mov r6,r9                   
8c03cb48:  add r14,r2                  
8c03cb4a:  cmp/gt r2,r6                
8c03cb4c:  bt 0x8c03cb66               
8c03cb4e:  mov r2,r10                  
8c03cb50:  sub r6,r10                  
8c03cb52:  mulu.w r10,r10              
8c03cb54:  sts macl,r10                
8c03cb56:  shlr8 r10                   
8c03cb58:  mulu.w r7,r10               
8c03cb5a:  sts macl,r10                
8c03cb5c:  shlr8 r10                   
8c03cb5e:  cmp/gt r10,r6               
8c03cb60:  bt.s 0x8c03cb66             
8c03cb62:  mov r6,r2                   
8c03cb64:  mov r6,r10                  
8c03cb66:  shll16 r0                   
8c03cb68:  shll8 r1                    
8c03cb6a:  or r0,r2                    
8c03cb6c:  or r1,r2                    
8c03cb6e:  or r3,r2                    
8c03cb70:  mov.l r2,@(0,r4)            ; base ARGB
8c03cb72:  shll16 r8                   
8c03cb74:  shll8 r9                    
8c03cb76:  or r8,r10                   
8c03cb78:  or r9,r10                   
8c03cb7a:  or r11,r10                  
8c03cb7c:  mov.l r10,@(4,r4)           ; offset ARGB
8c03cb7e:  dt r5                       
8c03cb80:  bf.s 0x8c03caea             
8c03cb82:  add #16,r4                  
8c03cb84:  mov.l @r15+,r14             
8c03cb86:  mov.l @r15+,r13             
8c03cb88:  mov.l @r15+,r12             
8c03cb8a:  mov.l @r15+,r11             
8c03cb8c:  mov.l @r15+,r10             
8c03cb8e:  mov.l @r15+,r9              
8c03cb90:  rts                         
8c03cb92:  mov.l @r15+,r8              

;; ==== 0x8c03c998  perspective pass over the skinned pool (after all bones) ====
;; 18 instr/vertex, FDIV result needed 3 instr later (~9 stall cycles); z<=0 -> +Inf sentinel
8c03c998:  mov.l 0x8c03c9bc,r0 ! 8c03c9e0
8c03c99a:  fmov @r0+,fr4               
8c03c99c:  fmov @r0+,fr5               
8c03c99e:  fmov @r0+,fr6               
8c03c9a0:  fldi0 fr7                   
8c03c9a2:  fmov @r4+,fr0               
8c03c9a4:  fmov @r4+,fr1               
8c03c9a6:  fmov @r4+,fr2               
8c03c9a8:  fldi1 fr3                   
8c03c9aa:  fcmp/gt fr7,fr2             
8c03c9ac:  fdiv fr2,fr3                ; 1/z
8c03c9ae:  bt 0x8c03c9c0               
8c03c9b0:  fmul fr6,fr0                
8c03c9b2:  fmul fr6,fr1                
8c03c9b4:  fmov fr6,@-r4               
8c03c9b6:  fmov fr1,@-r4               
8c03c9b8:  bra 0x8c03c9d0              
8c03c9ba:  fmov fr0,@-r4               
8c03c9bc:  and #224,r0                 
8c03c9c0:  fmov fr3,fr8                
8c03c9c2:  fmul fr3,fr0                ; waits for the FDIV
8c03c9c4:  fmul fr8,fr1                
8c03c9c6:  fadd fr4,fr0                
8c03c9c8:  fadd fr5,fr1                
8c03c9ca:  fmov fr3,@-r4               ; Z = 1/z
8c03c9cc:  fmov fr1,@-r4               
8c03c9ce:  fmov fr0,@-r4               
8c03c9d0:  dt r5                       
8c03c9d2:  add #16,r4                  
8c03c9d4:  bf.s 0x8c03c9a4             
8c03c9d6:  fmov @r4+,fr0               

;; ==== 0x8c03cc1a  character strip emitter: float-UV TA vertex (type 3, packed base+offset), 32 B ====
;; 8 B strip vertex: the u32 is two truncated 16-bit floats: u = word (low bits = v, < 1 ulp of noise), v = word<<16.
;; Strips are skipped by a part-visibility bitmask (header byte 2 = bit index). Common path 27 instr per strip vertex.
;; Second path (0x8c03cca8) adds a per-strip UV scroll (table entry header byte 1).
8c03cc1a:  mov.l @r15,r3               
8c03cc1c:  mov.l r8,@-r15              
8c03cc1e:  mov.l r9,@-r15              
8c03cc20:  mov.l r10,@-r15             
8c03cc22:  mov.l r11,@-r15             
8c03cc24:  mov.l r12,@-r15             
8c03cc26:  mov.l r13,@-r15             
8c03cc28:  mov.l r14,@-r15             
8c03cc2a:  mov.l 0x8c03cc60,r0 ! 8c03cd10
8c03cc2c:  fmov @r0+,fr8               
8c03cc2e:  fmov @r0+,fr9               
8c03cc30:  mov r5,r11                  
8c03cc32:  mov.l @r5,r5                
8c03cc34:  add #-8,r7                  
8c03cc36:  mov.l @(4,r6),r10           
8c03cc38:  mov.l @(0,r6),r6            
8c03cc3a:  mov.w 0x8c03cc5c,r9 ! 3fff  
8c03cc3c:  mov #4,r14                  
8c03cc3e:  mov #32,r0                  
8c03cc40:  fmov fr8,@r4                ; PCW persisted in both SQ halves
8c03cc42:  fmov fr8,@(r0,r4)           
8c03cc44:  mov.b @r5+,r2               
8c03cc46:  mov.b @r5+,r8               
8c03cc48:  mov.b @r5+,r1               
8c03cc4a:  mov.b @r5+,r0               
8c03cc4c:  mov #1,r2                   
8c03cc4e:  shld r1,r2                  
8c03cc50:  tst r3,r2                   ; part mask: strip hidden?
8c03cc52:  bf 0x8c03cc64               
8c03cc54:  shll r0                     
8c03cc56:  shll2 r0                    
8c03cc58:  bra 0x8c03ccec              
8c03cc5a:  add r0,r5                   
8c03cc5c:  addv r15,r15                
8c03cc60:  and.b #16,@(r0,gbr)         
8c03cc64:  cmp/pl r8                   
8c03cc66:  bt 0x8c03cc9e               
8c03cc68:  mov.w @r5+,r0               
8c03cc6a:  mov.w @r5+,r1               
8c03cc6c:  mov.l @r5+,r2               
8c03cc6e:  cmp/pz r1                   
8c03cc70:  and r9,r0                   
8c03cc72:  and r9,r1                   
8c03cc74:  shld r14,r0                 
8c03cc76:  shld r14,r1                 
8c03cc78:  add r6,r0                   
8c03cc7a:  add r10,r1                  
8c03cc7c:  mov.l @(0,r0),r12           
8c03cc7e:  mov.l @(4,r0),r13           
8c03cc80:  mov.l @(8,r0),r0            
8c03cc82:  mov.l r12,@(4,r4)           
8c03cc84:  mov.l r13,@(8,r4)           
8c03cc86:  mov.l r0,@(12,r4)           
8c03cc88:  mov.l @(0,r1),r12           
8c03cc8a:  mov.l @(4,r1),r13           
8c03cc8c:  mov.l r2,@(16,r4)           ; u = raw word
8c03cc8e:  mov.l r12,@(24,r4)          
8c03cc90:  mov.l r13,@(28,r4)          
8c03cc92:  shll16 r2                   ; v = low half << 16
8c03cc94:  bf.s 0x8c03ccec             
8c03cc96:  mov.l r2,@(20,r4)           
8c03cc98:  pref @r4                    ; burst
8c03cc9a:  bra 0x8c03cc68              
8c03cc9c:  add #32,r4                  
8c03cc9e:  shll r8                     
8c03cca0:  shll2 r8                    
8c03cca2:  add r7,r8                   
8c03cca4:  fmov @r8+,fr2               
8c03cca6:  fmov @r8+,fr3               
8c03cca8:  mov.w @r5+,r0               
8c03ccaa:  mov.w @r5+,r1               
8c03ccac:  mov.l @r5,r2                
8c03ccae:  fmov @r5+,fr0               
8c03ccb0:  shll16 r2                   
8c03ccb2:  cmp/pz r1                   
8c03ccb4:  lds r2,fpul                 
8c03ccb6:  and r9,r0                   
8c03ccb8:  and r9,r1                   
8c03ccba:  shld r14,r0                 
8c03ccbc:  shld r14,r1                 
8c03ccbe:  add r6,r0                   
8c03ccc0:  add r10,r1                  
8c03ccc2:  mov.l @(0,r0),r12           
8c03ccc4:  mov.l @(4,r0),r13           
8c03ccc6:  mov.l @(8,r0),r0            
8c03ccc8:  mov.l r12,@(4,r4)           
8c03ccca:  mov.l r13,@(8,r4)           
8c03cccc:  mov.l r0,@(12,r4)           
8c03ccce:  mov.l @(0,r1),r12           
8c03ccd0:  mov.l @(4,r1),r13           
8c03ccd2:  mov.l r12,@(24,r4)          
8c03ccd4:  mov.l r13,@(28,r4)          
8c03ccd6:  fsts fpul,fr1               
8c03ccd8:  fadd fr2,fr0                
8c03ccda:  fadd fr3,fr1                
8c03ccdc:  mov #16,r0                  
8c03ccde:  fmov fr0,@(r0,r4)           
8c03cce0:  mov #20,r0                  
8c03cce2:  bf.s 0x8c03ccec             
8c03cce4:  fmov fr1,@(r0,r4)           
8c03cce6:  pref @r4                    
8c03cce8:  bra 0x8c03cca8              
8c03ccea:  add #32,r4                  
8c03ccec:  mov.b @(3,r5),r0            
8c03ccee:  fmov fr9,@r4                
8c03ccf0:  cmp/pl r0                   
8c03ccf2:  pref @r4                    
8c03ccf4:  bt.s 0x8c03cc3e             
8c03ccf6:  add #32,r4                  
8c03ccf8:  add #4,r5                   
8c03ccfa:  mov.l r5,@r11               
8c03ccfc:  mov.l @r15+,r14             
8c03ccfe:  mov.l @r15+,r13             
8c03cd00:  mov.l @r15+,r12             
8c03cd02:  mov.l @r15+,r11             
8c03cd04:  mov.l @r15+,r10             
8c03cd06:  mov.l @r15+,r9              
8c03cd08:  mov.l @r15+,r8              
8c03cd0a:  rts                         
8c03cd0c:  mov r4,r0                   

;; ==== 0x8c03cd18  shadow: character mesh flattened by the shadow matrix -> opaque MODIFIER VOLUME triangles (64 B) ====
;; walks the strips as triangles, 2D back-face test on CPU (fschg pair loads of X,Y), emits {PCW, A.xyz, B.xyz, C.xyz} with
;; PCW 0xF0000000 written once (it always lands in SQ0). ~26 instr per triangle (loads, area test, strip step) + 22 per emitted triangle.
8c03cd18:  mov.l r8,@-r15              
8c03cd1a:  mov.l r9,@-r15              
8c03cd1c:  mov.l r10,@-r15             
8c03cd1e:  mov.l r11,@-r15             
8c03cd20:  mov.l r12,@-r15             
8c03cd22:  mov.l r13,@-r15             
8c03cd24:  mov.l r14,@-r15             
8c03cd26:  mov #4,r8                   
8c03cd28:  mov.l 0x8c03cd4c,r9 ! 3fff  
8c03cd2a:  mov.l 0x8c03cd50,r0 ! f0000000
8c03cd2c:  mov.l r0,@r4                ; PCW for every MV triangle, written once
8c03cd2e:  mov.l @r5,r0                
8c03cd30:  cmp/pl r0                   
8c03cd32:  bf 0x8c03cddc               
8c03cd34:  mov.b @(2,r5),r0            
8c03cd36:  mov #1,r1                   
8c03cd38:  shld r0,r1                  
8c03cd3a:  tst r7,r1                   
8c03cd3c:  bf 0x8c03cd54               
8c03cd3e:  mov.b @(3,r5),r0            
8c03cd40:  add #4,r5                   
8c03cd42:  shll r0                     
8c03cd44:  shll2 r0                    
8c03cd46:  bra 0x8c03cdca              
8c03cd48:  add r0,r5                   
8c03cd4c:  addv r15,r15                
8c03cd52:  fadd fr0,fr0                
8c03cd54:  mov.l @(4,r5),r0            
8c03cd56:  mov.l @(12,r5),r1           
8c03cd58:  add #20,r5                  
8c03cd5a:  and r9,r0                   
8c03cd5c:  and r9,r1                   
8c03cd5e:  shld r8,r0                  
8c03cd60:  shld r8,r1                  
8c03cd62:  add r6,r0                   
8c03cd64:  add r6,r1                   
8c03cd66:  mov #0,r10                  
8c03cd68:  fschg                       ; SZ=1
8c03cd6a:  mov.l @r5,r2                
8c03cd6c:  and r9,r2                   
8c03cd6e:  shld r8,r2                  
8c03cd70:  add r6,r2                   
8c03cd72:  fmov @r0,fr0                ; (X0,Y0) in one 64-bit load
8c03cd74:  fmov @r1,fr2                
8c03cd76:  fmov @r2,fr4                
8c03cd78:  fschg                       
8c03cd7a:  fsub fr0,fr2                
8c03cd7c:  fsub fr1,fr5                
8c03cd7e:  fsub fr0,fr4                
8c03cd80:  fsub fr1,fr3                
8c03cd82:  fmul fr2,fr5                
8c03cd84:  fmul fr3,fr4                
8c03cd86:  fcmp/gt fr5,fr4             ; signed area: one winding only (presumably front-facing)
8c03cd88:  bf 0x8c03cdb6               
8c03cd8a:  mov.l @(0,r0),r11           
8c03cd8c:  mov.l @(4,r0),r12           
8c03cd8e:  mov.l @(8,r0),r13           
8c03cd90:  mov.l r11,@(4,r4)           
8c03cd92:  mov.l r12,@(8,r4)           
8c03cd94:  mov.l r13,@(12,r4)          
8c03cd96:  mov.l @(0,r1),r11           
8c03cd98:  mov.l @(4,r1),r12           
8c03cd9a:  mov.l @(8,r1),r13           
8c03cd9c:  mov.l r11,@(16,r4)          
8c03cd9e:  mov.l r12,@(20,r4)          
8c03cda0:  mov.l r13,@(24,r4)          
8c03cda2:  mov.l @(0,r2),r11           
8c03cda4:  mov.l @(4,r2),r12           
8c03cda6:  mov.l @(8,r2),r13           
8c03cda8:  mov.l r11,@(28,r4)          
8c03cdaa:  pref @r4                    ; first 32 B
8c03cdac:  add #32,r4                  
8c03cdae:  mov.l r12,@(0,r4)           
8c03cdb0:  mov.l r13,@(4,r4)           
8c03cdb2:  pref @r4                    ; second 32 B
8c03cdb4:  add #32,r4                  
8c03cdb6:  tst r10,r10                 
8c03cdb8:  bt.s 0x8c03cdc0             
8c03cdba:  not r10,r10                 
8c03cdbc:  bra 0x8c03cdc2              
8c03cdbe:  mov r2,r1                   
8c03cdc0:  mov r2,r0                   
8c03cdc2:  mov.l @r5,r3                
8c03cdc4:  cmp/pz r3                   
8c03cdc6:  bt.s 0x8c03cd68             
8c03cdc8:  add #8,r5                   
8c03cdca:  mov.l @r5,r3                
8c03cdcc:  shlr16 r3                   
8c03cdce:  shlr8 r3                    
8c03cdd0:  cmp/pl r3                   
8c03cdd2:  bt 0x8c03cd34               
8c03cdd4:  mov.l @(4,r5),r3            
8c03cdd6:  cmp/pl r3                   
8c03cdd8:  bt.s 0x8c03cd2e             
8c03cdda:  add #4,r5                   
8c03cddc:  mov.l @r15+,r14             
8c03cdde:  mov.l @r15+,r13             
8c03cde0:  mov.l @r15+,r12             
8c03cde2:  mov.l @r15+,r11             
8c03cde4:  mov.l @r15+,r10             
8c03cde6:  mov.l @r15+,r9              
8c03cde8:  mov.l @r15+,r8              
8c03cdea:  rts                         
8c03cdec:  mov r4,r0                   

;; ==== 0x8c03cdee  METAL MODEL emitter: screen-space env map ====
;; u = X/640 - n'x, v = Y/480 - n'y (n' = view-space normal * (1/z) * k + c, from 0x8c03fc4e); colour constant:
;; base/offset written once into both SQ halves by the caller 0x8c03fcca (+24/+28/+56/+60) and never rewritten. 33 instr/strip vertex.
8c03cdee:  mov.l r8,@-r15              
8c03cdf0:  mov.l r9,@-r15              
8c03cdf2:  mov.l r10,@-r15             
8c03cdf4:  mov.l r11,@-r15             
8c03cdf6:  mov.l 0x8c03ce68,r0 ! 8c03ce90; fr10 = 1/640, fr11 = 1/480
8c03cdf8:  fmov @r0+,fr8               
8c03cdfa:  fmov @r0+,fr9               
8c03cdfc:  fmov @r0+,fr10              
8c03cdfe:  fmov @r0+,fr11              
8c03ce00:  mov r5,r11                  
8c03ce02:  mov.l @r5,r5                
8c03ce04:  mov.l @(4,r6),r7            
8c03ce06:  mov.l @(0,r6),r6            
8c03ce08:  mov.w 0x8c03ce5c,r9 ! 3fff  
8c03ce0a:  mov #4,r14                  
8c03ce0c:  mov #32,r0                  
8c03ce0e:  fmov fr8,@r4                
8c03ce10:  fmov fr8,@(r0,r4)           
8c03ce12:  mov.b @r5+,r3               
8c03ce14:  mov.b @r5+,r2               
8c03ce16:  mov.b @r5+,r1               
8c03ce18:  mov.b @r5+,r0               
8c03ce1a:  mov.w @r5+,r0               
8c03ce1c:  mov.w @r5+,r1               
8c03ce1e:  mov.l @r5+,r2               
8c03ce20:  cmp/pz r1                   
8c03ce22:  and r9,r0                   
8c03ce24:  and r9,r1                   
8c03ce26:  shld r14,r0                 
8c03ce28:  shld r14,r1                 
8c03ce2a:  add r6,r0                   
8c03ce2c:  add r7,r1                   
8c03ce2e:  fmov @r0+,fr0               
8c03ce30:  fmov @r0+,fr1               
8c03ce32:  fmov @r0+,fr2               
8c03ce34:  fmov @r1+,fr4               
8c03ce36:  fmov @r1+,fr5               
8c03ce38:  mov.w 0x8c03ce5e,r0 ! 4     
8c03ce3a:  fmov fr0,@(r0,r4)           
8c03ce3c:  mov.w 0x8c03ce60,r0 ! 8     
8c03ce3e:  fmov fr1,@(r0,r4)           
8c03ce40:  mov.w 0x8c03ce62,r0 ! c     
8c03ce42:  fmov fr2,@(r0,r4)           
8c03ce44:  fmul fr10,fr0               ; X/640
8c03ce46:  fmul fr11,fr1               
8c03ce48:  fsub fr4,fr0                ; - normal offset
8c03ce4a:  fsub fr5,fr1                
8c03ce4c:  mov.w 0x8c03ce64,r0 ! 10    
8c03ce4e:  fmov fr0,@(r0,r4)           
8c03ce50:  mov.w 0x8c03ce66,r0 ! 14    
8c03ce52:  bf.s 0x8c03ce6c             
8c03ce54:  fmov fr1,@(r0,r4)           
8c03ce56:  pref @r4                    
8c03ce58:  bra 0x8c03ce1a              
8c03ce5a:  add #32,r4                  
8c03ce5c:  addv r15,r15                
8c03ce5e:  mov.b r0,@(r0,r0)           
8c03ce60:  clrt                        
8c03ce62:  mov.b @(r0,r0),r0           
8c03ce66:  mov.b r1,@(r0,r0)           
8c03ce68:  xor.b #144,@(r0,gbr)        
8c03ce6c:  mov.b @(3,r5),r0            
8c03ce6e:  fmov fr9,@r4                
8c03ce70:  cmp/pl r0                   
8c03ce72:  pref @r4                    
8c03ce74:  bt.s 0x8c03ce0c             
8c03ce76:  add #32,r4                  
8c03ce78:  add #4,r5                   
8c03ce7a:  mov.l @r5,r0                
8c03ce7c:  cmp/pl r0                   
8c03ce7e:  bt 0x8c03ce0c               
8c03ce80:  mov.l r5,@r11               
8c03ce82:  mov.l @r15+,r11             
8c03ce84:  mov.l @r15+,r10             
8c03ce86:  mov.l @r15+,r9              
8c03ce88:  mov.l @r15+,r8              
8c03ce8a:  rts                         
8c03ce8c:  mov r4,r0                   

; Soulcalibur (DC USA) 1ST_READ.BIN, base 0x8C010000. Region 0x8c043000-0x8c05f000: character skeleton / motion / collision.
; No per-vertex loops live here; these are per-bone and per-hit-volume loops. Annotated objdump -EL output.

; ==== 0x8c043098-0x8c0431b6: skeleton hierarchy concatenation (local -> world, in place) ====
; Input : r4 = array of 64-byte 4x4 column-major bone matrices (local), r5 = byte list of parent indices
;         (-1 = no parent / skip, -2 = end). Bones are ordered parent-first, so a running pass works.
; Output: same array, world (camera-relative) matrices; consumed by the copy loop at 8c046026
;         (20 bones -> render matrix table) and by hit-volume / IK code.
; Trick : XMTRX caching - the parent matrix is only reloaded (frchg + 16 fmov + frchg) when the parent index
;         differs from the previous bone's parent (r14). Siblings / chains reuse XMTRX.
; Cost  : 41 instr for the product (4 x {4 fmov load, ftrv, 4 fmov store} + adds) + 10 for the parent test and loop,
;         +23 when the parent changes: 51-74 instructions per bone; ~20-32 bones per character.
; Caller: 8c046016 (character pose builder, ~8c045b04-8c046438). Either hand asm or SHC matrix intrinsics (ld_ext/ftrv); the C-like stack use elsewhere suggests intrinsics (uncertain).
8c043098:  mov.l 0x8c043108,r3 ! 8c267f78 ; r4 = bone matrix array (64 B column-major 4x4 each), r5 = parent-index byte list
8c04309a:  mov.l r14,@-r15
8c04309c:  mov #-1,r14                   ; r14 = index of matrix currently in XMTRX (-1 = none)
8c04309e:  mov.l @r3,r7
8c0430a0:  tst r7,r7
8c0430a2:  bf.s 0x8c0430aa
8c0430a4:  mov r4,r1
8c0430a6:  bra 0x8c0431ac                ; (root-copy block 8c0430aa-8c0430f6 elided: if global 8c267f78 != NULL, copies its 3x3 into slot 1 (r1+64) with w = 0,0,0,1; slot role uncertain)
8c0430a8:  nop
8c043120:  cmp/pz r6                     ; loop head: r6 = parent index; <0 (i.e. -1 root) -> skip bone
8c043122:  bf 0x8c0431aa
8c043124:  cmp/eq r14,r6                 ; parent == parent of previous bone? -> XMTRX already holds it
8c043126:  bt.s 0x8c043158
8c043128:  mov r4,r2
8c04312a:  mov r6,r14
8c04312c:  shll2 r6                      ; r6 = parent*64
8c04312e:  shll2 r6
8c043130:  frchg                         ; frchg: load parent world matrix into back bank = XMTRX (16 fmov)
8c043132:  shll2 r6
8c043134:  add r1,r6
8c043136:  fmov @r6+,fr0
8c043138:  fmov @r6+,fr1
8c04313a:  fmov @r6+,fr2
8c04313c:  fmov @r6+,fr3
8c04313e:  fmov @r6+,fr4
8c043140:  fmov @r6+,fr5
8c043142:  fmov @r6+,fr6
8c043144:  fmov @r6+,fr7
8c043146:  fmov @r6+,fr8
8c043148:  fmov @r6+,fr9
8c04314a:  fmov @r6+,fr10
8c04314c:  fmov @r6+,fr11
8c04314e:  fmov @r6+,fr12
8c043150:  fmov @r6+,fr13
8c043152:  fmov @r6+,fr14
8c043154:  fmov @r6+,fr15
8c043156:  frchg                         ; frchg back
8c043158:  fmov @r2+,fr0                 ; 4 columns of local matrix (in place at r4)
8c04315a:  mov r4,r3
8c04315c:  add #16,r3
8c04315e:  fmov @r2+,fr1
8c043160:  fmov @r2+,fr2
8c043162:  fmov @r2+,fr3
8c043164:  ftrv xmtrx,fv0                ; col0 = parent * local.col0
8c043166:  fmov fr3,@-r3                 ; stores backwards (pre-decrement) into the same slot: world = parent*local, in place
8c043168:  fmov fr2,@-r3
8c04316a:  fmov fr1,@-r3
8c04316c:  fmov fr0,@-r3
8c04316e:  fmov @r2+,fr0
8c043170:  add #32,r3
8c043172:  fmov @r2+,fr1
8c043174:  fmov @r2+,fr2
8c043176:  fmov @r2+,fr3
8c043178:  ftrv xmtrx,fv0                ; col1
8c04317a:  fmov fr3,@-r3
8c04317c:  fmov fr2,@-r3
8c04317e:  fmov fr1,@-r3
8c043180:  fmov fr0,@-r3
8c043182:  fmov @r2+,fr0
8c043184:  add #32,r3
8c043186:  fmov @r2+,fr1
8c043188:  fmov @r2+,fr2
8c04318a:  fmov @r2+,fr3
8c04318c:  ftrv xmtrx,fv0                ; col2
8c04318e:  fmov fr3,@-r3
8c043190:  fmov fr2,@-r3
8c043192:  fmov fr1,@-r3
8c043194:  fmov fr0,@-r3
8c043196:  fmov @r2+,fr0
8c043198:  fmov @r2+,fr1
8c04319a:  add #32,r3
8c04319c:  fmov @r2+,fr2
8c04319e:  fmov @r2+,fr3
8c0431a0:  ftrv xmtrx,fv0                ; col3 (translation)
8c0431a2:  fmov fr3,@-r3
8c0431a4:  fmov fr2,@-r3
8c0431a6:  fmov fr1,@-r3
8c0431a8:  fmov fr0,@-r3
8c0431aa:  add #64,r4                    ; next bone slot
8c0431ac:  mov.b @r5+,r6                 ; next parent index; -2 terminates list
8c0431ae:  mov r6,r0
8c0431b0:  cmp/eq #-2,r0
8c0431b2:  bf 0x8c043120
8c0431b4:  rts
8c0431b6:  mov.l @r15+,r14

; ==== 0x8c043004 -> 0x8c042ee0: per-bone pose blend (motion transition), NOT vertex skinning ====
; Called 32x per character from 8c045f68 (2 bones per iteration) with fr4 = blend weight clamped to [0,1],
; r5 = current pose matrix, r6 = other pose (array 8c2689d0), r4 = out.
; translation: t = a + w*(b-a) (3 fmac, 8c043016-8c04304e)
; rotation   : lerp X axis and Y axis rows (fmac), then re-orthonormalise:
;              normalize(X) [8c03c6ae: fipr + fsrra], Z = X x Y [8c03c680], normalize(Z), Y = Z x X;
;              w column = (0,0,0,1). Matrix nlerp + Gram-Schmidt instead of quaternion slerp.
; ~120 instr per bone incl. the 4 helper calls. No FTRV.

; ==== 0x8c04de34 (loop 0x8c04df7c-0x8c04e150): hit-volume transform (25 shape records per character) ====
; Input : r6 = table of 25 x 8-byte {u8 type, u8 bone, u16 count, ptr}; r5 = bone world matrices (64 B)
; Output: world-space sphere centres (type 0, 32 B stride) / capsule endpoints (type 1, 72 B stride, 2 FTRV)
;         written back into the records; min/max Y saved to char+0x278/+0x27c.
;         Type 11 characters (weapon owners?) also derive blade points from the extra matrices
;         at char+0x1800/0x1900/0x1a00 with tip = base + axis*85/1000 (8c04e1e0-8c04e4d4).
; Not rendering: collision/attack volumes (consumers: capsule distance tests 8c04e5f4/8c04e680/8c04cae6).
; Same "reload XMTRX only when bone changes" trick (8c04dfa6). Compiled C: ~50 instr/sphere, ~100/capsule.
8c04dfa0:  mov.l @(12,r15),r3            ; r12 = sphere/capsule count, r13 = shape record {type, bone, count, ...}
8c04dfa2:  mov.b @(1,r13),r0
8c04dfa4:  cmp/eq r0,r3
8c04dfa6:  bt 0x8c04dfd2                 ; same bone as last record? skip XMTRX reload
8c04dfa8:  frchg                         ; frchg: load bone world matrix (r3 = bonebase + bone*64) into XMTRX
8c04dfaa:  mov.b @(1,r13),r0
8c04dfac:  mov.l r0,@(12,r15)
8c04dfae:  mov.l @(4,r13),r3
8c04dfb0:  fmov @r3+,fr0
8c04dfb2:  fmov @r3+,fr1
8c04dfb4:  fmov @r3+,fr2
8c04dfb6:  fmov @r3+,fr3
8c04dfb8:  fmov @r3+,fr4
8c04dfba:  fmov @r3+,fr5
8c04dfbc:  fmov @r3+,fr6
8c04dfbe:  fmov @r3+,fr7
8c04dfc0:  fmov @r3+,fr8
8c04dfc2:  fmov @r3+,fr9
8c04dfc4:  fmov @r3+,fr10
8c04dfc6:  fmov @r3+,fr11
8c04dfc8:  fmov @r3+,fr12
8c04dfca:  fmov @r3+,fr13
8c04dfcc:  fmov @r3+,fr14
8c04dfce:  fmov @r3+,fr15
8c04dfd0:  frchg
8c04dfd2:  mov.b @r13,r0                 ; type 0 = sphere list (32 B records), type 1 = capsule list (72 B records, 8c04e080)
8c04dfd4:  cmp/eq #0,r0
8c04dfd6:  bt 0x8c04dfe0
8c04dfd8:  cmp/eq #1,r0
8c04dfda:  bt 0x8c04e04e
8c04dfdc:  bra 0x8c04e148
8c04dfde:  nop
8c04dfe0:  mov r13,r4
8c04dfe2:  bra 0x8c04e044
8c04dfe4:  add #8,r4
8c04dfe6:  fmov @r4,fr3                  ; per sphere: copy local centre to stack as (x,y,z,1)
8c04dfe8:  mov #36,r0
8c04dfea:  mov r15,r2
8c04dfec:  add #36,r2
8c04dfee:  fmov fr3,@(r0,r15)
8c04dff0:  mov #4,r0
8c04dff2:  fmov @(r0,r4),fr3
8c04dff4:  mov #40,r0
8c04dff6:  mov r15,r3
8c04dff8:  add #36,r3
8c04dffa:  fmov fr3,@(r0,r15)
8c04dffc:  mov #8,r0
8c04dffe:  fmov @(r0,r4),fr3
8c04e000:  mov #44,r0
8c04e002:  add #16,r3
8c04e004:  fmov fr3,@(r0,r15)
8c04e006:  mov #48,r0
8c04e008:  fmov fr5,@(r0,r15)
8c04e00a:  mov #36,r0
8c04e00c:  fmov @r2+,fr0
8c04e00e:  fmov @r2+,fr1
8c04e010:  fmov @r2+,fr2
8c04e012:  fmov @r2+,fr3
8c04e014:  ftrv xmtrx,fv0                ; world centre = bone * local (one FTRV)
8c04e016:  fmov fr3,@-r3
8c04e018:  fmov fr2,@-r3
8c04e01a:  fmov fr1,@-r3
8c04e01c:  fmov fr0,@-r3
8c04e01e:  fmov @(r0,r15),fr3            ; world centre written to record +16..+24
8c04e020:  mov #16,r0
8c04e022:  fmov fr3,@(r0,r4)
8c04e024:  mov #40,r0
8c04e026:  fmov @(r0,r15),fr4
8c04e028:  mov #20,r0
8c04e02a:  fcmp/gt fr7,fr4               ; track max/min world Y over all spheres (fr7 / fr6) -> character height extent
8c04e02c:  fmov fr4,@(r0,r4)
8c04e02e:  mov #44,r0
8c04e030:  fmov @(r0,r15),fr3
8c04e032:  mov #24,r0
8c04e034:  bf.s 0x8c04e03c
8c04e036:  fmov fr3,@(r0,r4)
8c04e038:  bra 0x8c04e042
8c04e03a:  fmov fr4,fr7
8c04e03c:  fcmp/gt fr4,fr6
8c04e03e:  bf 0x8c04e042
8c04e040:  fmov fr4,fr6
8c04e042:  add #32,r4
8c04e044:  cmp/pl r12                    ; loop: ~50 instructions per sphere, all through the stack (compiled C, no pipelining)
8c04e046:  bt.s 0x8c04dfe6
8c04e048:  add #-1,r12
8c04e04a:  bra 0x8c04e148

;; Soulcalibur (DC USA) 1ST_READ.BIN, base 0x8C010000, sh-elf-objdump -EL.
;; Excerpt B: range 0x8c05f000-0x8c077000 (math helpers, 2D prims, stage/effect renderers).
;; All of these write the TA through the store queues: the per-list write pointer table is
;; *(0x8c267304) (== 0x8c266c10+0x6f4, same table the character renderer uses); QACR0/1 = ptr>>24,
;; SQ address = (ptr & 0x03ffffff) | 0xE0000000, written back as (old & 0xfc000000)|(sq & 0x03ffffff).

;; ==== 0x8c060e26  load XMTRX from a 4x4 (r4) and transform one point (r5) ====
;; 33 callers. If the matrix is 8-byte aligned it is loaded with 8 paired fmov under FPSCR.SZ=1
;; (objdump prints the XD targets as fr1,fr3,..: fmov @r4+,xd0 ..), else frchg + 16 single loads.
8c060e26:  mov r4,r0
8c060e28:  and #7,r0                        ; aligned to 8?
8c060e2a:  cmp/eq #0,r0
8c060e2c:  bf 0x8c060e46
8c060e2e:  nop
8c060e30:  fschg                            ; SZ=1: 64-bit moves
8c060e32:  fmov @r4+,fr1                    ; xd0 <- m[0..1] (straight into back bank = XMTRX)
8c060e34:  fmov @r4+,fr3
8c060e36:  fmov @r4+,fr5
8c060e38:  fmov @r4+,fr7
8c060e3a:  fmov @r4+,fr9
8c060e3c:  fmov @r4+,fr11
8c060e3e:  fmov @r4+,fr13
8c060e40:  fmov @r4,fr15
8c060e42:  bra 0x8c060e6a
8c060e44:  fschg                            ; SZ=0 (delay slot)
8c060e46:  frchg                            ; unaligned path: swap banks, 16 x 32-bit loads
8c060e48:  fmov @r4+,fr0
8c060e4a:  fmov @r4+,fr1
8c060e4c:  fmov @r4+,fr2
8c060e4e:  fmov @r4+,fr3
8c060e50:  fmov @r4+,fr4
8c060e52:  fmov @r4+,fr5
8c060e54:  fmov @r4+,fr6
8c060e56:  fmov @r4+,fr7
8c060e58:  fmov @r4+,fr8
8c060e5a:  fmov @r4+,fr9
8c060e5c:  fmov @r4+,fr10
8c060e5e:  fmov @r4+,fr11
8c060e60:  fmov @r4+,fr12
8c060e62:  fmov @r4+,fr13
8c060e64:  fmov @r4+,fr14
8c060e66:  fmov @r4,fr15
8c060e68:  frchg
8c060e6a:  fmov @r5+,fr0
8c060e6c:  fmov @r5+,fr1
8c060e6e:  fmov @r5,fr2
8c060e70:  fldi1 fr3
8c060e72:  ftrv xmtrx,fv0                   ; one point
8c060e74:  fschg                            ; SZ=1: fmov dr2,xd14 / dr0,xd12 -> M*p written into XMTRX column 3 = new translation (M*translate(p) in 2 moves)
8c060e76:  fmov fr2,fr15
8c060e78:  fmov fr0,fr13
8c060e7a:  rts
8c060e7c:  fschg

;; ==== 0x8c0610a0  shared batch transform + perspective project into a RAM pool ====
;; Callers (9): 0x8c06bdce rain/splash, 0x8c06f882 mesh effect (type 5), 0x8c071e7e / 0x8c072978 effect-mesh shadow volume,
;;   0x8c078d12, 0x8c088f44/66, 0x8c08b100, 0x8c0933b6.  XMTRX = model*view*projection set by caller.
;; In : r4 = src, 16 B/vertex {x,y,z,pad} float (4th word skipped);  r6 = count; fr4 = depth scale.
;; Out: r5 = pool, 16 B/vertex {X = x/w+320, Y = y/w+240, Q = fr4/w, (4th word untouched)}.
;;   Pool is a cached RAM buffer (no movca.l here); strip emitters copy it to the SQ later.
;; Per vertex: 25 instr on the common path (+2 every 2nd vertex for pref), 3 branches
;;   (pref every 32 B, behind-camera test, loop). One FDIV, result used 2 instr later -> ~10 cycle
;;   stall; FTRV result read by fcmp 6 instr later (~1-2 stall). No software pipelining, no fsrra.
;;   Estimate ~25-30 cycles/vertex.  Behind camera (w<=0): X,Y,Q multiplied by +Inf (sentinel, 0x7f800000);
;;   no clipping here, caller must not draw such polygons or rely on TA rejection.
8c0610a0:  pref @r4                         ; prefetch first 32 B (2 src vertices)
8c0610a2:  mova 0x8c0610f0,r0               ; r0 -> {320.0, 240.0, +Inf}
8c0610a4:  mov #2,r7                        ; pref every 2nd vertex
8c0610a6:  fmov @r0+,fr8
8c0610a8:  fmov @r0+,fr9
8c0610aa:  fmov @r4+,fr0                    ; x
8c0610ac:  fmov @r4+,fr1
8c0610ae:  fmov @r4+,fr2
8c0610b0:  fldi1 fr3                        ; w-in = 1
8c0610b2:  dt r7
8c0610b4:  ftrv xmtrx,fv0                   ; fv0 = M*(x,y,z,1); fr2 holds w (rows arranged so lane 2 = w)
8c0610b6:  add #12,r5                       ; r5 += 12 (written backwards)
8c0610b8:  fldi0 fr5
8c0610ba:  bf.s 0x8c0610c2
8c0610bc:  add #4,r4                        ; skip pad word
8c0610be:  pref @r4                         ; next 32 B line
8c0610c0:  mov #2,r7
8c0610c2:  fldi1 fr3
8c0610c4:  fcmp/gt fr5,fr2                  ; w > 0 ?
8c0610c6:  bt 0x8c0610d2
8c0610c8:  fmov @r0,fr3                     ; behind: fr3 = +Inf
8c0610ca:  fmul fr3,fr1
8c0610cc:  dt r6
8c0610ce:  bra 0x8c0610e0
8c0610d0:  fmul fr3,fr0
8c0610d2:  fdiv fr2,fr3                     ; 1/w (FDIV, ~12 cycle latency)
8c0610d4:  dt r6
8c0610d6:  fmul fr3,fr0                     ; stalls on fdiv
8c0610d8:  fmul fr3,fr1
8c0610da:  fmul fr4,fr3                     ; Q = depthscale/w
8c0610dc:  fadd fr8,fr0                     ; +320 screen centre
8c0610de:  fadd fr9,fr1                     ; +240
8c0610e0:  fmov fr3,@-r5                    ; store Q,Y,X backwards
8c0610e2:  fmov fr1,@-r5
8c0610e4:  fmov fr0,@-r5
8c0610e6:  bf.s 0x8c0610aa                  ; loop
8c0610e8:  add #16,r5                       ; next pool slot (16 B)
8c0610ea:  rts
8c0610ec:  nop
8c0610ee:  nop
8c0610f0:  .word 0x0000                     ; 320.0f
8c0610f2:  .word 0x43a0
8c0610f4:  .word 0x0000                     ; 240.0f
8c0610f6:  .word 0x4370
8c0610f8:  .word 0x0000                     ; +Inf
8c0610fa:  add #-128,r15

;; ==== 0x8c06f9ac..0x8c06faa8  effect type 5 (mesh effect, 0x8c06f6ee) strip loop, mode 0 ====
;; 0x8c06f6ee: per-object cone/sphere test (0x8c06113c: view-space centre, fipr+fsrra normalise,
;;   fipr with (0,0,1,0) = cos(angle to view axis) vs per-object threshold), Euler matrix
;;   (0x8c03dfa0 / 0x8c03e2a0), scale, concat with camera (0x8c03c73e), XMTRX load, then
;;   0x8c0610a0 projects the object's vertices into the pool (aligned to 32 B).
;; Strip stream: u8 count, then u8 indices (<=256 vertices per mesh).  UV: 8 B float {u,v} per
;;   index plus a per-object scroll (fr15,fr14) -> scrolling texture.  Colour: one constant or
;;   per-vertex u32 (8 B stride table).
;; Out: 32 B TA vertex {PCW, X, Y, Q, U, V, base ARGB, offset} float UV, packed colour.
;;   PCW 0xE0000000 is written into BOTH store queues once per strip and the offset word (+28) once
;;   per object, and are never rewritten: the SQ keeps its contents after pref, so each vertex only
;;   writes X,Y,Q,U,V,base.  The last vertex gets 0xF0000000, then the next strip restores 0xE0.
;; Per vertex: 46 instr (41 with constant colour), 2-3 branches; compiled C: the SQ pointer lives
;;   on the stack (@r15) and is reloaded/stored every vertex.  Estimate ~30 cycles/vertex.
;; Modes 1 and 2 (0x8c06fae0, 0x8c06fbbc) are variants of the same loop.
8c06f9ac:  mov.l @r15,r3
8c06f9ae:  mov.l r9,@r3                     ; PCW 0xE0000000 into SQ0 slot
8c06f9b0:  mov.l @(12,r15),r0
8c06f9b2:  cmp/eq #0,r0
8c06f9b4:  bt 0x8c06f9ca
8c06f9b6:  cmp/eq #1,r0
8c06f9b8:  bf 0x8c06f9be
8c06f9ba:  bra 0x8c06fae0
8c06f9bc:  nop
8c06f9be:  cmp/eq #2,r0
8c06f9c0:  bf 0x8c06f9c6
8c06f9c2:  bra 0x8c06fbbc
8c06f9c4:  nop
8c06f9c6:  bra 0x8c06ffb8
8c06f9c8:  nop
8c06f9ca:  mov.l @r15,r3
8c06f9cc:  tst r13,r13
8c06f9ce:  mov.l r6,@(28,r5)                ; offset colour = 0 (SQ1 +28)
8c06f9d0:  mov.l r6,@(28,r3)                ; offset colour = 0 (SQ0 +28)
8c06f9d2:  bf 0x8c06f9d8
8c06f9d4:  bra 0x8c06ffb8
8c06f9d6:  nop
8c06f9d8:  mov.l @r15,r2
8c06f9da:  cmp/gt r12,r13
8c06f9dc:  add #32,r2
8c06f9de:  bf.s 0x8c06fa44
8c06f9e0:  mov.l r9,@r2                     ; PCW into SQ1 slot (+32)
8c06f9e2:  mov.b @r14+,r6                   ; u8 vertex index
8c06f9e4:  mov.l @(8,r15),r3
8c06f9e6:  extu.b r6,r6
8c06f9e8:  mov r6,r5
8c06f9ea:  mov r6,r7
8c06f9ec:  shll2 r5                         ; idx*16 -> pool entry
8c06f9ee:  shll2 r7
8c06f9f0:  shll2 r5
8c06f9f2:  add r11,r5
8c06f9f4:  shll r7                          ; idx*8 -> UV entry
8c06f9f6:  tst r3,r3                        ; constant colour?
8c06f9f8:  bf.s 0x8c06fa0c
8c06f9fa:  add r10,r7
8c06f9fc:  shll2 r6
8c06f9fe:  mov.l @r15,r3
8c06fa00:  shll r6
8c06fa02:  add r4,r6
8c06fa04:  mov.l @r6,r2                     ; per-vertex colour
8c06fa06:  mov.l r2,@(24,r3)                ; -> +24 base colour
8c06fa08:  bra 0x8c06fa12
8c06fa0a:  nop
8c06fa0c:  mov.l @(8,r15),r3
8c06fa0e:  mov.l @r15,r1
8c06fa10:  mov.l r3,@(24,r1)
8c06fa12:  fmov fr15,fr2
8c06fa14:  mov #16,r0
8c06fa16:  mov.l @r15,r6                    ; SQ ptr reloaded from stack
8c06fa18:  mov.l @r5,r3                     ; X/Y/Q copied as raw words (integer pipe)
8c06fa1a:  mov.l r3,@(4,r6)
8c06fa1c:  mov.l @(4,r5),r2
8c06fa1e:  mov.l r2,@(8,r6)
8c06fa20:  mov.l @(8,r5),r3
8c06fa22:  mov.l r3,@(12,r6)
8c06fa24:  fmov @r7,fr3                     ; u
8c06fa26:  fadd fr3,fr2                     ; + scroll u
8c06fa28:  fmov fr2,@(r0,r6)
8c06fa2a:  mov #4,r0
8c06fa2c:  fmov @(r0,r7),fr3
8c06fa2e:  mov #20,r0
8c06fa30:  fmov fr14,fr2                    ; v + scroll v
8c06fa32:  fadd fr3,fr2
8c06fa34:  fmov fr2,@(r0,r6)
8c06fa36:  pref @r6                         ; burst this 32 B queue
8c06fa38:  mov.l @r15,r3
8c06fa3a:  add #-1,r13
8c06fa3c:  cmp/gt r12,r13
8c06fa3e:  add #32,r3
8c06fa40:  bt.s 0x8c06f9e2                  ; loop over count-1 vertices
8c06fa42:  mov.l r3,@r15                    ; SQ ptr += 32, back to stack
8c06fa44:  mov.l @r15,r3
8c06fa46:  mov.l r8,@r3                     ; last vertex: PCW = 0xF0000000 (end of strip)
8c06fa48:  mov.b @r14+,r6
8c06fa4a:  mov.l @(8,r15),r3
8c06fa4c:  extu.b r6,r6
8c06fa4e:  mov r6,r7
8c06fa50:  mov r6,r5
8c06fa52:  shll2 r7
8c06fa54:  shll2 r5
8c06fa56:  shll r7
8c06fa58:  shll2 r5
8c06fa5a:  mov r7,r6
8c06fa5c:  tst r3,r3
8c06fa5e:  add r11,r5
8c06fa60:  bf.s 0x8c06fa70
8c06fa62:  add r10,r6
8c06fa64:  add r4,r7
8c06fa66:  mov.l @r15,r3
8c06fa68:  mov.l @r7,r2
8c06fa6a:  mov.l r2,@(24,r3)
8c06fa6c:  bra 0x8c06fa76
8c06fa6e:  nop
8c06fa70:  mov.l @(8,r15),r3
8c06fa72:  mov.l @r15,r1
8c06fa74:  mov.l r3,@(24,r1)
8c06fa76:  fmov fr15,fr2
8c06fa78:  mov #16,r0
8c06fa7a:  mov.l @r15,r7
8c06fa7c:  mov.l @r5,r3
8c06fa7e:  mov.l r3,@(4,r7)
8c06fa80:  mov.l @(4,r5),r2
8c06fa82:  mov.l r2,@(8,r7)
8c06fa84:  mov.l @(8,r5),r3
8c06fa86:  mov.l r3,@(12,r7)
8c06fa88:  fmov @r6,fr3
8c06fa8a:  fadd fr3,fr2
8c06fa8c:  fmov fr2,@(r0,r7)
8c06fa8e:  mov #4,r0
8c06fa90:  fmov @(r0,r6),fr3
8c06fa92:  mov #20,r0
8c06fa94:  fmov fr14,fr2
8c06fa96:  fadd fr3,fr2
8c06fa98:  fmov fr2,@(r0,r7)
8c06fa9a:  pref @r7
8c06fa9c:  mov.l @r15,r3
8c06fa9e:  add #32,r3
8c06faa0:  mov.l r3,@r15
8c06faa2:  mov.b @r14+,r13                  ; next strip count (0 ends)
8c06faa4:  extu.b r13,r13
8c06faa6:  tst r13,r13
8c06faa8:  bf 0x8c06f9d8
8c06faaa:  bra 0x8c06ffb8

;; ==== 0x8c070e30..0x8c070ed8  effect type 4: small polygon (<=8 vertices, count-1 masked with 7) strip emitter ====
;; Preceded by 0x8c070c2c (ftrv + fdiv per vertex into a stack pool, 16 B {X,Y,Q,-}) and a
;;   screen-space cross-product test on the first three vertices (0x8c070cba..: |area| > limit -> drop).
;; Out: 32 B TA vertex {PCW, X, Y, Q, UV16, -, base, offset}.  PCW (E0) and both colour words are
;;   written to SQ0 and SQ1 once (0x8c070da4/a6, 0x8c070e32..3a) and persist; per vertex only
;;   X,Y,Q and the packed 16-bit UV word are stored.
;; Per vertex: 14 instr, 1 branch; ~8-10 cycles (loads from a cached stack pool).
8c070d96:  mov.l 0x8c070df0,r1 ! 8c15ef84
8c070d98:  mova 0x8c070df4,r0
8c070d9a:  mov.l 0x8c070ddc,r2 ! 8c15ef80
8c070d9c:  mov.l 0x8c070dec,r3 ! e0000000
8c070d9e:  mov.l @r2,r14
8c070da0:  mov r14,r11
8c070da2:  add #32,r11
8c070da4:  mov.l r3,@r11                    ; PCW 0xE0000000 -> SQ1
8c070da6:  mov.l r3,@r14                    ; PCW 0xE0000000 -> SQ0
8c070da8:  fmov @r0,fr3
8c070daa:  fmov @r1,fr15
8c070dac:  fcmp/gt fr3,fr15
8c070dae:  bf 0x8c070e00
8c070db0:  mov.l @(24,r10),r12
8c070db2:  bra 0x8c070e30
8c070db4:  mov.l @(28,r10),r4
8c070e00:  mov.b @(15,r10),r0
8c070e02:  tst r0,r0
8c070e04:  bf 0x8c070e1c
8c070e06:  mov.l 0x8c070e80,r3 ! 8c06f39a
8c070e08:  fmov fr15,fr4
8c070e0a:  jsr @r3
8c070e0c:  mov.l @(24,r10),r4
8c070e0e:  mov.l 0x8c070e80,r2 ! 8c06f39a
8c070e10:  mov r0,r12
8c070e12:  fmov fr15,fr4
8c070e14:  jsr @r2
8c070e16:  mov.l @(28,r10),r4
8c070e18:  bra 0x8c070e2e
8c070e1a:  nop
8c070e1c:  mov.l 0x8c070e84,r3 ! 8c06f3d6
8c070e1e:  fmov fr15,fr4
8c070e20:  jsr @r3
8c070e22:  mov.l @(24,r10),r4
8c070e24:  mov.l 0x8c070e84,r2 ! 8c06f3d6
8c070e26:  mov r0,r12
8c070e28:  fmov fr15,fr4
8c070e2a:  jsr @r2
8c070e2c:  mov.l @(28,r10),r4
8c070e2e:  mov r0,r4
8c070e30:  mov #17,r0
8c070e32:  mov.l r12,@(24,r11)              ; base colour -> SQ1 +24
8c070e34:  mov.l r12,@(24,r14)              ; base colour -> SQ0 +24
8c070e36:  mov.l 0x8c070e88,r12 ! 8c15efac
8c070e38:  mov.l r4,@(28,r11)               ; offset colour -> SQ1 +28
8c070e3a:  mov.l r4,@(28,r14)               ; offset colour -> SQ0 +28
8c070e3c:  mov.b @(r0,r10),r3
8c070e3e:  tst r3,r3
8c070e40:  bf.s 0x8c070e48
8c070e42:  mov r9,r4
8c070e44:  bra 0x8c070e56
8c070e46:  mov r12,r5
8c070e48:  mov #116,r0
8c070e4a:  mov.l @(r0,r10),r5
8c070e4c:  mov #112,r0
8c070e4e:  mov.l @(r0,r10),r3
8c070e50:  shll2 r5
8c070e52:  shll2 r5
8c070e54:  add r3,r5
8c070e56:  mov #16,r0
8c070e58:  mov.b @(r0,r10),r0
8c070e5a:  mov #7,r6
8c070e5c:  extu.b r0,r0
8c070e5e:  add #-1,r0
8c070e60:  bra 0x8c070eb8
8c070e62:  and r0,r6
8c070ea0:  mov.l @r4,r2                     ; X (raw word)
8c070ea2:  mov.l r2,@(4,r14)
8c070ea4:  mov.l @(4,r4),r3                 ; Y
8c070ea6:  mov.l r3,@(8,r14)
8c070ea8:  mov.l @(8,r4),r2                 ; Q
8c070eaa:  mov.l r2,@(12,r14)
8c070eac:  mov.l @r5+,r3                    ; packed UV16 (u16:v16)
8c070eae:  mov.l r3,@(16,r14)
8c070eb0:  pref @r14                        ; burst
8c070eb2:  add #-1,r6
8c070eb4:  add #32,r14
8c070eb6:  add #16,r4
8c070eb8:  cmp/pl r6                        ; count-1 vertices
8c070eba:  bt 0x8c070ea0
8c070ebc:  mov.l 0x8c070fa4,r3 ! f0000000   ; last vertex: end-of-strip PCW
8c070ebe:  mov.l r3,@r14
8c070ec0:  mov.l @r4,r2
8c070ec2:  mov.l r2,@(4,r14)
8c070ec4:  mov.l @(4,r4),r3
8c070ec6:  mov.l r3,@(8,r14)
8c070ec8:  mov.l @(8,r4),r2
8c070eca:  mov.l r2,@(12,r14)
8c070ecc:  mov.l @r5,r3
8c070ece:  mov.l r3,@(16,r14)
8c070ed0:  pref @r14
8c070ed2:  mov #19,r0
8c070ed4:  mov.l 0x8c070fa8,r2 ! 8c15ef80
8c070ed6:  add #32,r14
8c070ed8:  mov.l r14,@r2
8c070eda:  mov.b @(r0,r10),r3

;; ==== 0x8c06be96..0x8c06bf68  rain streak / splash (task "Rain", 0x8c06b9a0) ====
;; Two points (drop head and tail) are projected by 0x8c0610a0; a screen-space perpendicular is
;;   built with fipr + fsrra (0x8c06be44) and scaled by depth, giving 5 screen points
;;   (centre line + two offset edges).  The strip is a fixed 8-vertex index list (u8 table
;;   0x8c15ed80) with a per-vertex PCW table (0x8c15ed9c, E0/F0) and a per-vertex colour table
;;   (0x8c15ed88, alpha bytes patched with the drop's fade) -> soft-edged streak.
;; Unrolled x4: 91 instr per 4 vertices (~23 per vertex), no FP.
8c06be96:  fmov @(r0,r12),fr3
8c06be98:  mov #4,r0
8c06be9a:  mov.l 0x8c06bfb4,r5 ! 8c15ed88
8c06be9c:  mov #8,r7
8c06be9e:  fmov fr3,@(r0,r13)
8c06bea0:  mov #19,r0
8c06bea2:  mov.l 0x8c06bfb0,r3 ! 8c15ef80
8c06bea4:  mov.l 0x8c06bfac,r14 ! 8c15ed80
8c06bea6:  mov.l @r3,r4
8c06bea8:  mov.b r6,@(r0,r5)                ; patch alpha of the colour table
8c06beaa:  mov r6,r0
8c06beac:  mov.l 0x8c06bfb8,r6 ! 8c15ed9c
8c06beae:  mov.b r0,@(15,r5)
8c06beb0:  mov.b r0,@(11,r5)
8c06beb2:  mov.b @r14+,r11                  ; u8 index into the 5-point screen pool
8c06beb4:  extu.b r11,r11
8c06beb6:  mov r11,r13
8c06beb8:  shll2 r11
8c06beba:  mov r11,r0
8c06bebc:  mov.l @(r0,r6),r3                ; PCW from table (E0 or F0)
8c06bebe:  shll2 r13
8c06bec0:  mov r11,r10
8c06bec2:  shll2 r13
8c06bec4:  mov.l r3,@r4
8c06bec6:  add r5,r10
8c06bec8:  add r12,r13
8c06beca:  mov.l @r10,r2                    ; base colour from table
8c06becc:  mov.l r2,@(24,r4)
8c06bece:  mov.l @r13,r3                    ; X
8c06bed0:  mov.l r3,@(4,r4)
8c06bed2:  mov.l @(4,r13),r2                ; Y
8c06bed4:  mov.l r2,@(8,r4)
8c06bed6:  mov.l @(8,r13),r3                ; Q
8c06bed8:  mov.l r3,@(12,r4)
8c06beda:  pref @r4                         ; burst
8c06bf60:  add #-4,r7
8c06bf62:  tst r7,r7
8c06bf64:  bf.s 0x8c06beb2
8c06bf66:  add #32,r4
8c06bf68:  mov.l 0x8c06bfb0,r3 ! 8c15ef80
8c06bf6a:  mov.l r4,@r3


; Soulcalibur (DC USA) 1ST_READ.BIN, base 0x8C010000. Effects-side vertex loops (range 0x8c077000-0x8c103000).
; sh-elf-objdump -EL listings, nop padding removed, annotated. All costs are static estimates.

; ==== 0x8c0c0942: transform + perspective of a point array (used by trails, ring effect, bone sprites) ====
; in : r4 = src float4 {x,y,z,1} (16 B stride), r5 = dst, r6 = count, XMTRX = view*proj (screen scale folded in)
; out: dst {X = cx + x/z, Y = cy + y/z, z, 1/z} 16 B; r0 = 1 if any point had z <= 0
; behind-camera point: 1/w := sentinel float at *0x8c1382bc (later tests use fcmp/eq against it)
; cost: 40 instr/point static, 37 on the common (z > 0) path; FDIV result consumed 3 instr later -> ~10-cycle stall; est. ~35 cycles/point
;       (0x8c0c08f2 = single-point twin, 0x8c0c09ae = same walking src backwards)
8c0c0942:  mova 0x8c0c0a44,r0               ; fr7 = cx
8c0c0944:  mov.l r13,@-r15                  
8c0c0946:  fmov @r0,fr7                     
8c0c0948:  mova 0x8c0c0a48,r0               
8c0c094a:  fmov @r0,fr6                     ; fr6 = cy
8c0c094c:  cmp/pl r6                        
8c0c094e:  mov.l 0x8c0c0a40,r13 ! 8c1382bc  ; sentinel 1/w for w<=0
8c0c0950:  mov #1,r1                        
8c0c0952:  mov #0,r7                        
8c0c0954:  bf.s 0x8c0c09a8                  
8c0c0956:  fldi1 fr5                        
8c0c0958:  mov r4,r2                        
8c0c095a:  fmov @r2+,fr0                    
8c0c095c:  mov r5,r3                        
8c0c095e:  mov #8,r0                        
8c0c0960:  fmov @r2+,fr1                    
8c0c0962:  add #16,r3                       
8c0c0964:  fmov @r2+,fr2                    
8c0c0966:  fmov @r2+,fr3                    
8c0c0968:  ftrv xmtrx,fv0                   ; clip-space (x,y,z,w)
8c0c096a:  fmov fr3,@-r3                    
8c0c096c:  fldi0 fr3                        
8c0c096e:  fmov fr2,@-r3                    
8c0c0970:  fmov fr1,@-r3                    
8c0c0972:  fmov fr0,@-r3                    ; store all four lanes to dst first
8c0c0974:  fmov @(r0,r5),fr4                ; reload lane 2 (view z) from dst+8: divides by z, lane 3 unused
8c0c0976:  fcmp/gt fr3,fr4                  ; z > 0 ?
8c0c0978:  bt.s 0x8c0c0982                  
8c0c097a:  fmov fr7,fr3                     
8c0c097c:  fmov @r13,fr4                    ; no: 1/w = sentinel, flag = 1
8c0c097e:  bra 0x8c0c0988                   
8c0c0980:  mov r1,r7                        
8c0c0982:  fmov fr4,fr2                     
8c0c0984:  fmov fr5,fr4                     
8c0c0986:  fdiv fr2,fr4                     ; yes: 1/w = 1/w  (FDIV ~12 cy)
8c0c0988:  fmov @r5,fr2                     
8c0c098a:  mov #4,r0                        
8c0c098c:  fmov fr4,fr0                     ; <- stalls on FDIV
8c0c098e:  add #-1,r6                       
8c0c0990:  fmac fr0,fr2,fr3                 ; X = cx + x*(1/w)
8c0c0992:  cmp/pl r6                        
8c0c0994:  add #16,r4                       
8c0c0996:  fmov fr3,@r5                     
8c0c0998:  fmov @(r0,r5),fr2                
8c0c099a:  fmov fr6,fr3                     
8c0c099c:  fmac fr0,fr2,fr3                 ; Y = cy + y*(1/w)
8c0c099e:  fmov fr3,@(r0,r5)                
8c0c09a0:  mov #12,r0                       
8c0c09a2:  fmov fr0,@(r0,r5)                ; store 1/w as the TA "Z"
8c0c09a4:  bt.s 0x8c0c0958                  ; 1 branch/point
8c0c09a6:  add #16,r5                       
8c0c09a8:  mov r7,r0                        
8c0c09aa:  rts                              
8c0c09ac:  mov.l @r15+,r13                  

; ==== 0x8c0ae560: WEAPON TRAIL, textured ribbon (mode 1 of driver 0x8c0adf80) ====
; driver: 16-entry ring of {tip, base} world points per weapon (+0x24 / +0x124, idx @+32 &15), filled by
;   the bone-matrix sampler 0x8c0c1d40; 0x8c0ae180 projects each rail with 0x8c0c0942 then 0x8c0ae216
;   subdivides in SCREEN space by repeated midpoints (FDIV by 2.0, not fmul 0.5) -> arrays 0x8c2909a8/0x8c290ea8.
; in : r9 = rail A, r8 = rail B, 16 B {X,Y,1/w,-} screen points; header PCW 0x8080000a (packed colour, textured,
;      gouraud, float UV), ISP 0x8e800000, TSP from effect @+0x338, TCW from texture table.
; out: one strip of 32 B TA vertices {PCW, X, Y, 1/w, U, V, ARGB, 0}, SQ -> list ptr (QACR from ptr>>24)
;      U = fr13 (rail A) / fr12 (rail B), V = fr15 stepping by -1/n, ARGB = colour ramp 0x8c30e158[int(fr4)]
; also: signed screen area of the first triangle (0x8c0ae4e0) /2 is added to global 0x8c24a938 (effect area counter)
; cost: 51 instr per 2 strip vertices (~25.5/vertex), 1 branch per pair, no FDIV in the loop
8c0ae774:  fmov @r8,fr3                     ; rail B vertex: X
8c0ae776:  mov #4,r0                        
8c0ae778:  ftrc fr4,fpul                    ; colour index = int(fr4)
8c0ae77a:  fmov fr3,@(r0,r12)               
8c0ae77c:  fmov @(r0,r8),fr3                
8c0ae77e:  mov #8,r0                        
8c0ae780:  fmov fr3,@(r0,r12)               
8c0ae782:  mov #12,r0                       
8c0ae784:  sts fpul,r3                      
8c0ae786:  fmov @(r0,r8),fr3                
8c0ae788:  shll2 r3                         
8c0ae78a:  fmov fr3,@(r0,r12)               
8c0ae78c:  add r14,r3                       
8c0ae78e:  mov #16,r0                       
8c0ae790:  fmov fr12,@(r0,r12)              ; U (rail B)
8c0ae792:  mov #20,r0                       
8c0ae794:  fmov fr15,@(r0,r12)              ; V
8c0ae796:  mov.l @r3,r2                     ; ARGB from fade ramp (r14 = 0x8c30e158)
8c0ae798:  mov.l r2,@(24,r12)               
8c0ae79a:  pref @r12                        ; flush SQ (vertex B)
8c0ae79c:  mov #4,r0                        
8c0ae79e:  fadd fr14,fr15                   ; V += dV
8c0ae7a0:  fmov @(r0,r15),fr3               
8c0ae7a2:  add #16,r9                       
8c0ae7a4:  mov #4,r0                        
8c0ae7a6:  fsub fr3,fr4                     ; fade index -= step
8c0ae7a8:  fmov @r9,fr3                     
8c0ae7aa:  add #32,r12                      
8c0ae7ac:  fmov fr3,@(r0,r12)               
8c0ae7ae:  add #-1,r13                      
8c0ae7b0:  fmov @(r0,r9),fr3                
8c0ae7b2:  mov #8,r0                        
8c0ae7b4:  ftrc fr4,fpul                    
8c0ae7b6:  add #16,r8                       
8c0ae7b8:  fmov fr3,@(r0,r12)               
8c0ae7ba:  mov #12,r0                       
8c0ae7bc:  fmov @(r0,r9),fr3                
8c0ae7be:  sts fpul,r3                      
8c0ae7c0:  fmov fr3,@(r0,r12)               
8c0ae7c2:  mov #16,r0                       
8c0ae7c4:  fmov fr13,@(r0,r12)              ; U (rail A)
8c0ae7c6:  mov #20,r0                       
8c0ae7c8:  shll2 r3                         
8c0ae7ca:  fmov fr15,@(r0,r12)              
8c0ae7cc:  add r14,r3                       
8c0ae7ce:  mov.l @r3,r2                     
8c0ae7d0:  mov.l r2,@(24,r12)               
8c0ae7d2:  pref @r12                        ; flush SQ (vertex A)
8c0ae7d4:  cmp/pl r13                       
8c0ae7d6:  bt.s 0x8c0ae774                  ; loop: PCW word 0 left as 0xE0000000 in both SQ halves (written once before)
8c0ae7d8:  add #32,r12                      

; ==== 0x8c0ae880: WEAPON TRAIL, untextured float-colour gradient (mode != 1) ====
; header PCW 0x80800012 (col_type 1 = 4 float colour, gouraud), ISP 0x8c800000.
; 8 FDIVs once per trail compute per-step deltas of A,R,G,B for both rails; per vertex the colour is DDA'd with FADD.
; out: 32 B {PCW, X, Y, 1/w, A, R, G, B} (TA type 1) via SQ
; cost: 67 instr per 2 strip vertices (~33/vertex); 1 branch per pair
8c0aea46:  fmov @r8,fr3                     ; rail B vertex
8c0aea48:  mov #4,r0                        
8c0aea4a:  fmov fr3,@(r0,r13)               
8c0aea4c:  fmov @(r0,r8),fr3                
8c0aea4e:  mov #8,r0                        
8c0aea50:  fmov fr3,@(r0,r13)               
8c0aea52:  mov #12,r0                       
8c0aea54:  fmov @(r0,r8),fr3                
8c0aea56:  fmov fr3,@(r0,r13)               
8c0aea58:  mov #16,r0                       
8c0aea5a:  fmov fr4,@(r0,r13)               ; A (rail B)
8c0aea5c:  mov #20,r0                       
8c0aea5e:  fmov fr13,@(r0,r13)              ; R
8c0aea60:  mov #8,r0                        
8c0aea62:  fmov @(r0,r15),fr3               
8c0aea64:  mov #24,r0                       
8c0aea66:  fmov fr3,@(r0,r13)               ; G (spilled to stack)
8c0aea68:  mov #4,r0                        
8c0aea6a:  fmov @(r0,r15),fr3               
8c0aea6c:  mov #28,r0                       
8c0aea6e:  fmov fr3,@(r0,r13)               ; B (spilled)
8c0aea70:  pref @r13                        ; flush
8c0aea72:  mov #16,r0                       
8c0aea74:  fadd fr0,fr4                     ; colour DDA: c += dc
8c0aea76:  fmov @(r0,r15),fr3               
8c0aea78:  mov #12,r0                       
8c0aea7a:  fmov @(r0,r15),fr2               
8c0aea7c:  mov #8,r0                        
8c0aea7e:  fmov @(r0,r15),fr1               
8c0aea80:  mov #8,r0                        
8c0aea82:  fadd fr3,fr13                    
8c0aea84:  add #16,r9                       
8c0aea86:  fadd fr2,fr1                     
8c0aea88:  add #32,r13                      
8c0aea8a:  fadd fr15,fr9                    
8c0aea8c:  add #16,r8                       
8c0aea8e:  fadd fr14,fr10                   
8c0aea90:  fadd fr11,fr8                    
8c0aea92:  fmov fr1,@(r0,r15)               
8c0aea94:  mov #4,r0                        
8c0aea96:  fmov @(r0,r15),fr3               
8c0aea98:  mov #4,r0                        
8c0aea9a:  fadd fr5,fr7                     
8c0aea9c:  fadd fr6,fr3                     
8c0aea9e:  fmov fr3,@(r0,r15)               
8c0aeaa0:  mov #4,r0                        
8c0aeaa2:  fmov @r9,fr3                     
8c0aeaa4:  fmov fr3,@(r0,r13)               
8c0aeaa6:  fmov @(r0,r9),fr3                
8c0aeaa8:  mov #8,r0                        
8c0aeaaa:  fmov fr3,@(r0,r13)               
8c0aeaac:  mov #12,r0                       
8c0aeaae:  fmov @(r0,r9),fr3                
8c0aeab0:  fmov fr3,@(r0,r13)               
8c0aeab2:  mov #16,r0                       
8c0aeab4:  fmov fr10,@(r0,r13)              ; rail A colours
8c0aeab6:  mov #20,r0                       
8c0aeab8:  fmov fr9,@(r0,r13)               
8c0aeaba:  mov #24,r0                       
8c0aeabc:  fmov fr8,@(r0,r13)               
8c0aeabe:  mov #28,r0                       
8c0aeac0:  fmov fr7,@(r0,r13)               
8c0aeac2:  pref @r13                        ; flush
8c0aeac4:  add #-1,r14                      
8c0aeac6:  cmp/pl r14                       
8c0aeac8:  bt.s 0x8c0aea46                  ; loop
8c0aeaca:  add #32,r13                      

; ==== 0x8c0b5da0: rotated particle sprite, 2D corner build (TA sprite, 64 B vertex) ====
; caller (e.g. 0x8c0b56b0, 0x8c0aece0): 0x8c0c08f2 projects the centre, size = scale*(1/w), size^2 summed
;   into 0x8c24a938; 0x8c0b5c44 writes the 32 B sprite header (PCW 0xa0800009 textured sprite / ISP 0x8e400000,
;   base colour from a per-age colour table); this routine writes the 4 corners, caller adds UVs @52/56/60.
; in : r5 = projected centre {X,Y,1/w}, fr4/fr5 = half sizes, r6 = angle (fsca units)
; out: {0xF0000000, Ax,Ay,Az, Bx,By,Bz, Cx,Cy,Cz, Dx,Dy, -, AUV,BUV,CUV} (16-bit packed UVs)
; cost: 72 instr per sprite here + ~40 header + ~25 projection: ~140-200 instr per particle (C code)
; 0x8c0b5e30 = same with every corner offset clamped to +-500 px (huge near-camera sprites)
8c0b5da0:  add #-8,r15                      
8c0b5da2:  mov #8,r0                        
8c0b5da4:  lds r6,fpul                      
8c0b5da6:  mov r15,r2                       
8c0b5da8:  fmov fr4,fr11                    
8c0b5daa:  mov.l 0x8c0b5f00,r3 ! f0000000   
8c0b5dac:  fsca fpul,dr0                    ; sin/cos of sprite angle in one instruction
8c0b5dae:  mov.l r3,@r4                     ; sprite vertex PCW (end of strip)
8c0b5db0:  mov r15,r3                       
8c0b5db2:  fmov @(r0,r5),fr3                
8c0b5db4:  mov #36,r0                       
8c0b5db6:  add #4,r3                        
8c0b5db8:  fmov fr3,@(r0,r4)                ; same 1/w for A,B,C (D z implied)
8c0b5dba:  mov #24,r0                       
8c0b5dbc:  fmov fr3,@(r0,r4)                
8c0b5dbe:  mov #12,r0                       
8c0b5dc0:  fmov fr3,@(r0,r4)                
8c0b5dc2:  mov #4,r0                        
8c0b5dc4:  fmov fr0,@r2                     
8c0b5dc6:  fmov fr5,fr0                     
8c0b5dc8:  fmov fr1,@r3                     
8c0b5dca:  fmov @r15,fr8                    
8c0b5dcc:  fmov @(r0,r15),fr7               
8c0b5dce:  mov #4,r0                        
8c0b5dd0:  fmul fr8,fr0                     
8c0b5dd2:  fmov @r5,fr6                     
8c0b5dd4:  fmul fr7,fr11                    
8c0b5dd6:  fmov @(r0,r5),fr9                
8c0b5dd8:  fmov fr4,fr1                     
8c0b5dda:  fmov fr0,fr3                     
8c0b5ddc:  fsub fr11,fr3                    
8c0b5dde:  fadd fr6,fr3                     
8c0b5de0:  fmov fr3,@(r0,r4)                ; Ax
8c0b5de2:  fmul fr8,fr1                     
8c0b5de4:  fmov fr5,fr10                    
8c0b5de6:  fmov fr9,fr3                     
8c0b5de8:  fmul fr7,fr10                    
8c0b5dea:  mov #8,r0                        
8c0b5dec:  fsub fr1,fr3                     
8c0b5dee:  fsub fr10,fr3                    
8c0b5df0:  fmov fr3,@(r0,r4)                ; Ay
8c0b5df2:  mov #16,r0                       
8c0b5df4:  fmov fr11,fr3                    
8c0b5df6:  fadd fr0,fr3                     
8c0b5df8:  fadd fr6,fr3                     
8c0b5dfa:  fmov fr3,@(r0,r4)                
8c0b5dfc:  mov #20,r0                       
8c0b5dfe:  fmov fr1,fr3                     
8c0b5e00:  fsub fr10,fr3                    
8c0b5e02:  fadd fr9,fr3                     
8c0b5e04:  fmov fr3,@(r0,r4)                
8c0b5e06:  mov #28,r0                       
8c0b5e08:  fmov fr11,fr3                    
8c0b5e0a:  fsub fr0,fr3                     
8c0b5e0c:  fadd fr6,fr3                     
8c0b5e0e:  fmov fr3,@(r0,r4)                
8c0b5e10:  pref @r4                         ; flush first 32 B
8c0b5e12:  fmov fr10,fr3                    
8c0b5e14:  fadd fr1,fr3                     
8c0b5e16:  fsub fr11,fr6                    
8c0b5e18:  mov #32,r0                       
8c0b5e1a:  fsub fr1,fr10                    
8c0b5e1c:  fadd fr9,fr3                     
8c0b5e1e:  fsub fr0,fr6                     
8c0b5e20:  fadd fr9,fr10                    
8c0b5e22:  fmov fr3,@(r0,r4)                
8c0b5e24:  mov #40,r0                       
8c0b5e26:  fmov fr6,@(r0,r4)                
8c0b5e28:  mov #44,r0                       
8c0b5e2a:  fmov fr10,@(r0,r4)               ; Dy; caller fills UVs and flushes 2nd half
8c0b5e2c:  rts                              
8c0b5e2e:  add #8,r15                       
