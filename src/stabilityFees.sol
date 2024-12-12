pragma solidity >=0.5.12;

import "./commonFunctions.sol";

contract VatLike {
    function ilks(bytes32)
        external
        returns (
            uint256 Art, // wad
            uint256 rate
        ); // ray

    function fold(bytes32, address, int256) external;
}

contract Jug is CommonFunctions {
    // --- Data ---
    struct Ilk {
        uint256 duty;
        uint256 timeOfLastCollectionRate;
    }

    mapping(bytes32 => Ilk) public ilks;
    VatLike public CDPEngine;
    address public debtEngine;
    uint256 public base;

    // --- Init ---
    constructor(address CDPEngine_) public {
        authorizedAccounts[msg.sender] = true;
        CDPEngine = VatLike(CDPEngine_);
    }

    // --- Math ---
    // computes z = ((x/b)^n)*b
    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := b }
                    // if x, n == 0, return b
                default { z := 0 } // if x == 0, n != 0, return 0
            }
            default {
                switch mod(n, 2)
                case 0 { z := b }
                    //if n is even, set z = b
                default { z := x } // otherwise set z = x

                let halfOfB := div(b, 2) // for rounding.

                for { n := div(n, 2) } n { n := div(n, 2) } {
                    //n starts at n/2 (floored)
                    //loop runs if n != 0
                    //n is divided by 2 after loop iteration
                    let xSqrd := mul(x, x) //x squared
                    if iszero(eq(div(xSqrd, x), x)) {
                        //multiplication overflow check. If xSqrd/x != x, revert
                        revert(0, 0)
                    }
                    let xSqrdRound := add(xSqrd, halfOfB)
                    if lt(xSqrdRound, xSqrd) {
                        //addition overfow check. revert if xSqrdRound < xSqrd
                        revert(0, 0)
                    }
                    x := div(xSqrdRound, b) // x = (xSqrd + b/2)/b
                        // note that the addition of halfOfB before dividing will help to round the result in the proper direction.
                        // we're obtaining the result of xSqrd/b, but with rounding to the nearest whole num
                    if mod(n, 2) {
                        // if n is odd
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            //mul overflow check.
                            //if x!=0, and zx/x != z, then revert
                            revert(0, 0)
                        }
                        let zxRound := add(zx, halfOfB)
                        if lt(zxRound, zx) {
                            //addition overflow, reverts if zxRound < zx
                            revert(0, 0)
                        }
                        z := div(zxRound, b) //z = z*x/b (rounded to nearest whole num)
                    }
                } // at end of loop, n = n/2 (floored)
            }
        }
    }

    uint256 constant ONE = 10 ** 27;

    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x);
    }

    function diff(uint256 x, uint256 y) internal pure returns (int256 z) {
        z = int256(x) - int256(y);
        require(int256(x) >= 0 && int256(y) >= 0);
    }

    function rsafeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / ONE;
    }

    // --- Administration ---
    function init(bytes32 ilk) external emitLog onlyOwners {
        Ilk storage i = ilks[ilk];
        require(i.duty == 0, "Jug/ilk-already-init");
        i.duty = ONE;
        i.timeOfLastCollectionRate = now;
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external emitLog onlyOwners {
        require(now == ilks[ilk].timeOfLastCollectionRate, "Jug/timeOfLastCollectionRate-not-updated");
        if (what == "duty") ilks[ilk].duty = data;
        else revert("Jug/file-unrecognized-param");
    }

    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        if (what == "base") base = data;
        else revert("Jug/file-unrecognized-param");
    }

    function file(bytes32 what, address data) external emitLog onlyOwners {
        if (what == "debtEngine") debtEngine = data;
        else revert("Jug/file-unrecognized-param");
    }

    // --- Stability Fee Collection ---
    function collectRate(bytes32 ilk) external emitLog returns (uint256 rate) {
        require(now >= ilks[ilk].timeOfLastCollectionRate, "Jug/invalid-now");
        (, uint256 prev) = CDPEngine.ilks(ilk);
        rate = rsafeMul(rpow(safeAdd(base, ilks[ilk].duty), now - ilks[ilk].timeOfLastCollectionRate, ONE), prev);
        CDPEngine.fold(ilk, debtEngine, diff(rate, prev));
        ilks[ilk].timeOfLastCollectionRate = now;
    }
}
