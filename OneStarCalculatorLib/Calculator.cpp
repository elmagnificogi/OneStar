#include <iostream>
#include "Util.h"
#include "Calculator.h"
#include "Const.h"
#include "XoroshiroState.h"
#include "Data.h"

// ���������ݒ�
static PokemonData l_Pokemon[3];

static int g_Rerolls;
static int g_FixedIndex;
static bool g_isEnableThird;

// �i�荞�ݏ����ݒ�

// V�m��p�Q��
const int* g_IvsRef[30] = {
	&(l_Pokemon[0].ivs[1]), &(l_Pokemon[0].ivs[2]), &(l_Pokemon[0].ivs[3]), &(l_Pokemon[0].ivs[4]), &(l_Pokemon[0].ivs[5]),
	&(l_Pokemon[0].ivs[0]), &(l_Pokemon[0].ivs[2]), &(l_Pokemon[0].ivs[3]), &(l_Pokemon[0].ivs[4]), &(l_Pokemon[0].ivs[5]),
	&(l_Pokemon[0].ivs[0]), &(l_Pokemon[0].ivs[1]), &(l_Pokemon[0].ivs[3]), &(l_Pokemon[0].ivs[4]), &(l_Pokemon[0].ivs[5]),
	&(l_Pokemon[0].ivs[0]), &(l_Pokemon[0].ivs[1]), &(l_Pokemon[0].ivs[2]), &(l_Pokemon[0].ivs[4]), &(l_Pokemon[0].ivs[5]),
	&(l_Pokemon[0].ivs[0]), &(l_Pokemon[0].ivs[1]), &(l_Pokemon[0].ivs[2]), &(l_Pokemon[0].ivs[3]), &(l_Pokemon[0].ivs[5]),
	&(l_Pokemon[0].ivs[0]), &(l_Pokemon[0].ivs[1]), &(l_Pokemon[0].ivs[2]), &(l_Pokemon[0].ivs[3]), &(l_Pokemon[0].ivs[4]),
};

#define LENGTH_BASE (56)

// �������Ȃ��������w�肠��̏ꍇAbilityBit���L��
// ���������聨����2�̎��̂�AbilityBit���L��(1��3�Ȃ̂Ŋ)
inline bool IsEnableAbilityBit()
{
	return (l_Pokemon[0].ability == 1) || (l_Pokemon[0].abilityFlag == 3 && l_Pokemon[0].ability >= 0);
}

void Set12Condition(int index, int iv0, int iv1, int iv2, int iv3, int iv4, int iv5, int ability, int nature, int characteristic, bool isNoGender, int abilityFlag, int flawlessIvs)
{
	if(index < 0 || index >= 3)
	{
		return;
	}
	if(index != 2)
	{
		g_isEnableThird = false;
	}
	else
	{
		g_isEnableThird = true; // 3�C�ڂ͕K���Ō�ɓo�^
	}

	l_Pokemon[index].ivs[0] = iv0;
	l_Pokemon[index].ivs[1] = iv1;
	l_Pokemon[index].ivs[2] = iv2;
	l_Pokemon[index].ivs[3] = iv3;
	l_Pokemon[index].ivs[4] = iv4;
	l_Pokemon[index].ivs[5] = iv5;
	l_Pokemon[index].ability = ability;
	l_Pokemon[index].nature = nature;
	l_Pokemon[index].characteristic = characteristic;
	l_Pokemon[index].isNoGender = isNoGender;
	l_Pokemon[index].abilityFlag = abilityFlag;
	l_Pokemon[index].flawlessIvs = flawlessIvs;

	// �v�Z�p
	if(index == 0)
	{
		for(int i = 0; i < 6; ++i)
		{
			if(l_Pokemon[index].ivs[i] == 31)
			{
				g_FixedIndex = i;
				break;
			}
		}
	}
}

