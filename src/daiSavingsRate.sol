/// daiSavingsRate.sol -- Dai Savings Rate

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.12;

import "./commonFunctions.sol";

/*
   "Savings Dai" is obtained when Dai is deposited into
   this contract. Each "Savings Dai" accrues Dai interest
   at the "Dai Savings Rate".

   This contract does not implement a user tradeable token
   and is intended to be used with adapters.

         --- `save` your `dai` in the `pot` ---

   - `daiSavingsRate`: the Dai Savings Rate
   - `userSavingsBalance`: user balance of Savings Dai

   - `enableDSR`: start saving some dai
   - `disableDSR`: remove some dai
   - `collectRate`: perform rate collection

*/

contract VatLike {
    function move(address, address, uint256) external;
    function suck(address, address, uint256) external;
}

contract DaiSavingsRateContract is CommonFunctions {
    // --- Data ---
    mapping(address => uint256) public userSavingsBalance; // user Savings Dai

    uint256 public totalSavingsRate; // total Savings Dai
    uint256 public daiSavingsRate; // the Dai Savings Rate
    uint256 public rateAccumulator; // the Rate Accumulator

    VatLike public CDPEngine; // CDP engine
    address public debtEngine; // debt engine
    uint256 public timeOfLastCollectionRate; // time of last collectRate

    bool public DSRisActive; // Access Flag

    // --- Init ---
    constructor(address CDPEngine_) public {
        authorizedAccounts[msg.sender] = true;
        CDPEngine = VatLike(CDPEngine_);
        daiSavingsRate = ONE;
        rateAccumulator = ONE;
        timeOfLastCollectionRate = now;
        DSRisActive = true;
    }

    // --- Math ---
    uint256 constant ONE = 10 ** 27;

    function rpow(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function rsafeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = safeMul(x, y) / ONE;
    }

    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function safeSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        require(DSRisActive == true, "DaiSavingsRateContract/not-DSRisActive");
        require(now == timeOfLastCollectionRate, "DaiSavingsRateContract/timeOfLastCollectionRate-not-updated");
        if (what == "daiSavingsRate") daiSavingsRate = data;
        else revert("DaiSavingsRateContract/file-unrecognized-param");
    }

    function file(bytes32 what, address addr) external emitLog onlyOwners {
        if (what == "debtEngine") debtEngine = addr;
        else revert("DaiSavingsRateContract/file-unrecognized-param");
    }

    function cage() external emitLog onlyOwners {
        DSRisActive = false;
        daiSavingsRate = ONE;
    }

    // --- Savings Rate Accumulation ---
    function collectRate() external emitLog returns (uint256 tmp) {
        require(now >= timeOfLastCollectionRate, "DaiSavingsRateContract/invalid-now");
        tmp = rsafeMul(rpow(daiSavingsRate, now - timeOfLastCollectionRate, ONE), rateAccumulator);
        uint256 rateAccumulator_ = safeSub(tmp, rateAccumulator);
        rateAccumulator = tmp;
        timeOfLastCollectionRate = now;
        CDPEngine.suck(address(debtEngine), address(this), safeMul(totalSavingsRate, rateAccumulator_));
    }

    // --- Savings Dai Management ---
    function enableDSR(uint256 wad) external emitLog {
        require(now == timeOfLastCollectionRate, "DaiSavingsRateContract/timeOfLastCollectionRate-not-updated");
        userSavingsBalance[msg.sender] = safeAdd(userSavingsBalance[msg.sender], wad);
        totalSavingsRate = safeAdd(totalSavingsRate, wad);
        CDPEngine.move(msg.sender, address(this), safeMul(rateAccumulator, wad));
    }

    function disableDSR(uint256 wad) external emitLog {
        userSavingsBalance[msg.sender] = safeSub(userSavingsBalance[msg.sender], wad);
        totalSavingsRate = safeSub(totalSavingsRate, wad);
        CDPEngine.move(address(this), msg.sender, safeMul(rateAccumulator, wad));
    }
}
