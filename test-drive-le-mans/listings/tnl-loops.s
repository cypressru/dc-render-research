; Test Drive Le Mans (DC, 2000) LEMANS24.BIN, base 0x8C010000.
; Track/car strip T&L kernel, disassembled (sh-elf-objdump -EL) with annotations.
; Input: 24- or 32-byte float vertices ({x,y,z,I,u,v} or {x,y,z,nx,ny,nz,u,v}), strip lengths as a byte list.
; Output: 8-word intensity-mode TA vertex {PCW, X, Y, 1/w, u, v, base, offset}
;         straight into the store queues, one pass, no intermediate buffer.

; ######## BULK PATH: no-clip twins (objects whose box is wholly past the near plane) ########

; ==== PIT no-clip: prelit intensity + UV, 24 B {x,y,z,I,u,v} (likely track bulk) 0x8c061fc0 ====
8c061fc0:  mov.l @r4+,r1               ; r1 = strip triangle counts (0 ends), r2 = src, r6 = SQ dest
8c061fc2:  mov.l @r4+,r2               
8c061fc4:  mov.l @r4+,r6               
8c061fc6:  mov r2,r3                   
8c061fc8:  pref @r2                    
8c061fca:  add #32,r3                  
8c061fcc:  fmov fr12,@-r15             
8c061fce:  mov.l r8,@-r15              
8c061fd0:  mov.l r9,@-r15              
8c061fd2:  add #-32,r6                 
8c061fd4:  fldi0 fr10                  ; offset intensity = 0
8c061fd6:  mov.l 0x8c062028,r4 ! e0000000
8c061fd8:  mov.l 0x8c06202c,r5 ! f0000000
8c061fda:  fschg                       ; FPSCR.SZ=1: fmov moves 64-bit pairs
8c061fdc:  mov.b @r1+,r0               
8c061fde:  cmp/eq #0,r0                
8c061fe0:  extu.b r0,r0                
8c061fe2:  bt.s 0x8c062034             
8c061fe4:  add #2,r0                   ; vertices = triangles + 2
8c061fe6:  fmov @r2+,fr4               ; dr4 = (x,y)
8c061fe8:  add #24,r3                  ; prefetch distance ~1 vertex (24 B stride)
8c061fea:  fmov @r2,fr6                ; dr6 = (z, I)  ... no post-inc
8c061fec:  fldi1 fr12                  ; fr12 = 1 (for 1/w)
8c061fee:  fldi1 fr7                   ; fr7 = 1 overwrites I: fv4 = (x,y,z,1)
8c061ff0:  ftrv xmtrx,fv4              ; (w, -, Y, X) = XMTRX * fv4
8c061ff2:  fmov @r2+,fr8               ; dr8 = (z, I) again: fr9 = I (prelit intensity)
8c061ff4:  cmp/eq #1,r0                ; last vertex of strip?
8c061ff6:  bf.s 0x8c061ffc             
8c061ff8:  mov r4,r7                   ; PCW 0xE0000000 (delay slot)
8c061ffa:  mov r5,r7                   ; PCW 0xF0000000 end of strip
8c061ffc:  mov.l @r2+,r8               ; u, v as raw words on the integer pipe
8c061ffe:  add #64,r6                  
8c062000:  mov.l @r2+,r9               
8c062002:  fdiv fr4,fr12               ; fr12 = 1/w
8c062004:  pref @r3                    ; prefetch next source
8c062006:  fschg                       ; back to 32-bit fmov
8c062008:  fmov fr10,@-r6              ; TA vertex backwards: offset, base, v, u, 1/w, Y, X, PCW
8c06200a:  fmov fr9,@-r6               
8c06200c:  mov.l r9,@-r6               
8c06200e:  fmul fr12,fr6               
8c062010:  mov.l r8,@-r6               
8c062012:  fmul fr12,fr7               
8c062014:  fmov fr12,@-r6              
8c062016:  fmov fr6,@-r6               
8c062018:  fmov fr7,@-r6               
8c06201a:  fschg                       
8c06201c:  mov.l r7,@-r6               
8c06201e:  dt r0                       
8c062020:  bf.s 0x8c061fe6             
8c062022:  pref @r6                    ; SQ burst for this vertex (delay slot)
8c062024:  bra 0x8c061fdc              
8c062026:  nop                         

