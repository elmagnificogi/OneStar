#pragma once
#include "CudaProcess.cuh"

// 6�A�̒l����v�Z�p

void Cuda6Initialize();
void Cuda6SetMasterData();

void Cuda6Process(_u32 param, int partition); //�����֐�
void Cuda6Finalize();
