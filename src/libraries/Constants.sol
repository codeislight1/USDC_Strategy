// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

uint constant COMP_FACTOR = 1e18;
uint constant ACCURACY = 1e3; // safer value as usually the value is around 1e8
uint constant COMP100APR = 317100000 * 100;
uint constant RAY = 1e27;
uint constant H_RAY = RAY / 2;
uint constant R = 1e9;
int constant PERCENT_FACTOR = 1e4;
uint constant DECIMALS = 6;

enum T {
    U, // USDC
    C, // Compound
    A2, // Aave V2
    A3 // Aave V3
}
enum StrategyType {
    COMPOUND,
    AAVE_V2,
    AAVE_V3
}
struct CompoundVars {
    int tS;
    int tB;
    int base;
    int rsl;
    int rsh;
    int kink;
}
struct AaveVars {
    int tVD;
    int tD;
    int aL;
    int tSD;
    int avgSBR;
    int subFactor; // percFacor - reserveFactor
    int base;
    int vrs1;
    int vrs2;
    int opt;
    int exc;
}
struct ReservesVars {
    CompoundVars c;
    AaveVars v2;
    AaveVars v3;
}
struct YieldVar {
    // apr offered
    // deposit: 0 unsupported or not used | x apr offered
    // withdrawal: x apr offered | uint.max unsupported or not used
    uint apr;
    // amount to be deployed
    uint amt;
    // @dev amount cap for deposit or withdraw
    // deposit: 0 maxed out | x amount available | uint.max unlimited, no limit
    // withdrawal: 0 no more available | x amount available
    uint limit;
    StrategyType stratType;
}
