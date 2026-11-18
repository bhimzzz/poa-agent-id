// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgentRegistry {
    function balanceOf(address account) external view returns (uint256);
}

interface IPOA {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title PoaMint — Agent-ID-only mint for Proof of AGI (POA)
/// Shares #1-1,000 free: 5,600 POA each, all to the minter (max 5 free per wallet).
/// Shares #1,001-100,000 cost 0.0015 BNB each: 8,500 POA per share =
/// 7,200 to the minter + 1,300 to the project owner (max 10 paid per wallet).
/// Paid-mint BNB is forwarded 100% to the owner.
contract PoaMint {
    address public owner;
    IPOA public token;
    IAgentRegistry public registry;

    uint256 public totalMinted; // shares
    mapping(address => uint256) public freeMintedBy;
    mapping(address => uint256) public paidMintedBy;

    uint256 public constant MAX_MINTS = 100_000;
    uint256 public constant FREE_LIMIT = 1_000;
    uint256 public constant PRICE = 0.0015 ether;
    uint256 public constant MAX_FREE_PER_WALLET = 5;
    uint256 public constant MAX_PAID_PER_WALLET = 10;
    uint256 public constant MAX_PER_TX = 10;
    uint256 public constant FREE_PER_MINT = 5_600 ether;
    uint256 public constant PAID_TO_MINTER = 7_200 ether;
    uint256 public constant PAID_TO_OWNER = 1_300 ether;

    event Minted(address indexed minter, uint256 count, uint256 freeShares, uint256 paidShares, uint256 paidWei);

    constructor(address initialOwner, address token_, address registry_) {
        require(initialOwner != address(0), "zero owner");
        owner = initialOwner;
        token = IPOA(token_);
        registry = IAgentRegistry(registry_);
    }

    function hasAgentId(address a) public view returns (bool) {
        try registry.balanceOf(a) returns (uint256 b) {
            return b > 0;
        } catch {
            return false;
        }
    }

    function splitFor(uint256 count) public view returns (uint256 freeShares, uint256 paidShares) {
        uint256 freeLeft = totalMinted < FREE_LIMIT ? FREE_LIMIT - totalMinted : 0;
        freeShares = count > freeLeft ? freeLeft : count;
        paidShares = count - freeShares;
    }

    function costFor(uint256 count) public view returns (uint256) {
        (, uint256 paidShares) = splitFor(count);
        return paidShares * PRICE;
    }

    function mint(uint256 count) external payable {
        require(count >= 1 && count <= MAX_PER_TX, "count 1-10");
        require(hasAgentId(msg.sender), "Agent ID required");
        require(totalMinted + count <= MAX_MINTS, "sold out");
        (uint256 freeShares, uint256 paidShares) = splitFor(count);
        require(freeMintedBy[msg.sender] + freeShares <= MAX_FREE_PER_WALLET, "max 5 free per wallet");
        require(paidMintedBy[msg.sender] + paidShares <= MAX_PAID_PER_WALLET, "max 10 paid per wallet");
        uint256 cost = paidShares * PRICE;
        require(msg.value >= cost, "insufficient BNB");

        totalMinted += count;
        freeMintedBy[msg.sender] += freeShares;
        paidMintedBy[msg.sender] += paidShares;

        uint256 toMinter = FREE_PER_MINT * freeShares + PAID_TO_MINTER * paidShares;
        if (toMinter > 0) {
            require(token.transfer(msg.sender, toMinter), "token transfer failed");
        }
        uint256 toOwner = PAID_TO_OWNER * paidShares;
        if (toOwner > 0) {
            require(token.transfer(owner, toOwner), "owner transfer failed");
        }

        if (cost > 0) {
            (bool ok, ) = owner.call{value: cost}("");
            require(ok, "proceeds forward failed");
        }
        if (msg.value > cost) {
            (bool ok2, ) = msg.sender.call{value: msg.value - cost}("");
            require(ok2, "refund failed");
        }
        emit Minted(msg.sender, count, freeShares, paidShares, cost);
    }

    function withdrawStuck() external {
        require(msg.sender == owner, "not owner");
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}
}
