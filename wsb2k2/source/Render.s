// --------------------------------------------------------------------------------
// $Id: Render.s,v 1.34 2000/11/17 23:42:31 jbrooks Exp $
// --------------------------------------------------------------------------------
// Render.s - Render animated heirarchical 3D models
//
// Created 3/5/00 by JBrooks
//
// Copyright (c) 2000 Blue Shift, Inc., All Rights Reserved
// --------------------------------------------------------------------------------
//

			.file	"Render.s"

// --------------------------------------------------
// Parameter Control Word
// --------------------------------------------------
//

#define KMY_PARAM_ENDOFLIST			(0x00000000)
#define KMY_PARAM_USERTILECLIP		(0x20000000)
#define KMY_PARAM_OBJECTLIST		(0x40000000)
#define KMY_PARAM_POLYGON			(0x80000000)
#define KMY_PARAM_MODIFIER			(0x80000000)
#define KMY_PARAM_SPRITE			(0xa0000000)
#define KMY_PARAM_VERTEX			(0xe0000000)
#define KMY_PARAM_ENDOFSTRIP		(0xf0000000)
#define KMY_PARAM_MASK				(0x0fffffff)

#define KMY_LIST_OPAQUE				(0x00000000)
#define KMY_LIST_OPAQUEMODIFIER		(0x01000000)
#define KMY_LIST_TRANS				(0x02000000)
#define KMY_LIST_TRANSMODIFIER		(0x03000000)
#define KMY_LIST_PUNCHTHROUGH		(0x04000000)
#define KMY_LIST_MASK				(0xf8ffffff)

#define KMY_GROUP_STRIP1			(0x00800000)
#define KMY_GROUP_STRIP2			(0x00840000)
#define KMY_GROUP_STRIP4			(0x00880000)
#define KMY_GROUP_STRIP6			(0x008c0000)
#define KMY_GROUP_STRIP_MASK		(0xff73ffff)

#define KMY_GROUP_CLIP_DISABLE		(0x00800000)
#define KMY_GROUP_CLIP_INSIDE		(0x00820000)
#define KMY_GROUP_CLIP_OUTSIDE		(0x00830000)
#define KMY_GROUP_CLIP_MASK			(0xff7cffff)

#define KMY_GROUP_MASK				(0xff70ffff)

#define KMY_OBJ_NORMAL_POLYGON		(0x00000000)
#define KMY_OBJ_SHADOW_POLYGON		(0x00000080)
#define KMY_OBJ_WTV_POLYGON			(0x000000c0)
#define KMY_OBJ_NORMAL_MODIFIER		(0x00000000)
#define KMY_OBJ_LAST_MODIFIER		(0x00000040)
#define KMY_OBJ_SHADOWMODE_MASK		(0xffffff3f)

#define KMY_OBJ_PACKED_COLOR		(0x00000000)
#define KMY_OBJ_FLOAT_COLOR			(0x00000010)
#define KMY_OBJ_INTENSITY1			(0x00000020)
#define KMY_OBJ_INTENSITY2			(0x00000030)
#define KMY_OBJ_COLORMODE_MASK		(0xffffffcf)

#define KMY_OBJ_TEXTURE				(0x00000008)
#define KMY_OBJ_TEXTURE_MASK		(0xfffffff7)
#define KMY_OBJ_OFFSET				(0x00000004)
#define KMY_OBJ_OFFSET_MASK			(0xfffffffb)
#define KMY_OBJ_GOURAUD				(0x00000002)
#define KMY_OBJ_GOURAUD_MASK		(0xfffffffd)
#define KMY_OBJ_16BITUV				(0x00000001)
#define KMY_OBJ_16BITUV_MASK		(0xfffffffe)

#define KMY_OBJ_MASK				(0xffffff00)
			

// --------------------------------------------------
// Local Defines
// --------------------------------------------------
// 
#define _kMaxCachedVertices	(256)

#define _PCW (	  KMY_PARAM_POLYGON | KMY_LIST_OPAQUE | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_SHADOW_POLYGON \
				| KMY_OBJ_WTV_POLYGON | KMY_OBJ_INTENSITY1 | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV )

// --------------------------------------------------
// Data section
// --------------------------------------------------
// 
			.data

// --------------------------------------------------
// 
// --------------------------------------------------
// 
/*
Ren_ScreenCenterX:
					.global	Ren_ScreenCenterX
					.float	320.0
Ren_ScreenCenterY:
					.global	Ren_ScreenCenterY
					.float	240.0
_fFloatZX:
					.float	0.0, 0.0

_fFloatY1:
					.float	0.0, 1.0
*/
// --------------------------------------------------
// 
// --------------------------------------------------
// 
/*					.data
					.offset	0
_InVert_s16TexU:	.short	0
_InVert_s16TexV:	.short	0
//
_InVert_s16VertX:	.short	0
_InVert_s16NormX:	.short	0
//
_InVert_s16VertY:	.short	0
_InVert_s16NormY:	.short	0
//
_InVert_s16VertZ:	.short	0
_InVert_s16NormZ:	.short	0
//
_InVert_iSize:		.equ	*

_InVert_s16TexU2:	.short	0
_InVert_s16TexV2:	.short	0
//
_InVert_s16VertX2:	.short	0
_InVert_s16NormX2:	.short	0
//
_InVert_s16VertY2:	.short	0
_InVert_s16NormY2:	.short	0
//
_InVert_s16VertZ2:	.short	0
_InVert_s16NormZ2:	.short	0
//
_InVert_iSize2:		.equ	*
*/
// --------------------------------------------------
// 
// --------------------------------------------------
// 
/*					.data
					.offset	0		
_f32Vert_s16ZLo:	.short	0
_f32Vert_s16ZHi:	.short	0
//
_f32Vert_s16XLo:	.short	0
_f32Vert_s16XHi:	.short	0
//
_f32Vert_s16YLo:	.short	0
_f32Vert_s16YHi:	.short	0
//
_f32Vert_fConst1:	.float	1.0
//
_f32Vert_iSize:		.equ	*

*/
			.text

// --------------------------------------------------
// Int Regs
// --------------------------------------------------
// 
#define	iOff			R0
#define iTemp			R1
#define pPrefetch		R2
#define iOne			R3
#define iVertCount		R4
#define pVertIn			R5
#define pVertOut		R6
#define iVisibleVerts	R7

// --------------------------------------------------
// FP0 Regs
// --------------------------------------------------
// 
#define fVertAX		FR0
#define fVertAY		FR1
#define fVertAZ		FR2
#define fVertAInvZ	FR3
#define fVertBX		FR4
#define fVertBY		FR5
#define fVertBZ		FR6
#define fVertBInvZ	FR7
#define fVertCX		FR8
#define fVertCY		FR9
#define fVertCZ		FR10
#define fVertCInvZ	FR11
#define fVertDX		FR12
#define fVertDY		FR13
#define fVertDZ		FR14
#define fVertDInvZ	FR15

// --------------------------------------------------
// 
#if	0
void Ren_TransformFloatVertices() {};
#endif
			.align	32
_Ren_TransformFloatVertices:
			.global	_Ren_TransformFloatVertices
			.function	"Ren_TransformFloatVertices", _Ren_TransformFloatVertices, _Ren_TransformFloatVerticesEnd - _Ren_TransformFloatVertices


// --------------------------------------------------
// 
//Setup:	LdA_00
//Step1		TrA_00	StB_-1	PjC_-2	DvA_00	LdB_01
//Step2		TrB_01	StC_-2	PjD_-3	DvB_01	LdC_02
//Step3		TrC_02	StD_-3	PjA_00	DvC_02	LdD_03
//Step4		TrD_03	StA_00	PjB_01	DvD_03	LdA_04

//Step4		TrD_03	Exp_04	StA_00	PjB_01	DvD_03	LdA_04
_mTransformFloatVertices	.macro	_FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ, _StoreVert, _IncVertPtr, _ExitBranch, _SkipDivLabel
												//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
 //fdiv3_f3						    							
			FMUL	_PjInvZ, _PjX					//	4F							PjC_-2
			FMOV.S	_StInvZ, _StoreVert				//	1L					StB_-1
 //fdiv4_f3						    							
 			FTRV	XMTRX, _FTRVVect				//	7F	TrA_00
			FMOV.S	_StY, _StoreVert				//	1L					StB_-1
 //fdiv5_f3						    							
 //ftrv2						    							
//			SHLL2	iExpZ							//	1X			Exp_01
			FMOV.S	_StX, _StoreVert				//	1L					StB_-1
 //fdiv6_f3						    							
 //ftrv3						    							
//			SHLL2	iExpX							//	1X			Exp_01
			FMOV.S	@ pVertIn+, _StX				//	2L											LdB_01
 //fdiv7_f3						    							
 //ftrv4						    							
//			SHLL2	iExpY							//	1X			Exp_01
			FMOV.S	@ pVertIn+, _StY				//	2L											LdB_01
 //fdiv8_f3						    							
 //ftrv4f1						    							
			ADD		_IncVertPtr, pVertOut			//	1X
			FMOV.S	@ pVertIn+, _StZ				//	2L											LdB_01
 //fdiv9_f3						    							
 			FMUL	_PjInvZ, _PjY					//	4F							PjC_-2
			FLDS	_DvZ, FPUL						//	0L
 //fdiv10_f1						    							
			STS		FPUL, iTemp						//	1L

			CMP/GT	iOne, iTemp
			FLDI1	_StInvZ							//	0L											LdB_01

			BF/S	_SkipDivLabel
//			BF/S	_FltClip
			DT		iVertCount						//	1X

			ADD		#1, iVisibleVerts
			FDIV	_DvZ, _DvInvZ					//	13F									DvA_00
_SkipDivLabel:
 //fdiv2_f3						    							
			_ExitBranch								//	2B
			
			.endm

// --------------------------------------------------
// 

			FMOV.S	FR15, @-R15
			FMOV.S	FR14, @-R15
			FMOV.S	FR13, @-R15
			FMOV.S	FR12, @-R15
			FMOV.S	FR11, @-R15
			FMOV.S	FR10, @-R15
			FMOV.S	FR9, @-R15
			FMOV.S	FR8, @-R15
			MOV.L	R14, @-R15
			MOV.L	R13, @-R15
			MOV.L	R12, @-R15
			MOV.L	R11, @-R15
			MOV.L	R10, @-R15
			MOV.L	R9, @-R15
			MOV.L	R8, @-R15
			STS.L   PR, @-R15

			MOV		pVertIn, pPrefetch
			MOV		#3*4+1, iOff
			MULU	iVertCount, iOff
			MOV		#-5, iTemp
			ADD		#32, iOff
			SHAD	iTemp, iOff
