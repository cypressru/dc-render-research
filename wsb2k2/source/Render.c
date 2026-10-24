// --------------------------------------------------------------------------------
// $Id: Render.c,v 1.88 2000/11/17 23:42:31 jbrooks Exp $
// --------------------------------------------------------------------------------
// Render.c - Transform, light, & render 3D objects and worlds
//
// Created 3/5/00 by JBrooks
//
// Copyright (c) 2000 Blue Shift, Inc., All Rights Reserved
// --------------------------------------------------------------------------------
//

// --------------------------------------------------------------------------------
// Includes
// --------------------------------------------------------------------------------
//
#include	"Render.h"
#include	"kamui2.h"				/* for Kamui Call */
#include	"dispstr.h"				/* for DisplayString */
#include	"Kmstool.h"
#include	"NormalTable.h"
// #include    "game.h"
#include    "xyz.h"
#include    "trig.h"
#include    "mstack.h"
#include	"databody.h"
#include	"texture.h"
#include	"Game.h"
#include	"PFData.h"
#include	"Profile.h"
#include	"Draw.h"

#include <string.h>    /* Shinobi system routines. */

//#define Ren_ProcessStrips(a,b,c,d)	c
//#define Ren_LightVertices if (0) Ren_LightVertices
//#define Ren_TransformVertices if(0) Ren_TransformVertices
//#define Ren_TransformFloatVertices(a,b,c) a

// --------------------------------------------------------------------------------
// Defines
// --------------------------------------------------------------------------------
//
#define _CULL_SEGMENT_DISTANCE	(2.5)
#define	_kVertexCount	(152)
//#define	_kVertexCount	(256)
#define	_kCoordBytes	(_kVertexCount * 3)
//#define	_kCoordBytes	(256/*_kVertexCount*/ * 3)
#define	_kNormBytes		(_kVertexCount)
#define	_kKeyframeSize	(_kCoordBytes + _kNormBytes)
//#define	_kKeyframeSize	(256*4)//_kCoordBytes + _kNormBytes)

//#define	_mLdByteInc( a_ps8Src, a_ps8Dst) { register si iResult=0; register void *pSrc=a_ps8Src; asm { mov.b @pSrc+, iResult}; *(a_ps8Dst) = iResult;a_ps8Src = pSrc;}
//#define	_mLdFloatInc( a_pf32Src, a_pf32Dst) { register f32 fResult=0; register void *pSrc=a_pf32Src; asm { fmov.s @pSrc+, fResult}; *(a_pf32Dst) = fResult;a_pf32Src = pSrc;}

#ifdef  __MWERKS__
#pragma align (32)
#endif

// --------------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------------
//


// --------------------------------------------------------------------------------
// Global Variables
// --------------------------------------------------------------------------------
//

// --------------------------------------------------------------------------------
// Local Variables
// --------------------------------------------------------------------------------
//

static float *_pfOnChipRAM = (float *)0x7dfff000;

// static Ren_tRender *_pActiveRender;

static float _IdentMatrix[4][4] =
{
	{1.0, 0.0, 0.0, 0.0},
  	{0.0, 1.0, 0.0, 0.0},
  	{0.0, 0.0, 1.0, 0.0},
  	{0.0, 0.0, 0.0, 1.0}
};

View_tView gView; // for now global since fieldofview used as camera parameter

static float _ProjMatrix[4][4] =
{
//	X				Y				Z
  	{600.0,			0.0,			0.0,		0.0},
  	{0.0,			-600.0,			0.0,		0.0},
	{320.0,			400.0,			1.0,		0.0},
  	{320.0*1000,	400.0*1000,		600.0,		1.0}
};

static Matrix4x4_tMatrix _LightMatrix =
{
	Ren_kLightMaxNeg, 	Ren_kLightMaxNeg, 	0.0,	Ren_kLightMaxNeg,
  	0.0, 	0.0, 	0.0, 	0.0,
  	0.0, 	0.0, 	0.0, 	0.0,
  	0.0, 	0.0, 	0.0, 	-0.5 * Ren_kLightScaleUp,
};

#if 1
static int _aiLightConstants[5] =
{
	0x7e800000,		// LargeFrac. Largest # a -1.0 to +1.0 float can be scaled up by and later still be scaled down with a reciprocal multiply by SmallFrac (1.0/(SmallFrac==0x00800000))
	0xff7fffff,		// MaxNeg. Subtracted from cos result to zero-limit light angles.
	0x00800000,		// SmallFrac. Used to scale zero-limited LargeFrac numbers back to -1.0 to 0.0 range
	0x413fffff,		// 3*-MaxNeg*smallfrac. Used to move zero-limited fracs back to 0.0 to 1.0 range for sum of 3 dir lights
	0x407fffff,		// -MaxNeg*smallfrac. Used to move zero-limited fracs back to 0.0 to 1.0 range
};
static float *_pfLightConstants = (float *)&_aiLightConstants[0];
#else
static float _afLightConstants[] =
{
	8.5070581730234616e37,		// LargeFrac. Largest # a -1.0 to +1.0 float can be scaled up by and later still be scaled down with a reciprocal multiply by SmallFrac (1.0/(SmallFrac==0x00800000))
	-3.408234664863886e38,		// MaxNeg. Subtracted from cos result to zero-limit light angles.
	1.1754943508222875e-38,		// SmallFrac. Used to scale zero-limited LargeFrac numbers back to -1.0 to 0.0 range
	3*3.9999997815814208e00,	// 3*-MaxNeg*smallfrac. Used to move zero-limited fracs back to 0.0 to 1.0 range for sum of 3 dir lights
	3.9999997815814208e00,		// -MaxNeg*smallfrac. Used to move zero-limited fracs back to 0.0 to 1.0 range
};
#endif

static struct _view_parms {
	float f_zoom_scale;
	float f_scale;
	float f_scale_x;
	float f_scale_y;
	float f_scale_z;
	float f_center_x;
	float f_center_y;
	float f_projection_plane_distance;
	float   rot_x;
	float   rot_y;
	float   rot_z;
	int   apply_local;
	float rot_y_delta;
} s_view_parameters = {
	0.2f, // float f_zoom_scale
	1.0f, // float f_scale
	1.0f, // float f_scale_x
	1.0f, // f_scale_y
	1.0f, // f_scale_z
	320.0f, // float f_center_x
	240.0f, // float f_center_y
	600.0f, // float f_projection_plane_distance
	0.0f, // float   rot_x
	0.0f, // float   rot_y
	0.0f, // float   rot_z
	1, // int   apply_local
	0.0f // float rot_y_delta
};

static Matrix4x4_tMatrix s_ProjMatrix =
{
//	X				Y				Z
  	0.0,			0.0,			0.0,		0.0,
  	0.0,			0.0,			0.0,		0.0,
	0.0,			0.0,			0.0,		0.0,
  	0.0f,			0.0f,		    0.0,		1.0
};

#ifdef  __MWERKS__
#pragma align (8)
#endif
static Matrix4x4_tMatrix _MatrixBuffer[Mstack_MAX_DEPTH][4];
static Matrix4x4_tMatrix _LightMatrixBuffer[Mstack_MAX_DEPTH][4];
static Matrix4x4_tMatrix _JointWeightMatrixBuffer[Mstack_MAX_DEPTH][4];

// --------------------------------------------------------------------------------
// Prototypes
// --------------------------------------------------------------------------------
//
extern s8 RamVertices[];
extern s8 Ram0Strips[];
extern s8 Ram0Tris[];
extern s8 Ram1Strips[];

// --------------------------------------------------------------------------------
// Inlines
// --------------------------------------------------------------------------------
//
#define _StFloatDec(a_pSrc, a_fValue)	asm	{	fmov.s	a_fValue, @-a_pSrc }
#define _StByteDec(a_pSrc, a_iValue)	asm	{	mov.b	a_iValue, @-a_pSrc }
#define _StShortDec(a_pSrc, a_iValue)	asm	{	mov.w	a_iValue, @-a_pSrc }
#define _StLongDec(a_pSrc, a_iValue)	asm	{	mov.l	a_iValue, @-a_pSrc }
#define _LdFloatInc(a_pSrc, a_fValue)	asm	{	fmov.s	@a_pSrc+, a_fValue }
#define _LdByteInc(a_pSrc, a_iValue)	asm	{	mov.b	@a_pSrc+, a_iValue }
#define _LdShortInc(a_pSrc, a_iValue)	asm	{	mov.w	@a_pSrc+, a_iValue }
#define _LdLongInc(a_pSrc, a_iValue)	asm	{	mov.l	@a_pSrc+, a_iValue }
#define _LdByte(a_pSrc, a_iValue)		asm	{	mov.b	@a_pSrc, a_iValue }
#define _LdShort(a_pSrc, a_iValue)		asm	{	mov.w	@a_pSrc, a_iValue }
#define _DT(a_iValue)					asm	{	DT		a_iValue}
#define _BT(a_Label)					asm	{	BT		a_Label}
#define _BF(a_Label)					asm	{	BF		a_Label}
#define _Pref(a_Ptr)					asm	{	Pref	@a_Ptr}
#define reg register


// --------------------------------------------------------------------------------
//
si *Ren_CopyVertexUVs( si a_siVertexCount, si a_siVertexSkip, si *a_psiUVData, float *a_pfVertBuffer)
{
	si	*psiOnChipUV;
	si	*psiCurUVData;
	si	siLoop;
	
	psiCurUVData = a_psiUVData;
	psiOnChipUV = (si*)&a_pfVertBuffer[1024 + 512 + a_siVertexCount + a_siVertexSkip];
	
	for (siLoop = 0; siLoop < a_siVertexCount; siLoop += 1)
	{
		*--psiOnChipUV = *psiCurUVData++;
	}
	a_psiUVData = (si*)&a_pfVertBuffer[1024+512+128];
	return a_psiUVData;
}

// --------------------------------------------------------------------------------
//
si *Ren_CopyFwdVertexUVs( si a_siVertexCount, si a_siVertexSkip, si *a_psiUVData, float *a_pfVertBuffer)
{
	si	*psiOnChipUV;
	si	*psiCurUVData;
	si	siLoop;
	
	psiCurUVData = a_psiUVData;
	psiOnChipUV = (si*)&a_pfVertBuffer[1024 + 512 + a_siVertexSkip];
	
	for (siLoop = 0; siLoop < a_siVertexCount; siLoop += 1)
	{
		*psiOnChipUV++ = *psiCurUVData++;
	}
	a_psiUVData = (si*)&a_pfVertBuffer[1024+512+128];
	return a_psiUVData;
}


// --------------------------------------------------------------------------------
//
// --------------------------------------------------------------------------------
//
void Ren_RenderNonMorph( Draw_tDrawPort *a_pDrawPort, Skin_tTypeList *a_pSkinTypeList, Ren_tpJointMatrices *a_paJointMatrices, si a_siLOD)
{
	si			siSegmentIndex;
	Skin_tType	*pSkintype;
	si			siMorphIndex = 0;
	s8			*ps8CoordData;
	s8			*ps8NormData;
	s8			*ps8StripData;
	si			*psiUVData;
	float		*pfVertBuffer;
	float		*pNormalTable;
	si			*piTAData;
	ui			*piHWRegs;
	ui			uiStartTime;
	ui			uiEndTime;
	si			siPolyCnt;
// --------------------------------------------------------------------------------
	static ui num_joints = 27;
// --------------------------------------------------------------------------------
//
	piHWRegs = (unsigned int *)0xFFD8000C;
	uiStartTime = *piHWRegs;

//_SetupShadow();
//_DrawShadow( a_pVertexBufferDesc);
//_DrawFirstShadow( a_pVertexBufferDesc);
	pNormalTable = (float *)&Nrm_anormal[0];
	pNormalTable = (float *)((int)pNormalTable ^ 0x02000000);

	Ren_MaterialCache.iShadowBase = 0x3f800000; // 1.0 float
	Ren_MaterialCache.iShadowOffset = 0;
	Ren_MaterialCache.iPCW = KMY_PARAM_POLYGON | KMY_LIST_OPAQUE | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_SHADOW_POLYGON
				| KMY_OBJ_WTV_POLYGON | KMY_OBJ_INTENSITY1 | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV;

	piTAData = Draw_SetupStoreQ( a_pDrawPort, KM_OPAQUE_POLYGON);

	siPolyCnt = 0;
	pfVertBuffer = _pfOnChipRAM;
	pSkintype = &a_pSkinTypeList->atype[0];
	for (siSegmentIndex = 0; siSegmentIndex < a_pSkinTypeList->iTypes; siSegmentIndex += 1)
//	for (siSegmentIndex = 0; siSegmentIndex < num_joints; siSegmentIndex += 1)
	{
		si		siVertexSkip;
		si		siVertexSrcOffset;
		si		siVertexCount;
		si		siVertexSkipAndCount;
		si		siBoneIndex;
		Skin_tPolySet	*pPolySet;
		Skin_tVertWeights 	*pVertWeights;
//static	float afTempBuf[512*1024/4];
static si s_siCtr;

if (siSegmentIndex == 0)
	s_siCtr++;

//		if ( ((uiStartTime >> 18) & 15) == siSegmentIndex)
		{
	
			pPolySet = pSkintype->ppolysetloclist->apolysetloc[a_siLOD].ppolyset; 
			// Transform vertices
			siVertexCount = pPolySet->s16Vertices;

			pVertWeights = pPolySet->pVertWeights;
			while (1)
			{
				si					iWeightOffset;
				Matrix4x4_tMatrix	*pRotMatrix;
				Matrix4x4_tMatrix	*pLightMatrix;
				
				siVertexCount = pVertWeights->s16VertexCount;
				iWeightOffset = pVertWeights->s16WeightIndex;

				if (siVertexCount == 0)
					break;

				siVertexSrcOffset = pVertWeights->s16SrcOffset;
				siVertexSkip = pVertWeights->s16DstOffset;
				siVertexSkipAndCount = (siVertexSkip << 16) | (u16)(siVertexCount);

				
//				pRotMatrix = a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pRotMatrix100;
				pRotMatrix = (&a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pRotMatrix100)[iWeightOffset >> 6];
				pLightMatrix = a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pLightMatrix;	
//				pRotMatrix = (Matrix4x4_tMatrix*)( (u32)(pRotMatrix) + iWeightOffset);
//				pLightMatrix = (Matrix4x4_tMatrix*)( (u32)(pLightMatrix) + iWeightOffset);

				ps8CoordData = &pSkintype->pmorphloclist->amorphloc[siMorphIndex]->pmorph->as8[0];
//Fnt_Printf("%3d %4d %4d %4d\n", iWeightOffset, siVertexSrcOffset, siVertexSkip, siVertexCount,a_paJointMatrices );
				// HERE: the skin actually points to the proper matrix (not necessarily 1:1)
				// Ren_LoadMatrix( &a_paJointMatrices->pRotMatrix->aaf[0][0]);	
				Ren_LoadMatrix( &pRotMatrix->aaf[0][0]);	
				// Ren_LoadMatrix( &(Game_pgame->ateam[0].aplayer[0].anim.animseq.pose.p_saved_matrix4x4[siSegmentIndex].aaf[0][0]) );
	
				Ren_TransformVertices( siVertexSkipAndCount, &ps8CoordData[3*siVertexSrcOffset], pfVertBuffer, &pNormalTable[128]);

				if ( (pfVertBuffer[siVertexSkip * 4 + 3] < 0) || ( pfVertBuffer[siVertexSkip * 4 + 3] > (1.0/_CULL_SEGMENT_DISTANCE) ))
					return;
		
				// Light vertices
				ps8NormData  = &ps8CoordData[pPolySet->s16NormalOffset+siVertexSrcOffset];
				Ren_LoadMatrix( &pLightMatrix->aaf[0][0]);
				Ren_LightVertices( siVertexSkipAndCount, ps8NormData, pfVertBuffer, &pNormalTable[256+128] );

if (0)
{
//	PRINTOUT(("%2d: %.4f %.4f %.4f %.4f\n", siSegmentIndex, pfVertBuffer[4*siVertexSkip], pfVertBuffer[4*siVertexSkip+4], pfVertBuffer[4*siVertexSkip+8], pfVertBuffer[4*siVertexSkip+12] ));
	PRINTOUT(("%2d: %.4f\n", siSegmentIndex, pfVertBuffer[4*siVertexSkip] ));
}	
				// Copy UVs to on-chip vertex pool
				psiUVData	= (si *)((int)pPolySet + pPolySet->s16UVDataOffset);
				psiUVData	+= siVertexSrcOffset;
				psiUVData 	= Ren_CopyFwdVertexUVs( siVertexCount, siVertexSkip, psiUVData, pfVertBuffer);

				pVertWeights += 1;
			};

			// Render triangles
			siPolyCnt += pPolySet->s16NumPolys;
			ps8StripData= (s8 *)((int)pPolySet + pPolySet->s16TriDataOffset);

			piTAData = Ren_ProcessStrips( ps8StripData, psiUVData, piTAData, pfVertBuffer );

		}
		pSkintype++;
	}
	a_pDrawPort->VertBufContext.apVertBuffer[KM_OPAQUE_POLYGON] = (void *)piTAData;
if (0) Fnt_Printf("Obj Polys=%5d\n", siPolyCnt);
}


