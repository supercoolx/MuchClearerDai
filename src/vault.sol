/// vault.sol -- Dai CDP database

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

contract Vault is CommonFunctions {
    mapping(address => mapping(address => uint256)) public can;

    function hope(address usr) external emitLog {
        can[msg.sender][usr] = 1;
    }

    function nope(address usr) external emitLog {
        can[msg.sender][usr] = 0;
    }

    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    // --- Data ---
    struct CollateralType {
        uint256 TotalDebt; // Total Normalised Debt     [wad]
        uint256 rate; // Accumulated Rates         [ray]
        uint256 maxDAIPerCollateral; // Price with Safety Margin  [ray]
        uint256 debtCeiling; // Debt Ceiling              [rad]
        uint256 debtFloor; // Urn Debt Floor            [rad]
    }

    struct Urn {
        uint256 lockedCollateral; // Locked Collateral  [wad]
        uint256 normalisedDebt; // Normalised Debt    [wad]
    }

    mapping(bytes32 => CollateralType) public collateralTypes;
    mapping(bytes32 => mapping(address => Urn)) public urns;
    mapping(bytes32 => mapping(address => uint256)) public tokenCollateral; // [wad]
    mapping(address => uint256) public dai; // [rad]
    mapping(address => uint256) public systemDebt; // [rad]

    uint256 public totalDaiIssued; // Total Dai Issued    [rad]
    uint256 public totalDebtIssued; // Total Unbacked Dai  [rad]
    uint256 public TotalDebtCeiling; // Total Debt Ceiling  [rad]
    uint256 public isLive; // Access Flag

    // --- Init ---
    constructor() public {
        authorizedAccounts[msg.sender] = true;
        isLive = 1;
    }

    // --- Math ---
    function safeAdd(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x + uint256(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }

    function safeSub(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x - uint256(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }

    function safeMul(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0);
        require(y == 0 || z / y == int256(x));
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
    function init(bytes32 collateralType) external emitLog onlyOwners {
        require(collateralTypes[collateralType].rate == 0, "Vault/collateralType-already-init");
        collateralTypes[collateralType].rate = 10 ** 27;
    }

    function createNewCollateralType(bytes32 what, uint256 data) external emitLog onlyOwners {
        require(isLive == 1, "Vault/not-isLive");
        if (what == "TotalDebtCeiling") TotalDebtCeiling = data;
        else revert("Vault/createNewCollateralType-unrecognized-param");
    }

    function createNewCollateralType(bytes32 collateralType, bytes32 what, uint256 data) external emitLog onlyOwners {
        require(isLive == 1, "Vault/not-isLive");
        if (what == "maxDAIPerCollateral") collateralTypes[collateralType].maxDAIPerCollateral = data;
        else if (what == "debtCeiling") collateralTypes[collateralType].debtCeiling = data;
        else if (what == "debtFloor") collateralTypes[collateralType].debtFloor = data;
        else revert("Vault/createNewCollateralType-unrecognized-param");
    }

    function cage() external emitLog onlyOwners {
        isLive = 0;
    }

    // --- Fungibility ---
    function slip(bytes32 collateralType, address usr, int256 wad) external emitLog onlyOwners {
        tokenCollateral[collateralType][usr] = safeAdd(tokenCollateral[collateralType][usr], wad);
    }

    function flux(bytes32 collateralType, address src, address dst, uint256 wad) external emitLog {
        require(wish(src, msg.sender), "Vault/not-allowed");
        tokenCollateral[collateralType][src] = safeSub(tokenCollateral[collateralType][src], wad);
        tokenCollateral[collateralType][dst] = safeAdd(tokenCollateral[collateralType][dst], wad);
    }

    function move(address src, address dst, uint256 rad) external emitLog {
        require(wish(src, msg.sender), "Vault/not-allowed");
        dai[src] = safeSub(dai[src], rad);
        dai[dst] = safeAdd(dai[dst], rad);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := or(x, y)
        }
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := and(x, y)
        }
    }

    // --- CDP Manipulation ---
    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external emitLog {
        // system is isLive
        require(isLive == 1, "Vault/not-isLive");

        Urn memory urn = urns[i][u];
        CollateralType memory collateralType = collateralTypes[i];
        // collateralType has been initialised
        require(collateralType.rate != 0, "Vault/collateralType-not-init");

        urn.lockedCollateral = safeAdd(urn.lockedCollateral, dink);
        urn.normalisedDebt = safeAdd(urn.normalisedDebt, dart);
        collateralType.TotalDebt = safeAdd(collateralType.TotalDebt, dart);

        int256 dtab = safeMul(collateralType.rate, dart);
        uint256 tab = safeMul(collateralType.rate, urn.normalisedDebt);
        totalDaiIssued = safeAdd(totalDaiIssued, dtab);

        // either totalDaiIssued has decreased, or totalDaiIssued ceilings are not exceeded
        require(
            either(
                dart <= 0,
                both(
                    safeMul(collateralType.TotalDebt, collateralType.rate) <= collateralType.debtCeiling,
                    totalDaiIssued <= TotalDebtCeiling
                )
            ),
            "Vault/ceiling-exceeded"
        );
        // urn is either less risky than before, or it is safe
        require(
            either(both(dart <= 0, dink >= 0), tab <= safeMul(urn.lockedCollateral, collateralType.maxDAIPerCollateral)),
            "Vault/not-safe"
        );

        // urn is either more safe, or the owner consents
        require(either(both(dart <= 0, dink >= 0), wish(u, msg.sender)), "Vault/not-allowed-u");
        // collateral src consents
        require(either(dink <= 0, wish(v, msg.sender)), "Vault/not-allowed-v");
        // totalDaiIssued dst consents
        require(either(dart >= 0, wish(w, msg.sender)), "Vault/not-allowed-w");

        // urn has no totalDaiIssued, or a non-dusty amount
        require(either(urn.normalisedDebt == 0, tab >= collateralType.debtFloor), "Vault/debtFloor");

        tokenCollateral[i][v] = safeSub(tokenCollateral[i][v], dink);
        dai[w] = safeAdd(dai[w], dtab);

        urns[i][u] = urn;
        collateralTypes[i] = collateralType;
    }
    // --- CDP Fungibility ---

    function fork(bytes32 collateralType, address src, address dst, int256 dink, int256 dart) external emitLog {
        Urn storage u = urns[collateralType][src];
        Urn storage v = urns[collateralType][dst];
        CollateralType storage i = collateralTypes[collateralType];

        u.lockedCollateral = safeSub(u.lockedCollateral, dink);
        u.normalisedDebt = safeSub(u.normalisedDebt, dart);
        v.lockedCollateral = safeAdd(v.lockedCollateral, dink);
        v.normalisedDebt = safeAdd(v.normalisedDebt, dart);

        uint256 utab = safeMul(u.normalisedDebt, i.rate);
        uint256 vtab = safeMul(v.normalisedDebt, i.rate);

        // both sides consent
        require(both(wish(src, msg.sender), wish(dst, msg.sender)), "Vault/not-allowed");

        // both sides safe
        require(utab <= safeMul(u.lockedCollateral, i.maxDAIPerCollateral), "Vault/not-safe-src");
        require(vtab <= safeMul(v.lockedCollateral, i.maxDAIPerCollateral), "Vault/not-safe-dst");

        // both sides non-dusty
        require(either(utab >= i.debtFloor, u.normalisedDebt == 0), "Vault/debtFloor-src");
        require(either(vtab >= i.debtFloor, v.normalisedDebt == 0), "Vault/debtFloor-dst");
    }
    // --- CDP Confiscation ---

    function grab(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external emitLog onlyOwners {
        Urn storage urn = urns[i][u];
        CollateralType storage collateralType = collateralTypes[i];

        urn.lockedCollateral = safeAdd(urn.lockedCollateral, dink);
        urn.normalisedDebt = safeAdd(urn.normalisedDebt, dart);
        collateralType.TotalDebt = safeAdd(collateralType.TotalDebt, dart);

        int256 dtab = safeMul(collateralType.rate, dart);

        tokenCollateral[i][v] = safeSub(tokenCollateral[i][v], dink);
        systemDebt[w] = safeSub(systemDebt[w], dtab);
        totalDebtIssued = safeSub(totalDebtIssued, dtab);
    }

    // --- Settlement ---
    function heal(uint256 rad) external emitLog {
        address u = msg.sender;
        systemDebt[u] = safeSub(systemDebt[u], rad);
        dai[u] = safeSub(dai[u], rad);
        totalDebtIssued = safeSub(totalDebtIssued, rad);
        totalDaiIssued = safeSub(totalDaiIssued, rad);
    }

    function suck(address u, address v, uint256 rad) external emitLog onlyOwners {
        systemDebt[u] = safeAdd(systemDebt[u], rad);
        dai[v] = safeAdd(dai[v], rad);
        totalDebtIssued = safeAdd(totalDebtIssued, rad);
        totalDaiIssued = safeAdd(totalDaiIssued, rad);
    }

    // --- Rates ---
    function fold(bytes32 i, address u, int256 rate) external emitLog onlyOwners {
        require(isLive == 1, "Vault/not-isLive");
        CollateralType storage collateralType = collateralTypes[i];
        collateralType.rate = safeAdd(collateralType.rate, rate);
        int256 rad = safeMul(collateralType.TotalDebt, rate);
        dai[u] = safeAdd(dai[u], rad);
        totalDaiIssued = safeAdd(totalDaiIssued, rad);
    }
}