; ==== PNT no-clip: lit (diffuse + specular), 32 B {x,y,z,nx,ny,nz,u,v} 0x8c061d40 ====
8c061d40:  mov.l @r4+,r1               
8c061d42:  mov.l @r4+,r2               
8c061d44:  mov.l @r4+,r6               
8c061d46:  mov r2,r3                   
8c061d48:  pref @r2                    
8c061d4a:  add #32,r3                  
8c061d4c:  fmov fr12,@-r15             
8c061d4e:  mov.l r8,@-r15              
8c061d50:  mov.l r9,@-r15              
8c061d52:  mov.l r10,@-r15             
8c061d54:  mov.l r11,@-r15             
8c061d56:  mov.l r12,@-r15             
8c061d58:  mov.l r13,@-r15             
8c061d5a:  mov.l 0x8c061de0,r10 ! 47800000
8c061d5c:  mova 0x8c061de4,r0          
8c061d5e:  mov r0,r13                  
8c061d60:  fmov @r4+,fr1               ; fv0 = light {amb, Lx, Ly, Lz}
8c061d62:  add #-32,r6                 
8c061d64:  fmov @r4+,fr2               
8c061d66:  fmov @r4+,fr3               
8c061d68:  fmov @r4+,fr0               
8c061d6a:  mov.l 0x8c061dd8,r4 ! e0000000
8c061d6c:  mov.l 0x8c061ddc,r5 ! f0000000
8c061d6e:  fschg                       
8c061d70:  mov.b @r1+,r0               
8c061d72:  cmp/eq #0,r0                
8c061d74:  extu.b r0,r0                
8c061d76:  bt.s 0x8c061de8             
8c061d78:  add #2,r0                   
8c061d7a:  fmov @r2+,fr4               ; dr4 = (x,y)
8c061d7c:  add #32,r3                  
8c061d7e:  fmov @r2,fr6                ; dr6 = (z,nx)
8c061d80:  fldi1 fr12                  
8c061d82:  fmov @r2+,fr8               ; dr8 = (z,nx) again (overlapping pair load)
8c061d84:  fldi1 fr7                   ; fv4 = (x,y,z,1)
8c061d86:  ftrv xmtrx,fv4              
8c061d88:  fmov @r2+,fr10              ; dr10 = (ny,nz)
8c061d8a:  fldi1 fr8                   ; fv8 = (1,nx,ny,nz)
8c061d8c:  cmp/eq #1,r0                
8c061d8e:  bf.s 0x8c061d94             
8c061d90:  mov r4,r7                   
8c061d92:  mov r5,r7                   
8c061d94:  mov.l @r2+,r8               
8c061d96:  add #64,r6                  
8c061d98:  mov.l @r2+,r9               
8c061d9a:  fdiv fr4,fr12               
8c061d9c:  pref @r3                    
8c061d9e:  fipr fv0,fv8                ; fr11 = ambient + N.L
8c061da0:  fschg                       
8c061da2:  fmov @r13,fr10              ; 0.5 threshold
8c061da4:  fcmp/gt fr10,fr11           
8c061da6:  bf.s 0x8c061db8             
8c061da8:  fldi0 fr10                  
8c061daa:  flds fr11,fpul              ; specular: bits<<4 + bits(65536.0f) ~ pow(x,16)
8c061dac:  sts fpul,r11                
8c061dae:  mov #4,r12                  
8c061db0:  shad r12,r11                
8c061db2:  add r10,r11                 
8c061db4:  lds r11,fpul                
8c061db6:  fsts fpul,fr10              
8c061db8:  fmov fr10,@-r6              
8c061dba:  fmov fr11,@-r6              
8c061dbc:  mov.l r9,@-r6               
8c061dbe:  fmul fr12,fr6               
8c061dc0:  mov.l r8,@-r6               
8c061dc2:  fmul fr12,fr7               
8c061dc4:  fmov fr12,@-r6              
8c061dc6:  fmov fr6,@-r6               
8c061dc8:  fmov fr7,@-r6               
8c061dca:  fschg                       
8c061dcc:  mov.l r7,@-r6               
8c061dce:  dt r0                       
8c061dd0:  bf.s 0x8c061d7a             
8c061dd2:  pref @r6                    ; SQ burst (delay slot)
8c061dd4:  bra 0x8c061d70              
8c061dd6:  nop                         