// --------------------------------------------------------------------------------
//

int *Ren_ShadowStrips( Draw_tDrawPort *a_pDrawPort, s8 *ps8StripData, float *a_pVertCache )
{
	s8			*ps8CoordData;
	s8			*ps8NormData;
	si			*psiUVData;
	float		*pfVertBuffer;
	float		*pNormalTable;
	reg si		*piTAData;
	ui			*piHWRegs;
	ui			uiStartTime;
	ui			uiEndTime;
	reg f32		fTemp;

			if (1)
#if 1
//if (s_siCtr & 256)
			{
				si		*piVertBuffer = (si *)(a_pVertCache + 128*4 + 1);
				reg si		iStripEnd = 0xf0000000;
				reg si		*piVert0, *piVert1, *piVert2;
				reg si		iVert0X, iVert0Y, iVert0Z, iVert0B;
				reg si		iVert1X, iVert1Y, iVert1Z, iVert1B;
				reg si		iVert2X, iVert2Y, iVert2Z, iVert2B;
				reg si		iShadowX, iShadowY, iShadowB;
				reg float	fShadowX, fShadowY, fShadowZ, fShadowZScale;
				reg float	fVert0X=0, fVert0Y, fVert0Z=0;
				reg float	fVert1X, fVert1Y, fVert1Z=0;
				reg float	fVert2X, fVert2Y, fVert2Z=0;

#undef _Z_DIST5
#undef _OFFSET
#define _Z_DIST	(500.)
#define	_OFFSET (1.)
				fShadowZScale = (_Z_DIST-_OFFSET)/_Z_DIST;
				fShadowX = a_pVertCache[1]; //320.0f;
				fShadowY = 100000240.0f;
				fShadowZ = *(float*)&piVertBuffer[3];
				fShadowZ *= fShadowZScale;
				iShadowB = *(si*)&Ren_fAmbient;

				piTAData = Draw_SetupStoreQ( a_pDrawPort, KM_OPAQUE_MODIFIER);
//if (siSegmentIndex == 2)
				{
					reg s8 *pStripWork;
					reg si	iTriCount=0, iTemp;
					reg si	iVert0=0, iVert1=0, iVert2=0;
					
					pStripWork = ps8StripData;
					
					while ( 1)
					{
StripParse:
						_LdByteInc( pStripWork, iTriCount);
						if (iTriCount > 0)
						{
							si	siShift = 4;
							
							_LdByteInc( pStripWork, iVert0);
							_LdByteInc( pStripWork, iVert1);
							_LdByteInc( pStripWork, iVert2);
							iTemp = iTriCount & 1;
							iTriCount = iTriCount >> 1;

							piVert0 = (si*)((si)piVertBuffer + (iVert0 << siShift));
							piVert1 = (si*)((si)piVertBuffer + (iVert1 << siShift));
							piVert2 = (si*)((si)piVertBuffer + (iVert2 << siShift));
							iVert0B = piVert0[0];
							iVert1B = piVert1[0];
							iVert2B = piVert2[0];

StartCW:
							_LdFloatInc( piVert0, fVert0X);
							_LdFloatInc( piVert0, fVert0Y);
							_LdFloatInc( piVert0, fVert0Z);
							_LdFloatInc( piVert1, fVert1X);
							_LdFloatInc( piVert1, fVert1Y);
							_LdFloatInc( piVert1, fVert1Z);
							_LdFloatInc( piVert2, fVert2X);
							_LdFloatInc( piVert2, fVert2Y);
							_LdFloatInc( piVert2, fVert2Z);
							fVert0Z *= fShadowZScale;
							fVert1Z *= fShadowZScale;
							fVert2Z *= fShadowZScale;
							
							fShadowX = fVert0X;

							// 0x81804000 0x10020000
//							piTAData[0] = 0x81804000;
//							piTAData[1] = 0x10020000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_NORMAL_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_NORMAL;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_StFloatDec( piTAData, fVert2X);
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_StFloatDec( piTAData, fVert0X);
							_StLongDec( piTAData, iStripEnd);
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
//							_StLongDec( piTAData, iStripEnd);
							_Pref(piTAData);
							piTAData += (32-4)/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_StFloatDec( piTAData, fVert2X);
//							_StFloatDec( piTAData, fShadowZ);
//							_StFloatDec( piTAData, fShadowY);
//							_StFloatDec( piTAData, fShadowX);
//							_StLongDec( piTAData, iStripEnd);
							_Pref(piTAData);
							piTAData += (32-16)/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							prefetch(piTAData);
							piTAData += 32/4;

//							goto ShadowCCW0;

							do
							{
ShadowCCW0:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert0);
								_BT( FinishCCW0);

								piVert0 = &piVertBuffer[iVert0 << 2];
								_LdFloatInc( piVert0, fVert0X);
								_LdFloatInc( piVert0, fVert0Y);
								_LdFloatInc( piVert0, fVert0Z);
								fVert0Z *= fShadowZScale;

								piTAData += 32/4;
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
//								_StLongDec( piTAData, iStripEnd);
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								_StLongDec( piTAData, iStripEnd);
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_Pref(piTAData);
								piTAData += 32/4;


ShadowCW1:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert1);
								_BT( FinishCW1);
	
								piVert1 = &piVertBuffer[iVert1 << 2];
								_LdFloatInc( piVert1, fVert1X);
								_LdFloatInc( piVert1, fVert1Y);
								_LdFloatInc( piVert1, fVert1Z);
								fVert1Z *= fShadowZScale;

								piTAData += 32/4;
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
//								_StLongDec( piTAData, iStripEnd);
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								_StLongDec( piTAData, iStripEnd);
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_Pref(piTAData);
								piTAData += 32/4;

ShadowCCW2:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert2);
								_BT( FinishCCW2);
	
								piVert2 = &piVertBuffer[iVert2 << 2];
								_LdFloatInc( piVert2, fVert2X);
								_LdFloatInc( piVert2, fVert2Y);
								_LdFloatInc( piVert2, fVert2Z);
								fVert2Z *= fShadowZScale;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_Pref(piTAData);
								piTAData += 32/4;

ShadowCW0:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert0);
								_BT( FinishCW0);
	
								piVert0 = &piVertBuffer[iVert0 << 2];
								_LdFloatInc( piVert0, fVert0X);
								_LdFloatInc( piVert0, fVert0Y);
								_LdFloatInc( piVert0, fVert0Z);
								fVert0Z *= fShadowZScale;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_StFloatDec( piTAData, fVert1X);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_Pref(piTAData);
								piTAData += 32/4;


ShadowCCW1:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert1);
								_BT( FinishCCW1);
	
								piVert1 = &piVertBuffer[iVert1 << 2];
								_LdFloatInc( piVert1, fVert1X);
								_LdFloatInc( piVert1, fVert1Y);
								_LdFloatInc( piVert1, fVert1Z);
								fVert1Z *= fShadowZScale;

								piTAData += 32/4;
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_Pref(piTAData);
								piTAData += 32/4;

ShadowCW2:
								_DT( iTriCount);
								_LdByteInc( pStripWork, iVert2);
								_BT( FinishCW2);
	
								piVert2 = &piVertBuffer[iVert2 << 2];
								_LdFloatInc( piVert2, fVert2X);
								_LdFloatInc( piVert2, fVert2Y);
								_LdFloatInc( piVert2, fVert2Z);
								fVert2Z *= fShadowZScale;

								piTAData += 32/4;
								_StFloatDec( piTAData, fVert1X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_StFloatDec( piTAData, fVert0X);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert1Z);
								_StFloatDec( piTAData, fVert1Y);
								_Pref(piTAData);
								piTAData += 32/4;
	
								piTAData += 32/4;
								_StFloatDec( piTAData, fVert0X);
								_StFloatDec( piTAData, fVert2Z);
								_StFloatDec( piTAData, fVert2Y);
								_StFloatDec( piTAData, fVert2X);
								_StFloatDec( piTAData, fShadowZ);
								_StFloatDec( piTAData, fShadowY);
								_StFloatDec( piTAData, fShadowX);
//								*--piTAData = iStripEnd;
								_Pref(piTAData);
								piTAData += (32-4)/4;
								piTAData += 8/4;
								_StFloatDec( piTAData, fVert0Z);
								_StFloatDec( piTAData, fVert0Y);
								_Pref(piTAData);
								piTAData += 32/4;

							} while (1);
FinishCCW0:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert2X);
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	

FinishCW1:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert2X);
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	

FinishCCW2:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	


FinishCW0:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_StFloatDec( piTAData, fVert2X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	

FinishCCW1:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fVert2Z);
							_StFloatDec( piTAData, fVert2Y);
							_StFloatDec( piTAData, fVert2X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	

FinishCW2:
							pStripWork -= 1;

							// 0x81804040 0x30200000
//							piTAData[0] = 0x81804040;
//							piTAData[1] = 0x30200000;
							piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
							piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
							_Pref(piTAData);
							piTAData += 32/4;

							piTAData += 32/4;
							_StFloatDec( piTAData, fVert0X);
							_StFloatDec( piTAData, fVert1Z);
							_StFloatDec( piTAData, fVert1Y);
							_StFloatDec( piTAData, fVert1X);
							_StFloatDec( piTAData, fShadowZ);
							_StFloatDec( piTAData, fShadowY);
							_StFloatDec( piTAData, fShadowX);
							*--piTAData = iStripEnd;
							_Pref(piTAData);
							piTAData += 32/4;
							piTAData += 8/4;
							_StFloatDec( piTAData, fVert0Z);
							_StFloatDec( piTAData, fVert0Y);
							_Pref(piTAData);
							piTAData += 32/4;

							goto StripParse;	

						}
						else if (iTriCount == 0)
						{
							break;
						}
					}
				}
				a_pDrawPort->VertBufContext.apVertBuffer[KM_OPAQUE_MODIFIER] = (void *)piTAData;
			}
#else
			else
			{

				piTAData = Draw_SetupStoreQ( a_pDrawPort, KM_OPAQUE_MODIFIER);
//if (siSegmentIndex == 2)
				{
					s8 *pStripWork;
					si siTriCount;
					si	siVert0, siVert1, siVert2, siVert3;
					
					pStripWork = ps8StripData;
					
					while ( *pStripWork != 0)
					{
						siTriCount = *pStripWork++;
						if (siTriCount > 0)
						{
							if (siTriCount & 1)
							{
								siTriCount = siTriCount >> 1;
								siVert2 = *pStripWork++;
								siVert3 = *pStripWork++;
								while (siTriCount--)
								{
									siVert0 = siVert2;
									siVert1 = siVert3;
									siVert2 = *pStripWork++;

									piTAData = _ShadowTri( piTAData, siVert0, siVert1, siVert2);
									
									if (siTriCount-- == 0)
										break;
									
									siVert3 = *pStripWork++;
									piTAData = _ShadowTri( piTAData, siVert1, siVert3, siVert2);

								}
							}
							else
							{
								siTriCount = siTriCount >> 1;
								siVert2 = *pStripWork++;
								siVert3 = *pStripWork++;
								while (siTriCount--)
								{
									siVert0 = siVert2;
									siVert1 = siVert3;
									siVert2 = *pStripWork++;

									piTAData = _ShadowTri( piTAData, siVert0, siVert2, siVert1);

									if (siTriCount-- == 0)
										break;

									siVert3 = *pStripWork++;
									piTAData = _ShadowTri( piTAData, siVert1, siVert2, siVert3);
								}
							}
						}
//break;
						if (siTriCount == 0)
						{
							break;
						}
					}
				}
				a_pDrawPort->VertBufContext.apVertBuffer[KM_OPAQUE_MODIFIER] = (void *)piTAData;
			}
#endif
	return 0;
}

