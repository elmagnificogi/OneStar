#pragma once
#include "CudaProcess.cuh"

// 5�A�̒l����v�Z�p

void Cuda5Initialize();
void Cuda5SetMasterData();

void Cuda5Process(_u32 param, int partition); //�����֐�
void Cuda5Finalize();
