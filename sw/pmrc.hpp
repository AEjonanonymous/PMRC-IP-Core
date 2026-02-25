/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc.hpp
 * Description: High-performance Parallel Mixed-Radix Conversion (PMRC) library 
 * supporting arbitrary precision arithmetic and recursive 
 * tree-based reconstruction.
 */

#ifndef PMRC_HPP
#define PMRC_HPP

#include <vector>
#include <string>
#include <algorithm>
#include <iostream>
#include <iomanip>

namespace mrc_pro {
    // ---------------------------------------------------------
    // 1. Type Definitions & Constants
    // ---------------------------------------------------------
    typedef long long int64;

    // ---------------------------------------------------------
    // 2. BigInt Arithmetic Engine
    // ---------------------------------------------------------
    struct BigInt {
        std::vector<int> d;
        bool neg = false;
        static const int BASE = 1e9;

        BigInt(long long v = 0) {
            if (v < 0) { neg = true; v = -v; }
            if (v == 0) d.push_back(0);
            while (v > 0) { d.push_back(v % BASE); v /= BASE; }
        }

        BigInt(std::string s) {
            if (s.empty()) { d.push_back(0); return; }
            if (s.find("0x") != std::string::npos) {
                *this = fromHex(s);
            } else {
                if (s[0] == '-') { neg = true; s = s.substr(1); }
                for (int i = (int)s.size(); i > 0; i -= 9) {
                    if (i < 9) d.push_back(std::stoi(s.substr(0, i)));
                    else d.push_back(std::stoi(s.substr(i - 9, 9)));
                }
                trim();
            }
        }

        static BigInt fromHex(std::string s) {
            BigInt res(0);
            size_t i = 0;
            if (s[0] == '-') i++;
            if (s.substr(i, 2) == "0x") i += 2;
            for (; i < s.length(); i++) {
                int val = 0;
                if (s[i] >= '0' && s[i] <= '9') val = s[i] - '0';
                else if (s[i] >= 'a' && s[i] <= 'f') val = s[i] - 'a' + 10;
                else if (s[i] >= 'A' && s[i] <= 'F') val = s[i] - 'A' + 10;
                res = (res * 16) + BigInt(val);
            }
            if (s[0] == '-') res.neg = true;
            res.trim();
            return res;
        }

        void trim() {
            while (d.size() > 1 && d.back() == 0) d.pop_back();
            if (d.empty()) { d.push_back(0); neg = false; }
            if (d.size() == 1 && d[0] == 0) neg = false;
        }

        // --- Comparison Operators ---
        bool operator<(const BigInt& a) const {
            if (neg != a.neg) return neg;
            if (d.size() != a.d.size()) return neg ? d.size() > a.d.size() : d.size() < a.d.size();
            for (int i = (int)d.size() - 1; i >= 0; i--)
                if (d[i] != a.d[i]) return neg ? d[i] > a.d[i] : d[i] < a.d[i];
            return false;
        }
        bool operator>(const BigInt& a) const { return a < *this; }
        bool operator<=(const BigInt& a) const { return !(*this > a); }
        bool operator>=(const BigInt& a) const { return !(*this < a); }
        bool operator==(const BigInt& a) const { return neg == a.neg && d == a.d; }
        bool operator!=(const BigInt& a) const { return !(*this == a); }

        // --- Mathematical Operators ---
        BigInt operator+(const BigInt& a) const {
            if (neg == a.neg) {
                BigInt res = *this; int c = 0;
                for (size_t i = 0; i < std::max(res.d.size(), a.d.size()) || c; ++i) {
                    if (i == res.d.size()) res.d.push_back(0);
                    long long cur = (long long)c + res.d[i] + (i < a.d.size() ? a.d[i] : 0);
                    res.d[i] = (int)(cur % BASE); c = (int)(cur / BASE);
                }
                return res;
            }
            BigInt tmp = a; tmp.neg = !a.neg; return *this - tmp;
        }

