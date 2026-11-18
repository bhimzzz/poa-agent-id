// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Proof of AGI (POA) — the singularity's proof on BNB Chain
/// Supply 1B: 847.1M mint allocation (held by deployer, moved to mint contract at setup),
/// 152.9M LP reserve straight to the project owner wallet.
/// Transfers locked until the owner opens trading (after manual LP on PancakeSwap V2).
/// Tax once trading is open: buy 6% -> owner; sell 6% -> 3% burn + 3% owner.
contract PoaToken {
    string public name = "Proof of AGI";
    string public symbol = "POA";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    address public admin; // deployer, setup only; zeroed by lockSetup()
    address public mintContract;
    address public pair;
    bool public tradingOpen;
    bool public setupLocked;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant LP_RESERVE = 152_900_000 ether;
    uint256 public constant MINT_ALLOCATION = 847_100_000 ether;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event TradingOpened(address pair);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "zero owner");
        owner = initialOwner;
        admin = msg.sender;
        totalSupply = TOTAL_SUPPLY;
        balanceOf[initialOwner] = LP_RESERVE;
        emit Transfer(address(0), initialOwner, LP_RESERVE);
        balanceOf[msg.sender] = MINT_ALLOCATION;
        emit Transfer(address(0), msg.sender, MINT_ALLOCATION);
    }

    function setMintContract(address mc) external {
        require(!setupLocked, "setup locked");
        require(msg.sender == admin || msg.sender == owner, "not admin/owner");
        mintContract = mc;
    }

    function lockSetup() external {
        require(msg.sender == admin || msg.sender == owner, "not admin/owner");
        setupLocked = true;
        admin = address(0);
    }

    function openTrading(address pair_) external onlyOwner {
        require(pair_ != address(0), "zero pair");
        pair = pair_;
        tradingOpen = true;
        emit TradingOpened(pair_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "zero to");
        require(balanceOf[from] >= amount, "balance");

        uint256 tax = 0;
        bool sellTax = false;
        if (!tradingOpen) {
            // Locked phase: only mint distribution, owner moves and setup moves.
            require(
                from == mintContract || from == owner || from == admin || to == owner || to == mintContract,
                "trading locked"
            );
        } else if (pair != address(0)) {
            if (from == pair && to != owner && to != mintContract) {
                tax = (amount * 6) / 100; // buy: 6% to owner
            } else if (to == pair && from != owner && from != mintContract) {
                tax = (amount * 6) / 100; // sell: 3% burn + 3% owner
                sellTax = true;
            }
        }

        balanceOf[from] -= amount;
        if (tax > 0) {
            if (sellTax) {
                uint256 burnAmt = tax / 2;
                uint256 ownerAmt = tax - burnAmt;
                totalSupply -= burnAmt;
                balanceOf[owner] += ownerAmt;
                emit Transfer(from, owner, ownerAmt);
                emit Transfer(from, address(0), burnAmt);
            } else {
                balanceOf[owner] += tax;
                emit Transfer(from, owner, tax);
            }
        }
        balanceOf[to] += amount - tax;
        emit Transfer(from, to, amount - tax);
    }
}
