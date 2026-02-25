/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc_test_bench.cpp (Software)
 * Description: Verification suite for Software PMRC implementation.
 * Provides reconstructed coefficients and digital signatures
 * for comparison with RTL simulation results.
 */

#include <iostream>
#include <vector>
#include <string>
#include "pmrc.hpp"

int main() {
    // ---------------------------------------------------------
    // 1. Initialization and Input Parsing
    // ---------------------------------------------------------
    int k;
    if (!(std::cin >> k)) return 0;

    std::vector<mrc_pro::int64> moduli(k);
    std::vector<mrc_pro::int64> residues(k);
    std::vector<mrc_pro::BigInt> lut(k - 1);

    std::string temp;

    for (int i = 0; i < k; i++) {
        if (std::cin >> temp) moduli[i] = std::stoll(temp, nullptr, 0);
    }

    for (int i = 0; i < k; i++) {
        if (std::cin >> temp) residues[i] = std::stoll(temp, nullptr, 0);
    }
    
    for (int i = 0; i < k - 1; i++) {
        if (std::cin >> temp) lut[i] = mrc_pro::BigInt(temp);
    }

    // ---------------------------------------------------------
    // 2. Execution and Metrics
    // ---------------------------------------------------------
    mrc_pro::BigInt result = mrc_pro::Parallel_MRC_Tree(residues, moduli, lut);
    
    // Calculate decimal string for the digital signature calculation 
    std::string resStr = result.toString();
    int sig = 0;
    for(char c : resStr) if(isdigit(c)) sig += (c - '0');

    // Generate the hex string for the report output
    std::string hexResult = result.toHexString();

    // ---------------------------------------------------------
    // 3. Status Reporting 
    // ---------------------------------------------------------
    std::cout << "\n==========================================" << std::endl;
    std::cout << "   MRC SOFTWARE VERIFICATION REPORT" << std::endl;
    std::cout << "==========================================" << std::endl;
    
    // Output the hex version 
    std::cout << "RECONSTRUCTED X (Hex): " << hexResult << std::endl;
    
    // Output the digital signature
    std::cout << "DIGITAL SIGNATURE:     " << sig << std::endl;
    std::cout << "==========================================" << std::endl;

    return 0;
}