// --------------------------------------------------------------------------------
//
void Ren_ShadowNonMorph( Draw_tDrawPort *a_pDrawPort, Skin_tTypeList *a_pSkinTypeList, Ren_tpJointMatrices *a_paJointMatrices, si a_siLOD)
{
	si			siSegmentIndex;
	Skin_tType	*pSkintype;
	si			siMorphIndex = 0;
	s8			*ps8CoordData;
	s8			*ps8NormData;
	s8			*ps8StripData;
	si			*psiUVData;
	float		*pfVertBuffer;
	float		*pNormalTable;
	si			*piTAData;
	ui			*piHWRegs;
	ui			uiStartTime;
	ui			uiEndTime;
	si			siPolyCnt;
// --------------------------------------------------------------------------------
	static ui num_joints = 22;
// --------------------------------------------------------------------------------
//
//	KMVERTEXBUFFDESC *pVertexBufferDesc = a_pVertexBufferDesc;
//	Skin_tTypeList *pSkinTypeList = a_pSkinTypeList;
//	Ren_tpJointMatrices *paJointMatrices = a_paJointMatrices;
//	si siLOD = a_siLOD;

//static si iCtr;
//if (++iCtr & 256) return;

	siPolyCnt = 0;

	piHWRegs = (unsigned int *)0xFFD8000C;
	uiStartTime = *piHWRegs;

	pNormalTable = (float *)&Nrm_anormal[0];
	pNormalTable = (float *)((int)pNormalTable ^ 0x02000000);

	pfVertBuffer = _pfOnChipRAM;
	pSkintype = &a_pSkinTypeList->atype[0];
	for (siSegmentIndex = 0; siSegmentIndex < a_pSkinTypeList->iTypes; siSegmentIndex += 1)
//	for (siSegmentIndex = 0; siSegmentIndex < num_joints; siSegmentIndex += 1)
	{
		si		siVertexSrcOffset;
		si		siVertexSkip;
		si		siVertexCount;
		si		siVertexSkipAndCount;
		si		siBoneIndex;
		Skin_tPolySet	*pPolySet;
		Skin_tVertWeights 	*pVertWeights;
static si s_siCtr;

if (siSegmentIndex == 0)
	s_siCtr++;

//		if ( ((uiStartTime >> 18) & 15) == siSegmentIndex)
		{
	
			pPolySet = pSkintype->ppolysetloclist->apolysetloc[a_siLOD].ppolyset; 
			// Transform vertices
			siVertexCount = pPolySet->s16Vertices;

			pVertWeights = pPolySet->pVertWeights;
			while (1)
			{
				si					iWeightOffset;
				Matrix4x4_tMatrix	*pRotMatrix;
				Matrix4x4_tMatrix	*pLightMatrix;
				
				siVertexCount = pVertWeights->s16VertexCount;
				iWeightOffset = pVertWeights->s16WeightIndex;

				if (siVertexCount == 0)
					break;

				siVertexSrcOffset = pVertWeights->s16SrcOffset;
				siVertexSkip = pVertWeights->s16DstOffset;
				siVertexSkipAndCount = (siVertexSkip << 16) | (u16)(siVertexCount);

				
//				pRotMatrix = a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pRotMatrix100;
				pRotMatrix = (&a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pRotMatrix100)[iWeightOffset >> 6];
				pLightMatrix = a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pLightMatrix;	
//				pRotMatrix = (Matrix4x4_tMatrix*)( (u32)(pRotMatrix) + iWeightOffset);
//				pLightMatrix = (Matrix4x4_tMatrix*)( (u32)(pLightMatrix) + iWeightOffset);

				ps8CoordData = &pSkintype->pmorphloclist->amorphloc[siMorphIndex]->pmorph->as8[0];
//Fnt_Printf("%3d %4d %4d %4d\n", iWeightOffset, siVertexSrcOffset, siVertexSkip, siVertexCount,a_paJointMatrices );
				// HERE: the skin actually points to the proper matrix (not necessarily 1:1)
				// Ren_LoadMatrix( &a_paJointMatrices->pRotMatrix->aaf[0][0]);	
				Ren_LoadMatrix( &pRotMatrix->aaf[0][0]);	
				// Ren_LoadMatrix( &(Game_pgame->ateam[0].aplayer[0].anim.animseq.pose.p_saved_matrix4x4[siSegmentIndex].aaf[0][0]) );
	
				Ren_TransformVertices( siVertexSkipAndCount, &ps8CoordData[3*siVertexSrcOffset], pfVertBuffer, &pNormalTable[128]);

				if ( (pfVertBuffer[siVertexSkip * 4 + 3] < 0) || ( pfVertBuffer[siVertexSkip * 4 + 3] > (1.0/_CULL_SEGMENT_DISTANCE) ))
					return;
		

				pVertWeights += 1;
			};

			ps8StripData= (s8 *)((int)pPolySet + pPolySet->s16TriDataOffset);

			Ren_ShadowStrips( a_pDrawPort, ps8StripData, pfVertBuffer );

		}
		pSkintype++;
	}
}

// --------------------------------------------------------------------------------
// Build new strips of clipped and unclipped triangles
// --------------------------------------------------------------------------------
//
#if 1
si Ren_BuildClippedStrip(reg s8 *pStripWork, s8 *as8VisibleStrip, s8 *as8ClippedStrip, float *pfVertBuffer)
{
	reg si	iTriangleFacing;
	reg si	iVisibleStripFacing;
	reg si 	iVisibleStripTriCnt;
	reg si	iVisibleStripTriCntOffset;
	reg si	iVisibleOffset;
	reg si	iClippedOffset;
	reg s8	*ps8VisTriCnt;
	reg s8	*ps8VisStrip;
	reg s8	*ps8ClipStrip;	
	reg s8	*ps8VisMat;	
	reg s8	*ps8ClipMat;
	reg si	iOne;
	f32		fOne = 1.0;
	
	iVisibleOffset = 0;
	iClippedOffset = 0;
	
	iOne = *(si*)&fOne;

	pfVertBuffer += 128*4 + 3;
	
	ps8VisStrip = as8VisibleStrip;
	ps8ClipStrip = as8ClippedStrip;
	ps8VisMat = 0;
	ps8ClipMat = 0;
	
	// Build new strips of unclipped and clipped triangles
	{
		reg si	siTriCount;
			si		siVertIndex;
			si		iVertCount;
			si		*piVert;
			si		iVertsVisible;
			reg si	iVert0;
			reg si	iVert1;
			reg si	iVert2;
			si		siShift = 4;
		
		_LdByteInc( pStripWork, siTriCount);
		while ( 1)
		{
			if (siTriCount > 0)
			{
				iTriangleFacing = siTriCount & 1;
				iVisibleStripTriCnt = 0;
				siTriCount = siTriCount >> 1;
				iVisibleStripTriCntOffset = 0;

				{
TriLoop:
					_LdByteInc( pStripWork, iVert0 );
					_LdByteInc( pStripWork, iVert1 );
					iVert0 <<= siShift;
					_LdByteInc( pStripWork, iVert2 );
					iVert1 <<= siShift;
					iVert0 = *(si*)((si)pfVertBuffer + iVert0);
					iVert2 <<= siShift;
					iVert1 = *(si*)((si)pfVertBuffer + iVert1);
					iVert2 = *(si*)((si)pfVertBuffer + iVert2);
					pStripWork -= 3;

					iVertsVisible = 3;
					if ( iVert0 == iOne)
					{
						iVertsVisible -= 1;
					}
					if ( iVert1 == iOne)
					{
						iVertsVisible -= 1;
					}
					if ( iVert2 == iOne)
					{
						iVertsVisible -= 1;
					}
					
					if (iVertsVisible == 3)
					{
						if (iVisibleStripTriCnt != 0)
						{
							s8	s8VertIndex;
							
							s8VertIndex = pStripWork[2];
							iVisibleStripTriCnt += 1;
							ps8VisStrip[0] = s8VertIndex;
							ps8VisStrip += 1;
						}
						else
						{

							_LdByteInc( pStripWork, iVert0 );

							_LdByteInc( pStripWork, iVert1 );

							_LdByteInc( pStripWork, iVert2 );
//							ps8VisStrip[0] = 0;

							pStripWork -= 3;
							ps8VisStrip[1] = (s8)iVert0;

							ps8VisStrip[2] = (s8)iVert1;

							iVisibleStripTriCnt = 1;
							ps8VisStrip[3] = (s8)iVert2;

							iVisibleStripFacing = iTriangleFacing;
							ps8VisTriCnt = ps8VisStrip;
							ps8VisStrip += 4;
//							Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[0], pfVertBuffer[(pStripWork[0]+128) * 4 + 1], pfVertBuffer[(pStripWork[0]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[0]+128) * 4 + 3] );
//							Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[1], pfVertBuffer[(pStripWork[1]+128) * 4 + 1], pfVertBuffer[(pStripWork[1]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[1]+128) * 4 + 3] );
						}
//						Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[2], pfVertBuffer[(pStripWork[2]+128) * 4 + 1], pfVertBuffer[(pStripWork[2]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[2]+128) * 4 + 3] );
					}
					else
					{
						if (iVisibleStripTriCnt != 0)
						{
							ps8VisTriCnt[0] = (s8)((iVisibleStripTriCnt << 1) | iVisibleStripFacing);
							iVisibleStripTriCnt = 0;
						}
						
						if (iVertsVisible)
						{
							ps8ClipStrip[0] = (s8)((1 << 1) | iTriangleFacing);

							_LdByteInc( pStripWork, iVert0 );

							_LdByteInc( pStripWork, iVert1 );

							_LdByteInc( pStripWork, iVert2 );

							ps8ClipStrip[1] = (s8)iVert0;

							pStripWork -= 3;
							ps8ClipStrip[2] = (s8)iVert1;

							ps8ClipStrip[3] = (s8)iVert2;
							ps8ClipStrip += 4;
//							as8ClippedStrip[ iClippedOffset++] = pStripWork[2];		// Leave room for extra vertex in clipped tri
						}
					}
					_DT( siTriCount);
					pStripWork += 1;
					iTriangleFacing ^= 1;
					_BF( TriLoop);
				}
				pStripWork += 2;

				// End visible strip if one is partially built
				if (iVisibleStripTriCnt != 0)
				{
					ps8VisTriCnt[0] = (s8)((iVisibleStripTriCnt << 1) | iVisibleStripFacing);
					iVisibleStripTriCnt = 0;
				}
				_LdByteInc( pStripWork, siTriCount);
			}
			else if (siTriCount < 0)
			{
				// Add material to clipped list
				if (ps8ClipMat == ps8ClipStrip)
					ps8ClipStrip[-1] = (s8)siTriCount;
				else
				{
					ps8ClipStrip[0] = (s8)siTriCount;
					ps8ClipStrip += 1;
					ps8ClipMat = ps8ClipStrip;
				}

				// Add material to visible list
				if (ps8VisMat == ps8VisStrip)
					ps8VisStrip[-1] = (s8)siTriCount;
				else
				{
					ps8VisStrip[0] = (s8)siTriCount;
					ps8VisStrip += 1;
					ps8VisMat = ps8VisStrip;
				}
				_LdByteInc( pStripWork, siTriCount);
			}
			else
			{
				break;
			}
		}
	}
	ps8VisStrip[0] = 0;
	ps8VisStrip += 1;
	iVisibleOffset = (si)((ui)ps8VisStrip - (ui)as8VisibleStrip);
	
	ps8ClipStrip[0] = 0;
	ps8ClipStrip += 1;
	iClippedOffset = (si)((ui)ps8ClipStrip - (ui)as8ClippedStrip);

	return (iVisibleOffset & 0xffff) | (iClippedOffset << 16);
}
#else
si Ren_BuildClippedStrip(reg s8 *pStripWork, s8 *as8VisibleStrip, s8 *as8ClippedStrip, float *pfVertBuffer)
{
	reg si	iTriangleFacing;
	reg si	iVisibleStripFacing;
	reg si 	iVisibleStripTriCnt;
	reg si	iVisibleStripTriCntOffset;
	reg si	iVisibleOffset;
	reg si	iClippedOffset;
	reg s8	*ps8VisTriCnt;
	reg s8	*ps8VisStrip;
	reg s8	*ps8ClipStrip;	
	reg s8	*ps8VisMat;	
	reg s8	*ps8ClipMat;
	reg si	iOne;
	f32		fOne = 1.0;
	
	iVisibleOffset = 0;
	iClippedOffset = 0;
	
	iOne = *(si*)&fOne;

	pfVertBuffer += 128*4 + 3;
	
	ps8VisStrip = as8VisibleStrip;
	ps8ClipStrip = as8ClippedStrip;
	ps8VisMat = 0;
	ps8ClipMat = 0;
	
	// Build new strips of unclipped and clipped triangles
	{
		reg si	siTriCount;
		
		_LdByteInc( pStripWork, siTriCount);
		while ( 1)
		{
			if (siTriCount > 0)
			{
				iTriangleFacing = siTriCount & 1;
				iVisibleStripTriCnt = 0;
				siTriCount = siTriCount >> 1;
				iVisibleStripTriCntOffset = 0;

				{
					si		siVertIndex;
					si		iVertCount;
					si		*piVert;
					si		iVertsVisible;
					reg si	iVert0;
					reg si	iVert1;
					reg si	iVert2;
					si		siShift = 4;
							
TriLoop:
					_LdByteInc( pStripWork, iVert0 );
					_LdByteInc( pStripWork, iVert1 );
					_LdByteInc( pStripWork, iVert2 );
					iVert0 <<= siShift;
					iVert1 <<= siShift;
					iVert2 <<= siShift;
					iVert0 = *(si*)((si)pfVertBuffer + iVert0);
					iVert1 = *(si*)((si)pfVertBuffer + iVert1);
					iVert2 = *(si*)((si)pfVertBuffer + iVert2);
					pStripWork -= 3;

					iVertsVisible = 3;
					if ( iVert0 == iOne)
					{
						iVertsVisible -= 1;
					}
					if ( iVert1 == iOne)
					{
						iVertsVisible -= 1;
					}
					if ( iVert2 == iOne)
					{
						iVertsVisible -= 1;
					}
					
					if (iVertsVisible == 3)
					{
						if (iVisibleStripTriCnt == 0)
						{
							iVisibleStripTriCnt += 1;
							iVisibleStripFacing = iTriangleFacing;
							ps8VisTriCnt = ps8VisStrip;
//							ps8VisStrip[0] = 0;
							ps8VisStrip[1] = pStripWork[0];
							ps8VisStrip[2] = pStripWork[1];
							ps8VisStrip[3] = pStripWork[2];
							ps8VisStrip += 4;
//							Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[0], pfVertBuffer[(pStripWork[0]+128) * 4 + 1], pfVertBuffer[(pStripWork[0]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[0]+128) * 4 + 3] );
//							Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[1], pfVertBuffer[(pStripWork[1]+128) * 4 + 1], pfVertBuffer[(pStripWork[1]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[1]+128) * 4 + 3] );
						}
						else
						{
							iVisibleStripTriCnt += 1;
							ps8VisStrip[0] = pStripWork[2];
							ps8VisStrip += 1;
						}
//						Fnt_Printf("%2x X=%.2f, Y=%.2f, Z=%.2f\n", (u8)pStripWork[2], pfVertBuffer[(pStripWork[2]+128) * 4 + 1], pfVertBuffer[(pStripWork[2]+128) * 4 + 2], 1.0/pfVertBuffer[(pStripWork[2]+128) * 4 + 3] );
					}
					else
					{
						if (iVisibleStripTriCnt != 0)
						{
							ps8VisTriCnt[0] = (s8)((iVisibleStripTriCnt << 1) | iVisibleStripFacing);
							iVisibleStripTriCnt = 0;
						}
						
						if (iVertsVisible)
						{
							ps8ClipStrip[0] = (s8)((1 << 1) | iTriangleFacing);
							ps8ClipStrip[1] = pStripWork[0];
							ps8ClipStrip[2] = pStripWork[1];
							ps8ClipStrip[3] = pStripWork[2];
							ps8ClipStrip += 4;
//							as8ClippedStrip[ iClippedOffset++] = pStripWork[2];		// Leave room for extra vertex in clipped tri
						}
					}
					_DT( siTriCount);
					pStripWork += 1;
					iTriangleFacing ^= 1;
					_BF( TriLoop);
				}
				pStripWork += 2;

				// End visible strip if one is partially built
				if (iVisibleStripTriCnt != 0)
				{
					ps8VisTriCnt[0] = (s8)((iVisibleStripTriCnt << 1) | iVisibleStripFacing);
					iVisibleStripTriCnt = 0;
				}
				_LdByteInc( pStripWork, siTriCount);
			}
			else if (siTriCount < 0)
			{
				// Add material to clipped list
				if (ps8ClipMat == ps8ClipStrip)
					ps8ClipStrip[-1] = (s8)siTriCount;
				else
				{
					ps8ClipStrip[0] = (s8)siTriCount;
					ps8ClipStrip += 1;
					ps8ClipMat = ps8ClipStrip;
				}

				// Add material to visible list
				if (ps8VisMat == ps8VisStrip)
					ps8VisStrip[-1] = (s8)siTriCount;
				else
				{
					ps8VisStrip[0] = (s8)siTriCount;
					ps8VisStrip += 1;
					ps8VisMat = ps8VisStrip;
				}
				_LdByteInc( pStripWork, siTriCount);
			}
			else
			{
				break;
			}
		}
	}
	ps8VisStrip[0] = 0;
	ps8VisStrip += 1;
	iVisibleOffset = (si)((ui)ps8VisStrip - (ui)as8VisibleStrip);
	
	ps8ClipStrip[0] = 0;
	ps8ClipStrip += 1;
	iClippedOffset = (si)((ui)ps8ClipStrip - (ui)as8ClippedStrip);

	return (iVisibleOffset & 0xffff) | (iClippedOffset << 16);
}
#endif