        BigInt operator-(const BigInt& a) const {
            if (neg != a.neg) { BigInt tmp = a; tmp.neg = !a.neg; return *this + tmp; }
            if ((!neg && *this < a) || (neg && *this > a)) { BigInt res = a - *this; res.neg = !neg; return res; }
            BigInt res = *this; int c = 0;
            for (size_t i = 0; i < a.d.size() || c; ++i) {
                long long cur = (long long)res.d[i] - c - (i < a.d.size() ? a.d[i] : 0);
                c = cur < 0; if (c) cur += BASE; res.d[i] = (int)cur;
            }
            res.trim(); return res;
        }

        BigInt operator*(const BigInt& a) const {
            BigInt res; res.d.resize(d.size() + a.d.size(), 0);
            for (size_t i = 0; i < d.size(); ++i) {
                long long c = 0;
                for (size_t j = 0; j < a.d.size() || c; ++j) {
                    long long cur = res.d[i+j] + (long long)d[i] * (j < a.d.size() ? a.d[j] : 0) + c;
                    res.d[i+j] = (int)(cur % BASE); c = cur / BASE;
                }
            }
            res.neg = neg != a.neg; res.trim(); return res;
        }

        BigInt operator%(const BigInt& a) const {
            if (a.d.size() == 1 && a.d[0] == 0) return 0;
            BigInt b = a; b.neg = false;
            BigInt cur(0);
            for (int i = (int)d.size() - 1; i >= 0; i--) {
                cur = (cur * BASE) + BigInt(d[i]);
                int l = 0, r = BASE - 1, x = 0;
                while (l <= r) {
                    int m = l + (r - l) / 2;
                    if (b * (long long)m <= cur) { x = m; l = m + 1; }
                    else r = m - 1;
                }
                cur = cur - (b * (long long)x);
            }
            cur.neg = neg; cur.trim();
            return cur;
        }

        std::string toString() const {
            if (d.empty() || (d.size()==1 && d[0]==0)) return "0";
            std::string s = neg ? "-" : "";
            s += std::to_string(d.back());
            for (int i = (int)d.size() - 2; i >= 0; i--) {
                std::string t = std::to_string(d[i]);
                s += std::string(9 - t.size(), '0') + t;
            }
            return s;
        }

        // Logic to convert BigInt to Hex for verification parity
        std::string toHexString() const {
            if (d.empty() || (d.size() == 1 && d[0] == 0)) return "0";
            std::string hex = "";
            const char* hex_chars = "0123456789abcdef";
            BigInt temp = *this;
            temp.neg = false;
            while (!(temp.d.size() == 1 && temp.d[0] == 0)) {
                long long rem = 0;
                for (int i = (int)temp.d.size() - 1; i >= 0; --i) {
                    long long cur = temp.d[i] + rem * BASE;
                    temp.d[i] = (int)(cur / 16);
                    rem = cur % 16;
                }
                hex += hex_chars[rem];
                temp.trim();
            }
            std::reverse(hex.begin(), hex.end());
            return hex;
        }
    };

    // ---------------------------------------------------------
    // 3. MRC Tree Logic
    // ---------------------------------------------------------
    struct MRC_Node { BigInt v; BigInt p; };

    inline MRC_Node merge_nodes(MRC_Node L, MRC_Node R, BigInt inv) {
        BigInt diff = R.v - L.v;
        diff = diff % R.p;
        if (diff.neg) diff = diff + R.p;
        BigInt k_val = (diff * inv) % R.p;
        return { L.v + (L.p * k_val), L.p * R.p };
    }

    inline MRC_Node build_tree_recursive(const std::vector<int64>& resi, const std::vector<int64>& mods, const std::vector<BigInt>& lut, int& ptr, int s, int e) {
        if (e - s == 1) return { BigInt(resi[s]), BigInt(mods[s]) };
        int m = s + (e - s) / 2;
        MRC_Node L = build_tree_recursive(resi, mods, lut, ptr, s, m);
        MRC_Node R = build_tree_recursive(resi, mods, lut, ptr, m, e);
        return merge_nodes(L, R, lut[ptr++]);
    }

    inline BigInt Parallel_MRC_Tree(const std::vector<int64>& residues, const std::vector<int64>& moduli, const std::vector<BigInt>& lut) {
        int ptr = 0;
        return build_tree_recursive(residues, moduli, lut, ptr, 0, (int)moduli.size()).v;
    }
}
#endif