FltPrefLoop:
			DT		iOff
			PREF	@ pPrefetch
			BF/S	FltPrefLoop
			ADD		#32, pPrefetch

			MOV		#0, iVisibleVerts
//Setup:	LdA_00
			FMOV.S	@ pVertIn+, fVertAX
			FMOV.S	@ pVertIn+, fVertAY
			FMOV.S	@ pVertIn+, fVertAZ
			FLDI1	fVertAInvZ

			MOV.L	_FltOne, iOne
			ADD		#3, iVertCount
			ADD		#3*4, pVertOut
			_mTransformFloatVertices	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@ pVertOut, #0, , SkipDiv1
			_mTransformFloatVertices	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@ pVertOut, #0, , SkipDiv2
			_mTransformFloatVertices	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@ pVertOut, #4, BRA _FltLoop, SkipDiv3
			NOP

_FltOne:	.float	1.0

			.align	4
_FltLoop:
//Step4		TrD_03	StA_00	PjB_01	DvD_03	LdA_04
			_mTransformFloatVertices	FV12, fVertDX, fVertDY, fVertDZ, fVertDInvZ, 	fVertBX, fVertBY, fVertBZ, fVertBInvZ, 		fVertAX, fVertAY, fVertAZ, fVertAInvZ,	@-pVertOut, #(3+4)*4, BT/S _FltDone, SkipDiv4
			_mTransformFloatVertices	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@-pVertOut, #(3+4)*4, BT/S _FltDone, SkipDiv5
			_mTransformFloatVertices	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@-pVertOut, #(3+4)*4, BT/S _FltDone, SkipDiv6
			_mTransformFloatVertices	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@-pVertOut, #(3+4)*4, BF _FltLoop, SkipDiv7

			.align	4
_FltDone:
			BRA	_FltExit
			MOV	iVisibleVerts, R0

			.align	4
_FltClip:			
			BRA	_FltExit
			MOV	#1, R0
			
			.align	4
_FltExit:

			LDS.L  	@R15+, PR
			MOV.L	@R15+, R8
			MOV.L	@R15+, R9
			MOV.L	@R15+, R10
			MOV.L	@R15+, R11
			MOV.L	@R15+, R12
			MOV.L	@R15+, R13
			MOV.L	@R15+, R14
			FMOV.S	@R15+, FR8
			FMOV.S	@R15+, FR9
			FMOV.S	@R15+, FR10
			FMOV.S	@R15+, FR11
			FMOV.S	@R15+, FR12
			FMOV.S	@R15+, FR13
			FMOV.S	@R15+, FR14
			FMOV.S	@R15+, FR15
			RTS						
			NOP
_Ren_TransformFloatVerticesEnd:

// --------------------------------------------------
// Undef Regs
// --------------------------------------------------
// 
#undef	iOff
#undef	iVertCount
#undef	pVertIn
#undef	pVertOut
#undef	iTemp
#undef	a_pFloatTbl
#undef	pPrefetch

/*
#undef fVertAZ
#undef fVertAX
#undef fVertAY
#undef fVertAInvZ
#undef fVertBZ
#undef fVertBX
#undef fVertBY
#undef fVertBInvZ
#undef fVertCZ
#undef fVertCX
#undef fVertCY
#undef fVertCInvZ
#undef fVertDZ
#undef fVertDX
#undef fVertDY
#undef fVertDInvZ
*/

// --------------------------------------------------
// Int Regs
// --------------------------------------------------
// 
#define	iOff			R0
#define	pFloatTbl		R0
#define	iExpX			R1
#define	iExpY			R2
#define iExpZ			R3
#define iVertCount		R4
#define pVertIn			R5
#define pVertOut		R6
#define	a_pFloatTbl		R7
#define iTemp			R8
#define pPrefetch		R9

// --------------------------------------------------
// FP0 Regs
// --------------------------------------------------
// 
/*
#define fVertAX		FR0
#define fVertAY		FR1
#define fVertAZ		FR2
#define fVertAInvZ	FR3
#define fVertBX		FR4
#define fVertBY		FR5
#define fVertBZ		FR6
#define fVertBInvZ	FR7
#define fVertCX		FR8
#define fVertCY		FR9
#define fVertCZ		FR10
#define fVertCInvZ	FR11
#define fVertDX		FR12
#define fVertDY		FR13
#define fVertDZ		FR14
#define fVertDInvZ	FR15
*/
// --------------------------------------------------
// 
#if	0
void Ren_TransformVertices() {};
#endif
			.align	32
_Ren_TransformVertices:
			.global	_Ren_TransformVertices
			.function	"Ren_TransformVertices", _Ren_TransformVertices, _Ren_TransformVerticesEnd - _Ren_TransformVertices


// --------------------------------------------------
// 
//Setup:	Exp_00	LdA_00	Exp_01
//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
//Step2		TrB_01	Exp_02	StC_-2	PjD_-3	DvB_01	LdC_02
//Step3		TrC_02	Exp_03	StD_-3	PjA_00	DvC_02	LdD_03
//Step4		TrD_03	Exp_04	StA_00	PjB_01	DvD_03	LdA_04

//Step4		TrD_03	Exp_04	StA_00	PjB_01	DvD_03	LdA_04

_mTransformVertices	.macro	_FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ, _StoreVert, _IncVertPtr, _ExitBranch
												//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
 //fdiv3_f3						    							
			FMUL	_PjInvZ, _PjX					//	4F							PjC_-2
			FMOV.S	_StInvZ, _StoreVert				//	1L					StB_-1
 //fdiv4_f3						    							
 			FTRV	XMTRX, _FTRVVect				//	7F	TrA_00
			FMOV.S	_StY, _StoreVert				//	1L					StB_-1
 //fdiv5_f3						    							
 //ftrv2						    							
			SHLL2	iExpZ							//	1X			Exp_01
			FMOV.S	_StX, _StoreVert				//	1L					StB_-1
 //fdiv6_f3						    							
 //ftrv3						    							
			SHLL2	iExpX							//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpZ), _StZ		//	2L											LdB_01
 //fdiv7_f3						    							
 //ftrv4						    							
			SHLL2	iExpY							//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpX), _StX		//	2L											LdB_01
 //fdiv8_f3						    							
 //ftrv4f1						    							
			ADD		_IncVertPtr, pVertOut			//	1X
			FMOV.S	@(pFloatTbl, iExpY), _StY		//	2L											LdB_01
 //fdiv9_f3						    							
 			FMUL	_PjInvZ, _PjY					//	4F							PjC_-2
			FLDI1	_StInvZ							//	0L											LdB_01
 //fdiv10_f1						    							

			DT		iVertCount						//	1X
			MOV.B	@ pVertIn+, iExpX				//	2L			Exp_02

			FDIV	_DvZ, _DvInvZ					//	13F									DvA_00
			MOV.B	@ pVertIn+, iExpY				//	2L			Exp_02
 //fdiv2_f3						    							
			_ExitBranch								//	2B
			MOV.B	@ pVertIn+, iExpZ				//	2L			Exp_02
			
			.endm

_mTransformVerticesDiv	.macro	_FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ
												//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
 //fdiv4_f3						    							
			FMUL	_PjInvZ, _PjX					//	4F							PjC_-2
			FMOV.S	_StX, @-pVertOutX				//	1L					StB_-1
 //fdiv5_f3						    							
 			FTRV	XMTRX, _FTRVVect				//	7F	TrA_00
			FMOV.S	_StInvZ, @-pVertOutZ			//	1L					StB_-1
 //fdiv6_f3						    							
 //ftrv2						    							
			SHLL2	iExpZ							//	1X			Exp_01
			FMOV.S	_StY, @-pVertOutY				//	1L					StB_-1
 //fdiv7_f3						    							
 //ftrv3						    							
			SHLL2	iExpX							//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpZ), _StZ		//	2L											LdB_01
 //fdiv8_f3						    							
 //ftrv4						    							
			SHLL2	iExpY							//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpX), _StX		//	2L											LdB_01
 //fdiv9_f3						    							
 //ftrv4f1						    							
			ADD		#0,	pVertIn						//	1X
			FMOV.S	@(pFloatTbl, iExpY), _StY		//	2L											LdB_01
 //fdiv10_f1						    							
 			FMUL	_PjInvZ, _PjY					//	4F							PjC_-2
			FLDI1	_StInvZ							//	0L											LdB_01

			DT		iVertCount						//	1X
			MOV.B	@ pVertIn+, iExpX				//	2L			Exp_02

			FDIV	_DvZ, _DvInvZ					//	13F									DvA_00
			MOV.B	@ pVertIn+, iExpY				//	2L			Exp_02
 //fdiv2_f3						    							
			.endm



_mTransformVertices2	.macro	_FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ
												//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
 //fdiv4_f3						    							
 			FTRV	XMTRX, _FTRVVect				//	7F	TrA_00
			FMOV.S	_StX, @-pVertOutUVX				//	1L					StB_-1
 //fdiv5_f3						    							
 //ftrv2						    							
			ADD		#-4, pVertOutUVX				//	1X
			FMOV.S	_StInvZ, @-pVertOutYZ			//	1L					StB_-1
 //fdiv6_f3						    							
 //ftrv3						    							
			SHLD	iShiftL4, iExpZ					//	1X			Exp_01
			FMOV.S	_StY, @-pVertOutYZ				//	1L					StB_-1
 //fdiv7_f3						    							
 //ftrv4						    							
			SHLD	iShiftL4, iExpX					//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpZ), _StZ		//	2L											LdB_01
 //fdiv8_f3						    							
 //ftrv4f1						    							
			SHLD	iShiftL4, iExpY					//	1X			Exp_01
			FMOV.S	@(pFloatTbl, iExpX), _StX		//	2L											LdB_01
 //fdiv9_f3						    							
			FMUL	_PjInvZ, _PjX					//	4F							PjC_-2
			FMOV.S	@(pFloatTbl, iExpY), _StY		//	2L											LdB_01
 //fdiv10_f1						    							
			DT		iVertCount						//	1X
			FLDI1	_StInvZ							//	0L											LdB_01

			FDIV	_DvZ, _DvInvZ					//	13F									DvA_00
			MOV.B	@ pVertIn+, iExpX				//	2L			Exp_02
 //fdiv2_f3						    							
 			FMUL	_PjInvZ, _PjY					//	4F							PjC_-2
			MOV.B	@ pVertIn+, iExpY				//	2L			Exp_02
 //fdiv3_f3						    							
			.endm



