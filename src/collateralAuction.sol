/// flip.sol -- Collateral auction

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

interface VaultContract {
    function move(address, address, uint256) external;
    function flux(bytes32, address, address, uint256) external;
}

/*
   This thing lets you flip some gems for a given amount of dai.
   Once the given amount of dai is raised, gems are forgone instead.

 - `lot` gems for sale
 - `tab` total dai wanted
 - `bid` dai paid
 - `gal` receives dai income
 - `usr` receives tokenCollateral forgone
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `end` max auction duration
*/

contract CollateralAuction is CommonFunctions {
    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address guy; // high bidder
        uint48 tic; // expiry time
        uint48 end;
        address usr;
        address gal;
        uint256 tab;
    }

    mapping(uint256 => Bid) public bids;

    VaultContract public vault;
    bytes32 public collateralType;

    uint256 constant ONE = 1.0e18;
    uint256 public beg = 1.05e18; // 5% minimum bid increase
    uint48 public ttl = 3 hours; // 3 hours bid duration
    uint48 public tau = 2 days; // 2 days total auction length
    uint256 public kicks = 0;

    // --- Events ---
    event Kick(uint256 id, uint256 lot, uint256 bid, uint256 tab, address indexed usr, address indexed gal);

    // --- Init ---
    constructor(address vault_, bytes32 collateralType_) public {
        vault = VaultContract(vault_);
        collateralType = collateralType_;
        authorizedAccounts[msg.sender] = true;
    }

    // --- Math ---
    function safeAdd(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        if (what == "beg") beg = data;
        else if (what == "ttl") ttl = uint48(data);
        else if (what == "tau") tau = uint48(data);
        else revert("CollateralAuction/file-unrecognized-param");
    }

    // --- Auction ---
    function kick(address usr, address gal, uint256 tab, uint256 lot, uint256 bid)
        public
        onlyOwners
        returns (uint256 id)
    {
        require(kicks < uint256(-1), "CollateralAuction/overflow");
        id = ++kicks;

        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].guy = msg.sender; // configurable??
        bids[id].end = safeAdd(uint48(now), tau);
        bids[id].usr = usr;
        bids[id].gal = gal;
        bids[id].tab = tab;

        vault.flux(collateralType, msg.sender, address(this), lot);

        emit Kick(id, lot, bid, tab, usr, gal);
    }

    function tick(uint256 id) external emitLog {
        require(bids[id].end < now, "CollateralAuction/not-finished");
        require(bids[id].tic == 0, "CollateralAuction/bid-already-placed");
        bids[id].end = safeAdd(uint48(now), tau);
    }

    function tend(uint256 id, uint256 lot, uint256 bid) external emitLog {
        require(bids[id].guy != address(0), "CollateralAuction/guy-not-set");
        require(bids[id].tic > now || bids[id].tic == 0, "CollateralAuction/already-finished-tic");
        require(bids[id].end > now, "CollateralAuction/already-finished-end");

        require(lot == bids[id].lot, "CollateralAuction/lot-not-matching");
        require(bid <= bids[id].tab, "CollateralAuction/higher-than-tab");
        require(bid > bids[id].bid, "CollateralAuction/bid-not-higher");
        require(
            safeMul(bid, ONE) >= safeMul(beg, bids[id].bid) || bid == bids[id].tab, "CollateralAuction/insufficient-increase"
        );

        vault.move(msg.sender, bids[id].guy, bids[id].bid);
        vault.move(msg.sender, bids[id].gal, bid - bids[id].bid);

        bids[id].guy = msg.sender;
        bids[id].bid = bid;
        bids[id].tic = safeAdd(uint48(now), ttl);
    }

    function dent(uint256 id, uint256 lot, uint256 bid) external emitLog {
        require(bids[id].guy != address(0), "CollateralAuction/guy-not-set");
        require(bids[id].tic > now || bids[id].tic == 0, "CollateralAuction/already-finished-tic");
        require(bids[id].end > now, "CollateralAuction/already-finished-end");

        require(bid == bids[id].bid, "CollateralAuction/not-matching-bid");
        require(bid == bids[id].tab, "CollateralAuction/tend-not-finished");
        require(lot < bids[id].lot, "CollateralAuction/lot-not-lower");
        require(safeMul(beg, lot) <= safeMul(bids[id].lot, ONE), "CollateralAuction/insufficient-decrease");

        vault.move(msg.sender, bids[id].guy, bid);
        vault.flux(collateralType, address(this), bids[id].usr, bids[id].lot - lot);

        bids[id].guy = msg.sender;
        bids[id].lot = lot;
        bids[id].tic = safeAdd(uint48(now), ttl);
    }

    function deal(uint256 id) external emitLog {
        require(bids[id].tic != 0 && (bids[id].tic < now || bids[id].end < now), "CollateralAuction/not-finished");
        vault.flux(collateralType, address(this), bids[id].guy, bids[id].lot);
        delete bids[id];
    }

    function yank(uint256 id) external emitLog onlyOwners {
        require(bids[id].guy != address(0), "CollateralAuction/guy-not-set");
        require(bids[id].bid < bids[id].tab, "CollateralAuction/already-dent-phase");
        vault.flux(collateralType, address(this), msg.sender, bids[id].lot);
        vault.move(msg.sender, bids[id].guy, bids[id].bid);
        delete bids[id];
    }
}