// --------------------------------------------------------------------------------
//
// --------------------------------------------------------------------------------
//
#if 0
static s8 *_CullPFBBoxes( s8 *a_pas8CullFlags, si a_iVertPoolCnt, f32 *a_pfCoord, f32 *a_pfVertBuffer)
{
	static f32	fScreenLeft = -320.0;
	static f32	fScreenRight = 320.0;
	static f32	fScreenTop = -240.0;
	static f32	fScreenBottom = 240.0;
	static f32	fNearZ = 1.0;
	static si	iFloatMask = 0x7fffffff;
	si			*piVertCoords;
	si			iMinH;
	si			iMaxH;
	si			iMinV;
	si			iMaxV;
	si			iMaxZ;
	si			iVertsCulled;

	// Calc screen coordinates of bbox
	Ren_TransformFloatVertices( a_iVertPoolCnt, a_pfCoord, a_pfVertBuffer);

	// Int compares are much faster than float compares...		
	piVertCoords = (si*)&a_pfVertBuffer[ a_iVertPoolCnt*4];
	iMinH = *(si*)&fScreenLeft;
	iMaxH = *(si*)&fScreenRight;
	iMinV = *(si*)&fScreenTop;
	iMaxV = *(si*)&fScreenBottom;
	iMaxZ = *(si*)&fNearZ;

	// See if bboxes are onscreen
	while (a_iVertPoolCnt)
	{
		si	iCullFlags = 0x1f;
		si	iVertIndex;

		a_iVertPoolCnt -= 8;

		iVertsCulled = 0;
		for ( iVertIndex = 0; iVertIndex < 8; iVertIndex++)
		{
			si	siX;
			si	siY;
			si	siZ;
			
			piVertCoords -= 4;
			siX = piVertCoords[1];
			siY = piVertCoords[2];
			siZ = piVertCoords[3];
			
			if ( (siX & iFloatMask) < iMaxH)
			{
				iCullFlags &= ~(1|2);
			}
			else
			{
				if (siX < 0)
				{
					iCullFlags &= ~1;
				}
				else
				{
					iCullFlags &= ~2;
				}
			}
			
			if ( (siY & iFloatMask) < iMaxV)
			{
				iCullFlags &= ~(4|8);
			}
			else
			{
				if (siY < 0)
				{
					iCullFlags &= ~4;
				}
				else
				{
					iCullFlags &= ~8;
				}
			}

			if (siZ < iMaxZ)
			{
				iCullFlags &= ~0x10;
				iVertsCulled += 1;
			}
		}
		if (iCullFlags != 0)
			a_pas8CullFlags[0] = FALSE;
		else if (iVertsCulled)
			a_pas8CullFlags[0] = -1;
		else
			a_pas8CullFlags[0] = TRUE;

		a_pas8CullFlags += 1;
	}

	return a_pas8CullFlags;
}
#endif
// --------------------------------------------------------------------------------
// Ren_DrawPlayfield()
// --------------------------------------------------------------------------------
// Draw a textured playfield using geometry rather than just a background texture.
//

//
//  This must be aligned like a double for Ren_LoadMatrix
//
double				dAlignment;
Matrix4x4_tMatrix 	identityMatrix;

void Ren_DrawPlayfield(Draw_tDrawPort *a_pDrawPort)
{
	si			siSegmentIndex;
	Skin_tType	*pSkintype;
	si			siMorphIndex = 0;
	float		*pfCoordData;
	s8			*ps8NormData;
	s8			*ps8StripData;
	si			*psiUVData;
	float		*pfVertBuffer;
	float		*pNormalTable;
	si			*piTAData;
	ui			*piHWRegs;
	ui			uiStartTime;
	ui			uiEndTime;
	si			siVertexCount;
	si			siVertexSkip;
	extern f32	_as8Morphball_field177_Joint1[];
	extern s16	_as16PolySetball_field177_Joint1[];
	extern s8   _as8TriStripball_field177_Joint1[];
	extern	float	nStrip2;
	extern	float	nCylinders2;
	Ren_tpJointMatrices _aJointMatrices[2];
	Vector3_tVector   v3origin;
	static float f_scale = 1.0f;
	si			iVisibleVerts;
	float		fCenterH, fCenterV;
	si			iAreaIndex;
	si			iLoop;
	si			iPolyCnt;
	s8			as8CullFlags[1024];
	s8			*ps8CurCullFlag;
	G_tpArea	pArea;
	static si	iCtr;

iCtr += 1;
// --------------------------------------------------------------------------------
//	
	//
	if (0)
	{
		float fManhatten;
		
		fManhatten = Game_game.cameraGame.vectorFrom.fX + Game_game.cameraGame.vectorFrom.fY;
//Fnt_Printf("cam manhatten = %3.0f\n", fManhatten );
		
		if ( fManhatten >= 60.0f )
		{
			return;
		}
	}

	iPolyCnt = 0;
	// Temp - Save screen center, and rebuild proj matrix with center of 0 so polys can be clipped
	fCenterH = Game_game.renderGame.pView->fcenterH;
	fCenterV = Game_game.renderGame.pView->fcenterV;
	Game_game.renderGame.pView->fcenterH = 0;
	Game_game.renderGame.pView->fcenterV = 0;
	Ren_MaterialCache.fCenterX = fCenterH;
	Ren_MaterialCache.fCenterY = fCenterV;
	View_CreateProjectionMatrix( Game_game.renderGame.pView);
	Matrix4x4_MultByMatrix4x4( &Game_game.renderGame.RenMatrix, &Game_game.renderGame.pView->ProjectionMatrix, &Game_game.renderGame.pCam->matrix4x4 );
	
	Ren_LoadMaterials( pf_pMaterials, (si)pf_dh->materialCnt, -1, REN_VERT_POOL_MATERIALS );	

	piHWRegs = (unsigned int *)0xFFD8000C;
	uiStartTime = *piHWRegs;

	Matrix4x4_Build_Identity( &identityMatrix );
	Vector3_Set( &v3origin, 0.0f, 0.0f, 0.0f );
	Ren_Debug_Build_Matrices(
		&Game_game.renderGame,
		FALSE,						// Don't calc weighted joints
		&_aJointMatrices[0],
		&identityMatrix,
		1,
		&v3origin,
		f_scale,
		1.0f,
		0.0f,
		0.0f,
		0.0f,               // zrot
		NULL
//		,&Game_game.cameraGame.matrix4x4
		);

//	Fnt_Printf("\n\n");

	pNormalTable = (float *)&Nrm_anormal[0];
	pNormalTable = (float *)((int)pNormalTable ^ 0x02000000);

	pfVertBuffer = _pfOnChipRAM;

//	Ren_CopyNormalTable( Nrm_anormal, (float *)((int)Nrm_anormal ^ 0x02000000));

	// Check if area is visible
/*	{
		f32	*pfCoord;
		si	iVertPoolCnt;
		
		Err_mAssert( pf_cdbPtr->areaCnt <= 1024);

		Ren_LoadMatrix( (float*)_aJointMatrices[0].pRotMatrix );

		pfCoord = &pfVertBuffer[256*4]; 	// Start at end of 256 vert on-chip VertPool
		iVertPoolCnt = 0;
		pArea = &pf_cdbPtr->area[ 0];
		ps8CurCullFlag = &as8CullFlags[0];
		for (iAreaIndex = 0; iAreaIndex < pf_cdbPtr->areaCnt; iAreaIndex++)
		{
			f32 fMinX;
			f32 fMaxX;
			f32 fMinY;
			f32 fMaxY;
			f32 fMinZ;
			f32 fMaxZ;
			si	iVertsCulled;
		
			fMinX = pArea->fBBox[0];
			fMinY = pArea->fBBox[1];
			fMinZ = pArea->fBBox[2];
			fMaxX = pArea->fBBox[3];
			fMaxY = pArea->fBBox[4];
			fMaxZ = pArea->fBBox[5];
		
			// Build 8 vertices at corners of bounding box
			*--pfCoord = fMinZ;
			*--pfCoord = fMinY;
			*--pfCoord = fMinX;
		
			*--pfCoord = fMinZ;
			*--pfCoord = fMinY;
			*--pfCoord = fMaxX;
		
			*--pfCoord = fMinZ;
			*--pfCoord = fMaxY;
			*--pfCoord = fMinX;
		
			*--pfCoord = fMinZ;
			*--pfCoord = fMaxY;
			*--pfCoord = fMaxX;
		
			*--pfCoord = fMaxZ;
			*--pfCoord = fMinY;
			*--pfCoord = fMinX;
		
			*--pfCoord = fMaxZ;
			*--pfCoord = fMinY;
			*--pfCoord = fMaxX;
		
			*--pfCoord = fMaxZ;
			*--pfCoord = fMaxY;
			*--pfCoord = fMinX;
		
			*--pfCoord = fMaxZ;
			*--pfCoord = fMaxY;
			*--pfCoord = fMaxX;
			
			iVertPoolCnt += 8;
			
			if (iVertPoolCnt == 256)
			{
				ps8CurCullFlag = _CullPFBBoxes( ps8CurCullFlag, iVertPoolCnt, pfCoord, pfVertBuffer);
				iVertPoolCnt = 0;
			}
		}
		if (iVertPoolCnt != 0)
		{
			ps8CurCullFlag = _CullPFBBoxes( ps8CurCullFlag, iVertPoolCnt, pfCoord, pfVertBuffer);
		}
		
	}
*/

	for (iAreaIndex = 0; iAreaIndex < pf_cdbPtr->areaCnt; iAreaIndex++)
//	for (iAreaIndex = 27; iAreaIndex < 28; iAreaIndex++)
	{
		siBool			bVisible;
		si				iAreaType;
		
		pArea = &pf_cdbPtr->area[ iAreaIndex];
		
		// Transform vertices
		siVertexCount = pArea->vertexCnt;
		siVertexSkip = 0;
		pfCoordData   = (f32*)pArea->vertex;

		iAreaType = pArea->areaType;
		if (iAreaType == g_kAT_GT_BG)
			iAreaType = g_kAT_GT_Shadow;
#if 0	
		if (siVertexCount <= 0)
		{
			Fnt_Printf("Skipping %d\n", iAreaIndex);
			continue;
		}
#else
		if (siVertexCount == 0)
			siVertexCount = 256;
#endif
			
		// Check if area is visible
if (1)
		{
			Vector3_tVector AreaCenter;
			f32				fAreaRadius;

			AreaCenter.fX = pArea->offset.x * (1.0/256.0);
			AreaCenter.fY = pArea->offset.y * (1.0/256.0);
			AreaCenter.fZ = pArea->offset.z * (1.0/256.0);
			fAreaRadius = pArea->radius*2.0 * (1.0/256.0);
			bVisible = Ren_CheckVisible( &AreaCenter, fAreaRadius);
//			bVisible = Ren_CheckVisible( (void *)&pArea->sphere[0], pArea->sphere[3]);

			if (bVisible == FALSE)
			{
				continue;
			}
			bVisible = -1;
		}
		else
		{
			bVisible = as8CullFlags[iAreaIndex];
			if ( (bVisible == FALSE) && ( iAreaType != g_kAT_GT_Shadow) )
			{
				continue;
			}
		}
		iVisibleVerts = Ren_TransformFloatVertices( siVertexCount, pfCoordData, pfVertBuffer);
	
		if (0) Fnt_Printf("\n\nVisVerts=%3d of %3d\n", iVisibleVerts, siVertexCount);
		// Temp - Add screen center and check if area is visible

		if ( iAreaType == g_kAT_GT_Shadow)
		{
			si	siLoop;
			si	siLoopEnd;
			f32	*pfVert;
	
			if (iVisibleVerts > siVertexCount)
				iVisibleVerts = siVertexCount;
			pfVert = &pfVertBuffer[4*siVertexSkip+1];
			siLoopEnd = (siVertexCount + 1) & (~1);
			for (siLoop = 0; siLoop < siLoopEnd; siLoop += 2)
			{
				f32	fH1, fV1;
				f32	fH2, fV2;
				
				fH1 = pfVert[0];
				fV1 = pfVert[1];
				fH2 = pfVert[4];
				fV2 = pfVert[5];
				fH1 += fCenterH;
				fV1 += fCenterV;
				fH2 += fCenterH;
				fV2 += fCenterV;
				pfVert[0] = fH1;
				pfVert[1] = fV1;
				pfVert[4] = fH2;
				pfVert[5] = fV2;
				pfVert += 2*4;
			}
			iVisibleVerts += 1;
		}

		if (0)	Fnt_Printf("VisVerts=%3d of %3d\n", iVisibleVerts, siVertexCount);

		if (iVisibleVerts)
		{
			si	iPolyType;
			si	iPCW;
			
			iPolyCnt += pArea->polyCnt;
			Ren_fAmbient = 0.40;//4;
			switch( iAreaType)
			{
				case g_kAT_GT_Shadow:
				{
					ps8StripData	= (s8 *)pArea->polyList + (siVertexCount*4);
	
					Ren_ShadowStrips( a_pDrawPort, ps8StripData, pfVertBuffer );

					continue;
				}

				case g_kAT_GT_BG:
				{
					Ren_fAmbient = 1.00;
					iPolyType = KM_OPAQUE_POLYGON;
					break;
				}
				case g_kAT_GT_Land:
				{
					iPolyType = KM_OPAQUE_POLYGON;
					break;
				}
				case g_kAT_GT_Trans:
				{
					iPolyType = KM_TRANS_POLYGON;
					break;
				}
				case g_kAT_GT_ClipMap:
				{
//					iPolyType = KM_PUNCHTHROUGH_POLYGON;
					iPolyType = KM_TRANS_POLYGON;
					break;
				}
			}
			
//iPolyType = KM_OPAQUE_POLYGON;
			// Light vertices
			ps8NormData  = (s8*)&pfCoordData[3*siVertexCount];

			iPCW = iPolyType<<24;
			iPCW |= KMY_PARAM_POLYGON | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_SHADOW_POLYGON
					| KMY_OBJ_WTV_POLYGON | KMY_OBJ_INTENSITY1 | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV;
			Ren_MaterialCache.iPCW = iPCW;
			piTAData = Draw_SetupStoreQ( a_pDrawPort, iPolyType);

				Ren_LoadMatrix( (float*)_aJointMatrices[0].pLightMatrix );
				Ren_LightVertices( siVertexCount, ps8NormData, pfVertBuffer, &pNormalTable[256+128] );
			
				// Copy UVs to on-chip vertex pool
				psiUVData	= (si *)(pArea->polyList);
				psiUVData 	= Ren_CopyVertexUVs( siVertexCount, 0, psiUVData, pfVertBuffer);
		
				ps8StripData	= (s8 *)pArea->polyList + (siVertexCount*4);

				if ((iVisibleVerts == siVertexCount) || (bVisible > 0) )
				{
					// Render all triangles
					piTAData 		= Ren_ProcessStrips( ps8StripData, psiUVData, piTAData, pfVertBuffer );
				}
				else
				{
					s8	as8VisibleStrip[512*5];	//MaxTris * MaxStripBytesPerTri (Mat+tricnt+3verts)
					s8	as8ClippedStrip[512*5];
					si	iOffsets;
					si	iVisibleOffset;
					si	iClippedOffset;
					
					iOffsets = Ren_BuildClippedStrip( ps8StripData, &as8VisibleStrip[0], &as8ClippedStrip[0], pfVertBuffer);
		
					iVisibleOffset = iOffsets & 0xffff;
					iClippedOffset = iOffsets >> 16;
		
					if (iVisibleOffset)
					{
						piTAData 		= Ren_ProcessStrips( &as8VisibleStrip[0], psiUVData, piTAData, pfVertBuffer );
					}
					if (iClippedOffset)
					{
						piTAData 		= Ren_ProcessStrips( &as8ClippedStrip[0], psiUVData, piTAData, pfVertBuffer );
					}
				}
			a_pDrawPort->VertBufContext.apVertBuffer[iPolyType] = (void *)piTAData;
			
			// Restore rot matrix for next iteration's cull or project	
			Ren_LoadMatrix( (float*)_aJointMatrices[0].pRotMatrix100 );
	
		}
	}
		
#if 0
	{
		si	siLoop;
		
		Fnt_Printf("\n\nVertCount=%d Verts to TA =%d\n", siVertexCount, ((int)piTAData - (int)piTADataStart));
		for (siLoop = 0; siLoop < siVertexCount; siLoop += 1)
		{
			Fnt_Printf("%d X=%.2f, Y=%.2f, Z=%.2f\n", siLoop, pfVertBuffer[siLoop * 4 + 1], pfVertBuffer[siLoop * 4 + 2], pfVertBuffer[siLoop * 4 + 3] );
		}
	}
#endif

	// Temp - Restore view center & rebuild projection matrix
	Game_game.renderGame.pView->fcenterH = fCenterH;
	Game_game.renderGame.pView->fcenterV = fCenterV;
	Ren_MaterialCache.fCenterX = 0;
	Ren_MaterialCache.fCenterY = 0;
	View_CreateProjectionMatrix( Game_game.renderGame.pView);
	Matrix4x4_MultByMatrix4x4( &Game_game.renderGame.RenMatrix, &Game_game.renderGame.pView->ProjectionMatrix, &Game_game.renderGame.pCam->matrix4x4 );

	Ren_MaterialCache.iPCW = KMY_PARAM_POLYGON | KMY_LIST_OPAQUE | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_SHADOW_POLYGON
			| KMY_OBJ_WTV_POLYGON | KMY_OBJ_INTENSITY1 | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV;

if (0)	Fnt_Printf("\n\n\nBkg Polys=%5d\n", iPolyCnt);
}