// --------------------------------------------------
// 

			FMOV.S	FR15, @-R15
			FMOV.S	FR14, @-R15
			FMOV.S	FR13, @-R15
			FMOV.S	FR12, @-R15
			FMOV.S	FR11, @-R15
			FMOV.S	FR10, @-R15
			FMOV.S	FR9, @-R15
			FMOV.S	FR8, @-R15
			MOV.L	R14, @-R15
			MOV.L	R13, @-R15
			MOV.L	R12, @-R15
			MOV.L	R11, @-R15
			MOV.L	R10, @-R15
			MOV.L	R9, @-R15
			MOV.L	R8, @-R15
			STS.L   PR, @-R15

			MOV		iVertCount, iTemp
			EXTU.W	iVertCount, iVertCount
			SHLR16	iTemp
//			ADD		iVertCount, iTemp
			SHLL2	iTemp
			SHLL2	iTemp
			ADD		iTemp, pVertOut

			MOV		pVertIn, pPrefetch
			MOV		iVertCount, iOff
			ADD		#(32/4)-1, iOff
			SHLR	iOff
			SHLR2	iOff
PrefLoop:
			DT		iOff
			PREF	@ pPrefetch
			BF/S	PrefLoop
			ADD		#32, pPrefetch

			MOV		a_pFloatTbl, pFloatTbl

//Setup:	Exp_00	LdA_00	Exp_01
			MOV.B	@ pVertIn+, iExpX

			MOV.B	@ pVertIn+, iExpY
			SHLL2	iExpX
			MOV.B	@ pVertIn+, iExpZ
			SHLL2	iExpY
			FMOV.S	@(pFloatTbl, iExpX), fVertAX
			SHLL2	iExpZ
			FMOV.S	@(pFloatTbl, iExpY), fVertAY
			FMOV.S	@(pFloatTbl, iExpZ), fVertAZ
			FLDI1	fVertAInvZ

			MOV.B	@ pVertIn+, iExpX
			MOV.B	@ pVertIn+, iExpY
			MOV.B	@ pVertIn+, iExpZ

//Setup:	Exp_00	LdA_00	Exp_01
//Step1		TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01
//Step2		TrB_01	Exp_02	StC_-2	PjD_-3	DvB_01	LdC_02
//Step3		TrC_02	Exp_03	StD_-3	PjA_00	DvC_02	LdD_03
			ADD		#3, iVertCount
			ADD		#3*4, pVertOut
			_mTransformVertices		FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@ pVertOut, #0, 
			_mTransformVertices		FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@ pVertOut, #0, 
			_mTransformVertices		FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@ pVertOut, #4, BRA Loop

			.align	4
Loop:
//Step4		TrD_03	Exp_04	StA_00	PjB_01	DvD_03	LdA_04
			_mTransformVertices		FV12, fVertDX, fVertDY, fVertDZ, fVertDInvZ, 	fVertBX, fVertBY, fVertBZ, fVertBInvZ, 		fVertAX, fVertAY, fVertAZ, fVertAInvZ,	@-pVertOut, #(3+4)*4, BT/S BtmExit
			_mTransformVertices		FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@-pVertOut, #(3+4)*4, BT/S BtmExit
			_mTransformVertices		FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@-pVertOut, #(3+4)*4, BT/S BtmExit
			_mTransformVertices		FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@-pVertOut, #(3+4)*4, BF/S Loop

BtmExit:

			LDS.L  	@R15+, PR
			MOV.L	@R15+, R8
			MOV.L	@R15+, R9
			MOV.L	@R15+, R10
			MOV.L	@R15+, R11
			MOV.L	@R15+, R12
			MOV.L	@R15+, R13
			MOV.L	@R15+, R14
			FMOV.S	@R15+, FR8
			FMOV.S	@R15+, FR9
			FMOV.S	@R15+, FR10
			FMOV.S	@R15+, FR11
			FMOV.S	@R15+, FR12
			FMOV.S	@R15+, FR13
			FMOV.S	@R15+, FR14
			FMOV.S	@R15+, FR15
			RTS						
			NOP
_Ren_TransformVerticesEnd:

// --------------------------------------------------
// Undef Regs
// --------------------------------------------------
// 
#undef	iOff
#undef	pFloatTbl
#undef	iExpX
#undef	iExpY
#undef	iExpZ
#undef	iVertCount
#undef	pVertIn
#undef	pVertOut
#undef	iTemp
#undef	a_pFloatTbl
#undef	pPrefetch

/*
#undef fVertAZ
#undef fVertAX
#undef fVertAY
#undef fVertAInvZ
#undef fVertBZ
#undef fVertBX
#undef fVertBY
#undef fVertBInvZ
#undef fVertCZ
#undef fVertCX
#undef fVertCY
#undef fVertCInvZ
#undef fVertDZ
#undef fVertDX
#undef fVertDY
#undef fVertDInvZ
*/

// --------------------------------------------------
// 

#if	0
void Ren_LightVertices() {};
#endif
			.text
			.align	32
_Ren_LightVertices:
			.global	_Ren_LightVertices
			.function	"Ren_LightVertices", _Ren_LightVertices, _Ren_LightVerticesEnd - _Ren_LightVertices

// --------------------------------------------------
// 

#define	iOff			R0
#define	iSpecular		R1
#define	iShiftL4		R2
#define iSpecConst		R3
#define iVertCount		R4
#define pNormIn			R5
#define pColorOut		R6
#define pNormalX		R7
#define pNormalY		R8
#define pNormalZ		R9
#define	pSpecOut		R10
#define	iTemp			R11

/*
SmA
Tr
st
tr

3 LdA-4
1 TrA-7
2 SmA-5
3 StA-1
*/

//Step1		TrC_02	StA_00	LdA_03	SpB_01	SmB_01
//Step2		TrA_03	StB_01	LdB_01	SpC_02	SmC_02
//Step3		TrB_04	StC_02	LdC_02	SpA_03	SmA_03

_mLightVertices	.macro	_FTRVVect, _SumVect, _FTRVSpec, _SmX, _SmY, _SmZ, _SmW, _StX, _StY, _StZ, _StW, _ColorAdd, _ExitBranch
												//Step1		TrC_02	StA_00	LdA_03	SpB_01	SmB_01
 			FTRV	XMTRX, _FTRVVect				//	7F	TrC_02
			FLDI1	_SmZ							//	0L					LdA_03+1

 //ftrv2						    							
			SHLL2	iOff							//	1X					LdA_03
			FMOV.S	_StW, @ pColorOut				//	1L			StA_00
 //ftrv3						    							
			DT		iVertCount						//	1X
			FMOV.S	@(iOff, pNormalX), _StY			//	2L					LdA_03
 //ftrv4						    							
			ADD		#_ColorAdd,	pColorOut			//	1X			StA_00
			FMOV.S	@(iOff, pNormalY), _StZ			//	2L					LdA_03

			FIPR	FV12, _SumVect					//	5F									SmB_01
			FMOV.S	@(iOff, pNormalZ), _StW			//	2L					LdA_03

			ADD		#4, pSpecOut					//	1X			StA_00
			MOV.B	@ pNormIn+ , iOff				//	2L					LdA_03

//			NOP
			FMOV.S	_FTRVSpec, @ pSpecOut			//	1L			StA_00
			_ExitBranch
			FLDI1	_SmX							//	0L					LdA_03+1
//			FLOAT	FPUL, _SmX						//	4F					LdA_03+1

			.endm


_mLightVertices2	.macro	_FTRVVect, _SumVect, _SmX, _SmY, _SmZ, _SmW, _StX, _StY, _StZ, _StW, _ExitBranch
												//Step1		TrC_02	StA_00	LdA_03	SpB_01	SmB_01
			FTRV	XMTRX, _FTRVVect				//	7F	TrC_02
			MOV.L	@ pSpecularTemp, iSpecular		//	2L							SpB_01
 //ftrv2						    							
			SHLD	iShiftL4, iOff					//	1X					LdA_03
			FMOV.S	_StW, @ pRGBOut					//	1L			StA_00
 //ftrv3						    							
			DT		iVertCount						//	1X
			FMOV.S	@(iOff, pNormalX), _StY			//	2L					LdA_03
 //ftrv4						    							
			ADD		iSpecConst, iSpecular			//	1X							SpB_01
			FMOV.S	@(iOff, pNormalY), _StZ			//	2L					LdA_03

			FIPR	FV12, _SumVect					//	5F									SmB_01
			FMOV.S	@(iOff, pNormalZ), _StW			//	2L					LdA_03

			SHLD	iShiftL4, iSpecular				//	1X							SpB_01
			FMOV.S	_SmZ, @ pSpecularTemp			//	1L							SpB_01

			MOV.B	@ pNormIn+ , iOff				//	2L					LdA_03
			_ExitBranch

			MOV.L	iSpecular, @ pRGBOut			//	1L			StA_00
			FLOAT	FPUL, _SmX						//	4F					LdA_03+1
			.endm

			FMOV.S	FR15, @-R15
			FMOV.S	FR14, @-R15
			FMOV.S	FR13, @-R15
			FMOV.S	FR12, @-R15
			FMOV.S	FR11, @-R15
			FMOV.S	FR10, @-R15
			FMOV.S	FR9, @-R15
			FMOV.S	FR8, @-R15
			MOV.L	R14, @-R15
			MOV.L	R13, @-R15
			MOV.L	R12, @-R15
			MOV.L	R11, @-R15
			MOV.L	R10, @-R15
			MOV.L	R9, @-R15
			MOV.L	R8, @-R15
			STS.L   PR,@-R15

			// Make sure rounding mode is set to 'round-to-zero' because 'round-to-nearest' give +- infinities
			STS		FPSCR, iOff
			MOV		#0xfffffffc, iTemp
			AND		iTemp, iOff
			OR		#1, iOff
			LDS		iOff, FPSCR
			
			// Calc ptrs to NormalTable X, Y, & Z
			MOV		#256*4/256, iTemp
			SHLL8	iTemp
			MOV		pNormalX, pNormalY
			ADD		iTemp, pNormalY
			MOV		pNormalY, pNormalZ
			ADD		iTemp, pNormalZ

			// Load light constants into regs
			MOV.L	_pLTConstants, iTemp
			FMOV.S	@ iTemp, fVertDX			// SmallFrac
			FMOV.S	@ iTemp, fVertDY			// SmallFrac
			FMOV.S	@ iTemp+, fVertDInvZ		// SmallFrac
			FMOV.S	@ iTemp+, fVertDZ			// ClampOffset
			FMOV.S	@ iTemp, fVertCX			// Ambient
			FADD	fVertCX, fVertDZ			// ClampOffset += Ambient

			MOV		pColorOut, pSpecOut
			MOV		iVertCount, iTemp
			EXTU.W	iVertCount, iVertCount
			SHLR16	iTemp
			SHLL2	iTemp
			ADD		iTemp, pSpecOut
			SHLL2	iTemp
			ADD		iTemp, pColorOut
			MOV		#_kMaxCachedVertices*4*4/256, iTemp
			SHLL8	iTemp
			ADD		iTemp, pSpecOut