void Prepare(int rerolls)
{
	const int length = (IsEnableAbilityBit() ? LENGTH_BASE + 1 : LENGTH_BASE);

	g_Rerolls = rerolls;

	// �g�p����s��l���Z�b�g
	// �g�p����萔�x�N�g�����Z�b�g
	
	g_ConstantTermVector = 0;

	// r[3+rerolls]��V�ӏ��Ar[4+rerolls]����r[8+rerolls]���̒l�Ƃ��Ďg��

	// �ϊ��s����v�Z
	InitializeTransformationMatrix(); // r[1]��������ϊ��s�񂪃Z�b�g�����
	for(int i = 0; i <= rerolls + 1; ++i)
	{
		ProceedTransformationMatrix(); // r[2 + i]��������
	}

	int bit = 0;
	for (int i = 0; i < 6; ++i, ++bit)
	{
		int index = 61 + (i / 3) * 64 + (i % 3);
		g_InputMatrix[bit] = GetMatrixMultiplier(index);
		if(GetMatrixConst(index) != 0)
		{
			g_ConstantTermVector |= (1ull << (length - 1 - bit));
		}
	}
	for (int a = 0; a < 5; ++a)
	{
		ProceedTransformationMatrix();
		for(int i = 0; i < 10; ++i, ++bit)
		{
			int index = 59 + (i / 5) * 64 + (i % 5);
			g_InputMatrix[bit] = GetMatrixMultiplier(index);
			if(GetMatrixConst(index) != 0)
			{
				g_ConstantTermVector |= (1ull << (length - 1 - bit));
			}
		}
	}
	// Ability��2�����k r[9+rerolls]
	if(IsEnableAbilityBit())
	{
		ProceedTransformationMatrix();

		g_InputMatrix[LENGTH_BASE] = GetMatrixMultiplier(63) ^ GetMatrixMultiplier(127);
		if((GetMatrixConst(63) ^ GetMatrixConst(127)) != 0)
		{
			g_ConstantTermVector |= 1;
		}
	}

	// �s��{�ό`�ŋ��߂�
	CalculateInverseMatrix(length);

	// ���O�f�[�^���v�Z
	CalculateCoefficientData(length);
}

