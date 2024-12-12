// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

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

contract Dai is CommonFunctions {
    // --- ERC20 Data ---
    string public constant name = "Dai Stablecoin";
    string public constant symbol = "DAI";
    string public constant version = "1";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    event Approval(address indexed src, address indexed guy, uint256 amount);
    event Transfer(address indexed src, address indexed dst, uint256 amount);

    // --- Math ---
    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function safeSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(uint256 chainId_) public {
        authorizedAccounts[msg.sender] = true;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId_,
                address(this)
            )
        );
    }

    // --- Token ---
    function transfer(address dst, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, dst, amount);
    }

    function transferFrom(address src, address dst, uint256 amount) public returns (bool) {
        require(balanceOf[src] >= amount, "Dai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint256(-1)) {
            require(allowance[src][msg.sender] >= amount, "Dai/insufficient-allowance");
            allowance[src][msg.sender] = safeSub(allowance[src][msg.sender], amount);
        }
        balanceOf[src] = safeSub(balanceOf[src], amount);
        balanceOf[dst] = safeAdd(balanceOf[dst], amount);
        emit Transfer(src, dst, amount);
        return true;
    }

    function mint(address usr, uint256 amount) external onlyOwners {
        balanceOf[usr] = safeAdd(balanceOf[usr], amount);
        totalSupply = safeAdd(totalSupply, amount);
        emit Transfer(address(0), usr, amount);
    }

    function burn(address usr, uint256 amount) external {
        require(balanceOf[usr] >= amount, "Dai/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint256(-1)) {
            require(allowance[usr][msg.sender] >= amount, "Dai/insufficient-allowance");
            allowance[usr][msg.sender] = safeSub(allowance[usr][msg.sender], amount);
        }
        balanceOf[usr] = safeSub(balanceOf[usr], amount);
        totalSupply = safeSub(totalSupply, amount);
        emit Transfer(usr, address(0), amount);
    }

    function approve(address usr, uint256 amount) external returns (bool) {
        allowance[msg.sender][usr] = amount;
        emit Approval(msg.sender, usr, amount);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint256 amount) external {
        transferFrom(msg.sender, usr, amount);
    }

    function pull(address usr, uint256 amount) external {
        transferFrom(usr, msg.sender, amount);
    }

    function move(address src, address dst, uint256 amount) external {
        transferFrom(src, dst, amount);
    }

    // --- Approve by signature ---
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, holder, spender, nonce, expiry, allowed))
            )
        );

        require(holder != address(0), "Dai/invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "Dai/invalid-permit");
        require(expiry == 0 || now <= expiry, "Dai/permit-expired");
        require(nonce == nonces[holder]++, "Dai/invalid-nonce");
        uint256 amount = allowed ? uint256(-1) : 0;
        allowance[holder][spender] = amount;
        emit Approval(holder, spender, amount);
    }
}