//			MOV		#1, iTemp
//			LDS		iTemp, FPUL			

//			TRAPA	#1

			// Prime pump with 1st two normals
			MOV.B	@ pNormIn+ , iOff
			SHLL2	iOff
			FMOV.S	@(iOff, pNormalX), fVertAY			//	2L
			FMOV.S	@(iOff, pNormalY), fVertAZ			//	2L
			FMOV.S	@(iOff, pNormalZ), fVertAInvZ		//	2L
			FLDI1	fVertAX
			FLDI1	fVertBX
			MOV.B	@ pNormIn+ , iOff

			ADD		#-4, pSpecOut
			_mLightVertices	FV0, FV8, fVertAZ, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	0, BT/S LightExitA
			_mLightVertices	FV4, FV0, fVertBZ, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	0, BT/S LightExitB

//			_mLightVertices	FV0, FV8, fVertAZ, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	0, BT/S LightExit
//			_mLightVertices	FV4, FV0, fVertBZ, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	0, BT/S LightExit
//	BRA		LightExit
//	NOP

			BRA		LightStart
			MOV		#0, iTemp

			.align	4
LightExitA:
			FLDI1	fVertAZ							//	0L					LdA_03+1

			FMOV.S	fVertCInvZ, @ pColorOut			//	1L			StA_00

			ADD		#4*4,	pColorOut				//	1X			StA_00

			FIPR	FV12, FV0						//	5F									SmB_01

			BRA		LightExit
			FMOV.S	fVertAInvZ, @ pColorOut			//	1L			StA_00
			
			.align	4
LightExitB:
			FLDI1	fVertBZ							//	0L					LdA_03+1

			FMOV.S	fVertAInvZ, @ pColorOut			//	1L			StA_00

			ADD		#4*4,	pColorOut				//	1X			StA_00

			FIPR	FV12, FV4						//	5F									SmB_01

			BRA		LightExit
			FMOV.S	fVertBInvZ, @ pColorOut			//	1L			StA_00
			
			.align	4
LightLoop:
//Step1		TrC_02	StA_00	LdA_03	SpB_01	SmB_01
//Step2		TrA_03	StB_01	LdB_01	SpC_02	SmC_02
//Step3		TrB_04	StC_02	LdC_02	SpA_03	SmA_03

			_mLightVertices	FV0, FV8, fVertAZ, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	4*4, BT/S LightExitA
			_mLightVertices	FV4, FV0, fVertBZ, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	4*4, BT/S LightExitB
LightStart:
			_mLightVertices	FV8, FV4, fVertCZ, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 		fVertAX, fVertAY, fVertAZ, fVertAInvZ,	4*4, BF/S LightLoop

LightExitC:
			FLDI1	fVertCZ							//	0L					LdA_03+1

			FMOV.S	fVertBInvZ, @ pColorOut			//	1L			StA_00

			ADD		#4*4,	pColorOut				//	1X			StA_00

			FIPR	FV12, FV8						//	5F									SmB_01

			BRA		LightExit
			FMOV.S	fVertCInvZ, @ pColorOut			//	1L			StA_00

			.align	4
LightExit:

			LDS.L  	@R15+, PR
			MOV.L	@R15+, R8
			MOV.L	@R15+, R9
			MOV.L	@R15+, R10
			MOV.L	@R15+, R11
			MOV.L	@R15+, R12
			MOV.L	@R15+, R13
			MOV.L	@R15+, R14
			FMOV.S	@R15+, FR8
			FMOV.S	@R15+, FR9
			FMOV.S	@R15+, FR10
			FMOV.S	@R15+, FR11
			FMOV.S	@R15+, FR12
			FMOV.S	@R15+, FR13
			FMOV.S	@R15+, FR14
			FMOV.S	@R15+, FR15
			RTS						
			NOP

_LTScaleDown:
//			.float	1.1754943508222875e-38
			.LONG	0x00800000,		// SmallFrac. Used to scale zero-limited LargeFrac numbers back to -1.0 to 0.0 range

_LTClampOffset:
			.float	11.999999046325684

			.global	_Ren_fAmbient
_Ren_fAmbient:
			.float	0.2

_pLTConstants:
			.long	_LTScaleDown
			
_Ren_LightVerticesEnd:

#undef	iOff
#undef	iSpecular
#undef	iShiftL4
#undef	iSpecConst
#undef	iVertCount
#undef	pNormIn
#undef pColorOut
#undef	pNormalX
#undef	pNormalY
#undef	pNormalZ
#undef	pSpecOut
#undef	iTemp


// --------------------------------------------------
// 

#if	0
void Ren_ProcessStrips() {};
#endif
			.text
			.align	32
_Ren_ProcessStrips:
			.global	_Ren_ProcessStrips
			.function	"Ren_ProcessStrips", _Ren_ProcessStrips, _Ren_ProcessStripsEnd - _Ren_ProcessStrips

// --------------------------------------------------
// Scratch RAM usage:
// 0x7dfff000	256 structs containing:
// 					float	vertColor
// 					float	screenX
// 					float	screenY
// 					float	inverseZ
// 0x7e000000	float VertSpec[256]
// 0x7e000400	64 Material structs:
// 					char	REAType
// 					char	Brightness Range
// 					char	Alpha Range
// 					char	Specular Range
// 					long	ISP
// 					long	TSP
// 					long	TCW
// 0x7e000800	float VertUV[256]
// 0x7e000C00	256 longs available (matrix stack?)
// 0x7e000fff	Scratch RAM end
// --------------------------------------------------
// 

#define	iOff			R0
#define iTriCount		R1
#define	iSpecular		R2
#define iShiftL4		R3
#define	pStripIn		R4
#define	pMaterialIn		R5
#define	pVertUV			R5
#define	pTAOut			R6
#define	pVertX			R7
#define	pVertY			R8
#define	pVertColor		R9
#define	pVertSpec		R10
#define	iMinSpecular	R11
#define	iTemp1			R12
#define	iTemp2			R13
#define	iTemp3			R14

// --------------------------------------------------
// FP1 Regs
// --------------------------------------------------
// 
#define fCenterX	FR2
#define fCenterY	FR3
#define fAmbient	FR4
#define fSpecBright	FR5
#define fSpecExp	FR6
#define fSpecExpAdd	FR7
#define fVertPCW	FR10
#define fVertX		FR11
#define fVertY		FR12
#define fVertZ		FR13
#define fVertBright	FR14
#define fVertSpec	FR15


_mCullTri	.macro	_LdX1, _LdY1, _LdY2, _SaveOff, _CullBranch, _ExitBranch, _LoopBranch
			FIPR	FV0, FV4						//	5F
			MOV.B	@ pStripIn, iOff				//	2L

 			_CullBranch								//	2B
			FIPR	FV0, FV8						//	5F

			SHAD	iShiftL4, iOff					//	1X
			FMOV	_LdX1, fVertDX					//	0L

			FMOV.S	@(iOff, pVertX), _LdX1			//	2L
			DT		iTriCount						//	1X

			FMOV.S	@(iOff, pVertY), _LdY1			//	2L
			_ExitBranch								//	2B

			FCMP/GT	FR11, FR7						//	4F
			MOV.B	@ iTemp1+, iTemp2				//	2L

			ADD		#1, pStripIn					//	2L
			_LoopBranch								//	2B
			FMOV	_LdY1, _LdY2					//	0L
//			NOP
			.endm

// rts
// mov pTAOut, r0
 
			FMOV.S	FR15, @-R15
			FMOV.S	FR14, @-R15
			FMOV.S	FR13, @-R15
			FMOV.S	FR12, @-R15
			FMOV.S	FR11, @-R15
			FMOV.S	FR10, @-R15
			FMOV.S	FR9, @-R15
			FMOV.S	FR8, @-R15
			MOV.L	R14, @-R15
			MOV.L	R13, @-R15
			MOV.L	R12, @-R15
			MOV.L	R11, @-R15
			MOV.L	R10, @-R15
			MOV.L	R9, @-R15
			MOV.L	R8, @-R15
			STS.L   PR,@-R15

			MOV		#128/32, iOff
			MOV		pStripIn, iTemp1
StripPrefLoop:
			DT		iOff
			PREF	@ iTemp1
			ADD		#32, iTemp1
			BF		StripPrefLoop


			MOV		#0, iSpecular
			MOV		#_kMaxCachedVertices*4/16, iTemp1
			SHLL2	iTemp1
			SHLL2	iTemp1
			SHLL2	iTemp1
			MOV		pVertX, pVertSpec
			ADD		iTemp1, pVertSpec

			MOV		#-128, iTemp1
			SHLL2	iTemp1
			SUB		iTemp1, pVertSpec
			
			SHLL2	iTemp1
			SUB		iTemp1, pVertX
			MOV		pVertX, pVertColor
			MOV		pVertX, pVertY
			ADD		#4, pVertX
			ADD		#8, pVertY

#if 0
			FSCHG
			MOV		pVertSpec, iTemp2
			ADD		iTemp1, iTemp2
			MOV		pStripIn, iTemp1
			MOV		iTemp2, pStripIn
			MOV		#1024/32, iOff
			ADD		#-32, iTemp2
StripTest:
			ADD		#2*32, iTemp2
			FMOV.S	@ iTemp1+, fVertAX
			DT		iOff
			FMOV.S	@ iTemp1+, fVertBX
			FMOV.S	@ iTemp1+, fVertCX
			FMOV.S	@ iTemp1+, fVertDX
			FMOV.S	fVertDX, @-iTemp2
			FMOV.S	fVertCX, @-iTemp2
			FMOV.S	fVertBX, @-iTemp2
			FMOV.S	fVertAX, @-iTemp2
			BF		StripTest
			NOP
			FSCHG
//			BRA		StripExit
#endif

			MOV		#-0x20, iTemp2
			SHLL8	iTemp2
			SHLL16	iTemp2
			MOV.L	iTemp2, @ pTAOut

			MOV.L	_iShadowBase, iTemp3
			
			MOV.L	_iShadowOffset, iTemp2
			
			MOV.L	iTemp3, @(0x28, pTAOut)

			MOV.L	iTemp2, @(0x2c, pTAOut)

			FSCHG
			MOV		#4, iShiftL4

			MOVA	_fCenterX, iOff
			FMOV	@ iOff+, fCenterX
			FMOV	@ iOff+, fAmbient
			FMOV	@ iOff+, fSpecExp

			FSCHG
			MOV.L	_iSpec, iSpecular

			FRCHG
			MOV.L	_fMinSpec, iMinSpecular

			FLDI0	fVertAInvZ
			BRA		StripParse
			ADD		#8, pTAOut						//	1X

			.align	4
