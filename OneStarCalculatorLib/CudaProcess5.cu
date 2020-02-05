#include "CudaProcess5.cuh"
#include "Data.h"

//�f�o�C�X�������̃|�C���^
static CudaInputMaster* pDeviceInput;
static _u32* pDeviceCoefficientData;
static _u32* pDeviceSearchPattern;
static int* pDeviceResultCount;
static _u64* pDeviceResult;

// ������s�萔
const int c_SizeBlockX = 1024;
const int c_SizeGridX = 1024 * 512;
const int c_SizeResult = 32;

// �v�Z����J�[�l��
__global__ static void kernel_calc(
	CudaInputMaster* pSrc,
	_u32* pCoefficient,
	_u32* pSearchPattern,
	int* pResultCount,
	_u64* pResult,
	_u32 param)
{
	int targetId = (blockIdx.x / 16) * 1024 + threadIdx.x; // �ő�19bit - 4bit + 10bit = 25bit
	int chunkId = blockIdx.x % 16;

	param |= targetId; // 25bit

	_u32 targetUpper = 0;
	_u32 targetLower = 0;

	// ����25bit = �̒l
	targetUpper |= (param & 0x1F00000ul); // iv0_0
	targetLower |= ((param & 0x3E0ul) << 10); // iv3_0
	targetUpper |= ((param & 0xF8000ul) >> 5); // iv1_0
	targetLower |= ((param & 0x1Ful) << 5); // iv4_0
	targetUpper |= ((param & 0x7C00ul) >> 10); // iv2_0

	// �B���ꂽ�l�𐄒�
	targetUpper |= ((32ul + pSrc->ivs[0] - ((param & 0x1F00000ul) >> 20)) & 0x1F) << 15;
	targetLower |= ((32ul + pSrc->ivs[3] - ((param & 0x3E0ul) >> 5)) & 0x1F) << 10;
	targetUpper |= ((32ul + pSrc->ivs[1] - ((param & 0xF8000ul) >> 15)) & 0x1F) << 5;
	targetLower |= ((32ul + pSrc->ivs[4] - (param & 0x1Ful)) & 0x1F);
	targetLower |= ((32ul + pSrc->ivs[2] - ((param & 0x7C00ul) >> 10)) & 0x1F) << 20;

	// target�x�N�g�����͊���

	targetUpper ^= pSrc->constantTermVector[0];
	targetLower ^= pSrc->constantTermVector[1];

	// ���������L���b�V��

	__shared__ _u32 answerFlag[128];
	__shared__ _u32 coefficientData[1024 * 2];
	__shared__ _u32 searchPattern[1024];
	__shared__ PokemonData pokemon[4];
	__shared__ int ecBit;
	__shared__ bool ecMod[3][6];

	if(threadIdx.x % 8 == 0)
	{
		answerFlag[threadIdx.x / 8] = pSrc->answerFlag[threadIdx.x / 8];
	}
	else if(threadIdx.x % 8 == 1)
	{
		pokemon[0] = pSrc->pokemon[0];
	}
	else if(threadIdx.x % 8 == 2)
	{
		pokemon[1] = pSrc->pokemon[1];
	}
	else if(threadIdx.x % 8 == 3)
	{
		pokemon[2] = pSrc->pokemon[2];
	}
	else if(threadIdx.x % 8 == 4)
	{
		pokemon[3] = pSrc->pokemon[3];
	}
	else if(threadIdx.x % 8 == 5)
	{
		ecBit = pSrc->ecBit;
	}
	else if(threadIdx.x % 8 == 6)
	{
		ecMod[0][0] = pSrc->ecMod[0][0];
		ecMod[0][1] = pSrc->ecMod[0][1];
		ecMod[0][2] = pSrc->ecMod[0][2];
		ecMod[0][3] = pSrc->ecMod[0][3];
		ecMod[0][4] = pSrc->ecMod[0][4];
		ecMod[0][5] = pSrc->ecMod[0][5];
		ecMod[1][0] = pSrc->ecMod[1][0];
		ecMod[1][1] = pSrc->ecMod[1][1];
		ecMod[1][2] = pSrc->ecMod[1][2];
	}
	else if(threadIdx.x % 8 == 7)
	{
		ecMod[1][3] = pSrc->ecMod[1][3];
		ecMod[1][4] = pSrc->ecMod[1][4];
		ecMod[1][5] = pSrc->ecMod[1][5];
		ecMod[2][0] = pSrc->ecMod[2][0];
		ecMod[2][1] = pSrc->ecMod[2][1];
		ecMod[2][2] = pSrc->ecMod[2][2];
		ecMod[2][3] = pSrc->ecMod[2][3];
		ecMod[2][4] = pSrc->ecMod[2][4];
		ecMod[2][5] = pSrc->ecMod[2][5];
	}
	coefficientData[threadIdx.x * 2] = pCoefficient[chunkId * 2048 + threadIdx.x * 2];
	coefficientData[threadIdx.x * 2 + 1] = pCoefficient[chunkId * 2048 + threadIdx.x * 2 + 1];
	searchPattern[threadIdx.x] = pSearchPattern[chunkId * 1024 + threadIdx.x];

	__syncthreads();

	_u32 processedTargetUpper = 0;
	_u32 processedTargetLower = 0;
	for(int i = 0; i < 32; ++i)
	{
		processedTargetUpper |= (CudaGetSignature(answerFlag[i * 2] & targetUpper) ^ CudaGetSignature(answerFlag[i * 2 + 1] & targetLower)) << (31 - i);
		processedTargetLower |= (CudaGetSignature(answerFlag[(i + 32) * 2] & targetUpper) ^ CudaGetSignature(answerFlag[(i + 32) * 2 + 1] & targetLower)) << (31 - i);
	}

	_u32 seeds[7]; // S0Upper�AS0Lower�AS1Upper�AS1Lower
	_u32 next[7]; // S0Upper�AS0Lower�AS1Upper�AS1Lower
	_u64 temp64;
	_u32 temp32;
	for(int i = 0; i < 1024; ++i)
	{
		seeds[0] = processedTargetUpper ^ coefficientData[i * 2];
		seeds[1] = processedTargetLower ^ coefficientData[i * 2 + 1] | searchPattern[i];

		// ��`�ӏ�

		if(ecBit >= 0 && (seeds[1] & 1) != ecBit)
		{
			continue;
		}

		temp64 = ((_u64)seeds[0] << 32 | seeds[1]) + 0x82a2b175229d6a5bull;

		seeds[2] = 0x82a2b175ul;
		seeds[3] = 0x229d6a5bul;

		next[0] = (_u32)(temp64 >> 32);
		next[1] = (_u32)temp64;
		next[2] = 0x82a2b175ul;
		next[3] = 0x229d6a5bul;

		temp64 = ((_u64)seeds[0] << 32 | seeds[1]);

		// ��������i�荞��

		// EC
		temp32 = CudaNext(seeds, 0xFFFFFFFFu);
		// 1�C�ڌ�
		if(ecMod[0][temp32 % 6] == false)
		{
			continue;
		}
		// 2�C�ڌ�
		if(ecMod[1][temp32 % 6] == false)
		{
			continue;
		}

		// EC
		temp32 = CudaNext(next, 0xFFFFFFFFu);
		// 3�C�ڌ�
		if(ecMod[2][temp32 % 6] == false)
		{
			continue;
		}

		// 2�C�ڂ��Ƀ`�F�b�N
		CudaNext(next); // OTID
		CudaNext(next); // PID

		{
			int ivs[6] = { -1, -1, -1, -1, -1, -1 };
			temp32 = 0;
			do {
				int fixedIndex = 0;
				do {
					fixedIndex = CudaNext(next, 7); // V�ӏ�
				} while(fixedIndex >= 6);

				if(ivs[fixedIndex] == -1)
				{
					ivs[fixedIndex] = 31;
					++temp32;
				}
			} while(temp32 < pokemon[2].flawlessIvs);

			// �̒l
			temp32 = 1;
			for(int i = 0; i < 6; ++i)
			{
				if(ivs[i] == 31)
				{
					if(pokemon[2].ivs[i] != 31)
					{
						temp32 = 0;
						break;
					}
				}
				else if(pokemon[2].ivs[i] != CudaNext(next, 0x1F))
				{
					temp32 = 0;
					break;
				}
			}
			if(temp32 == 0)
			{
				continue;
			}

			// ����
			temp32 = 0;
			if(pokemon[2].abilityFlag == 3)
			{
				temp32 = CudaNext(next, 1);
			}
			else
			{
				do {
					temp32 = CudaNext(next, 3);
				} while(temp32 >= 3);
			}
			if((pokemon[2].ability >= 0 && pokemon[2].ability != temp32) || (pokemon[2].ability == -1 && temp32 >= 2))
			{
				continue;
			}

			// ���ʒl
			if(!pokemon[2].isNoGender)
			{
				temp32 = 0;
				do {
					temp32 = CudaNext(next, 0xFF);
				} while(temp32 >= 253);
			}

			// ���i
			temp32 = 0;
			do {
				temp32 = CudaNext(next, 0x1F);
			} while(temp32 >= 25);

			if(temp32 != pokemon[2].nature)
			{
				continue;
			}
		}

		// 1�C��
		CudaNext(seeds); // OTID
		CudaNext(seeds); // PIT

		{
			// ��Ԃ�ۑ�
			next[0] = seeds[0];
			next[1] = seeds[1];
			next[2] = seeds[2];
			next[3] = seeds[3];

			{
				int ivs[6] = { -1, -1, -1, -1, -1, -1 };
				temp32 = 0;
				do {
					int fixedIndex = 0;
					do {
						fixedIndex = CudaNext(seeds, 7); // V�ӏ�
					} while(fixedIndex >= 6);

					if(ivs[fixedIndex] == -1)
					{
						ivs[fixedIndex] = 31;
						++temp32;
					}
				} while(temp32 < pokemon[0].flawlessIvs);

				// �̒l
				temp32 = 1;
				for(int i = 0; i < 6; ++i)
				{
					if(ivs[i] == 31)
					{
						if(pokemon[0].ivs[i] != 31)
						{
							temp32 = 0;
							break;
						}
					}
					else if(pokemon[0].ivs[i] != CudaNext(seeds, 0x1F))
					{
						temp32 = 0;
						break;
					}
				}
				if(temp32 == 0)
				{
					continue;
				}
			}
			{
				int ivs[6] = { -1, -1, -1, -1, -1, -1 };
				temp32 = 0;
				do {
					int fixedIndex = 0;
					do {
						fixedIndex = CudaNext(next, 7); // V�ӏ�
					} while(fixedIndex >= 6);

					if(ivs[fixedIndex] == -1)
					{
						ivs[fixedIndex] = 31;
						++temp32;
					}
				} while(temp32 < pokemon[1].flawlessIvs);

				// �̒l
				temp32 = 1;
				for(int i = 0; i < 6; ++i)
				{
					if(ivs[i] == 31)
					{
						if(pokemon[1].ivs[i] != 31)
						{
							temp32 = 0;
							break;
						}
					}
					else if(pokemon[1].ivs[i] != CudaNext(next, 0x1F))
					{
						temp32 = 0;
						break;
					}
				}
				if(temp32 == 0)
				{
					continue;
				}
			}

			// ����
			temp32 = 0;
			if(pokemon[0].abilityFlag == 3)
			{
				temp32 = CudaNext(seeds, 1);
			}
			else
			{
				do {
					temp32 = CudaNext(seeds, 3);
				} while(temp32 >= 3);
			}
			if((pokemon[0].ability >= 0 && pokemon[0].ability != temp32) || (pokemon[0].ability == -1 && temp32 >= 2))
			{
				continue;
			}
			temp32 = 0;
			if(pokemon[1].abilityFlag == 3)
			{
				temp32 = CudaNext(next, 1);
			}
			else
			{
				do {
					temp32 = CudaNext(next, 3);
				} while(temp32 >= 3);
			}
			if((pokemon[1].ability >= 0 && pokemon[1].ability != temp32) || (pokemon[1].ability == -1 && temp32 >= 2))
			{
				continue;
			}

			// ���ʒl
			if(!pokemon[0].isNoGender)
			{
				temp32 = 0;
				do {
					temp32 = CudaNext(seeds, 0xFF);
				} while(temp32 >= 253);
			}
			if(!pokemon[1].isNoGender)
			{
				temp32 = 0;
				do {
					temp32 = CudaNext(next, 0xFF);
				} while(temp32 >= 253);
			}

			// ���i
			temp32 = 0;
			do {
				temp32 = CudaNext(seeds, 0x1F);
			} while(temp32 >= 25);
			if(temp32 != pokemon[0].nature)
			{
				continue;
			}
			temp32 = 0;
			do {
				temp32 = CudaNext(next, 0x1F);
			} while(temp32 >= 25);
			if(temp32 != pokemon[1].nature)
			{
				continue;
			}
		}
		// ���ʂ���������
		int old = atomicAdd(pResultCount, 1);
		pResult[old] = temp64;
	}
	return;
}