_u64 Search(_u64 ivs)
{
	const int length = (IsEnableAbilityBit() ? LENGTH_BASE + 1 : LENGTH_BASE);

	XoroshiroState xoroshiro;
	XoroshiroState oshiroTemp;
	XoroshiroState oshiroTemp2;

	_u64 target = (IsEnableAbilityBit() ? (l_Pokemon[0].ability & 1) : 0);
	int bitOffset = (IsEnableAbilityBit() ? 1 : 0);

	// ���3bit = V�ӏ�����
	target |= (ivs & 0xE000000ul) << (28 + bitOffset); // fixedIndex0

	// ����25bit = �̒l
	target |= (ivs & 0x1F00000ul) << (25 + bitOffset); // iv0_0
	target |= (ivs &   0xF8000ul) << (20 + bitOffset); // iv1_0
	target |= (ivs &    0x7C00ul) << (15 + bitOffset); // iv2_0
	target |= (ivs &     0x3E0ul) << (10 + bitOffset); // iv3_0
	target |= (ivs &      0x1Ful) << ( 5 + bitOffset); // iv4_0

	// �B���ꂽ�l�𐄒�
	target |= ((8ul + g_FixedIndex - ((ivs & 0xE000000ul) >> 25)) & 7) << (50 + bitOffset);

	target |= ((32ul + *g_IvsRef[g_FixedIndex * 5    ] - ((ivs & 0x1F00000ul) >> 20)) & 0x1F) << (40 + bitOffset);
	target |= ((32ul + *g_IvsRef[g_FixedIndex * 5 + 1] - ((ivs &   0xF8000ul) >> 15)) & 0x1F) << (30 + bitOffset);
	target |= ((32ul + *g_IvsRef[g_FixedIndex * 5 + 2] - ((ivs &    0x7C00ul) >> 10)) & 0x1F) << (20 + bitOffset);
	target |= ((32ul + *g_IvsRef[g_FixedIndex * 5 + 3] - ((ivs &     0x3E0ul) >> 5)) & 0x1F) << (10 + bitOffset);
	target |= ((32ul + *g_IvsRef[g_FixedIndex * 5 + 4] -  (ivs &      0x1Ful)) & 0x1F) << bitOffset;

	// target�x�N�g�����͊���

	target ^= g_ConstantTermVector;

	// 56~57bit���̌v�Z���ʃL���b�V��
	_u64 processedTarget = 0;
	for (int i = 0; i < 64; ++i)
	{
		if(g_AnswerFlag[i] != 0)
		{
			processedTarget |= (GetSignature(g_AnswerFlag[i] & target) << (63 - i));
		}
	}

	// ����7bit�����߂�
	_u64 max = ((1 << (64 - length)) - 1);
	for (_u64 search = 0; search <= max; ++search)
	{
		_u64 seed = (processedTarget ^ g_CoefficientData[search]) | g_SearchPattern[search];
		
		// ��������i�荞��
		{
			xoroshiro.SetSeed(seed);
			xoroshiro.Next(); // EC
			xoroshiro.Next(); // OTID
			xoroshiro.Next(); // PID

			// V�ӏ�
			int offset = -1;
			int fixedIndex = 0;
			do {
				fixedIndex = xoroshiro.Next(7); // V�ӏ�
				++offset;
			} while (fixedIndex >= 6);

			// reroll��
			if (offset != g_Rerolls)
			{
				continue;
			}

			xoroshiro.Next(); // �̒l1
			xoroshiro.Next(); // �̒l2
			xoroshiro.Next(); // �̒l3
			xoroshiro.Next(); // �̒l4
			xoroshiro.Next(); // �̒l5

			// �C�x���g���C�h�̖������������[�h
			bool isPassed = false;
			if(l_Pokemon[0].abilityFlag == 2 && l_Pokemon[0].ability == 2)
			{
				oshiroTemp2.Copy(&xoroshiro);

				// �����X�L�b�v

				// ���ʒl
				if(!l_Pokemon[0].isNoGender)
				{
					int gender = 0;
					do {
						gender = xoroshiro.Next(0xFF); // ���ʒl
					} while(gender >= 253);
				}

				int nature = 0;
				do {
					nature = xoroshiro.Next(0x1F); // ���i
				} while(nature >= 25);

				if(nature == l_Pokemon[0].nature)
				{
					isPassed = true;
				}

				xoroshiro.Copy(&oshiroTemp2);
			}
			if(isPassed == false)
			{
				// ����
				{
					int ability = 0;
					if(l_Pokemon[0].abilityFlag == 3)
					{
						ability = xoroshiro.Next(1);
					}
					else
					{
						do {
							ability = xoroshiro.Next(3);
						} while(ability >= 3);
					}
					if((l_Pokemon[0].ability >= 0 && l_Pokemon[0].ability != ability) || (l_Pokemon[0].ability == -1 && ability >= 2))
					{
						continue;
					}
				}

				// ���ʒl
				if(!l_Pokemon[0].isNoGender)
				{
					int gender = 0;
					do {
						gender = xoroshiro.Next(0xFF); // ���ʒl
					} while(gender >= 253);
				}

				int nature = 0;
				do {
					nature = xoroshiro.Next(0x1F); // ���i
				} while(nature >= 25);

				if(nature != l_Pokemon[0].nature)
				{
					continue;
				}
			}
		}

		// 2�C��
		_u64 nextSeed = seed + 0x82a2b175229d6a5bull;
		{
			xoroshiro.SetSeed(nextSeed);
			xoroshiro.Next(); // EC
			xoroshiro.Next(); // OTID
			xoroshiro.Next(); // PID

			int vCount = l_Pokemon[1].flawlessIvs;

			// �̒l�v�Z
			int ivs[6] = { -1, -1, -1, -1, -1, -1 };
			int fixedCount = 0;
			do {
				int fixedIndex = 0;
				do {
					fixedIndex = xoroshiro.Next(7); // V�ӏ�
				} while(fixedIndex >= 6);

				if(ivs[fixedIndex] == -1)
				{
					ivs[fixedIndex] = 31;
					++fixedCount;
				}
			} while(fixedCount < vCount);

			// �̒l�`�F�b�N
			bool isPassed = true;
			for(int i = 0; i < 6; ++i)
			{
				if(ivs[i] == 31)
				{
					if(l_Pokemon[1].ivs[i] != 31)
					{
						isPassed = false;
						break;
					}
				}
				else if(l_Pokemon[1].ivs[i] != xoroshiro.Next(0x1F))
				{
					isPassed = false;
					break;
				}
			}
			if(!isPassed)
			{
				continue;
			}

			// �C�x���g���C�h�̖������������[�h
			isPassed = false;
			if(l_Pokemon[1].abilityFlag == 2 && l_Pokemon[1].ability == 2)
			{
				oshiroTemp2.Copy(&xoroshiro);

				// �����X�L�b�v

				// ���ʒl
				if(!l_Pokemon[1].isNoGender)
				{
					int gender = 0;
					do {
						gender = xoroshiro.Next(0xFF); // ���ʒl
					} while(gender >= 253);
				}

				int nature = 0;
				do {
					nature = xoroshiro.Next(0x1F); // ���i
				} while(nature >= 25);

				if(nature == l_Pokemon[1].nature)
				{
					isPassed = true;
				}

				xoroshiro.Copy(&oshiroTemp2);
			}
			if(isPassed == false)
			{
				// ����
				int ability = 0;
				if(l_Pokemon[1].abilityFlag == 3)
				{
					ability = xoroshiro.Next(1);
				}
				else
				{
					do {
						ability = xoroshiro.Next(3);
					} while(ability >= 3);
				}
				if((l_Pokemon[1].ability >= 0 && l_Pokemon[1].ability != ability) || (l_Pokemon[1].ability == -1 && ability >= 2))
				{
					continue;
				}

				// ���ʒl
				if(!l_Pokemon[1].isNoGender)
				{
					int gender = 0;
					do {
						gender = xoroshiro.Next(0xFF);
					} while(gender >= 253);
				}

				// ���i
				int nature = 0;
				do {
					nature = xoroshiro.Next(0x1F);
				} while(nature >= 25);

				if(nature != l_Pokemon[1].nature)
				{
					continue;
				}
			}
		}
		// 3�C�ڃ`�F�b�N
		if(g_isEnableThird)
		{
			nextSeed = nextSeed + 0x82a2b175229d6a5bull;
			{
				xoroshiro.SetSeed(nextSeed);
				xoroshiro.Next(); // EC
				xoroshiro.Next(); // OTID
				xoroshiro.Next(); // PID

				int vCount = l_Pokemon[2].flawlessIvs;

				// �̒l�v�Z
				int ivs[6] = { -1, -1, -1, -1, -1, -1 };
				int fixedCount = 0;
				do {
					int fixedIndex = 0;
					do {
						fixedIndex = xoroshiro.Next(7); // V�ӏ�
					} while(fixedIndex >= 6);

					if(ivs[fixedIndex] == -1)
					{
						ivs[fixedIndex] = 31;
						++fixedCount;
					}
				} while(fixedCount < vCount);

				// �̒l�`�F�b�N
				bool isPassed = true;
				for(int i = 0; i < 6; ++i)
				{
					if(ivs[i] == 31)
					{
						if(l_Pokemon[2].ivs[i] != 31)
						{
							isPassed = false;
							break;
						}
					}
					else if(l_Pokemon[2].ivs[i] != xoroshiro.Next(0x1F))
					{
						isPassed = false;
						break;
					}
				}
				if(!isPassed)
				{
					continue;
				}

				// �C�x���g���C�h�̖������������[�h
				isPassed = false;
				if(l_Pokemon[2].abilityFlag == 2 && l_Pokemon[2].ability == 2)
				{
					oshiroTemp2.Copy(&xoroshiro);

					// �����X�L�b�v

					// ���ʒl
					if(!l_Pokemon[2].isNoGender)
					{
						int gender = 0;
						do {
							gender = xoroshiro.Next(0xFF); // ���ʒl
						} while(gender >= 253);
					}

					int nature = 0;
					do {
						nature = xoroshiro.Next(0x1F); // ���i
					} while(nature >= 25);

					if(nature == l_Pokemon[2].nature)
					{
						isPassed = true;
					}

					xoroshiro.Copy(&oshiroTemp2);
				}
				if(isPassed == false)
				{
					// ����
					int ability = 0;
					if(l_Pokemon[2].abilityFlag == 3)
					{
						ability = xoroshiro.Next(1);
					}
					else
					{
						do {
							ability = xoroshiro.Next(3);
						} while(ability >= 3);
					}
					if((l_Pokemon[2].ability >= 0 && l_Pokemon[2].ability != ability) || (l_Pokemon[2].ability == -1 && ability >= 2))
					{
						continue;
					}

					// ���ʒl
					if(!l_Pokemon[2].isNoGender)
					{
						int gender = 0;
						do {
							gender = xoroshiro.Next(0xFF);
						} while(gender >= 253);
					}

					// ���i
					int nature = 0;
					do {
						nature = xoroshiro.Next(0x1F);
					} while(nature >= 25);

					if(nature != l_Pokemon[2].nature)
					{
						continue;
					}
				}
			}
		}
		return seed;
	}
	return 0;
}