StripNewMaterial:
			ADD		iTemp1, iTriCount
			MOV.L	_iMatPCW, iSpecular

			ADD		#-3, pStripIn
			MOV.L	@(12, iTriCount), iTemp3

			MOV.L	@(8, iTriCount), iTemp2

			MOV.L	@(4, iTriCount), iTemp1

#if 0
	MOV.L	StripISP, iTemp1

	MOV.L	StripTSP, iTemp2

	BRA		StripSkip
	NOP
	
			.align	32
StripISP:	.long	0xc0000800
StripTSP	.long	0x209024ed
StripSkip:
#endif
			MOV.L	iTemp3, @(0x0C-8, pTAOut)

			MOV.L	iTemp3, @(0x14-8, pTAOut)

//			MOV		#0, iTemp3
			MOV.L	iTemp2, @ pTAOut

			MOV.L	iTemp2, @(0x10-8, pTAOut)

			MOV.L	iTemp1, @-pTAOut

			MOV.L	iSpecular, @-pTAOut
/*
			MOV.L	iTemp3, @(0x10, pTAOut)

			MOV.L	iTemp3, @(0x14, pTAOut)

			MOV.L	iTemp3, @(0x18, pTAOut)

			MOV.L	iTemp3, @(0x1C, pTAOut)
*/
			MOV		iSpecular, iOff
			MOV		pTAOut, iTemp1

			AND		#0x30, iOff
			PREF	@ iTemp1

			CMP/EQ	#KMY_OBJ_INTENSITY1, iOff

			ADD		#1, iTriCount
			MOV.L	_pCharToFloat, iOff

			ADD		#32, pTAOut						//	1X
			MOV.B	@ iTriCount+, iTemp1

			MOV.B	@ iTriCount+, iTemp2

			SHLL2	iTemp1
			MOV.B	@ iTriCount+, iTemp3

			SHLL2	iTemp2
//			MOV.L	@(iOff, iTemp1), iTemp1
			MOV.L	_fOne, iTemp1

			SHLL2	iTemp3
			MOV.L	@(iOff, iTemp2), iTemp2

			ADD		#-4, iTriCount
			MOV.L	@(iOff, iTemp3), iTemp3

			LDS		iTemp3, FPUL

			BT/S	MatSetIntensities			
			FSTS	FPUL, fSpecBright

			BRA		MatSkipIntensities
			ADD		#-32, pTAOut

MatSetIntensities:


			MOV.L	iTemp2, @ pTAOut

			MOV.L	iTemp1, @(0x04, pTAOut)

			MOV.L	iTemp1, @(0x08, pTAOut)

			MOV.L	iTemp1, @(0x0C, pTAOut)



			MOV.L	iTemp2, @(0x10, pTAOut)

	MOV.L	_fShadowR, iTemp3
			MOV.L	iTemp3, @(0x14, pTAOut)

	MOV.L	_fShadowG, iTemp3
			MOV.L	iTemp3, @(0x18, pTAOut)

	MOV.L	_fShadowB, iTemp3
			MOV.L	iTemp3, @(0x1C, pTAOut)

			MOV		pTAOut, iTemp1
			PREF	@ iTemp1

MatSkipIntensities:
//			MOV.L	_iSpec, iSpecular
//			MOV.L	_fMinSpec, iMinSpecular

			MOVA	Strip_SpecTable, iOff
			MOV		iOff, iTemp2

			MOV.B	@ iTriCount, iOff
			AND		#0xf0, iOff
			SHAR	iOff

			MOV.L	@(iOff, iTemp2), iSpecular
			ADD		#4, iTemp2
			MOV.L	@(iOff, iTemp2), iMinSpecular
			
			MOVA	_fSpecBright, iOff

			FMOV.S	fSpecBright, @ iOff

			MOV.L	iMinSpecular, @(4, iOff)

			MOV.L	iSpecular, @(8, iOff)

			MOV		#-0x20, iTemp2
			SHLL8	iTemp2
			SHLL16	iTemp2
			MOV.L	iTemp2, @(0x20, pTAOut)


			ADD		#32+8, pTAOut						//	1X
			MOV.L	_iShadowBase, iTemp3
			
			MOV.L	_iShadowOffset, iTemp2
			
			FRCHG
			MOV.L	iTemp3, @(0x28-8, pTAOut)

			BRA		StripParse
			MOV.L	iTemp2, @(0x2c-8, pTAOut)

			.align	4
StripEscape:
			CMP/PZ	iTriCount
			MOV		#-128, iTemp1

			FRCHG
			SHLL2	iTemp1

			ADD		pVertUV, iTemp1
			BF/S	StripNewMaterial
			SHAD	iShiftL4, iTriCount

			MOV		pTAOut, iOff
			BRA		StripExit
			ADD		#-8, iOff

						
				.align	32
				.import	_Nrm_anormal
_pCharToFloat:	.long	_Nrm_anormal+(128*4)+0x02000000
_pSpecTable		.long	Strip_SpecTable
_fOne:			.float	1.0

				.align	8
				.global _Ren_MaterialCache
_Ren_MaterialCache:
_iLastMat		.long	0							// Index of last material sent to PowerVR
_iMatPCW:		.long	0//_PCW
_fShadowR: 		.float	.41
_fShadowG: 		.float	.41
_fShadowB:	 	.float	.45
_iShadowBase:	.long	0
_iShadowOffset:	.long	0
				.long	0							// pad
_fMinSpec:		.float	.0045
_iSpec:			.long	0x44780004
_fCenterX:		.float	0//320.0
_fCenterY:		.float	0//240.0
_fAmbient:		.float	0.4
_fSpecBright:	.float	0.075
_fSpecExp:		.float	0.0
_fSpecExpAdd:	.float	0.0

Strip_SpecTable:
				.long	0x00000000	// Exp==1
				.float	.001
				.long	0x60400001	// Exp==2
				.float	.001
				.long	0x50600002	// Exp==4
				.float	.001
				.long	0x48700003	// Exp==8
				.float	.002
				.long	0x44780004	// Exp==16
				.float	.0045
				.long	0x427c0005	// Exp==32
				.float	.07


			.align	4
StripParse:
//			MOV		pTAOut, iTemp1
			MOV.B	@ pStripIn+, iTriCount

//			ADD		#-4, iTemp1
			MOV.B	@ pStripIn+, iOff

CullNext:
			MOV		pStripIn, iTemp1
			
			CMP/PL	iTriCount
/*
			BF		_Skip
			MOV		iOff, iTemp2
			SHAR	iTriCount			// Alters T bit
			BRA	StripToDraw
			ADD		#-1, iTriCount					//	1X
_Skip:
*/
			MOV.B	@ pStripIn+, iTemp2

			// MOV		#1, iTemp3
			// XOR		iTemp3, iTriCount

			SHAD	iShiftL4, iOff
			MOV.B	@ pStripIn+, iTemp3

			BF		StripEscape
			FMOV.S	@(iOff, pVertY), fVertBZ

			SHAD	iShiftL4, iTemp2
			FMOV.S	@(iOff, pVertX), fVertAX

			MOV		iTemp2, iOff
			FMOV	fVertBZ, fVertCY

			SHAR	iTriCount			// Alters T bit
			FMOV.S	@(iOff, pVertY), fVertBX

			SHAD	iShiftL4, iTemp3
			FMOV.S	@(iOff, pVertX), fVertAY

			MOV		iTemp3, iOff
			FMOV	fVertBX, fVertCZ

			ADD		#-1, iTemp1
			FMOV.S	@(iOff, pVertY), fVertBY

			FMOV.S	@(iOff, pVertX), fVertAZ
			BF/S	StripCull0
			FMOV	fVertBY, fVertCX
			BRA		StripCull3
			NOP

			.align	4
CullParse0:

			MOV.B	@ pStripIn+, iTriCount
			BT/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount

			.align	4
CullParse1:
			MOV.B	@ pStripIn+, iTriCount
			BF/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount

			.align	4
CullParse2:
			MOV.B	@ pStripIn+, iTriCount
			BT/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount


			.align	4
CullParse3:
			MOV.B	@ pStripIn+, iTriCount
			BF/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount

			.align	4
CullParse4:
			MOV.B	@ pStripIn+, iTriCount
			BT/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount

			.align	4
CullParse5:
			MOV.B	@ pStripIn+, iTriCount
			BF/S	CullNext
			MOV.B	@ pStripIn+, iOff
			MOV.B	@ iTemp1+, iTemp2				//	2L
			BRA		StripToDraw
			MOV		#0, iTriCount

			.align	4
StripCullLoop:
//			ADD			#1, pStripIn
//			FMOV		fVertBZ, fVertCY
StripCull0:
			_mCullTri	fVertAX, fVertBZ, fVertCY, iTemp2, BT/S StripToDraw, BT/S CullParse0,
StripCull1:
			_mCullTri	fVertAY, fVertBX, fVertCZ, iTemp3, BF/S StripToDraw, BT/S CullParse1,
StripCull2:
			_mCullTri	fVertAZ, fVertBY, fVertCX, iTemp2, BT/S StripToDraw, BT/S CullParse2,
StripCull3:
			_mCullTri	fVertAX, fVertBZ, fVertCY, iTemp3, BF/S StripToDraw, BT/S CullParse3,
StripCull4:
			_mCullTri	fVertAY, fVertBX, fVertCZ, iTemp2, BT/S StripToDraw, BT/S CullParse4,
StripCull5:
			_mCullTri	fVertAZ, fVertBY, fVertCX, iTemp3, BF/S StripToDraw, BT/S CullParse5, BRA StripCullLoop

#if 1
// --------------------------------------------------------------------------------
//
			.align	4
StripToDraw:
			MOV		iTemp1, pStripIn				//	0
			MOV		#-0x20, iTemp3					//	1X
//fVertDX
			MOV		iTemp2, iOff					//	0
			SHLL8	iTemp3							//	1X

			FSCHG
			SHLL2	iOff							//	1X

			SHLL16	iTemp3							//	1X
			MOV.L	@(iOff, pVertSpec), iTemp1		//	2L

			FRCHG
			MOV.L	@(iOff, pVertUV), iShiftL4		//	2L

			SHLL2	iOff							//	1X
			MOV.B	@ pStripIn+, iTemp2				//	2L

			CMP/GT	iMinSpecular, iTemp1
			FMOV.S	@(iOff, pVertColor), fVertBright //	2L

			FMOV	fVertBright, fVertPCW			//	0L
			BF/S	StripSkipSpec0
			FMOV.S	@(iOff, pVertY), fVertY			//	2L

			ADD		iSpecular, iTemp1				//	1X							SpB_01

			SHLD	iSpecular, iTemp1				//	1X							SpB_01

