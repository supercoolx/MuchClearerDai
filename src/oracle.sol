/// spot.sol -- Oracle

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

contract VaultContract {
    function file(bytes32, bytes32, uint256) external;
}

contract PipLike {
    function peek() external returns (bytes32, bool);
}

contract Oracle is CommonFunctions {
    // --- Data ---
    struct CollateralType {
        PipLike pip;
        uint256 mat;
    }

    mapping(bytes32 => CollateralType) public collateralTypes;

    VaultContract public vat;
    uint256 public par; // ref per dai

    uint256 public live;

    // --- Events ---
    event Poke(bytes32 collateralType, bytes32 val, uint256 spot);

    // --- Init ---
    constructor(address vault_) public {
        authorizedAccounts[msg.sender] = true;
        vat = VaultContract(vault_);
        par = ONE;
        live = 1;
    }

    // --- Math ---
    uint256 constant ONE = 10 ** 27;

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = safeMul(x, ONE) / y;
    }

    // --- Administration ---
    function file(bytes32 collateralType, bytes32 what, address pip_) external emitLog onlyOwners {
        require(live == 1, "Oracle/not-live");
        if (what == "pip") collateralTypes[collateralType].pip = PipLike(pip_);
        else revert("Oracle/file-unrecognized-param");
    }

    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        require(live == 1, "Oracle/not-live");
        if (what == "par") par = data;
        else revert("Oracle/file-unrecognized-param");
    }

    function file(bytes32 collateralType, bytes32 what, uint256 data) external emitLog onlyOwners {
        require(live == 1, "Oracle/not-live");
        if (what == "mat") collateralTypes[collateralType].mat = data;
        else revert("Oracle/file-unrecognized-param");
    }

    // --- Update value ---
    function poke(bytes32 collateralType) external {
        (bytes32 val, bool has) = collateralTypes[collateralType].pip.peek();
        uint256 spot = has ? rdiv(rdiv(safeMul(uint256(val), 10 ** 9), par), collateralTypes[collateralType].mat) : 0;
        vat.file(collateralType, "spot", spot);
        emit Poke(collateralType, val, spot);
    }

    function cage() external emitLog onlyOwners {
        live = 0;
    }
}
