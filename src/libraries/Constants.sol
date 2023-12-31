// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

uint constant COMP_FACTOR = 1e18;
uint constant ACCURACY = 1e4;
uint constant COMP100APR = 317100000 * 100;
uint constant RAY = 1e27;
uint constant H_RAY = RAY / 2;
uint constant R = 1e9;
int constant PERCENT_FACTOR = 1e4;
uint constant SECONDS_PER_YEAR = 365 days;
uint constant BYTE = 0xFF;

enum State {
    NO_ALLOCATION,
    PARTIAL_ALLOCATION,
    FULL_ALLOCATION
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
    int aL;
    int tVD;
    int tD;
    int tSD;
    int avgSBR;
    int subFactor; // percFacor - reserveFactor
    int base;
    int vrs1;
    int vrs2;
    int opt;
    int exc;
}

struct KeepData {
    uint8 id;
    uint128 percent;
}

struct YieldVars {
    uint8 id;
    // apr offered
    // deposit: 0 unsupported or not used | x apr offered
    // withdrawal: x apr offered | uint.max unsupported or not used
    uint apr;
    // caching apr, while not affecting the order
    uint cacheApr;
    // amount to be deployed
    uint amt;
    // @dev amount cap for deposit or withdraw
    // deposit: 0 maxed out | x amount available | uint.max unlimited, no limit
    // withdrawal: 0 no more available | x amount available
    uint limit;
    // reserve data
    bytes r;
}