// --------------------------------------------------------------------------------
//

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

#define _mTransformVertices( _FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ, _StoreVert, _IncVertPtr, _ExitBranch)	\
													/*Step1	TrA_00	Exp_01	StB_-1	PjC_-2	DvA_00	LdB_01	*/	\
 /*fdiv3_f3						    																		*/	\
			FMUL	_PjInvZ, _PjX					;/*	4F							PjC_-2					*/	\
			FMOV.S	_StInvZ, _StoreVert				;/*	1L					StB_-1							*/	\
 /*fdiv4_f3						    																		*/	\
 			FTRV	XMTRX, _FTRVVect				;/*	7F	TrA_00											*/	\
			FMOV.S	_StY, _StoreVert				;/*	1L					StB_-1							*/	\
 /*fdiv5_f3						    																		*/	\
 /*ftrv2						    																		*/	\
			SHLL2	iExpZ							;/*	1X			Exp_01									*/	\
			FMOV.S	_StX, _StoreVert				;/*	1L					StB_-1							*/	\
 /*fdiv6_f3						    																		*/	\
 /*ftrv3						    																		*/	\
			SHLL2	iExpX							;/*	1X			Exp_01									*/	\
			FMOV.S	@(pFloatTbl, iExpZ), _StZ		;/*	2L											LdB_01	*/	\
 /*fdiv7_f3						    																		*/	\
 /*ftrv4						    																		*/	\
			SHLL2	iExpY							;/*	1X			Exp_01									*/	\
			FMOV.S	@(pFloatTbl, iExpX), _StX		;/*	2L											LdB_01	*/	\
 /*fdiv8_f3						    																		*/	\
 /*ftrv4f1						    																		*/	\
			ADD		_IncVertPtr, pVertOut			;/*	1X													*/	\
			FMOV.S	@(pFloatTbl, iExpY), _StY		;/*	2L											LdB_01	*/	\
 /*fdiv9_f3						    																		*/	\
 			FMUL	_PjInvZ, _PjY					;/*	4F							PjC_-2					*/	\
			FLDI1	_StInvZ							;/*	0L											LdB_01	*/	\
 /*fdiv10_f1						    																	*/	\
													/*														*/	\
			DT		iVertCount						;/*	1X													*/	\
			MOV.B	@ pVertIn+, iExpX				;/*	2L			Exp_02									*/	\
													/*														*/	\
			FDIV	_DvZ, _DvInvZ					;/*	13F									DvA_00			*/	\
			MOV.B	@ pVertIn+, iExpY				;/*	2L			Exp_02									*/	\
 /*fdiv2_f3						    																		*/	\
			MOV.B	@ pVertIn+, iExpZ				;/*	2L			Exp_02									*/	\
			_ExitBranch								;/*	2B													*/	\


// --------------------------------------------------------------------------------
//
static inline void _TransformVertices( reg ui iVertCount, reg s8 *pVertIn, reg float *pVertOut, reg float *a_pFloatTbl )
{
	#define	iOff			R0
	#define	pFloatTbl		R0
	reg si		iExpX;
	reg si		iExpY;
	reg si		iExpZ;
	reg si		iTemp;
	reg ui		uiTemp;
	reg ui		uiSkip;
	reg float	*pPrefetch;
	ui dum1 = iVertCount;
	void *dum2 = pVertIn, *dum3 = pVertOut, *dum4 = a_pFloatTbl; 

	uiSkip = iVertCount >> 16;
	pVertOut = &pVertOut[4*uiSkip];
	iVertCount = (u16)iVertCount;

	pPrefetch = (float *)pVertIn;
	uiTemp = iVertCount + (32/4)-1;
	uiTemp >>= 3;
	do
	{
		prefetch(pPrefetch);
		pPrefetch += 32/sizeof(*pPrefetch);
		asm{ dt uiTemp};
	} while ( uiTemp != 0);
	asm
	{
			.set	noreorder
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
			ADD		3, iVertCount
			ADD		3*4, pVertOut
#if 1
			_mTransformVertices(	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@ pVertOut, 0, )
			_mTransformVertices(	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@ pVertOut, 0, )
			_mTransformVertices(	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@ pVertOut, 4, BRA Loop)

//			.align	4
Loop:
//Step4		TrD_03	Exp_04	StA_00	PjB_01	DvD_03	LdA_04
			_mTransformVertices(	FV12, fVertDX, fVertDY, fVertDZ, fVertDInvZ, 	fVertBX, fVertBY, fVertBZ, fVertBInvZ, 		fVertAX, fVertAY, fVertAZ, fVertAInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@-pVertOut, (3+4)*4, BF_S Loop)
#endif
BtmExit:
			.set	reorder
	}
}
#if 0
static void _TestAsm( ui iVertCount, s8 *pVertIn, float *pVertOut, float *a_pFloatTbl )
{
	_TransformVertices( iVertCount, pVertIn, pVertOut, a_pFloatTbl);
}
#endif

// --------------------------------------------------------------------------------
//
void Ren_CopyNormalTable( Nrm_tNormal *a_pNormalTableIn, float *a_pNormalTableOut)
{
	int	iLoop;
	
	for (iLoop = 256; iLoop != 0; iLoop -= 1)
	{
		float	fX, fY,fZ, fChar;
		
		fX = a_pNormalTableIn->fX;
		fY = a_pNormalTableIn->fY;
		fZ = a_pNormalTableIn->fZ;
		fChar = a_pNormalTableIn->fCvtChar;

		a_pNormalTableOut[0*256] = fChar;
		a_pNormalTableOut[1*256] = fX;
		a_pNormalTableOut[2*256] = fY;
		a_pNormalTableOut[3*256] = fZ;

		a_pNormalTableIn  += 1;
		a_pNormalTableOut += 1;
	}
}


// --------------------------------------------------------------------------------
//
int *Ren_PrepStoreQ( void *a_pData)
{
	reg int iTemp;
	reg int *piHWRegs;

	iTemp = (int)a_pData;
	piHWRegs = (int *)0xFF000038;
	piHWRegs[0] = (si)((ui)iTemp >> 24);
	piHWRegs[1] = (si)((ui)iTemp >> 24);

	iTemp &= 0x03FFFFFF;
	iTemp |= 0xE0000000;
	
	return (int *)iTemp;
	
}


// --------------------------------------------------------------------------------
//
void Ren_SelectUnloadedMaterial( Draw_tDrawPort *a_pDrawPort, Ren_tMaterial *a_pMaterial, si a_siPolyType)
{
	static s8	as8StripData[2] = {-1, 0};
	si			*piTAData;
	float		*pfVertBuffer;
	si			*psiUVData;

	piTAData = Draw_SetupStoreQ( a_pDrawPort, a_siPolyType);

	pfVertBuffer = _pfOnChipRAM;
	psiUVData = (si*)&a_pMaterial[1];
	
	// Send material to PowerVR
	piTAData = Ren_ProcessStrips( &as8StripData[0], psiUVData+128, piTAData, pfVertBuffer );
	
	a_pDrawPort->VertBufContext.apVertBuffer[a_siPolyType] = (void *)piTAData;
}

// --------------------------------------------------------------------------------
//
void Ren_SelectMaterial( Draw_tDrawPort *a_pDrawPort, si a_siMaterial, si a_siPolyType)
{
	s8			as8StripData[2];
	si			*piTAData;
	float		*pfVertBuffer;
	si			*psiUVData;

	Err_mAssert( (a_siMaterial < 0 ) && (a_siMaterial >= -64) );
	
	as8StripData[0] = (s8)a_siMaterial;
	as8StripData[1] = 0;

	piTAData = Draw_SetupStoreQ( a_pDrawPort, a_siPolyType);

	pfVertBuffer = _pfOnChipRAM;
	psiUVData = REN_VERT_POOL_UV;
	
	// Send material to PowerVR
	piTAData = Ren_ProcessStrips( &as8StripData[0], psiUVData+128, piTAData, pfVertBuffer );
	
	a_pDrawPort->VertBufContext.apVertBuffer[a_siPolyType] = (void *)piTAData;
	
}

// --------------------------------------------------------------------------------
//
siBool Ren_CheckVisible( Vector3_tVector *a_pVector, f32 a_fRadius)
{
	static f32 fScreenLeft = 0.0;
	static f32 fScreenRight = 640.0;
	static f32 fScreenTop = 0.0;
	static f32 fScreenBottom = 480.0;
	static f32 fNearZ = 1.0;
	Vector3_tVector aBBoxVerts[8];
	f32 *pfVertBuffer = _pfOnChipRAM;
	f32 fMinX;
	f32 fMaxX;
	f32 fMinY;
	f32 fMaxY;
	f32 fMinZ;
	f32 fMaxZ;
	f32	*pfCoord;
	si	iVertsCulled;


	fMinX = fMaxX = a_pVector->fX;
	fMinY = fMaxY = a_pVector->fY;
	fMinZ = fMaxZ = a_pVector->fZ;
	
	pfCoord = &aBBoxVerts[8].fX;

	fMinX -= a_fRadius;
	fMaxX += a_fRadius;
	fMinY -= a_fRadius;
	fMaxY += a_fRadius;
	fMinZ -= a_fRadius;
	fMaxZ += a_fRadius;

	// Build 8 vertices at corners of bounding box
	*--pfCoord = fMinZ;
	*--pfCoord = fMinY;
	*--pfCoord = fMinX;

	*--pfCoord = fMinZ;
	*--pfCoord = fMinY;
	*--pfCoord = fMaxX;

	*--pfCoord = fMinZ;
	*--pfCoord = fMaxY;
	*--pfCoord = fMinX;

	*--pfCoord = fMinZ;
	*--pfCoord = fMaxY;
	*--pfCoord = fMaxX;

	*--pfCoord = fMaxZ;
	*--pfCoord = fMinY;
	*--pfCoord = fMinX;

	*--pfCoord = fMaxZ;
	*--pfCoord = fMinY;
	*--pfCoord = fMaxX;

	*--pfCoord = fMaxZ;
	*--pfCoord = fMaxY;
	*--pfCoord = fMinX;

	*--pfCoord = fMaxZ;
	*--pfCoord = fMaxY;
	*--pfCoord = fMaxX;

	// Calc screen coordinates of bbox
	Ren_TransformFloatVertices( 8, &aBBoxVerts[0].fX, pfVertBuffer);

	// See if bbox is onscreen
	{
		si	iCullFlags = 0x1f;
		si	*piVertCoords;
		si	iVertIndex;
		si	iMinH;
		si	iMaxH;
		si	iMinV;
		si	iMaxV;
		si	iMaxZ;

		// Int compares are much faster than float compares...		
		piVertCoords = (si*)pfVertBuffer;
		iMinH = *(si*)&fScreenLeft;
		iMaxH = *(si*)&fScreenRight;
		iMinV = *(si*)&fScreenTop;
		iMaxV = *(si*)&fScreenBottom;
		iMaxZ = *(si*)&fNearZ;
		
		iVertsCulled = 0;
		for ( iVertIndex = 0; iVertIndex < 8; iVertIndex++)
		{
			si	siX;
			si	siY;
			si	siZ;
			
			siX = piVertCoords[1];
			siY = piVertCoords[2];
			siZ = piVertCoords[3];
			piVertCoords += 4;
			
			if (siX >= iMinH)
			{
				iCullFlags &= ~1;
			}
			if (siX < iMaxH)
			{
				iCullFlags &= ~2;
			}
			if (siY >= iMinV)
			{
				iCullFlags &= ~4;
			}
			if (siY < iMaxV)
			{
				iCullFlags &= ~8;
			}
			if (siZ < iMaxZ)
			{
				iCullFlags &= ~0x10;
			}
		}
		if (iCullFlags != 0)
			return FALSE;
	}

	if (iVertsCulled)
		return -1;

	return TRUE;
}

