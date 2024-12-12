/// globalSettlement.sol -- global settlement engine

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
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

contract CDPEngineContract {
    function dai(address) external view returns (uint256);
    function collateralTypes(bytes32 collateralType)
        external
        returns (uint256 debtAmount, uint256 accumulatedRates, uint256 spot, uint256 line, uint256 dust);
    function urns(bytes32 collateralType, address urn) external returns (uint256 ink, uint256 art);
    function debt() external returns (uint256);
    function move(address src, address dst, uint256 rad) external;
    function hope(address) external;
    function flux(bytes32 collateralType, address src, address dst, uint256 rad) external;
    function grab(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
    function suck(address u, address v, uint256 rad) external;
    function cage() external;
}

contract CatLike {
    function collateralTypes(bytes32)
        external
        returns (
            address liquidator, // Liquidator
            uint256 liquidatorPenalty, // Liquidation Penalty   [ray]
            uint256 liquidatorAmount
        ); // Liquidation Quantity  [rad]

    function cage() external;
}

contract PotLike {
    function cage() external;
}

contract VowLike {
    function cage() external;
}

contract Seller {
    function bids(uint256 id)
        external
        view
        returns (
            uint256 bid,
            uint256 tokensForSale,
            address guy,
            uint48 tic,
            uint48 end,
            address usr,
            address daiIncomeReceiver,
            uint256 tab
        );
    function yank(uint256 id) external;
}

contract PipLike {
    function read() external view returns (bytes32);
}

contract Spotty {
    function par() external view returns (uint256);
    function collateralTypes(bytes32) external view returns (PipLike pip, uint256 mat);
    function cage() external;
}

/*
    This is the `GlobalSettlement` and it coordinates Global Settlement. This is an
    involved, stateful process that takes place over nine steps.

    First we freeze the system and lock the prices for each collateralType.

    1. `cage()`:
        - freezes user entrypoints
        - cancels flop/buyCollateral auctions
        - starts cooldown period
        - stops pot collectRates

    2. `cage(collateralType)`:
       - set the cage price for each `collateralType`, reading off the price feed

    We must process some system state before it is possible to calculate
    the final dai / collateral price. In particular, we need to determine

      a. `gap`, the collateral shortfall per collateral type by
         considering under-collateralised CDPs.

      b. `debt`, the outstanding dai supply after including system
         surplus / deficit

    We determine (a) by processing all under-collateralised CDPs with
    `skim`:

    3. `skim(collateralType, urn)`:
       - cancels CDP debt
       - any excess collateral remains
       - backing collateral taken

    We determine (b) by processing ongoing dai generating processes,
    i.e. auctions. We need to ensure that auctions will not generate any
    further dai income. In the two-way auction model this occurs when
    all auctions are in the reverse (`dent`) phase. There are two ways
    of ensuring this:

    4.  i) `wait`: set the cooldown period to be at least as long as the
           longest auction duration, which needs to be determined by the
           cage administrator.

           This takes a fairly predictable time to occur but with altered
           auction dynamics due to the now varying price of dai.

       ii) `skip`: cancel all ongoing auctions and seize the collateral.

           This allows for faster processing at the expense of more
           processing calls. This option allows dai holders to retrieve
           their collateral faster.

           `skip(collateralType, id)`:
            - cancel individual liquidator auctions in the `tend` (forward) phase
            - retrieves collateral and returns dai to bidder
            - `dent` (reverse) phase auctions can continue normally

    Option (i), `wait`, is sufficient for processing the system
    settlement but option (ii), `skip`, will speed it up. Both options
    are available in this implementation, with `skip` being enabled on a
    per-auction basis.

    When a CDP has been processed and has no debt remaining, the
    remaining collateral can be removed.

    5. `free(collateralType)`:
        - remove collateral from the caller's CDP
        - owner can call as needed

    After the processing period has elapsed, we enable calculation of
    the final price for each collateral type.

    6. `thaw()`:
       - only callable after processing time period elapsed
       - assumption that all under-collateralised CDPs are processed
       - fixes the total outstanding supply of dai
       - may also require extra CDP processing to cover debtEngine surplus

    7. `flow(collateralType)`:
        - calculate the `fix`, the cash price for a given collateralType
        - adjusts the `fix` in the case of deficit / surplus

    At this point we have computed the final price for each collateral
    type and dai holders can now turn their dai into collateral. Each
    unit dai can claim a fixed basket of collateral.

    Dai holders must first `pack` some dai into a `bag`. Once packed,
    dai cannot be unpacked and is not transferrable. More dai can be
    added to a bag later.

    8. `pack(amount)`:
        - put some dai into a bag in preparation for `cash`

    Finally, collateral can be obtained with `cash`. The bigger the bag,
    the more collateral can be released.

    9. `cash(collateralType, amount)`:
        - exchange some dai from your bag for gems from a specific collateralType
        - the number of gems is limited by how big your bag is
*/

contract GlobalSettlement is CommonFunctions {
    // --- Data ---
    CDPEngineContract public CDPEngine;
    CatLike public cat;
    VowLike public debtEngine;
    PotLike public pot;
    Spotty public spot;

    bool public DSRisActive; // cage flag
    uint256 public when; // time of cage
    uint256 public wait; // processing cooldown length
    uint256 public debt; // total outstanding dai following processing [rad]

    mapping(bytes32 => uint256) public tag; // cage price           [ray]
    mapping(bytes32 => uint256) public gap; // collateral shortfall [amount]
    mapping(bytes32 => uint256) public debtAmount; // total debt per collateralType   [amount]
    mapping(bytes32 => uint256) public fix; // final cash price     [ray]

    mapping(address => uint256) public bag; // [amount]
    mapping(bytes32 => mapping(address => uint256)) public out; // [amount]

    // --- Init ---
    constructor() public {
        authorizedAccounts[msg.sender] = true;
        DSRisActive = true;
    }

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, y) / RAY;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, RAY) / y;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, WAD) / y;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external emitLog onlyOwners {
        require(DSRisActive, "GlobalSettlement/not-DSRisActive");
        if (what == "CDPEngine") CDPEngine = CDPEngineContract(data);
        else if (what == "cat") cat = CatLike(data);
        else if (what == "debtEngine") debtEngine = VowLike(data);
        else if (what == "pot") pot = PotLike(data);
        else if (what == "spot") spot = Spotty(data);
        else revert("GlobalSettlement/file-unrecognized-param");
    }

    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        require(DSRisActive, "GlobalSettlement/not-DSRisActive");
        if (what == "wait") wait = data;
        else revert("GlobalSettlement/file-unrecognized-param");
    }

    // --- Settlement ---
    function cage() external emitLog onlyOwners {
        require(DSRisActive, "GlobalSettlement/not-DSRisActive");
        DSRisActive = false;
        when = now;
        CDPEngine.cage();
        cat.cage();
        debtEngine.cage();
        spot.cage();
        pot.cage();
    }

    function cage(bytes32 collateralType) external emitLog {
        require(!DSRisActive, "GlobalSettlement/still-DSRisActive");
        require(tag[collateralType] == 0, "GlobalSettlement/tag-collateralType-already-defined");
        (debtAmount[collateralType],,,,) = CDPEngine.collateralTypes(collateralType);
        (PipLike pip,) = spot.collateralTypes(collateralType);
        // par is a ray, pip returns a amount
        tag[collateralType] = wdiv(spot.par(), uint256(pip.read()));
    }

    function skip(bytes32 collateralType, uint256 id) external emitLog {
        require(tag[collateralType] != 0, "GlobalSettlement/tag-collateralType-not-defined");

        (address flipV,,) = cat.collateralTypes(collateralType);
        Seller liquidator = Seller(flipV);
        (, uint256 accumulatedRates,,,) = CDPEngine.collateralTypes(collateralType);
        (uint256 bid, uint256 tokensForSale,,,, address usr,, uint256 tab) = liquidator.bids(id);

        CDPEngine.suck(address(debtEngine), address(debtEngine), tab);
        CDPEngine.suck(address(debtEngine), address(this), bid);
        CDPEngine.hope(address(liquidator));
        liquidator.yank(id);

        uint256 art = tab / accumulatedRates;
        debtAmount[collateralType] = add(debtAmount[collateralType], art);
        require(int256(tokensForSale) >= 0 && int256(art) >= 0, "GlobalSettlement/overflow");
        CDPEngine.grab(collateralType, usr, address(this), address(debtEngine), int256(tokensForSale), int256(art));
    }

    function skim(bytes32 collateralType, address urn) external emitLog {
        require(tag[collateralType] != 0, "GlobalSettlement/tag-collateralType-not-defined");
        (, uint256 accumulatedRates,,,) = CDPEngine.collateralTypes(collateralType);
        (uint256 ink, uint256 art) = CDPEngine.urns(collateralType, urn);

        uint256 owe = rmul(rmul(art, accumulatedRates), tag[collateralType]);
        uint256 amount = min(ink, owe);
        gap[collateralType] = add(gap[collateralType], sub(owe, amount));

        require(amount <= 2 ** 255 && art <= 2 ** 255, "GlobalSettlement/overflow");
        CDPEngine.grab(collateralType, urn, address(this), address(debtEngine), -int256(amount), -int256(art));
    }

    function free(bytes32 collateralType) external emitLog {
        require(!DSRisActive, "GlobalSettlement/still-DSRisActive");
        (uint256 ink, uint256 art) = CDPEngine.urns(collateralType, msg.sender);
        require(art == 0, "GlobalSettlement/art-not-zero");
        require(ink <= 2 ** 255, "GlobalSettlement/overflow");
        CDPEngine.grab(collateralType, msg.sender, msg.sender, address(debtEngine), -int256(ink), 0);
    }

    function thaw() external emitLog {
        require(!DSRisActive, "GlobalSettlement/still-DSRisActive");
        require(debt == 0, "GlobalSettlement/debt-not-zero");
        require(CDPEngine.dai(address(debtEngine)) == 0, "GlobalSettlement/surplus-not-zero");
        require(now >= add(when, wait), "GlobalSettlement/wait-not-finished");
        debt = CDPEngine.debt();
    }

    function flow(bytes32 collateralType) external emitLog {
        require(debt != 0, "GlobalSettlement/debt-zero");
        require(fix[collateralType] == 0, "GlobalSettlement/fix-collateralType-already-defined");

        (, uint256 accumulatedRates,,,) = CDPEngine.collateralTypes(collateralType);
        uint256 amount = rmul(rmul(debtAmount[collateralType], accumulatedRates), tag[collateralType]);
        fix[collateralType] = rdiv(mul(sub(amount, gap[collateralType]), RAY), debt);
    }

    function pack(uint256 amount) external emitLog {
        require(debt != 0, "GlobalSettlement/debt-zero");
        CDPEngine.move(msg.sender, address(debtEngine), mul(amount, RAY));
        bag[msg.sender] = add(bag[msg.sender], amount);
    }

    function cash(bytes32 collateralType, uint256 amount) external emitLog {
        require(fix[collateralType] != 0, "GlobalSettlement/fix-collateralType-not-defined");
        CDPEngine.flux(collateralType, address(this), msg.sender, rmul(amount, fix[collateralType]));
        out[collateralType][msg.sender] = add(out[collateralType][msg.sender], amount);
        require(out[collateralType][msg.sender] <= bag[msg.sender], "GlobalSettlement/insufficient-bag-balance");
    }
}