; ######## NEAR-CLIP PATH (only objects straddling w=1) ########

; ==== setup (entry 0x8c0b0260) ====
8c0b0260:  mov.l r6,@-r15              
8c0b0262:  mov.l r7,@-r15              
8c0b0264:  mov.l r8,@-r15              
8c0b0266:  mov.l r9,@-r15              
8c0b0268:  mov.l r10,@-r15             
8c0b026a:  mov.l r11,@-r15             
8c0b026c:  mov.l r12,@-r15             
8c0b026e:  mov.l r13,@-r15             
8c0b0270:  mov.l r14,@-r15             
8c0b0272:  mov #0,r14                  
8c0b0274:  fmov fr12,@-r15             
8c0b0276:  fmov fr13,@-r15             
8c0b0278:  fmov fr14,@-r15             
8c0b027a:  fmov fr15,@-r15             
8c0b027c:  add #-4,r15                 
8c0b027e:  mov.l @r4+,r12              ; r12 = strip-length byte list (0 = end)
8c0b0280:  mov.l @r4+,r3               ; r3 = source vertices (8 floats, 32 B)
8c0b0282:  mov.l @r4+,r2               ; r2 = store-queue dest
8c0b0284:  add #32,r2                  
8c0b0286:  fmov @r4+,fr9               ; fv8 = light: memory {Lx,Ly,Lz,ambient} -> fr9,fr10,fr11,fr8
8c0b0288:  fmov @r4+,fr10              
8c0b028a:  fmov @r4+,fr11              
8c0b028c:  fmov @r4+,fr8               
8c0b028e:  mov r3,r5                   
8c0b0290:  add #32,r5                  
8c0b0292:  mov.l 0x8c0b02a8,r13 ! 47800000; r13 = 0x47800000 (65536.0f bits): specular bias
8c0b0294:  mova 0x8c0b02ac,r0          ; r14 -> 0.5f (specular threshold)
8c0b0296:  mov.l 0x8c0b02b0,r10 ! e0000000; r10 = PCW 0xE0000000 (vertex)
8c0b0298:  mov.l 0x8c0b02b4,r11 ! f0000000; r11 = PCW 0xF0000000 (end of strip)
8c0b029a:  mov r0,r14                  
8c0b029c:  mov.l 0x8c0b02b8,r6 ! 8c0b01e0; r6/r7/r8 = 3-vertex ring for near clipping
8c0b029e:  mov.l 0x8c0b02bc,r7 ! 8c0b0200
8c0b02a0:  mov.l 0x8c0b02c0,r8 ! 8c0b0220