StripSkipSpec0:
			FADD	fCenterX, fVertX				//  3F
			LDS		iTemp1, FPUL					//	1L

			FADD	fCenterY, fVertY				//  3F
			FSTS	FPUL, fVertSpec					//	0L

			ADD		#32-8, pTAOut					//	1X
			FMUL	fSpecBright, fVertSpec			//	4F

			ADD		#2, iTriCount					//	1X
			FMOV.S	fVertBright, @-pTAOut			//	1L

			MOV.L	iShiftL4, @-pTAOut				//	1L

			SHLL2	iTemp2							//	1X
			MOV.L	iShiftL4, @-pTAOut				//	1L

			FMOV.S	fVertY, @-pTAOut				//	1L

			MOV		iTemp2, iOff					//	0
			FMOV.S	fVertPCW, @-pTAOut				//	1L

			MOV.L	iTemp3, @ pTAOut				//	1L
			BRA		StripDraw						//	2B
			MOV.L	iShiftL4, @(0x20, pTAOut)		//	1L


			.align	4
StripDraw:
			MOV		iOff, iTemp2					//	1X
			PREF	@ pTAOut						//	1L

			SHLL2	iTemp2							//	1X
			MOV.L	@(iOff, pVertSpec), iTemp1		//	2L

			ADD		pVertColor, iTemp2				//	1X
			MOV.L	@(iOff, pVertUV), iShiftL4		//	2L

			CMP/GT	iMinSpecular, iTemp1
			FMOV.S	@ iTemp2+, fVertBright			//	2L

			BF/S	StripSkipSpec1
			FMOV.S	@ iTemp2, fVertY				//	2L

			ADD		iSpecular, iTemp1				//	1X							SpB_01

			SHLD	iSpecular, iTemp1				//	1X							SpB_01

StripSkipSpec1:
			FMOV	fVertBright, fVertPCW
			FADD	fCenterX, fVertX				//  3F

			ADD		#32, pTAOut						//	1X
			LDS		iTemp1, FPUL					//	1L

			FSTS	FPUL, fVertSpec					//	0L
			FMUL	fSpecBright, fVertSpec			//	4F

			MOV.L	@(iOff, pVertUV), iTemp2		//	2L

			FADD	fCenterY, fVertY				//  3F
			PREF	@ pTAOut						//	1L

			ADD		#2*32, pTAOut					//	1X
			MOV.B	@ pStripIn+, iOff				//	2L
		
			DT		iTriCount						//	1X
			FMOV.S	fVertBright, @-pTAOut			//	1L

			SHLL2	iOff							//	1X
			MOV.L	iTemp2, @-pTAOut				//	1L

			MOV.L	iShiftL4, @-pTAOut				//	1L

			FMOV.S	fVertY, @-pTAOut				//	1L

			FMOV.S	fVertPCW, @-pTAOut				//	1L
			BT/S	StripDrawDone					//	2B
			MOV.L	iTemp3, @ pTAOut				//	1L

			MOV.L	iShiftL4, @(0x20, pTAOut)		//	1L
			BRA		StripDraw
			MOV.L	iTemp2, @(0x24, pTAOut)			//	1L

			.align	4
StripDrawDone:
			MOV		#-0x10, iTemp2

			SHLL8	iTemp2
			FSCHG

			SHLL16	iTemp2
			MOV.L	iShiftL4, @(0x20, pTAOut)		//	1L

			MOV.L	iTemp2, @ pTAOut				//	1L

			MOV		#4, iShiftL4

			PREF	@ pTAOut
			ADD		#32+8, pTAOut					//	1X

			FRCHG
			ADD		#-1, pStripIn					//	1X
	
			PREF	@ pTAOut
			BRA		StripParse
			ADD		#32, pTAOut						//	1X

#else
// --------------------------------------------------------------------------------
//
			.align	4
StripToDraw:
			ADD		#-4, pStripIn
			MOV		#-0x20, iTemp3					//	1X

			MOV.B	@ pStripIn+, iOff
			SHLL8	iTemp3							//	1X

			FSCHG
			SHLL16	iTemp3							//	1X

			SHLL2	iOff							//	1X
			MOV.L	@(iOff, pVertUV), iShiftL4		//	2L

			ADD		#2, iTriCount					//	1X
			MOV.L	@(iOff, pVertSpec), iTemp1		//	2L

			SHLL2	iOff							//	1X
			MOV.L	iTemp3, @(0x00-8+0x40, pTAOut)	//	1L	// Wrap forward to 1st store Q, since -offset is not allowed by SH4

			FMOV.S	@(iOff, pVertY), fVertBX		//	2L

			CMP/GT	iMinSpecular, iTemp1
			MOV.L	@(iOff, pVertColor), iTemp2		//	2L

			BF/S	StripSkipSpec1
			MOV.B	@ pStripIn+, iOff				//	2L
			ADD		iSpecular, iTemp1				//	1X							SpB_01

			SHLD	iSpecular, iTemp1				//	1X							SpB_01

			LDS		iTemp1, FPUL					//	1L

			FSTS	FPUL, fVertDY					//	0L

			FMUL	fVertDX, fVertDY				//	4F

			FLDS	fVertDY, FPUL					//	0L

			STS		FPUL, iTemp1					//	1L

StripSkipSpec1:
			MOV.L	iTemp2, @(0x18-8, pTAOut)		//	1L

			FMOV.S	fVertBX, @ pTAOut				//	1L

			MOV.L	iShiftL4, @(0x10-8, pTAOut)		//	1L

			SHLL2	iOff							//	1X
			MOV.L	iTemp1, @(0x1c-8, pTAOut)		//	1L

			BRA		StripDraw						//	2B
			MOV.L	iShiftL4, @(0x20-8, pTAOut)		//	1L

			.align	4
StripDraw:
			MOV		iOff, iTemp3					//	1X
			PREF	@ pTAOut						//	1L

			SHLL2	iTemp3							//	1X
			MOV.L	@(iOff, pVertUV), iShiftL4		//	2L

			ADD		pVertY, iTemp3					//	1X
			MOV.L	@(iOff, pVertSpec), iTemp1		//	2L

			SHLL2	iOff							//	1X
			FMOV.S	@ iTemp3, fVertBX				//	2L

			CMP/GT	iMinSpecular, iTemp1
			MOV.L	@(iOff, pVertX), iTemp2			//	2L

			MOV.L	@(iOff, pVertColor), iTemp3		//	2L
			BF/S	StripNoSpecular					//	2B
			MOV.B	@ pStripIn+, iOff				//	2L
			ADD		iSpecular, iTemp1				//	1X							SpB_01

#if 1
			NOP
			NOP
			
			NOP
			NOP
#endif
	ADD		#32-8, pTAOut					//	1X
	PREF	@ pTAOut						//	1L
//			SHLD	iSpecular, iTemp1				//	1X							SpB_01

//			ADD		#32-8, pTAOut					//	1X
			LDS		iTemp1, FPUL					//	1L

			FSTS	FPUL, fVertDY					//	0L

			FMUL	fVertDX, fVertDY				//	4F
//			PREF	@ pTAOut						//	1L

			DT		iTriCount						//	1X
			MOV.L	iTemp2, @(0x04+32, pTAOut)		//	1L

			MOV.L	iTemp3, @(0x18+32, pTAOut)		//	1L

			MOV.L	iShiftL4, @(0x10+32, pTAOut)	//	1L

			FLDS	fVertDY, FPUL					//	0L
			BT/S	StripDrawDone					//	2B
			STS		FPUL, iTemp1					//	1L
			ADD		#32+8, pTAOut					//	1X

			SHLL2	iOff							//	1X
			MOV.L	iTemp1, @(0x1c-8, pTAOut)		//	1L

#if 1
			NOP
			NOP
			
			NOP
			NOP
			
#endif
			FMOV.S	fVertBX, @ pTAOut				//	1L
			BRA		StripDraw
			MOV.L	iShiftL4, @(0x20-8, pTAOut)		//	1L

			.align	4
StripNoSpecular:
#if 1
			NOP
			NOP
			
			NOP
			NOP
			
#endif
			ADD		#32-8, pTAOut					//	1X

			PREF	@ pTAOut						//	1L
		
			DT		iTriCount						//	1X
			MOV.L	iTemp2, @(0x04+32, pTAOut)		//	1L

			MOV.L	iTemp3, @(0x18+32, pTAOut)		//	1L
			BT/S	StripDrawDone					//	2B
			MOV.L	iShiftL4, @(0x10+32, pTAOut)	//	1L
			ADD		#32+8, pTAOut					//	1X

			SHLL2	iOff							//	1X
			MOV.L	iTemp1, @(0x1c-8, pTAOut)		//	1L

			FMOV.S	fVertBX, @ pTAOut				//	1L
#if 1
			NOP

			NOP
			NOP
			
			NOP
			NOP
			
			NOP
			NOP
			
			NOP
			NOP
			
			NOP
#endif
			BRA		StripDraw
			MOV.L	iShiftL4, @(0x20-8, pTAOut)		//	1L

			.align	4
StripDrawDone:
			MOV		#-0x10, iTemp2
			MOV.L	iTemp1, @(0x1c+32, pTAOut)		//	1L

			ADD		#32+8, pTAOut					//	1X

			SHLL8	iTemp2
			FMOV.S	fVertBX, @ pTAOut				//	1L

			SHLL16	iTemp2
			FSCHG

			MOV.L	iShiftL4, @(0x20-8, pTAOut)		//	1L

			MOV.L	iTemp2, @(0x00-8+0x40, pTAOut)	//	1L	// Wrap forward to 1st store Q, since -ve offset is illegal

			MOV		pTAOut, iTemp2					//	1X
			MOV		#4, iShiftL4

			PREF	@ iTemp2
			ADD		#32, pTAOut						//	1X

			MOV		pTAOut, iTemp3					//	1X
			ADD		#-1, pStripIn					//	1X
	
			PREF	@ iTemp3
			BRA		StripParse
			ADD		#32, pTAOut						//	1X

// --------------------------------------------------------------------------------
//
#endif


			.align	4
