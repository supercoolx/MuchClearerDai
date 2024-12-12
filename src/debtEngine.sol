/// debtEngine.sol -- Dai settlement module

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

contract FlopLike {
    function kick(address daiIncomeReceiver, uint256 tokensForSale, uint256 bid) external returns (uint256);
    function cage() external;
    function DSRisActive() external returns (uint256);
}

contract FlapLike {
    function kick(uint256 tokensForSale, uint256 bid) external returns (uint256);
    function cage(uint256) external;
    function DSRisActive() external returns (uint256);
}

contract CDPEngineContract {
    function dai(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function heal(uint256) external;
    function hope(address) external;
    function nope(address) external;
}

contract DebtEngine is CommonFunctions {
    // --- Data ---
    CDPEngineContract public CDPEngine;
    FlapLike public flapper;
    FlopLike public flopper;

    mapping(uint256 => uint256) public sin; // debt queue
    uint256 public Sin; // queued debt          [rad]
    uint256 public Ash; // on-auction debt      [rad]

    uint256 public wait; // flop delay
    uint256 public dump; // flop initial tokensForSale size  [amount]
    uint256 public sump; // flop fixed bid size    [rad]

    uint256 public bump; // buyCollateral fixed tokensForSale size    [rad]
    uint256 public hump; // surplus buffer       [rad]

    bool public DSRisActive;

    // --- Init ---
    constructor(address CDPEngine_, address flapper_, address flopper_) public {
        authorizedAccounts[msg.sender] = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        flapper = FlapLike(flapper_);
        flopper = FlopLike(flopper_);
        CDPEngine.hope(flapper_);
        DSRisActive = true;
    }

    // --- Math ---
    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function safeSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        if (what == "wait") wait = data;
        else if (what == "bump") bump = data;
        else if (what == "sump") sump = data;
        else if (what == "dump") dump = data;
        else if (what == "hump") hump = data;
        else revert("DebtEngine/file-unrecognized-param");
    }

    function file(bytes32 what, address data) external emitLog onlyOwners {
        if (what == "flapper") {
            CDPEngine.nope(address(flapper));
            flapper = FlapLike(data);
            CDPEngine.hope(data);
        } else if (what == "flopper") {
            flopper = FlopLike(data);
        } else {
            revert("DebtEngine/file-unrecognized-param");
        }
    }

    // Push to debt-queue
    function fess(uint256 tab) external emitLog onlyOwners {
        sin[now] = safeAdd(sin[now], tab);
        Sin = safeAdd(Sin, tab);
    }
    // Pop from debt-queue

    function flog(uint256 era) external emitLog {
        require(safeAdd(era, wait) <= now, "DebtEngine/wait-not-finished");
        Sin = safeSub(Sin, sin[era]);
        sin[era] = 0;
    }

    // Debt settlement
    function heal(uint256 rad) external emitLog {
        require(rad <= CDPEngine.dai(address(this)), "DebtEngine/insufficient-surplus");
        require(rad <= safeSub(safeSub(CDPEngine.sin(address(this)), Sin), Ash), "DebtEngine/insufficient-debt");
        CDPEngine.heal(rad);
    }

    function kiss(uint256 rad) external emitLog {
        require(rad <= Ash, "DebtEngine/not-enough-ash");
        require(rad <= CDPEngine.dai(address(this)), "DebtEngine/insufficient-surplus");
        Ash = safeSub(Ash, rad);
        CDPEngine.heal(rad);
    }

    // Debt auction
    function flop() external emitLog returns (uint256 id) {
        require(sump <= safeSub(safeSub(CDPEngine.sin(address(this)), Sin), Ash), "DebtEngine/insufficient-debt");
        require(CDPEngine.dai(address(this)) == 0, "DebtEngine/surplus-not-zero");
        Ash = safeAdd(Ash, sump);
        id = flopper.kick(address(this), dump, sump);
    }
    // Surplus auction

    function buyCollateral() external emitLog returns (uint256 id) {
        require(
            CDPEngine.dai(address(this)) >= safeAdd(safeAdd(CDPEngine.sin(address(this)), bump), hump),
            "DebtEngine/insufficient-surplus"
        );
        require(safeSub(safeSub(CDPEngine.sin(address(this)), Sin), Ash) == 0, "DebtEngine/debt-not-zero");
        id = flapper.kick(bump, 0);
    }

    function cage() external emitLog onlyOwners {
        require(DSRisActive, "DebtEngine/not-DSRisActive");
        DSRisActive = false;
        Sin = 0;
        Ash = 0;
        flapper.cage(CDPEngine.dai(address(flapper)));
        flopper.cage();
        CDPEngine.heal(min(CDPEngine.dai(address(this)), CDPEngine.sin(address(this))));
    }
}