; ==== steady-state strip loop, unclipped vertex (0x8c0b04ea-0x8c0b056c) ====
8c0b04ea:  fmov @r3+,fr4               ; --- per vertex: load x,y,z
8c0b04ec:  fmov @r3+,fr5               
8c0b04ee:  fmov @r3+,fr6               
8c0b04f0:  fldi1 fr7                   ; w = 1
8c0b04f2:  add #32,r5                  
8c0b04f4:  ftrv xmtrx,fv4              ; XMTRX rows permuted: fv4 -> (w, 1, Y, X)
8c0b04f6:  fmov @r3+,fr13              ; normal -> fr13..15 while FTRV runs
8c0b04f8:  fmov @r3+,fr14              
8c0b04fa:  fmov @r3+,fr15              
8c0b04fc:  fldi1 fr12                  ; fv12 = (1, nx, ny, nz)
8c0b04fe:  fipr fv8,fv12               ; fr15 = ambient + N.L (one FIPR)
8c0b0500:  fdiv fr4,fr5                ; fr5 = 1/w (row 1 of the matrix is 0,0,0,1)
8c0b0502:  fmov @r14,fr14              ; fr14 reused: 0.5 threshold
8c0b0504:  fcmp/gt fr14,fr15           ; lit > 0.5 ?
8c0b0506:  bf.s 0x8c0b0518             
8c0b0508:  fldi0 fr3                   ; offset (specular) = 0
8c0b050a:  flds fr15,fpul              ; spec: float bits <<4 + 65536.0f bits ~ pow(x,16) via exponent math, integer pipe
8c0b050c:  sts fpul,r1                 
8c0b050e:  shll2 r1                    
8c0b0510:  shll2 r1                    
8c0b0512:  add r13,r1                  
8c0b0514:  lds r1,fpul                 
8c0b0516:  fsts fpul,fr3               
8c0b0518:  fmov fr15,fr2               ; base intensity = diffuse
8c0b051a:  pref @r5                    ; prefetch the next source vertex
8c0b051c:  fmov @r3+,fr12              ; u, v
8c0b051e:  fmov @r3+,fr13              
8c0b0520:  fldi1 fr0                   ; near plane: w > 1 ?
8c0b0522:  fcmp/gt fr0,fr4             
8c0b0524:  bt 0x8c0b052a               
8c0b0526:  bra 0x8c0b056e              
8c0b0528:  nop                         
8c0b052a:  add #32,r8                  ; save clip-space vertex in the ring (8 stores)
8c0b052c:  fmov fr3,@-r8               
8c0b052e:  fmov fr2,@-r8               
8c0b0530:  fmov fr13,@-r8              
8c0b0532:  fmov fr12,@-r8              
8c0b0534:  fmov fr5,@-r8               
8c0b0536:  fmov fr6,@-r8               
8c0b0538:  fmov fr7,@-r8               
8c0b053a:  fmov fr4,@-r8               
8c0b053c:  fmov fr3,@-r2               ; TA vertex, written backwards into the SQ: offset, base, v, u, 1/w
8c0b053e:  fmov fr2,@-r2               
8c0b0540:  fmov fr13,@-r2              
8c0b0542:  fmov fr12,@-r2              
8c0b0544:  fmov fr5,@-r2               
8c0b0546:  fmov fr7,fr14               ; X*1/w, Y*1/w
8c0b0548:  fmov fr6,fr15               
8c0b054a:  fmul fr5,fr14               
8c0b054c:  fmul fr5,fr15               
8c0b054e:  fmov fr15,@-r2              
8c0b0550:  fmov fr14,@-r2              
8c0b0552:  mov.l r10,@-r2              ; PCW last
8c0b0554:  pref @r9                    ; flush the OTHER SQ (previous vertex): double-buffered SQ
8c0b0556:  mov r2,r9                   
8c0b0558:  add #64,r2                  ; next 32 B slot (alternates SQ0/SQ1)
8c0b055a:  dt r0                       ; vertices left in strip
8c0b055c:  bf 0x8c0b0562               
8c0b055e:  bra 0x8c0b0b20              
8c0b0560:  nop                         
8c0b0562:  mov r6,r1                   ; rotate the ring
8c0b0564:  mov r7,r6                   
8c0b0566:  mov r8,r7                   
8c0b0568:  mov r1,r8                   
8c0b056a:  bra 0x8c0b04ea              
8c0b056c:  nop                         

; ==== near-plane clip: intersection vertex (one of the variants) ====
8c0b056e:  add #32,r8                  ; --- near-clip path: emit the vertex that was in front, then the lerped intersection
8c0b0570:  fmov fr3,@-r8               
8c0b0572:  fmov fr2,@-r8               
8c0b0574:  fmov fr13,@-r8              
8c0b0576:  fmov fr12,@-r8              
8c0b0578:  fmov fr5,@-r8               
8c0b057a:  fmov fr6,@-r8               
8c0b057c:  fmov fr7,@-r8               
8c0b057e:  fmov fr4,@-r8               
8c0b0580:  fldi1 fr0                   ; t = (1-w0)/(w1-w0)
8c0b0582:  fmov @r6+,fr14              
8c0b0584:  fsub fr4,fr0                
8c0b0586:  fsub fr4,fr14               
8c0b0588:  fdiv fr14,fr0               
8c0b058a:  fldi1 fr4                   
8c0b058c:  fldi1 fr5                   
8c0b058e:  fmov @r6+,fr14              
8c0b0590:  fmov @r6+,fr15              
8c0b0592:  fsub fr7,fr14               
8c0b0594:  fsub fr6,fr15               
8c0b0596:  fmac fr0,fr14,fr7           ; lerp every attribute with FMAC
8c0b0598:  fmac fr0,fr15,fr6           
8c0b059a:  add #4,r6                   
8c0b059c:  fmov @r6+,fr14              
8c0b059e:  fmov @r6+,fr15              
8c0b05a0:  fsub fr12,fr14              
8c0b05a2:  fsub fr13,fr15              
8c0b05a4:  fmac fr0,fr14,fr12          
8c0b05a6:  fmac fr0,fr15,fr13          
8c0b05a8:  fmov @r6+,fr14              
8c0b05aa:  fmov @r6+,fr15              
8c0b05ac:  fsub fr2,fr14               
8c0b05ae:  fsub fr3,fr15               
8c0b05b0:  fmac fr0,fr14,fr2           
8c0b05b2:  fmac fr0,fr15,fr3           
8c0b05b4:  add #-32,r6                 
8c0b05b6:  fmov fr3,@-r2               
8c0b05b8:  fmov fr2,@-r2               
8c0b05ba:  fmov fr13,@-r2              
8c0b05bc:  fmov fr12,@-r2              
8c0b05be:  fmov fr5,@-r2               
8c0b05c0:  fmov fr7,fr14               
8c0b05c2:  fmov fr6,fr15               
8c0b05c4:  fmul fr5,fr14               
8c0b05c6:  fmul fr5,fr15               
8c0b05c8:  fmov fr15,@-r2              
8c0b05ca:  fmov fr14,@-r2              
8c0b05cc:  mov.l r10,@-r2              
8c0b05ce:  pref @r9                    
8c0b05d0:  mov r2,r9                   
8c0b05d2:  add #64,r2                  

