#pragma once
#include "Type.h"
#include "cuda_runtime.h"
#include "Util.h"

// GPU�R�[�h
__device__ __forceinline__ _u32 CudaGetSignature(_u32 value)
{
	value ^= (value >> 16);
	value ^= (value >> 8);
	value ^= (value >> 4);
	value ^= (value >> 2);
	return (value ^ (value >> 1)) & 1;
}
__device__ __forceinline__ _u32 CudaNext(_u32* seeds, _u32 mask)
{
	_u32 value = (seeds[1] + seeds[3]) & mask;

	// m_S1 = m_S0 ^ m_S1;
	seeds[4] = seeds[0] ^ seeds[2];
	seeds[5] = seeds[1] ^ seeds[3];

	// m_S1 = RotateLeft(m_S1, 37);
	seeds[2] = seeds[5] << 5 | seeds[4] >> 27;
	seeds[3] = seeds[4] << 5 | seeds[5] >> 27;

	// m_S0 = RotateLeft(m_S0, 24) ^ m_S1 ^ (m_S1 << 16)
	seeds[6] = (seeds[0] << 24 | seeds[1] >> 8) ^ seeds[4] ^ (seeds[4] << 16 | seeds[5] >> 16);
	seeds[1] = (seeds[1] << 24 | seeds[0] >> 8) ^ seeds[5] ^ (seeds[5] << 16);

	seeds[0] = seeds[6];

	return value;
}
__device__ __forceinline__ void CudaNext(_u32* seeds)
{
	// m_S1 = m_S0 ^ m_S1;
	seeds[4] = seeds[0] ^ seeds[2];
	seeds[5] = seeds[1] ^ seeds[3];

	// m_S1 = RotateLeft(m_S1, 37);
	seeds[2] = seeds[5] << 5 | seeds[4] >> 27;
	seeds[3] = seeds[4] << 5 | seeds[5] >> 27;

	// m_S0 = RotateLeft(m_S0, 24) ^ m_S1 ^ (m_S1 << 16)
	seeds[6] = (seeds[0] << 24 | seeds[1] >> 8) ^ seeds[4] ^ (seeds[4] << 16 | seeds[5] >> 16);
	seeds[1] = (seeds[1] << 24 | seeds[0] >> 8) ^ seeds[5] ^ (seeds[5] << 16);

	seeds[0] = seeds[6];
}

// ���͗p�\����
struct CudaConst
{
	NatureTable natureTable[3];
};
struct CudaInputMaster
{
	// seed�v�Z�萔
	_u32 constantTermVector[2];
	_u32 answerFlag[128];

	// ��������
	int ecBit;
	bool ecMod[3][6];
	int ivs[6];
	int ivsOffset;
	PokemonData pokemon[4];
};

// ���͋���
extern CudaConst* cu_DeviceConstData;
extern CudaInputMaster* cu_HostInputMaster;
extern _u32* cu_HostInputCoefficientData;
extern _u32* cu_HostInputSearchPattern;

// ���ʋ���
extern int* cu_HostResultCount;
extern _u64* cu_HostResult;

// ������
void CudaInitializeImpl();

// �I��
void CudaFinalizeImpl();