#if 0
KMSTRIPCONTEXT DefaultContext =     /* Standard opaque polygon. */
{
    0x90, {KM_OPAQUE_POLYGON, KM_USERCLIP_DISABLE, KM_NORMAL_POLYGON,
    KM_FLOATINGCOLOR, KM_FALSE, KM_TRUE}, {KM_GREATER, KM_CULLCCW, KM_FALSE,
    KM_FALSE, 0}, {0, 0}, {KM_ONE, KM_ZERO, KM_FALSE, KM_FALSE, KM_NOFOG,
    KM_FALSE, KM_FALSE, KM_FALSE, KM_NOFLIP, KM_NOCLAMP, KM_BILINEAR,
    KM_FALSE, KM_MIPMAP_D_ADJUST_1_00, KM_MODULATE, 0, 0}
};

static KMVERTEX_17         MV[13];                 /* Modifier volume (simple cube). */
static KMSTRIPHEAD         StripHead_17_Normal;    /* Render Params for cheap shadow volume. */
static KMSTRIPHEAD         StripHead_17_Last;      /* Params for end of cheap shadow volume. */

static void _SetupShadow( void)
{
	float	fx = 128.0;
	float	fw = 640.0;
#define _NEARZ	(1.0/1000000000)
#define _FARZ	(1.0/10000000000)
	float	fNearZ = _NEARZ;
	float	fFarZ = _FARZ;
//						0		1		2		3		4		5		6		7
#if 1
	float	afX[8] = { 128,		268,	128,	268,	220,	420,	220,	420};
	float	afY[8] = { 310,		310,	170,	170,	140,	140,	340,	340};
	float	afZ[8] = { _NEARZ,	_NEARZ,	_NEARZ,	_NEARZ,	_FARZ,	_FARZ,	_FARZ,	_FARZ};
#else
	float	afX[8] = { 128,		268,	128,	268,	220,	420,	220,	420};
	float	afY[8] = { 310,		310,	170,	170,	140,	140,	340,	340};
	float	afZ[8] = { _NEARZ,	_NEARZ,	_NEARZ,	_NEARZ,	_FARZ,	_FARZ,	_FARZ,	_FARZ};
#endif
#define _mSetTri( _index, _vert0, _vert1, _vert2)	\
    MV[_index].ParamControlWord  = KM_VERTEXPARAM_ENDOFSTRIP;	\
    MV[_index].fAX    = afX[_vert0];	MV[_index].fBX    = afX[_vert1];	MV[_index].fCX    = afX[_vert2];	\
    MV[_index].fAY    = afY[_vert0];	MV[_index].fBY    = afY[_vert1];	MV[_index].fCY    = afY[_vert2];	\
    MV[_index].uA.fAZ = afZ[_vert0];	MV[_index].uB.fBZ = afZ[_vert1];	MV[_index].uC.fCZ = afX[_vert2];	\

    memset (&StripHead_17_Normal, 0, sizeof(StripHead_17_Normal));
    kmGenerateStripHead17 (&StripHead_17_Normal, &DefaultContext);
    kmChangeStripModifierInstruction (&StripHead_17_Normal, KM_MODIFIER_NORMAL_POLY);

    memset (&StripHead_17_Last, 0, sizeof(StripHead_17_Last));
    kmGenerateStripHead17 (&StripHead_17_Last, &DefaultContext);
    kmChangeStripModifierInstruction (&StripHead_17_Last, KM_MODIFIER_INCLUDE_LAST_POLY);

#if 1
								// LdB 0	LdA 1 StA->B	
    // Front side
	_mSetTri(0,		0, 1, 2);	// StB->A		LdB 2 StB->C
	_mSetTri(1,		1, 3, 2);	// StA->A		LdA 3 StA->B

    // Top
	_mSetTri(2,		2, 3, 4);	// StB->A		LdB 4 StB->C
	_mSetTri(3,		3, 5, 4);	// StA->A		LdA 5 StA->B

    // Back side
	_mSetTri(5,		4, 5, 6);
	_mSetTri(4,		5, 7, 6);

    // Bottom
	_mSetTri(6,		6, 7, 0);
	_mSetTri(7,		7, 1, 0);

    // Right side
	_mSetTri(8,		1, 7, 3);
	_mSetTri(9,		7, 5, 3);

    // Left side
	_mSetTri(10,	6, 0, 4);
	_mSetTri(11,	0, 2, 4);

#else
    // Front side
	_mSetTri(0,		2, 1, 0);
	_mSetTri(1,		2, 3, 1);

    // Top
	_mSetTri(2,		2, 4, 3);
	_mSetTri(3,		4, 5, 3);

    // Back side
	_mSetTri(5,		7, 5, 6);
	_mSetTri(4,		6, 5, 4);

    // Left side
	_mSetTri(6,		6, 4, 0);
	_mSetTri(7,		0, 4, 2);

    // Right side
	_mSetTri(8,		1, 3, 7);
	_mSetTri(9,		7, 3, 5);

    // Bottom
	_mSetTri(10,	6, 0, 7);
	_mSetTri(11,	7, 0, 1);
#endif

	// End Tri
	_mSetTri(12,	0, 0, 0);
}

static void _DrawShadow( Draw_tDrawPort *a_pDrawPort)
{
	si	i;

	// 0x81804000 0x10020000
	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&StripHead_17_Normal,	32);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 32 / sizeof(KMDWORD);

	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&MV[0],	12*64);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 12*64 / sizeof(KMDWORD);

	// 0x81804040 0x30200000
	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&StripHead_17_Last,	32);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 32 / sizeof(KMDWORD);

	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&MV[12],	1*64);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 1*64 / sizeof(KMDWORD);

#if 0
    /* Send cheap shadow modifier volume to render system. */
    kmStartStrip (a_pVertexBufferDesc, &StripHead_17_Normal);
    kmSetVertex (a_pVertexBufferDesc, &MV[0], KM_VERTEXTYPE_17, sizeof (KMVERTEX_17));

    for (i=1; i<=10; i++)
        kmSetVertex (a_pVertexBufferDesc, &MV[i], KM_VERTEXTYPE_17, sizeof (KMVERTEX_17));

    kmStartStrip (a_pVertexBufferDesc, &StripHead_17_Last);
    kmSetVertex (a_pVertexBufferDesc, &MV[11], KM_VERTEXTYPE_17, sizeof (KMVERTEX_17));
#endif

}

static void _DrawFirstShadow( Draw_tDrawPort *a_pDrawPort)
{

	// 0x81804000 0x10020000
	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&StripHead_17_Normal,	32);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 32 / sizeof(KMDWORD);
}

static void _DrawLastShadow( Draw_tDrawPort *a_pDrawPort)
{
	float		*pfVertBuffer;
	KMVERTEX_17	LastVertex;

	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER]-32/4,	(PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] - 64/4,	1*64);

	// 0x81804040 0x30200000
	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER]-64/4,	(PKMDWORD)&StripHead_17_Last,	32);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 32 / sizeof(KMDWORD);

/*	pfVertBuffer = _pfOnChipRAM;
    LastVertex.ParamControlWord  = KM_VERTEXPARAM_ENDOFSTRIP;
    LastVertex.fAX    = pfVertBuffer[1];	LastVertex.fBX    = pfVertBuffer[1];	LastVertex.fCX    = pfVertBuffer[1];
    LastVertex.fAY    = pfVertBuffer[2];	LastVertex.fBY    = pfVertBuffer[2];	LastVertex.fCY    = pfVertBuffer[2];
    LastVertex.uA.fAZ = pfVertBuffer[3];	LastVertex.uB.fBZ = pfVertBuffer[3];	LastVertex.uC.fCZ = pfVertBuffer[3];

	memcpy( (PKMDWORD)a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER],	(PKMDWORD)&LastVertex,	1*64);
	a_pVertexBufferDesc->pCurrentPtr[KM_OPAQUE_MODIFIER] += 1*64 / sizeof(KMDWORD);
*/
}
#endif

static inline si *_ShadowTri( si *a_piTAData, int a_iVert0, int a_iVert1, int a_iVert2)
{
	si		*piVertBuffer = (si *)(_pfOnChipRAM + 128*4);
	si		*piVert0, *piVert1, *piVert2;
	si		iVert0X, iVert0Y, iVert0Z, iVert0B;
	si		iVert1X, iVert1Y, iVert1Z, iVert1B;
	si		iVert2X, iVert2Y, iVert2Z, iVert2B;
	si		iShadowX, iShadowY, iShadowB;
	float	fVert0X, fVert0Y, fVert0Z;
	float	fVert1X, fVert1Y, fVert1Z;
	float	fVert2X, fVert2Y, fVert2Z;

	piVert0 = &piVertBuffer[a_iVert0 << 2];
	iVert0B = piVert0[0];

	piVert1 = &piVertBuffer[a_iVert1 << 2];
	iVert1B = piVert1[0];

	piVert2 = &piVertBuffer[a_iVert2 << 2];
	iVert2B = piVert2[0];

//	if ( (iVert0B <= iShadowB) && (iVert1B <= iShadowB) && (iVert2B <= iShadowB) )
//		return a_piTAData;
	
	*(float *)&iShadowX = 320.0f;
	*(float *)&iShadowY = 100000240.0f;
//Ren_fAmbient += .05;
	iShadowB = *(si*)&Ren_fAmbient;
//Ren_fAmbient -= .05;
	
	// 0x81804000 0x10020000
//	a_piTAData[0] = 0x81804000;
//	a_piTAData[1] = 0x10020000;
	a_piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_NORMAL_MODIFIER;
	a_piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_NORMAL;
	prefetch(a_piTAData);
	a_piTAData += 32/4;

#if 1
	iVert0X = piVert0[1];
	iVert0Y = piVert0[2];
//	fVert0X = *(float *)&piVert0[1];
//	fVert0Y = *(float *)&piVert0[2];
	fVert0Z = *(float *)&piVert0[3];

	iVert1X = piVert1[1];
	iVert1Y = piVert1[2];
//	fVert1X = *(float *)&piVert1[1];
//	fVert1Y = *(float *)&piVert1[2];
	fVert1Z = *(float *)&piVert1[3];

	iVert2X = piVert2[1];
	iVert2Y = piVert2[2];
//	fVert2X = *(float *)&piVert2[1];
//	fVert2Y = *(float *)&piVert2[2];
	fVert2Z = *(float *)&piVert2[3];

//	fVert0Y += 1.0;
//	fVert1Y += 1.0;
//	fVert2Y += 1.0;

#define _Z_DIST	(500.)
#define	_OFFSET (1.)
	fVert0Z *= (_Z_DIST-_OFFSET)/_Z_DIST;
	fVert1Z *= (_Z_DIST-_OFFSET)/_Z_DIST;
	fVert2Z *= (_Z_DIST-_OFFSET)/_Z_DIST;

//	fVert0Z *= 500/(500+1);
//	fVert1Z *= 500/(500+1);
//	fVert2Z *= 500/(500+1);

//	iVert0X = *(si*)&fVert0X;
//	iVert0Y = *(si*)&fVert0Y;
	iVert0Z = *(si*)&fVert0Z;

//	iVert1X = *(si*)&fVert1X;
//	iVert1Y = *(si*)&fVert1Y;
	iVert1Z = *(si*)&fVert1Z;

//	iVert2X = *(si*)&fVert2X;
//	iVert2Y = *(si*)&fVert2Y;
	iVert2Z = *(si*)&fVert2Z;

//	iVert0Z -= 4*128;
//	iVert1Z -= 4*128;
//	iVert2Z -= 4*128;

#else
//	piVert = &piVertBuffer[a_iVert0 << 2];
//	iVert0B = piVert0[0];
	iVert0X = piVert0[1];
	iVert0Y = piVert0[2];
	iVert0Z = piVert0[3]-128*1;

//	piVert = &piVertBuffer[a_iVert1 << 2];
//	iVert1B = piVert1[0];
	iVert1X = piVert1[1];
	iVert1Y = piVert1[2];
	iVert1Z = piVert1[3]-128*1;

//	piVert = &piVertBuffer[a_iVert2 << 2];
//	iVert2B = piVert2[0];
	iVert2X = piVert2[1];
	iVert2Y = piVert2[2];
	iVert2Z = piVert2[3]-128*1;
#endif

//	VP_Printf("0=%02X: %.2f, %.2f, %.2f\n", (a_iVert0) & 0xff, iVert0X, iVert0Y, iVert0Z);
//	VP_Printf("1=%02X: %.2f, %.2f, %.2f\n", (a_iVert1) & 0xff, iVert1X, iVert1Y, iVert1Z);
//	VP_Printf("2=%02X: %.2f, %.2f, %.2f\n", (a_iVert2) & 0xff, iVert2X, iVert2Y, iVert2Z);

	a_piTAData[0] = 0xf0000000;
	a_piTAData[1] = iVert0X;
	a_piTAData[2] = iVert0Y;
	a_piTAData[3] = iVert0Z;
	a_piTAData[4] = iVert1X;
	a_piTAData[5] = iVert1Y;
	a_piTAData[6] = iVert1Z;
	a_piTAData[7] = iVert2X;
	prefetch(a_piTAData);
	a_piTAData += 32/4;
	a_piTAData[0] = iVert2Y;
	a_piTAData[1] = iVert2Z;
	prefetch(a_piTAData);
	a_piTAData += 32/4;

//	a_piTAData[0] = 0xf0000000;
	a_piTAData[1] = iShadowX;
	a_piTAData[2] = iShadowY;
	a_piTAData[3] = iVert0Z;
//	a_piTAData[4] = iVert1X;
//	a_piTAData[5] = iVert1Y;
//	a_piTAData[6] = iVert1Z;
	a_piTAData[7] = iVert0X;
	prefetch(a_piTAData);
	a_piTAData += 32/4;
	a_piTAData[0] = iVert0Y;
	a_piTAData[1] = iVert0Z;
	prefetch(a_piTAData);
	a_piTAData += 32/4;

//	a_piTAData[0] = 0xf0000000;
//	a_piTAData[1] = iShadowX;
//	a_piTAData[2] = iShadowY;
//	a_piTAData[3] = iVert0Z;
	a_piTAData[4] = iVert2X;
	a_piTAData[5] = iVert2Y;
	a_piTAData[6] = iVert2Z;
	a_piTAData[7] = iVert1X;
	prefetch(a_piTAData);
	a_piTAData += 32/4;
	a_piTAData[0] = iVert1Y;
	a_piTAData[1] = iVert1Z;
	prefetch(a_piTAData);
	a_piTAData += 32/4;

	// 0x81804040 0x30200000
//	a_piTAData[0] = 0x81804040;
//	a_piTAData[1] = 0x30200000;
	a_piTAData[0] = KMY_PARAM_MODIFIER | KMY_LIST_OPAQUEMODIFIER | KMY_GROUP_STRIP1 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_LAST_MODIFIER;
	a_piTAData[1] = KMY_CULLING_NONE | KMY_VOLUME_INSIDE_LAST;
	prefetch(a_piTAData);
	a_piTAData += 32/4;

	a_piTAData[0] = 0xf0000000;
	a_piTAData[1] = iShadowX;
	a_piTAData[2] = iShadowY;
	a_piTAData[3] = iVert0Z;
	a_piTAData[4] = iVert0X;
	a_piTAData[5] = iVert0Y;
	a_piTAData[6] = iVert0Z;
	a_piTAData[7] = iVert2X;
	prefetch(a_piTAData);
	a_piTAData += 32/4;
	a_piTAData[0] = iVert2Y;
	a_piTAData[1] = iVert2Z;
	prefetch(a_piTAData);
	a_piTAData += 32/4;
	
	return a_piTAData;
}