// ������������
void Cuda5Initialize()
{
	// �z�X�g�������̊m��
	cudaMallocHost(&cu_HostInputCoefficientData, sizeof(_u32) * 0x8000);
	cudaMallocHost(&cu_HostInputSearchPattern, sizeof(_u32) * 0x4000);

	// �f�o�C�X�������̊m��
	cudaMalloc(&pDeviceInput, sizeof(CudaInputMaster));
	cudaMalloc(&pDeviceCoefficientData, sizeof(_u32) * 0x8000);
	cudaMalloc(&pDeviceSearchPattern, sizeof(_u32) * 0x4000);
	cudaMalloc(&pDeviceResultCount, sizeof(int));
	cudaMalloc(&pDeviceResult, sizeof(_u64) * c_SizeResult);
}

// �f�[�^�Z�b�g
void Cuda5SetMasterData()
{
	// �z�X�g�f�[�^�̐ݒ�
	cu_HostInputMaster->constantTermVector[0] = (_u32)(g_ConstantTermVector >> 25);
	cu_HostInputMaster->constantTermVector[1] = (_u32)(g_ConstantTermVector & 0x1FFFFFFull);
	for(int i = 0; i < 64; ++i)
	{
		cu_HostInputMaster->answerFlag[i * 2] = (_u32)(g_AnswerFlag[i] >> 25);
		cu_HostInputMaster->answerFlag[i * 2 + 1] = (_u32)(g_AnswerFlag[i] & 0x1FFFFFFull);
	}
	for(int i = 0; i < 16 * 1024; ++i)
	{
		cu_HostInputCoefficientData[i * 2] = (_u32)(g_CoefficientData[i] >> 32);
		cu_HostInputCoefficientData[i * 2 + 1] = (_u32)(g_CoefficientData[i] & 0xFFFFFFFFull);
		cu_HostInputSearchPattern[i] = (_u32)g_SearchPattern[i];
	}

	// �f�[�^��]��
	cudaMemcpy(pDeviceInput, cu_HostInputMaster, sizeof(CudaInputMaster), cudaMemcpyHostToDevice);
	cudaMemcpy(pDeviceCoefficientData, cu_HostInputCoefficientData, sizeof(_u32) * 0x8000, cudaMemcpyHostToDevice);
	cudaMemcpy(pDeviceSearchPattern, cu_HostInputSearchPattern, sizeof(_u32) * 0x4000, cudaMemcpyHostToDevice);
}