StripExit:
			LDS.L  	@R15+, PR
			MOV.L	@R15+, R8
			MOV.L	@R15+, R9
			MOV.L	@R15+, R10
			MOV.L	@R15+, R11
			MOV.L	@R15+, R12
			MOV.L	@R15+, R13
			MOV.L	@R15+, R14
			FMOV.S	@R15+, FR8
			FMOV.S	@R15+, FR9
			FMOV.S	@R15+, FR10
			FMOV.S	@R15+, FR11
			FMOV.S	@R15+, FR12
			FMOV.S	@R15+, FR13
			FMOV.S	@R15+, FR14
			FMOV.S	@R15+, FR15
			RTS						
			NOP
_Ren_ProcessStripsEnd:

#undef	iOff
#undef	iTriCount
#undef	iSpecular
#undef	iShiftL4
#undef	pStripIn
#undef	pMaterialIn
#undef	pVertUV
#undef	pTAOut
#undef	pVertX
#undef	pVertY
#undef	iStripEnd
#undef	pVertColor
#undef	pVertSpec
#undef	iMinSpecular
#undef	iTemp1
#undef	iTemp2
#undef	iTemp3

// --------------------------------------------------
// 
#if 1


#if	0
void Ren_DrawShadow() {};
#endif
			.text
			.align	32
_Ren_DrawShadow:
			.global	_Ren_DrawShadow
			.function	"Ren_DrawShadow", _Ren_DrawShadow, _Ren_DrawShadowEnd - _Ren_DrawShadow

// --------------------------------------------------
// Scratch RAM usage:
// 0x7dfff000	256 structs containing:
// 					float	vertColor
// 					float	screenX
// 					float	screenY
// 					float	inverseZ
// 0x7e000000	float VertSpec[256]
// 0x7e000400	64 Material structs:
// 					char	REAType
// 					char	Brightness Range
// 					char	Alpha Range
// 					char	Specular Range
// 					long	ISP
// 					long	TSP
// 					long	TCW
// 0x7e000800	float VertUV[256]
// 0x7e000C00	256 longs available (matrix stack?)
// 0x7e000fff	Scratch RAM end
// --------------------------------------------------
// 

#define	iOff			R0
#define	iAmbient		R1
#define	iTemp1			R2
#define	iTemp2			R3
#define	pStripIn		R4
#define	pTAOut			R5
#define	pVertX			R6
#define	pShadowVert		R7
#define iTriCount		R8
#define	iVertAX			R9
#define	iVertAY			R10
#define	iVertAZ			R11
#define	iVertBX			R12
#define	iVertBY			R13
#define	iVertBZ			R14


			FMOV.S	FR15, @-R15
			FMOV.S	FR14, @-R15
			FMOV.S	FR13, @-R15
			FMOV.S	FR12, @-R15
			FMOV.S	FR11, @-R15
			FMOV.S	FR10, @-R15
			FMOV.S	FR9, @-R15
			FMOV.S	FR8, @-R15
			MOV.L	R14, @-R15
			MOV.L	R13, @-R15
			MOV.L	R12, @-R15
			MOV.L	R11, @-R15
			MOV.L	R10, @-R15
			MOV.L	R9, @-R15
			MOV.L	R8, @-R15
			STS.L   PR,@-R15

			MOV.L	@ pShadowVert+, iAmbient
			
			MOV		#128*16/256, iOff
			SHLL8	iOff
			ADD		iOff, pVertX
			
			MOV		#0xfffffff0, iTemp1
			SHLL8	iTemp1
			SHLL16	iTemp1
			MOV.L	iTemp1, @ pTAOut
			
			MOV.B	@ pStripIn+, iTriCount
			BRA		ShadowParse
			MOV.B	@ pStripIn+, iOff

			.align	4
ShadowEscape:
			CMP/PZ	iTriCount
			ADD		#-1, pStripIn

			MOV.B	@ pStripIn+, iTriCount
			BF/S	ShadowParse
			MOV.B	@ pStripIn+, iOff

			BRA		ShadowExit
			MOV		pTAOut, iOff

			.align	4
ShadowParse:

			CMP/PL	iTriCount
			SHLL2	iOff

			BF		ShadowEscape
			SHLL2	iOff

			SHAR	iTriCount			// Alters T bit
			ADD		pVertX, iOff 

			BF/S	StartShadowCW
			MOV.L	@ iOff+, iTemp1
			CMP/GT	iAmbient, iTemp1
			
			MOV.B	@ pStripIn+, iTemp1
			BT		StartShadowCCW1

			MOV		pShadowVert, iOff

StartShadowCCW1:
			MOV.L	@ iOff+, iVertBX
			SHLL2	iTemp1

			MOV.L	@ iOff+, iVertBY
			SHLL2	iTemp1

			MOV.L	@ iOff+, iVertBZ
			ADD		pVertX, iTemp1


			MOV.L	@ iTemp1+, iOff
			CMP/GT	iAmbient, iOff
			BT		StartShadowCCW2

			MOV		pShadowVert, iTemp1

StartShadowCCW2:
			MOV.B	@ pStripIn+, iOff

			MOV.L	@ iTemp1+, iVertAX

			SHLL2	iOff
			MOV.L	@ iTemp1+, iVertAY

			SHLL2	iOff
			MOV.L	@ iTemp1+, iVertAZ

			ADD		pVertX, iOff
			MOV.L	iVertAX, @(0x10, pTAOut)

			MOV.L	@ iOff+, iTemp1

			MOV.L	iVertAY, @(0x14, pTAOut)

			CMP/GT	iAmbient, iTemp1
			MOV.L	iVertAZ, @(0x18, pTAOut)

			BT/S	DrawShadowCCW
			ADD		#-32, pTAOut

			BRA		DrawShadowCCW
// NOP
			MOV		pShadowVert, iTemp1


StartShadowCW:
			CMP/GT	iAmbient, iTemp1
			MOV.B	@ pStripIn+, iTemp1
			BT		StartShadowCW1

			MOV		pShadowVert, iOff

StartShadowCW1:

			MOV.L	@ iOff+, iVertAX
			SHLL2	iTemp1

			MOV.L	@ iOff+, iVertAY
			SHLL2	iTemp1

			MOV.L	@ iOff+, iVertAZ
			ADD		pVertX, iTemp1


			MOV.L	@ iTemp1+, iOff
			CMP/GT	iAmbient, iOff
			BT		StartShadowCW2

			MOV		pShadowVert, iTemp1

StartShadowCW2:
			MOV.B	@ pStripIn+, iOff

			MOV.L	@ iTemp1+, iVertBX

			SHLL2	iOff
			MOV.L	@ iTemp1+, iVertBY

			SHLL2	iOff
			MOV.L	@ iTemp1+, iVertBZ


			ADD		pVertX, iOff
			MOV.L	iVertBX, @(0x1c, pTAOut)

			MOV.L	@ iOff+, iTemp1

			MOV.L	iVertBY, @(0x20, pTAOut)

			CMP/GT	iAmbient, iTemp1
			MOV.L	iVertBZ, @(0x24, pTAOut)

			BT/S	DrawShadowCW
			ADD		#-32, pTAOut

			BRA		DrawShadowCW
// NOP
			MOV		pShadowVert, iTemp1

			.align	4
DrawShadowCCW:
			ADD		#32, pTAOut						//	1X
			MOV.B	@ pStripIn+, iTemp1				//	2L
			

			MOV.L	iVertBX, @(0x04, pTAOut)		//	1L

			SHLL2	iTemp1							//	1X
			MOV.L	iVertBY, @(0x08, pTAOut)		//	1L

			SHLL2	iTemp1							//	1X
			MOV.L	iVertBZ, @(0x0C, pTAOut)		//	1L

			ADD		pVertX, iTemp1					//	1X
			MOV.L	@ iOff+, iVertBX				//	2L


			MOV.L	@ iTemp1+, iTemp2				//	2L


			MOV.L	@ iOff+, iVertBY				//	2L

			CMP/GT	iAmbient, iTemp2
			MOV.L	@ iOff+, iVertBZ				//	2L

			MOV		pTAOut, iTemp2					//	1X
			MOV.L	iVertBX, @(0x1C, pTAOut)		//	1L

			PREF	@ iTemp2						//	1L
			BT/S	ShadowLitCCW					//	2B
			MOV		iTemp1, iOff					//	1X

			MOV		pShadowVert, iOff

ShadowLitCCW:				
			ADD		#32, pTAOut						//	1X

			MOV.L	iVertBY, @(0x20-32, pTAOut)		//	1L

			DT		iTriCount						//	1X
			MOV.L	iVertBZ, @(0x24-32, pTAOut)		//	1L

			MOV		pTAOut, iTemp2					//	1X
			BF/S	DrawShadowCW
			PREF	@ iTemp2						//	1L

			ADD		#32, pTAOut						//	1X
			ADD		#-1, pStripIn

			MOV.B	@ pStripIn+, iTriCount
			BRA		ShadowParse
//			BRA		ShadowExit
			MOV.B	@ pStripIn+, iOff


			.align	4
DrawShadowCW:
			ADD		#32, pTAOut						//	1X
			MOV.B	@ pStripIn+, iTemp1				//	2L

			MOV.L	iVertAX, @(0x04, pTAOut)		//	1L

			SHLL2	iTemp1							//	1X
			MOV.L	iVertAY, @(0x08, pTAOut)		//	1L

			SHLL2	iTemp1							//	1X
			MOV.L	iVertAZ, @(0x0C, pTAOut)		//	1L

			ADD		pVertX, iTemp1					//	1X
			MOV.L	@ iOff+, iVertAX				//	2L

			MOV.L	@ iOff+, iVertAY				//	2L

			MOV.L	@ iOff+, iVertAZ				//	2L

			MOV.L	iVertAX, @(0x10, pTAOut)		//	1L

			MOV		iTemp1, iOff					//	1X
			MOV.L	iVertAY, @(0x14, pTAOut)		//	1L

			MOV		pTAOut, iTemp2					//	1X
			MOV.L	iVertAZ, @(0x18, pTAOut)		//	1L

			PREF	@ iTemp2						//	1L


			MOV.L	@ iOff+, iTemp1					//	2L

			ADD		#32, pTAOut						//	1X

			CMP/GT	iAmbient, iTemp1

			BT		ShadowLitCW						//	2B

			MOV		pShadowVert, iOff

ShadowLitCW:				
			DT		iTriCount						//	1X

			MOV		pTAOut, iTemp2					//	1X
			BF/S	DrawShadowCCW
			PREF	@ iTemp2						//	1L

			ADD		#32, pTAOut						//	1X
			ADD		#-1, pStripIn

			MOV.B	@ pStripIn+, iTriCount
			BRA		ShadowParse
//			BRA		ShadowExit
			MOV.B	@ pStripIn+, iOff


			.align	4
