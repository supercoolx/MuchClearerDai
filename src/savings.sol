/// savings.sol -- Dai Savings Rate

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

pragma solidity 0.5.12;

import "./commonFunctions.sol";

/*
   "Savings Dai" is obtained when Dai is deposited into
   this contract. Each "Savings Dai" accrues Dai interest
   at the "Dai Savings Rate".

   This contract does not implement a user tradeable token
   and is intended to be used with adapters.

         --- `save` your `dai` in the `savings` ---

   - `dsr`: the Dai Savings Rate
   - `pie`: user balance of Savings Dai

   - `join`: start saving some dai
   - `exit`: remove some dai
   - `drip`: perform rate collection

*/

contract VaultContract {
    function move(address, address, uint256) external;
    function suck(address, address, uint256) external;
}

contract Savings is CommonFunctions {
    // --- Data ---
    mapping(address => uint256) public pie; // user Savings Dai

    uint256 public Pie; // total Savings Dai
    uint256 public dsr; // the Dai Savings Rate
    uint256 public chi; // the Rate Accumulator

    VaultContract public vault; // CDP engine
    address public settlement; // debt engine
    uint256 public rho; // time of last drip

    uint256 public live; // Access Flag

    // --- Init ---
    constructor(address vault_) public {
        authorizedAccounts[msg.sender] = true;
        vault = VaultContract(vault_);
        dsr = ONE;
        chi = ONE;
        rho = now;
        live = 1;
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

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, y) / ONE;
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        require(live == 1, "Savings/not-live");
        require(now == rho, "Savings/rho-not-updated");
        if (what == "dsr") dsr = data;
        else revert("Savings/file-unrecognized-param");
    }

    function file(bytes32 what, address addr) external emitLog onlyOwners {
        if (what == "settlement") settlement = addr;
        else revert("Savings/file-unrecognized-param");
    }

    function cage() external emitLog onlyOwners {
        live = 0;
        dsr = ONE;
    }

    // --- Savings Rate Accumulation ---
    function drip() external emitLog returns (uint256 tmp) {
        require(now >= rho, "Savings/invalid-now");
        tmp = rmul(rpow(dsr, now - rho, ONE), chi);
        uint256 chi_ = sub(tmp, chi);
        chi = tmp;
        rho = now;
        vault.suck(address(settlement), address(this), mul(Pie, chi_));
    }

    // --- Savings Dai Management ---
    function join(uint256 wad) external emitLog {
        require(now == rho, "Savings/rho-not-updated");
        pie[msg.sender] = add(pie[msg.sender], wad);
        Pie = add(Pie, wad);
        vault.move(msg.sender, address(this), mul(chi, wad));
    }

    function exit(uint256 wad) external emitLog {
        pie[msg.sender] = sub(pie[msg.sender], wad);
        Pie = sub(Pie, wad);
        vault.move(address(this), msg.sender, mul(chi, wad));
    }
}