; ==== SDK-style prelit transform loop (0x8c0eaace, no references found) for comparison ====
8c0eaace:  mov.l @r4+,r1               
8c0eaad0:  mov.l @r4+,r2               
8c0eaad2:  mov.l @r4+,r3               
8c0eaad4:  pref @r3                    
8c0eaad6:  add #32,r2                  
8c0eaad8:  mov.l r6,@-r15              
8c0eaada:  mov r3,r5                   
8c0eaadc:  mov.l r7,@-r15              
8c0eaade:  mov.l r8,@-r15              
8c0eaae0:  mov.l r9,@-r15              
8c0eaae2:  mov.l r10,@-r15             
8c0eaae4:  mov.l r11,@-r15             
8c0eaae6:  mov.l @r3+,r6               
8c0eaae8:  add #32,r5                  
8c0eaaea:  fmov @r3+,fr4               
8c0eaaec:  pref @r5                    
8c0eaaee:  fmov @r3+,fr5               
8c0eaaf0:  fmov @r3+,fr6               
8c0eaaf2:  fldi1 fr7                   
8c0eaaf4:  ftrv xmtrx,fv4              
8c0eaaf6:  add #32,r5                  
8c0eaaf8:  mov.l @r3+,r7               
8c0eaafa:  pref @r5                    
8c0eaafc:  fldi1 fr2                   
8c0eaafe:  mov.l @r3+,r8               
8c0eab00:  fdiv fr4,fr2                
8c0eab02:  mov.l @r3+,r9               
8c0eab04:  mov r6,r11                  
8c0eab06:  mov.l @r3+,r10              
8c0eab08:  fmov fr6,fr1                
8c0eab0a:  mov.l r10,@-r2              
8c0eab0c:  fmov fr7,fr0                
8c0eab0e:  mov.l r9,@-r2               
8c0eab10:  mov.l @r3+,r6               
8c0eab12:  fldi1 fr7                   
8c0eab14:  mov.l r8,@-r2               
8c0eab16:  mov.l r7,@-r2               
8c0eab18:  fmov @r3+,fr4               
8c0eab1a:  fmov @r3+,fr5               
8c0eab1c:  fmul fr2,fr1                
8c0eab1e:  fmul fr2,fr0                
8c0eab20:  fmov @r3+,fr6               
8c0eab22:  fmov fr2,@-r2               
8c0eab24:  fmov fr1,@-r2               
8c0eab26:  fmov fr0,@-r2               
8c0eab28:  mov.l r11,@-r2              
8c0eab2a:  dt r1                       
8c0eab2c:  pref @r2                    
8c0eab2e:  bf.s 0x8c0eaaf4             
8c0eab30:  add #64,r2                  
8c0eab32:  mov.l @r15+,r11             
8c0eab34:  mov.l @r15+,r10             
8c0eab36:  mov.l @r15+,r9              
8c0eab38:  mov.l @r15+,r8              
8c0eab3a:  mov.l @r15+,r7              
8c0eab3c:  rts                         
8c0eab3e:  mov.l @r15+,r6              