ShadowExit:
			LDS.L  	@R15+, PR
			MOV.L	@R15+, R8
			MOV.L	@R15+, R9
			MOV.L	@R15+, R10
			MOV.L	@R15+, R11
			MOV.L	@R15+, R12
			MOV.L	@R15+, R13
			MOV.L	@R15+, R14
			FMOV.S	@R15+, FR8
			FMOV.S	@R15+, FR9
			FMOV.S	@R15+, FR10
			FMOV.S	@R15+, FR11
			FMOV.S	@R15+, FR12
			FMOV.S	@R15+, FR13
			FMOV.S	@R15+, FR14
			FMOV.S	@R15+, FR15
			RTS						
			NOP
_Ren_DrawShadowEnd:

#undef	iOff
#undef	iSpecular
#undef	iVertCount
#undef	pNormIn
#undef	pRGBOut
#undef	pNormalX
#undef	pNormalY
#undef	pNormalZ
#undef	pSpecularTemp
#endif
// --------------------------------------------------------------------------------
//
#if	0
void _Ren_LoadMatrix()
#endif

#if 0
#define	a_pMatrix	(R4)

			.text
			.align	32
_Ren_LoadMatrix:
			.global	_Ren_LoadMatrix
			.function	"Ren_LoadMatrix", _Ren_LoadMatrix, _Ren_LoadMatrixEnd - _Ren_LoadMatrix

			.align	32
			.global	_Ren_LoadMatrix
		
			FRCHG
			FSCHG
			FMOV.S	@a_pMatrix+, FR0
			FMOV.S	@a_pMatrix+, FR2
			FMOV.S	@a_pMatrix+, FR4
			FMOV.S	@a_pMatrix+, FR6
			FMOV.S	@a_pMatrix+, FR8
			FMOV.S	@a_pMatrix+, FR10
			FMOV.S	@a_pMatrix+, FR12
			FMOV.S	@a_pMatrix+, FR14
			FSCHG
			RTS
			FRCHG
_Ren_LoadMatrixEnd:
#undef	a_pMatrix
#endif


// --------------------------------------------------------------------------------
//
#if	0
void _Ren_LoadMaterials( Ren_tMaterial *a_paMaterials, si a_siNumMaterials, si a_siDestMaterial, float *a_pfVertPool)
{};
#endif

#define	iTemp				R0
#define	pPrefetch			R1
#define	a_paMaterials		R4
#define	a_siNumMaterials	R5
#define	a_siDestMaterial	R6
#define	a_pfVertPool		R7

			.text
			.align	32
_Ren_LoadMaterials:
			.global	_Ren_LoadMaterials
			.function	"_Ren_LoadMaterials", _Ren_LoadMaterials, _Ren_LoadMaterialsEnd - _Ren_LoadMaterials

			.align	32
			.global	_Ren_LoadMaterials
		
			FSCHG
			MOV		a_paMaterials, pPrefetch
			MOV		a_siNumMaterials, iTemp
			SHLR2	iTemp
			ADD		#1, iTemp
MatPrefLoop:
			DT		iTemp
			PREF	@ pPrefetch
			BF/S	MatPrefLoop
			ADD		#32, pPrefetch

			ADD 	#1, a_siDestMaterial
			FMOV.S	@ a_paMaterials+, FR0
			FMOV.S	@ a_paMaterials+, FR2

			SHLL2 	a_siDestMaterial
			SHLL2 	a_siDestMaterial
			MOV		#4, iTemp
			SHLL8	iTemp
			ADD		iTemp, a_pfVertPool				// VertPool += 0x400

			BRA		MatLoadLoop
			ADD		a_siDestMaterial, a_pfVertPool	// VertPool -= a_siDestMaterial * sizeof(Ren_tMaterial) /* 16 */

			.align	4
MatLoadLoop:
			DT		a_siNumMaterials
			FMOV.S	@ a_paMaterials+, FR4
			FMOV.S	@ a_paMaterials+, FR6
			FMOV.S	FR2, @-a_pfVertPool
			BT/S	MatExit
			FMOV.S	FR0, @-a_pfVertPool

			DT		a_siNumMaterials
			FMOV.S	@ a_paMaterials+, FR0
			FMOV.S	@ a_paMaterials+, FR2
			FMOV.S	FR6, @-a_pfVertPool
			BF/S	MatLoadLoop
			FMOV.S	FR4, @-a_pfVertPool

MatExit:
			RTS
			FSCHG
_Ren_LoadMaterialsEnd:
#undef	iTemp
#undef	pPrefetch
#undef	a_paMaterials
#undef	a_siNumMaterials
#undef	a_siDestMaterial
#undef	a_pfVertPool


//;*****************************************************************************
//;
//; void VCCPU_SplitCache(void)
//;
//;*****************************************************************************
#if	0
void __VCCPU_SplitCache() {};
#endif

	.align	32
	.global	__VCCPU_SplitCache

#if 1

__VCCPU_SplitCache:

	stc	sr,r7
	mov.l	L200,r1
	stc	sr,r0
	or	r1,r0
	ldc	r0,sr	//; set block bit

	mov.l	L201,r5	//; r5 = OC address array
	mov	#0xfffffffc,r2
	mov.l	L202,r6	//; r6 = SH4 CCR address
	shll8	r2	//; r2 = cache line tag mask

	mov	#128*3/4,r3
	shll2	r3	//; r3 = loop counter (384 lines)
	.align	4
L220:
	mov.l	@r5,r0	//; read OC address array entry
	not	r2,r1	//; copy line mask
	and	r2,r0	//; mask tag from address array entry
	and	r5,r1	//; mask index from cache line
	add	#0x20,r5	//; next OC address array entry
	or	r0,r1	//; r1 = constructed address
	dt	r3
	bf/s	L220
	ocbp	@r1	//; purge the line

	mov.l	@r6,r0
	or	#0x20+0x80,r0	//; cache RAM enable bit + index mode
	mov.l	r0,@r6

	ldc	r7,sr
	rts
	nop

	.align	4
L200:	.long	0x100000f0	; block bit
L201:	.long	0xf4001000	; non-associative, line 128
L202:	.long	0xff00001c	; SH4 CCR cache control register

#else
__VCCPU_SplitCache:

	stc	sr,r7
	mov.l	L200,r1
	stc	sr,r0
	or	r1,r0
	ldc	r0,sr	//; set block bit

	mov.l	L201,r5	//; r5 = OC address array
	mov	#0xfffffffc,r2
	mov.l	L202,r6	//; r6 = SH4 CCR address
	shll8	r2	//; r2 = cache line tag mask

	mov	#0xffffff80,r3
	extu.b	r3,r3	//; r3 = loop counter (128 lines)
	.align	4
L220:
	mov.l	@r5,r0	//; read OC address array entry
	not	r2,r1	//; copy line mask
	and	r2,r0	//; mask tag from address array entry
	and	r5,r1	//; mask index from cache line
	add	#0x20,r5	//; next OC address array entry
	or	r0,r1	//; r1 = constructed address
	dt	r3
	bf/s	L220
	ocbp	@r1	//; purge the line

	mov	#0x10,r0
	shll8	r0
	add	r0,r5	//; increment OC address array pointer to lines 384-511
	mov	#0xffffff80,r3
	extu.b	r3,r3	//; r3 = loop counter (128 lines)
	.align	4
L230:
	mov.l	@r5,r0	//; read OC address array entry
	not	r2,r1	//; copy line mask
	and	r2,r0	//; mask tag from address array entry
	and	r5,r1	//; mask index from cache line
	add	#0x20,r5	//; next OC address array entry
	or	r0,r1	//; r1 = constructed address
	dt	r3
	bf/s	L230
	ocbp	@r1	//; purge the line

	mov.l	@r6,r0
	or	#0x20+0x80,r0	//; cache RAM enable bit + index mode
	mov.l	r0,@r6

	ldc	r7,sr
	rts
	nop

	.align	4
L200:	.long	0x100000f0	; block bit
L201:	.long	0xf4001000	; non-associative, lines 128-255
L202:	.long	0xff00001c	; SH4 CCR cache control register
#endif

//;*****************************************************************************
//;
//; void VCCPU_UnsplitCache(void)
//;
//;*****************************************************************************
#if	0
void __VCCPU_UnsplitCache() {};
#endif

	.align	32
	.global	__VCCPU_UnsplitCache

__VCCPU_UnsplitCache:

	stc	sr,r7
	mov.l	L300,r1
	stc	sr,r0
	or	r1,r0
	ldc	r0,sr	//; set block bit

	mov.l	L301,r5	//; r5 = OC address array
	mov	#0xfffffffc,r2
	mov.l	L302,r6	//; r6 = SH4 CCR address
	shll8	r2	//; r2 = cache line tag mask
	mov.w	L303,r4	//; r4 = criteria mask

	mov	#0xffffff80,r3
	extu.b	r3,r3	//; r3 = loop counter (128 lines)
	.align	4
L320:
	mov.l	@r5,r0	//; read OC address array entry
	and	r4,r0	//; mask criteria bits
	cmp/eq	r4,r0	//; match?
	bf	L320b

	mov.l	@r5,r0	//; read OC address array entry
	not	r2,r1	//; copy line mask
	and	r2,r0	//; mask tag from address array entry
	and	r5,r1	//; mask index from cache line
	or	r0,r1	//; r1 = constructed address
	ocbp	@r1	//; purge the line
L320b:
	dt	r3
	bf	L320
	add	#0x20,r5	//; next OC address array entry

	mov	#0x10,r0
	shll8	r0
	add	r0,r5	//; increment OC address array pointer to lines 384-511
	mov	#0xffffff80,r3
	extu.b	r3,r3	//; r3 = loop counter (128 lines)
	.align	4
L330:
	mov.l	@r5,r0	//; read OC address array entry
	and	r4,r0	//; mask criteria bits
	cmp/eq	r4,r0	//; match?
	bf	L330b

	mov.l	@r5,r0	//; read OC address array entry
	not	r2,r1	//; copy line mask
	and	r2,r0	//; mask tag from address array entry
	and	r5,r1	//; mask index from cache line
	or	r0,r1	//; r1 = constructed address
	ocbp	@r1	//; purge the line
L330b:
	dt	r3
	bf	L330
	add	#0x20,r5	//; next OC address array entry

	mov.l	@r6,r0
	mov	#-33,r1
	and	r1,r0	//; cache RAM enable bit
	mov.l	r0,@r6

	ldc	r7,sr
	rts
	nop

L303:	.word	0x1001	//; lines that need to be purged
	.align	4
L300:	.long	0x100000f0	//; block bit
L301:	.long	0xf4000000	//; non-associative, lines 0-127
L302:	.long	0xff00001c	//; SH4 CCR cache control register


// --------------------------------------------------