// �v�Z
void Cuda5Process(_u32 param, int partition)
{
	// ���ʂ����Z�b�g
	*cu_HostResultCount = 0;
	cudaMemcpy(pDeviceResultCount, cu_HostResultCount, sizeof(int), cudaMemcpyHostToDevice);

	//�J�[�l��
	dim3 block(c_SizeBlockX, 1, 1);
	dim3 grid(c_SizeGridX / partition, 1, 1);
	kernel_calc << < grid, block >> > (pDeviceInput, pDeviceCoefficientData, pDeviceSearchPattern, pDeviceResultCount, pDeviceResult, param);

	//�f�o�C�X->�z�X�g�֌��ʂ�]��
	cudaMemcpy(cu_HostResult, pDeviceResult, sizeof(_u64) * c_SizeResult, cudaMemcpyDeviceToHost);
	cudaMemcpy(cu_HostResultCount, pDeviceResultCount, sizeof(int), cudaMemcpyDeviceToHost);
}

void Cuda5Finalize()
{
	//�f�o�C�X�������̊J��
	cudaFree(pDeviceResult);
	cudaFree(pDeviceResultCount);
	cudaFree(pDeviceSearchPattern);
	cudaFree(pDeviceCoefficientData);
	cudaFree(pDeviceInput);
	//�z�X�g�������̊J��
	cudaFreeHost(cu_HostInputSearchPattern);
	cudaFreeHost(cu_HostInputCoefficientData);
}
