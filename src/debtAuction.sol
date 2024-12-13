/// flop.sol -- Debt auction

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
    function suck(address, address, uint256) external;
}

interface TokenContract {
    function mint(address, uint256) external;
}

/*
   This thing creates gems on demand in return for dai.

 - `lot` gems for sale
 - `bid` dai paid
 - `gal` receives dai income
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `end` max auction duration
*/

contract DebtAuction is CommonFunctions {
    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address guy; // high bidder
        uint48 tic; // expiry time
        uint48 end;
    }

    mapping(uint256 => Bid) public bids;

    VaultContract public vat;
    TokenContract public tokenCollateral;

    uint256 constant ONE = 1.0e18;
    uint256 public beg = 1.05e18; // 5% minimum bid increase
    uint256 public pad = 1.5e18; // 50% lot increase for tick
    uint48 public ttl = 3 hours; // 3 hours bid lifetime
    uint48 public tau = 2 days; // 2 days total auction length
    uint256 public kicks = 0;
    uint256 public live;
    address public settlement; // not used until shutdown

    // --- Events ---
    event Kick(uint256 id, uint256 lot, uint256 bid, address indexed gal);

    // --- Init ---
    constructor(address vault_, address gem_) public {
        authorizedAccounts[msg.sender] = true;
        vat = VaultContract(vault_);
        tokenCollateral = TokenContract(gem_);
        live = 1;
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
        else if (what == "pad") pad = data;
        else if (what == "ttl") ttl = uint48(data);
        else if (what == "tau") tau = uint48(data);
        else revert("DebtAuction/file-unrecognized-param");
    }

    // --- Auction ---
    function kick(address gal, uint256 lot, uint256 bid) external onlyOwners returns (uint256 id) {
        require(live == 1, "DebtAuction/not-live");
        require(kicks < uint256(-1), "DebtAuction/overflow");
        id = ++kicks;

        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].guy = gal;
        bids[id].end = safeAdd(uint48(now), tau);

        emit Kick(id, lot, bid, gal);
    }

    function tick(uint256 id) external emitLog {
        require(bids[id].end < now, "DebtAuction/not-finished");
        require(bids[id].tic == 0, "DebtAuction/bid-already-placed");
        bids[id].lot = safeMul(pad, bids[id].lot) / ONE;
        bids[id].end = safeAdd(uint48(now), tau);
    }

    function dent(uint256 id, uint256 lot, uint256 bid) external emitLog {
        require(live == 1, "DebtAuction/not-live");
        require(bids[id].guy != address(0), "DebtAuction/guy-not-set");
        require(bids[id].tic > now || bids[id].tic == 0, "DebtAuction/already-finished-tic");
        require(bids[id].end > now, "DebtAuction/already-finished-end");

        require(bid == bids[id].bid, "DebtAuction/not-matching-bid");
        require(lot < bids[id].lot, "DebtAuction/lot-not-lower");
        require(safeMul(beg, lot) <= safeMul(bids[id].lot, ONE), "DebtAuction/insufficient-decrease");

        vat.move(msg.sender, bids[id].guy, bid);

        bids[id].guy = msg.sender;
        bids[id].lot = lot;
        bids[id].tic = safeAdd(uint48(now), ttl);
    }

    function deal(uint256 id) external emitLog {
        require(live == 1, "DebtAuction/not-live");
        require(bids[id].tic != 0 && (bids[id].tic < now || bids[id].end < now), "DebtAuction/not-finished");
        tokenCollateral.mint(bids[id].guy, bids[id].lot);
        delete bids[id];
    }

    // --- Shutdown ---
    function cage() external emitLog onlyOwners {
        live = 0;
        settlement = msg.sender;
    }

    function yank(uint256 id) external emitLog {
        require(live == 0, "DebtAuction/still-live");
        require(bids[id].guy != address(0), "DebtAuction/guy-not-set");
        vat.suck(settlement, bids[id].guy, bids[id].bid);
        delete bids[id];
    }
}
