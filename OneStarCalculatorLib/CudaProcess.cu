#include "CudaProcess.cuh"

// �ϐ�����
CudaInputMaster* cu_HostInputMaster;
_u32* cu_HostInputCoefficientData;
_u32* cu_HostInputSearchPattern;

// ���ʋ���
int* cu_HostResultCount;
_u64* cu_HostResult;

// �萔
const int c_SizeResult = 32;

// ������
void CudaInitializeImpl()
{
	// �z�X�g�������̊m��
	cudaMallocHost(&cu_HostInputMaster, sizeof(CudaInputMaster));
	cudaMallocHost(&cu_HostResultCount, sizeof(int));
	cudaMallocHost(&cu_HostResult, sizeof(_u64) * c_SizeResult);

	// �f�[�^�̏�����
	cu_HostInputMaster->ecBit = -1;
}

// �I��
void CudaFinalizeImpl()
{
	// �z�X�g���������
	cudaFreeHost(cu_HostResult);
	cudaFreeHost(cu_HostResultCount);
	cudaFreeHost(cu_HostInputMaster);
}