// --------------------------------------------------------------------------------
//
// --------------------------------------------------------------------------------
//
#if 0
void Ren_BumpmapNonMorph( Draw_tDrawPort *a_pDrawPort, Skin_tTypeList *a_pSkinTypeList, Ren_tpJointMatrices *a_paJointMatrices, si a_siLOD)
{
	si			siSegmentIndex;
	Skin_tType	*pSkintype;
	si			siMorphIndex = 0;
	s8			*ps8CoordData;
	s8			*ps8NormData;
	s8			*ps8StripData;
	si			*psiUVData;
	float		*pfVertBuffer;
	float		*pNormalTable;
	si			*piTAData;
	ui			*piHWRegs;
	ui			uiStartTime;
	ui			uiEndTime;
	si			iSavedPCW;
// --------------------------------------------------------------------------------
	static ui num_joints = 1;//27;
// --------------------------------------------------------------------------------
//
	piHWRegs = (unsigned int *)0xFFD8000C;
	uiStartTime = *piHWRegs;

	pNormalTable = (float *)&Nrm_anormal[0];
	pNormalTable = (float *)((int)pNormalTable ^ 0x02000000);

	Ren_MaterialCache.iShadowBase = 0x10000000;
	Ren_MaterialCache.iShadowOffset = 0x8000ff40;
	Ren_MaterialCache.iPCW = KMY_PARAM_POLYGON | KMY_LIST_TRANS/*KMY_LIST_OPAQUE*/ | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_SHADOW_POLYGON
				| KMY_OBJ_WTV_POLYGON | KMY_OBJ_PACKED_COLOR | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV;

	pfVertBuffer = _pfOnChipRAM;
	pSkintype = &a_pSkinTypeList->atype[0];
	for (siSegmentIndex = 0; siSegmentIndex < a_pSkinTypeList->iTypes; siSegmentIndex += 1)
//	for (siSegmentIndex = 0; siSegmentIndex < num_joints; siSegmentIndex += 1)
	{
		si		siVertexSrcOffset;
		si		siVertexSkip;
		si		siVertexCount;
		si		siVertexSkipAndCount;
		si		siBoneIndex;
		Skin_tPolySet	*pPolySet;
//static	float afTempBuf[512*1024/4];
static si s_siCtr;

if (siSegmentIndex == 0)
	s_siCtr++;
//		if ( ((uiStartTime >> 18) & 15) == siSegmentIndex)
		{
	
			pPolySet = pSkintype->ppolysetloclist->apolysetloc[a_siLOD].ppolyset; 
			// Transform vertices
			siVertexCount = pPolySet->s16Vertices;

			if ( siVertexCount > 0 )
			{
				siVertexSrcOffset = pPolySet->s16VertexSrcOffset;
				siVertexSkip = pPolySet->s16VertexDstOffset;
				siVertexSkipAndCount = (siVertexSkip << 16) | (u16)(siVertexCount);
				
				ps8CoordData = &pSkintype->pmorphloclist->amorphloc[siMorphIndex]->pmorph->as8[0];
	
				// HERE: the skin actually points to the proper matrix (not necessarily 1:1)
				// Ren_LoadMatrix( &a_paJointMatrices->pRotMatrix->aaf[0][0]);	
				Ren_LoadMatrix( &a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pRotMatrix100->aaf[0][0]);	
				// Ren_LoadMatrix( &(Game_pgame->ateam[0].aplayer[0].anim.animseq.pose.p_saved_matrix4x4[siSegmentIndex].aaf[0][0]) );
	
				Ren_TransformVertices( siVertexSkipAndCount, &ps8CoordData[3*siVertexSrcOffset], pfVertBuffer, &pNormalTable[128]);
		
				// Light vertices
				ps8NormData  = &ps8CoordData[pPolySet->s16NormalOffset+siVertexSrcOffset];
//				Ren_LoadMatrix( &a_paJointMatrices[pSkintype->s16DefaultBoneIndex].pLightMatrix->aaf[0][0]);
//				Ren_LightVertices( siVertexSkipAndCount, ps8NormData, pfVertBuffer, &pNormalTable[256+128] );
				{
					si	iLoop, *piColor, *piSpecular;
					
					piColor = (si*)&pfVertBuffer[ siVertexSkip * 4];
					piSpecular = (si*)&pfVertBuffer[ 256*4 + siVertexSkip];

					for (iLoop = 0; iLoop < siVertexCount; iLoop++)
					{
						piColor[0] = 0x30000000;
//						piColor[0] = (s_siCtr/2&0x70) << 24;
						piSpecular[0] = (si)(0x8000ff40);// + (s_siCtr & 0x7f));
						piColor += 4;
						piSpecular += 1;
						
					}
				}

if (0)
{
//	PRINTOUT(("%2d: %.4f %.4f %.4f %.4f\n", siSegmentIndex, pfVertBuffer[4*siVertexSkip], pfVertBuffer[4*siVertexSkip+4], pfVertBuffer[4*siVertexSkip+8], pfVertBuffer[4*siVertexSkip+12] ));
	PRINTOUT(("%2d: %.4f\n", siSegmentIndex, pfVertBuffer[4*siVertexSkip] ));
}	
				// Copy UVs to on-chip vertex pool
				psiUVData	= (si *)((int)pPolySet + pPolySet->s16UVDataOffset);
				psiUVData 	= Ren_CopyVertexUVs( siVertexCount, siVertexSkip, psiUVData, pfVertBuffer);
			
			}
			// HERE: tris but no verts possible?
			// Render triangles
			ps8StripData= (s8 *)((int)pPolySet + pPolySet->s16TriDataOffset);
#if 1
#if 1
			piTAData = Ren_PrepStoreQ( a_pVertexBufferDesc->pCurrentPtr[KM_TRANS_POLYGON]);
#else
			piTAData = (int*)((int)(&afTempBuf[32/4]) & (~31));
			piTAData = Ren_PrepStoreQ( piTAData);
#endif

			piTAData = Ren_ProcessStrips( ps8StripData, psiUVData, piTAData, pfVertBuffer );
			a_pVertexBufferDesc->pCurrentPtr[KM_TRANS_POLYGON] = (PKMDWORD)((int)a_pVertexBufferDesc->pCurrentPtr[KM_TRANS_POLYGON] + ((int)piTAData - (int)piTADataStart));
#endif

		}
		pSkintype++;
		// a_paJointMatrices++; // HERE: no, the skintype points to the bone index through [pSkintype->s16DefaultBoneIndex].
	}
}
#endif

void Ren_Init( Ren_tRender *a_pRenderContext, Cam_tCamera *a_pCam, View_tView *a_pView )
{
	
	a_pRenderContext->pView = a_pView;
	a_pRenderContext->pCam  = a_pCam;

}

void Ren_Update( Ren_tRender *a_pRenderContext, float a_fElapsedSeconds )
{
	float dummy = a_fElapsedSeconds;

	Cam_Update(  a_pRenderContext->pCam );
	View_SetFieldOfView( a_pRenderContext->pView, a_pRenderContext->pCam->fFieldOfView );
	View_Update( a_pRenderContext->pView );
	// _pActiveRender = a_pRenderContext; // The Ren_tRender object is now updated by the user and passed explicitly to Ren_ routines
	
	Matrix4x4_MultByMatrix4x4( &a_pRenderContext->RenMatrix, &a_pRenderContext->pView->ProjectionMatrix, &a_pRenderContext->pCam->matrix4x4 );

}

// --------------------------------------------------------------------------------
// View_CreateProjectionMatrix()
// --------------------------------------------------------------------------------
//
// Create a simple projection matrix
// Note: Renderer (TransformVertices) divides by resulting z
//
// cf
// Inspecting the 3D Pipeline Part I, Game Dev Dec 96/Jan 97 issue p 36-40
// For homogeneous projection matrix see Watt and Watt p 12-13
//
// HERE: Should use inverseTan lookup if it exists
void View_CreateProjectionMatrix( View_tView *a_pView )
{
	/* Compute projection matrix */
	a_pView->brecompute = false;

	#define _CORRECT_PERSPECTIVE 0
	#if _CORRECT_PERSPECTIVE
	{
		float h;

		h = 1.0f / (float) tan( a_pView->fViewAngleHalf );
		a_pView->ProjectionMatrix.aaf[0][0] = _PROJECTION_X * h;
		a_pView->ProjectionMatrix.aaf[1][1] = _PROJECTION_Y * h;
	}
	#else
		a_pView->ProjectionMatrix.aaf[0][0] = _PROJECTION_X / (float) tan( a_pView->fviewAngleHalf );
		a_pView->ProjectionMatrix.aaf[1][1] = -_PROJECTION_X / (float) tan( a_pView->fviewAngleHalf );
	#endif

	a_pView->ProjectionMatrix.aaf[2][0] = a_pView->fcenterH;
	a_pView->ProjectionMatrix.aaf[2][1] = a_pView->fcenterV;

}

void View_Init( View_tView *a_pView,
	float a_fviewAngle )
{ 
	a_pView->brecompute = true;
	a_pView->fcenterH   = _PIXEL_WIDTH_HALF;
	a_pView->fcenterV   = _PIXEL_HEIGHT_HALF;

	Matrix4x4_Build_Identity( &a_pView->ProjectionMatrix );
	
	// HERE: NOTE that camera fieldofview will override this!!!
	// we need a real viewport/camera interface...
	View_SetFieldOfView( a_pView, a_fviewAngle );

}

static inline void _Scale( Matrix4x4_tMatrix *a_pmatrix, float a_fScale, float a_fUnitScale)
{
	a_fUnitScale *= a_fScale;

	a_pmatrix->aaf[0][0] *= a_fUnitScale;
	a_pmatrix->aaf[0][1] *= a_fUnitScale;
	a_pmatrix->aaf[0][2] *= a_fUnitScale;
//	a_pmatrix->aaf[0][3] *= a_fUnitScale;
	
	a_pmatrix->aaf[1][0] *= a_fUnitScale;
	a_pmatrix->aaf[1][1] *= a_fUnitScale;
	a_pmatrix->aaf[1][2] *= a_fUnitScale;
//	a_pmatrix->aaf[1][3] *= a_fUnitScale;
	
	a_pmatrix->aaf[2][0] *= a_fUnitScale;
	a_pmatrix->aaf[2][1] *= a_fUnitScale;
	a_pmatrix->aaf[2][2] *= a_fUnitScale;
// 	a_pmatrix->aaf[2][3] *= a_fUnitScale;
	
	a_pmatrix->aaf[3][0] *= a_fScale;
	a_pmatrix->aaf[3][1] *= a_fScale;
	a_pmatrix->aaf[3][2] *= a_fScale;
	a_pmatrix->aaf[3][3] = 1.0f;
	
}


// --------------------------------------------------------------------------------
//
static Matrix4x4_tMatrix _matrix_25 =
{
	0.25, 0.00, 0.00, 0.00,
  	0.00, 0.25, 0.00, 0.00,
  	0.00, 0.00, 0.25, 0.00,
  	0.00, 0.00, 0.00, 0.25
};
static Matrix4x4_tMatrix _matrix_50 =
{
	0.50, 0.00, 0.00, 0.00,
  	0.00, 0.50, 0.00, 0.00,
  	0.00, 0.00, 0.50, 0.00,
  	0.00, 0.00, 0.00, 0.50
};
static Matrix4x4_tMatrix _matrix_75 =
{
	0.75, 0.00, 0.00, 0.00,
  	0.00, 0.75, 0.00, 0.00,
  	0.00, 0.00, 0.75, 0.00,
  	0.00, 0.00, 0.00, 0.75
};

static Matrix4x4_tMatrix _matrix_100 =
{
	1.00, 0.00, 0.00, 0.00,
  	0.00, 1.00, 0.00, 0.00,
  	0.00, 0.00, 1.00, 0.00,
  	0.00, 0.00, 0.00, 0.00
};


// --------------------------------------------------------------------------------
//
void Ren_BuildWeightedMatrices( HIER_tHierarchy *pHeirarchy)
{
	si	iNumNodes;
	si	iJoint;
	si  iChannel;
	si	iLoop;
	static Vector4_tVector	NullTransVect = {0, 0, 0, 0};
	// PY October 29, 2000: renamed enumeration to conform to naming conventions
	tp_CHANNEL_QUAT_LIST  pDynamicChannelsQuat = gpAnimDataBody[ CharAnim_kMotionPlayerPlaceHolder ]->p_dynamic_channels_quat;

	iNumNodes = Hier_iGetNumNodes( pHeirarchy );

	// Shouldn't be needed - For now, copy bindpos animation quats to heirarchy restpos quats
	for (iChannel = 0; iChannel < pDynamicChannelsQuat->u32_NumChannels; ++iChannel )
	{
		iJoint = (si)pDynamicChannelsQuat->p_Channel[ iChannel ].channel_data.u32_anim_node_index;
		Quat_i_Assign( &pHeirarchy->nodes[ iJoint ].restOrientation, &pDynamicChannelsQuat->p_Channel[ iChannel ].keyvalues[0] );
	}

	for (iJoint = 1; iJoint < iNumNodes; iJoint += 1)
	{
		Matrix4x4_tMatrix	DeltaMatrix;

		Matrix4x4_SetFromQuatVector4( &DeltaMatrix, &pHeirarchy->nodes[ iJoint].restOrientation, &NullTransVect);

		Matrix4x4_MultByMatrix4x4( &_JointWeightMatrixBuffer[ iJoint][1], &_matrix_25, &DeltaMatrix);
		Matrix4x4_MultByMatrix4x4( &_JointWeightMatrixBuffer[ iJoint][2], &_matrix_50, &DeltaMatrix);
		Matrix4x4_MultByMatrix4x4( &_JointWeightMatrixBuffer[ iJoint][3], &_matrix_75, &DeltaMatrix);

	}
}

#if 0
// --------------------------------------------------------------------------------
//
#include <sh4_mwerks.h>

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

#define _mTransformVertices( _FTRVVect, _DvX, _DvY, _DvZ, _DvInvZ, 	_PjX, _PjY, _PjZ, _PjInvZ, 		_StX, _StY, _StZ, _StInvZ, _StoreVert, _IncVertPtr, _ExitBranch)	\
			FMUL	_PjInvZ, _PjX					;	\
			FMOV.S	_StInvZ, _StoreVert				;	\
 			FTRV	XMTRX, _FTRVVect				;	\
			FMOV.S	_StY, _StoreVert				;	\
			SHLL2	iExpZ							;	\
			FMOV.S	_StX, _StoreVert				;	\
			SHLL2	iExpX							;	\
			FMOV.S	@(pFloatTbl, iExpZ), _StZ		;	\
			SHLL2	iExpY							;	\
			FMOV.S	@(pFloatTbl, iExpX), _StX		;	\
			ADD		_IncVertPtr, pVertOut			;	\
			FMOV.S	@(pFloatTbl, iExpY), _StY		;	\
 			FMUL	_PjInvZ, _PjY					;	\
			FLDI1	_StInvZ							;	\
			DT		iVertCount						;	\
			MOV.B	@ pVertIn+, iExpX				;	\
			FDIV	_DvZ, _DvInvZ					;	\
			MOV.B	@ pVertIn+, iExpY				;	\
			MOV.B	@ pVertIn+, iExpZ				;	\
			_ExitBranch								;	\


// --------------------------------------------------------------------------------
//
static inline void _TransformVertices( reg unsigned int iVertCount, reg char *pVertIn, reg float *pVertOut, reg float *a_pFloatTbl )
{
	#define	iOff			R0
	#define	pFloatTbl		R0
	reg int	iExpX;
	reg int	iExpY;
	reg int	iExpZ;
	reg int	iTemp;
	reg unsigned int	uiTemp;
	reg unsigned int	uiSkip;
	reg float	*pPrefetch;
	unsigned int dum1 = iVertCount;
	void *dum2 = pVertIn, *dum3 = pVertOut, *dum4 = a_pFloatTbl; 

	uiSkip = iVertCount >> 16;
	pVertOut = &pVertOut[4*uiSkip];
	iVertCount = (u16)iVertCount;

	pPrefetch = (float *)pVertIn;
	uiTemp = iVertCount + (32/4)-1;
	uiTemp >>= 3;
	do
	{
		prefetch(pPrefetch);
		pPrefetch += 32/sizeof(*pPrefetch);
		asm{ dt uiTemp};
	} while ( uiTemp != 0);
	asm
	{
			.set	noreorder
			MOV		a_pFloatTbl, pFloatTbl

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

			ADD		3, iVertCount
			ADD		3*4, pVertOut

			_mTransformVertices(	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@ pVertOut, 0, )
			_mTransformVertices(	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@ pVertOut, 0, )
			_mTransformVertices(	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@ pVertOut, 4, BRA Loop)

Loop:
			_mTransformVertices(	FV12, fVertDX, fVertDY, fVertDZ, fVertDInvZ, 	fVertBX, fVertBY, fVertBZ, fVertBInvZ, 		fVertAX, fVertAY, fVertAZ, fVertAInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV0, fVertAX, fVertAY, fVertAZ, fVertAInvZ, 	fVertCX, fVertCY, fVertCZ, fVertCInvZ, 		fVertBX, fVertBY, fVertBZ, fVertBInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV4, fVertBX, fVertBY, fVertBZ, fVertBInvZ, 	fVertDX, fVertDY, fVertDZ, fVertDInvZ, 		fVertCX, fVertCY, fVertCZ, fVertCInvZ,	@-pVertOut, (3+4)*4, BT_S BtmExit)
			_mTransformVertices(	FV8, fVertCX, fVertCY, fVertCZ, fVertCInvZ, 	fVertAX, fVertAY, fVertAZ, fVertAInvZ, 		fVertDX, fVertDY, fVertDZ, fVertDInvZ,	@-pVertOut, (3+4)*4, BF_S Loop)
BtmExit:
			.set	reorder
	}
}
static void _TestAsm( unsigned int iVertCount, char *pVertIn, float *pVertOut, float *a_pFloatTbl )
{
	_TransformVertices( iVertCount, pVertIn, pVertOut, a_pFloatTbl);
}
#endif


static int Test( signed char *pStripWork)
{
	int	iTriCount, iTemp;
	int	iVert0, iVert1, iVert2;
	int	iVert0B, iVert1B, iVert2B;
	int	*piVert0, *piVert1, *piVert2;
	int	iResult=0;
	int	*piVertBuffer = (int *)(0x7dfff000);
	
	while ( 1)
	{
		iTriCount = *pStripWork++;
		if (iTriCount > 0)
		{
#if 0
			iVert0 = *pStripWork++;
			iVert1 = *pStripWork++;
			iVert2 = *pStripWork++;

			piVert0 = &piVertBuffer[iVert0 << 2];
			piVert1 = &piVertBuffer[iVert1 << 2];
			piVert2 = &piVertBuffer[iVert2 << 2];

			iVert0B = piVert0[0];
			iVert1B = piVert1[0];
			iVert2B = piVert2[0];

			iResult += iVert0B + iVert1B + iVert2B;
#else
			static si	siShift = 4;
			
			iVert0 = *pStripWork; pStripWork += 1;
			iVert1 = *pStripWork; pStripWork += 1;
			iVert2 = *pStripWork; pStripWork += 1;

			piVert0 = (si*)((si)piVertBuffer + (iVert0 << siShift));
			piVert1 = (si*)((si)piVertBuffer + (iVert1 << siShift));
			piVert2 = (si*)((si)piVertBuffer + (iVert2 << siShift));

			iVert0B = piVert0[0];
			iVert1B = piVert1[0];
			iVert2B = piVert2[0];
			iResult += iVert0B + iVert1B + iVert2B;
#endif
		}
		else
			break;
	}
	return iResult;
}

//	X1	Y1	Z1	0
//
//	0	Z2	-Y2	0
//	-Z2	0	X2	0
//	Y2	-X2	0	0

// Bump Map material
// 0x828c010e - KMY_PARAM_POLYGON | KMY_LIST_TRANS | KMY_GROUP_STRIP6 | KMY_GROUP_CLIP_DISABLE | KMY_OBJ_NORMAL_POLYGON | KMY_OBJ_PACKED_COLOR | KMY_OBJ_TEXTURE | KMY_OBJ_OFFSET | KMY_OBJ_GOURAUD | KMY_OBJ_16BITUV
// 0xc0000008 - KMY_COMPARE_GREATEREQUAL | KMY_CULLING_SMALL
// 0x949024ed - KMY_SRCBLEND_SRCALPHA | KMY_DSTBLEND_INVSRCALPHA | KMY_FOG_NOFOG | KMY_ALPHA_ENABLE | KMY_BILINEAR | KMY_MIPMAP_D_100 | KMY_SHADING_DECALPLHA
// --------------------------------------------------------------------------------
//

// --------------------------------------------------------------------------------
//
// Add Projection matrix to LocalToWorld matrices from hierarchy
void Ren_Debug_Build_Matrices(
	Ren_tRender             *a_pRender,
	siBool					a_bCalcWeights,
	Ren_tpJointMatrices     *a_paJointMatrices,
	const Matrix4x4_tMatrix *a_paMatrices,
	const si                 a_num_matrices,
	const Vector3_tVector   *a_ptrans,
	const float              a_fscale,
	const float              a_fUnitScale,
	const float              a_fRotXradians,
	const float              a_fRotYradians,
	const float              a_fRotZradians,
	Vector3_tVector         *a_world_position_vector
//	,	const Matrix4x4_tMatrix *a_pCameraMatrix )
)
{
	si	siSegmentIndex;
	Matrix4x4_tMatrix *pCTM1, *pCTM2, *pLightMatrix;
	Matrix4x4_tMatrix CTM2,RM, matrixWorldToLocal;
	static Vector4_tVector	aV3WorldLights[4] = { 
#if 1
//		{-0.11 * Ren_kLightScaleUp, 0.0 * Ren_kLightScaleUp, 0.27 * Ren_kLightScaleUp, 0},
//		{0.0 * Ren_kLightScaleUp, -0.11 * Ren_kLightScaleUp, 0.27 * Ren_kLightScaleUp, 0},
		{0.0, 0, 0, 0},
		{0.0 * Ren_kLightScaleUp, 0.0 * Ren_kLightScaleUp, -0.1 * Ren_kLightScaleUp, 0},
		{0.0, 0, 0, 0},
		{0.0 * Ren_kLightScaleUp, 0.0 * Ren_kLightScaleUp, 0.55 * Ren_kLightScaleUp, 0},
#else
		{0.0 * Ren_kLightScaleUp, 0.0 * Ren_kLightScaleUp, 0.8 * Ren_kLightScaleUp, 0},
		{0.0, 0, 0, 0},
		{0.0, 0, 0, 0},
		{0.0, 0, 0, 0},
#endif
	};

Prof_StartSection( PROF_SECTION_DRAWCHARMATH );

	pCTM2 = &CTM2;
	
//	Ren_fAmbient = 0.40;//4;

	aV3WorldLights[2].fX = -a_pRender->pCam->matrix4x4.aaf[0][2];//*.89;
	aV3WorldLights[2].fY = -a_pRender->pCam->matrix4x4.aaf[1][2];//*.89;
	aV3WorldLights[2].fZ = -a_pRender->pCam->matrix4x4.aaf[2][2];//*.89;
	
//	aV3WorldLights[1].fX = -a_pRender->pCam->matrix4x4.aaf[0][2] * Ren_kLightScaleUp * .05;
//	aV3WorldLights[1].fY = -a_pRender->pCam->matrix4x4.aaf[1][2] * Ren_kLightScaleUp * .05;
//	aV3WorldLights[1].fZ = -a_pRender->pCam->matrix4x4.aaf[2][2] * Ren_kLightScaleUp * .05;
	
	// Transformation on the complete animation (same applied to all nodes)
	Matrix4x4_Build_Rot_XYZTrans3( &RM, a_fRotXradians, a_fRotYradians, a_fRotZradians, a_ptrans );

	ld_ext( (void*)&a_pRender->RenMatrix);
	mtrx4mul( (void*)&RM, (void*)pCTM2);

	for (siSegmentIndex = 0; siSegmentIndex < a_num_matrices; siSegmentIndex += 1)
	{
		si	siLightIndex;
		f32	fMaxNeg;
		
		// Local to World
		pCTM1 = &_MatrixBuffer[ siSegmentIndex ][0];
//		Matrix4x4_Assign( pCTM1, &a_paMatrices[ siSegmentIndex ] );
		ld_ext( (void*)&a_paMatrices[ siSegmentIndex ]);
		st_ext( (void*)pCTM1);


		// World Transforms

		// Scale the guy
		_Scale( &pCTM1[0], a_fscale, a_fUnitScale);

//		Matrix4x4_MultByMatrix4x4( &matrixWorldToLocal, &RM, &a_paMatrices[ siSegmentIndex ] ); // no scale
		ld_ext( (void*)&RM);
		mtrx4mul( (void*)&a_paMatrices[ siSegmentIndex ], (void*)&matrixWorldToLocal);

		// Calculate joint-space light vectors
		fMaxNeg = _pfLightConstants[1];
		pLightMatrix = &_LightMatrixBuffer[ siSegmentIndex ][0];
		for (siLightIndex = 0; siLightIndex < 4; siLightIndex += 1)
		{
			f32	fX, fY, fZ;

			fX = fipr(&matrixWorldToLocal.aaf[0], &aV3WorldLights[siLightIndex]); 
			fY = fipr(&matrixWorldToLocal.aaf[1], &aV3WorldLights[siLightIndex]); 
			fZ = fipr(&matrixWorldToLocal.aaf[2], &aV3WorldLights[siLightIndex]); 

			pLightMatrix[0].aaf[0][siLightIndex] = fMaxNeg;
			pLightMatrix[0].aaf[1][siLightIndex] = fX; 
			pLightMatrix[0].aaf[2][siLightIndex] = fY; 
			pLightMatrix[0].aaf[3][siLightIndex] = fZ; 

		}
		pLightMatrix[0].aaf[0][2] = 0;

		if ( ( 0 == siSegmentIndex ) && ( a_world_position_vector != NULL ) )
		{
			Vector3_Set( a_world_position_vector, pCTM1->aaf[3][0], pCTM1->aaf[3][1], pCTM1->aaf[3][2] );
		}

//		Matrix4x4_MultByMatrix4x4( &pCTM1[0], pCTM2, &pCTM1[0] );
		ld_ext( (void*)pCTM2);
		mtrx4mul( (void*)&pCTM1[0], (void*)&pCTM1[0]);

		if (a_bCalcWeights)
		{
			// Calculate weighted matrices for 75/25, 50/50, & 25/75
			if (DataBody_aiHierHighParentMap[siSegmentIndex] >= 0)
			{
				si	iLoop;
				const Matrix4x4_tMatrix *pParentMatrix;
	
	//			pParentMatrix = &a_paMatrices[ DataBody_aiHierHighParentMap[siSegmentIndex] ];
				pParentMatrix = &_MatrixBuffer[ DataBody_aiHierHighParentMap[siSegmentIndex] ][0];
	
				ld_ext( (void*)pParentMatrix);
				mtrx4mul( (void*)&_JointWeightMatrixBuffer[siSegmentIndex][1], (void*)&pCTM1[1]);
				mtrx4mul( (void*)&_JointWeightMatrixBuffer[siSegmentIndex][2], (void*)&pCTM1[2]);
				mtrx4mul( (void*)&_JointWeightMatrixBuffer[siSegmentIndex][3], (void*)&pCTM1[3]);
	
				ld_ext( (void*)pCTM1);
				mtrx4muladd( (void*)&_matrix_75, (void*)&pCTM1[1], (void*)&pCTM1[1]);
				mtrx4muladd( (void*)&_matrix_50, (void*)&pCTM1[2], (void*)&pCTM1[2]);
				mtrx4muladd( (void*)&_matrix_25, (void*)&pCTM1[3], (void*)&pCTM1[3]);
	
				for (iLoop = 0; iLoop < 4; iLoop += 1)
				{
					pCTM1[1].aaf[3][iLoop] = pCTM1[0].aaf[3][iLoop];
					pCTM1[2].aaf[3][iLoop] = pCTM1[0].aaf[3][iLoop];
					pCTM1[3].aaf[3][iLoop] = pCTM1[0].aaf[3][iLoop];
				}
	
			}
	
	
			// save result in a temporary buffer (shared buffer so needs to be used before next call)
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix100   = &pCTM1[0];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix75   = &pCTM1[1];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix50   = &pCTM1[2];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix25   = &pCTM1[3];
			a_paJointMatrices[ siSegmentIndex ].pLightMatrix = pLightMatrix;
		}
		else
		{
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix100   = &pCTM1[0];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix75   = &pCTM1[0];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix50   = &pCTM1[0];
			a_paJointMatrices[ siSegmentIndex ].pRotMatrix25   = &pCTM1[0];
			a_paJointMatrices[ siSegmentIndex ].pLightMatrix = pLightMatrix;
		}
	}

Prof_EndSection( PROF_SECTION_DRAWCHARMATH );	

}

